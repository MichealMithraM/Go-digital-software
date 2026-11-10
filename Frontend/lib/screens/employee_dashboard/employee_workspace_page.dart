import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:godigital_portal/services/authenticated_http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../core/constants/employee_role.dart';
import 'package:godigital_portal/core/theme/premium_theme.dart';
import '../../services/api_config.dart';
import '../../services/auth_service.dart';
import '../../services/socket_auth.dart';
import 'content_calendar_screen.dart';
import 'workspace_my_tasks_section.dart';
import 'workspace_task_review_section.dart';
import 'task_actions.dart';
import 'additional_task_dialog.dart';
import 'package:godigital_portal/layouts/admin_layout.dart';

part 'admin_workspace_page.dart';

class EmployeeWorkspacePage extends StatefulWidget {
  final EmployeeRole role;
  final List<String> allowedPages;
  final String? initialSection;

  /// Called with a sidebar page name (e.g. 'Day Planner') when a workspace
  /// button should open another page. Wire it to the dashboard's page switch.
  final ValueChanged<String>? onNavigate;

  /// Open a specific client card + tab, e.g. from the top-bar running chip:
  /// {client, due_date: 'yyyy-mm-dd', section: 'My Tasks' | 'Content Calendar'}
  final Map<String, dynamic>? focus;

  /// Top-bar search text — filters the client cards by client name.
  final String searchQuery;

  const EmployeeWorkspacePage({
    super.key,
    required this.role,
    required this.allowedPages,
    this.initialSection,
    this.onNavigate,
    this.focus,
    this.searchQuery = '',
  });

  @override
  State<EmployeeWorkspacePage> createState() => _EmployeeWorkspacePageState();
}

class _EmployeeWorkspacePageState extends State<EmployeeWorkspacePage> {
  _WorkspaceClient? _selectedClient;
  // Client whose previous / current cards are open (key = _clientKey(name)).
  String? _openGroup;
  Map<String, dynamic>? _pendingFocus;
  String? _focusSection;
  int _focusStamp = 0;

  @override
  void initState() {
    super.initState();
    _pendingFocus = widget.focus;
  }

  @override
  void didUpdateWidget(covariant EmployeeWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focus != null && !identical(widget.focus, oldWidget.focus)) {
      // Go back to the card list; it reloads and opens the requested card.
      setState(() {
        _pendingFocus = widget.focus;
        _selectedClient = null;
        _focusStamp++;
      });
    }
  }

  /// Pick the card for a pending focus request once the cards are loaded.
  /// An additional task lives inside its client's existing card, so a focus
  /// on an additional task's own date opens that card on "Additional Tasks".
  void _applyFocus(List<_WorkspaceClient> clients) {
    final focus = _pendingFocus;
    if (focus == null) return;
    final name = _clientKey('${focus['client'] ?? ''}');
    final due = '${focus['due_date'] ?? ''}';
    final sameClient = clients
        .where((c) => _clientKey(c.name) == name)
        .toList();
    if (sameClient.isEmpty) {
      _pendingFocus = null;
      return;
    }
    bool viaExtra(_WorkspaceClient c) =>
        due.isNotEmpty &&
        c.additionalDates.any((x) => _dateKey(x) == _dateKey(due));
    final match = sameClient.firstWhere(
      (c) =>
          due.isNotEmpty &&
          (_dateKey(c.submissionDate) == _dateKey(due) || viaExtra(c)),
      orElse: () => sameClient.first,
    );
    setState(() {
      _selectedClient = match;
      _openGroup = _clientKey(match.name);
      _focusSection = viaExtra(match)
          ? 'Additional Tasks'
          : '${focus['section'] ?? 'My Tasks'}';
      _pendingFocus = null;
    });
  }

  /// 'Page Handler' / 'Ads Handler' when the Tasks Assign screen names this
  /// employee as such for the client (or they prepare its calendar), else null.
  String? _handlerRoleFor(_WorkspaceClient client) {
    for (final t in client.tasks) {
      if (t.role == 'Ads Handler') return 'Ads Handler';
    }
    for (final t in client.tasks) {
      if (t.role == 'Page Handler' || t.role == 'Content Calendar') {
        return 'Page Handler';
      }
    }
    return null;
  }

  List<_WorkspaceSection> _clientSections(_WorkspaceClient client) {
    final pages = widget.allowedPages.toSet();
    final sections = <_WorkspaceSection>[
      _WorkspaceSection('My Tasks', Icons.task_alt_rounded),
    ];
    if (pages.contains('Additional Task') ||
        client.additionalDates.isNotEmpty) {
      sections.add(
        _WorkspaceSection('Additional Tasks', Icons.add_task_rounded),
      );
    }
    // The Content Calendar belongs to the client's assignment (Tasks Assign):
    // it shows when this employee is the Page / Ads Handler for THIS client,
    // whatever their job role is.
    final canSeeContentCalendar = _handlerRoleFor(client) != null;
    if (canSeeContentCalendar) {
      sections.add(
        _WorkspaceSection('Content Calendar', Icons.event_note_rounded),
      );
    }

    // Completed rows move here until a manager approves / asks for rework.
    sections.add(_WorkspaceSection('Task Review', Icons.fact_check_rounded));
    if (pages.contains('Chat') || pages.contains('Notifications')) {
      sections.add(_WorkspaceSection('Team Chat', Icons.forum_rounded));
    }
    sections.add(_WorkspaceSection('Live Tracking', Icons.timer_rounded));
    return sections;
  }

  String _dateKey(String value) {
    final parsed = DateTime.tryParse(value.trim());
    if (parsed == null) return value.trim().toLowerCase();
    return '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
  }

  bool get _isHandler =>
      widget.role == EmployeeRole.pageHandler ||
      widget.role == EmployeeRole.adsHandler;

  /// "Add Additional Task" → form → open the new card on My Tasks.
  Future<void> _openAddTask(
    String employeeName,
    String token, {
    String? client,
  }) async {
    final created = await AdditionalTaskDialog.show(
      context,
      employeeName: employeeName,
      token: token,
      initialClient: client,
    );
    if (!mounted || created == null) return;
    setState(() {
      _pendingFocus = {
        'client': created['client'],
        'due_date': created['due_date'],
        'section': 'Additional Tasks',
      };
      _selectedClient = null;
      _focusStamp++; // reload the cards, then open the new one
    });
  }

  int _initialClientSectionIndex(List<_WorkspaceSection> sections) {
    final requested = _focusSection ?? widget.initialSection;
    final requestedIndex = sections.indexWhere(
      (section) => section.title == requested,
    );
    if (requestedIndex >= 0) return requestedIndex;
    final tasksIndex = sections.indexWhere(
      (section) => section.title == 'My Tasks',
    );
    return tasksIndex < 0 ? 0 : tasksIndex;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    final employeeName =
        (user?['fullName'] ?? user?['full_name'] ?? user?['name'] ?? '')
            .toString()
            .trim();
    final employeeId = int.tryParse((user?['id'] ?? '').toString()) ?? 0;
    final rawRole = (auth.userRole ?? widget.role.title).trim();

    return PremiumTheme.wrap(
      context,
      Container(
        color: const Color(0xFFF4F7FC),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selectedClient == null &&
                MediaQuery.sizeOf(context).width >= 600)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: _WorkspaceHeader(
                  employeeName: employeeName,
                  role: widget.role.title,
                  // Page / Ads Handlers can add their own additional task.
                  onAddTask: _isHandler
                      ? () => _openAddTask(employeeName, auth.token ?? '')
                      : null,
                ),
              ),
            Expanded(
              child: _selectedClient == null
                  ? _ClientWorkspace(
                      key: ValueKey('client-cards-$_focusStamp'),
                      employeeName: employeeName,
                      role: widget.role,
                      mobileHeader: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: _WorkspaceHeader(
                          employeeName: employeeName,
                          role: widget.role.title,
                          onAddTask: _isHandler
                              ? () =>
                                    _openAddTask(employeeName, auth.token ?? '')
                              : null,
                        ),
                      ),
                      // Page/Ads handlers must load their assigned clients just
                      // like the reference Client sidebar, even if the standalone
                      // Assigned Task page is not enabled for their account.
                      // Every role sees the tasks the admin assigned to them
                      // (developer, UI/UX … included), not only handlers.
                      showAssignedTasks: true,
                      showAdditionalTasks: widget.allowedPages.contains(
                        'Additional Task',
                      ),
                      searchQuery: widget.searchQuery,
                      onClientsLoaded: (clients) {
                        if (_pendingFocus != null) {
                          _applyFocus(clients);
                          return;
                        }
                        final selectedClient = _selectedClient;
                        if (selectedClient == null) return;
                        for (final client in clients) {
                          if (client.name.toLowerCase() ==
                                  selectedClient.name.toLowerCase() &&
                              _dateKey(client.submissionDate) ==
                                  _dateKey(selectedClient.submissionDate)) {
                            setState(() => _selectedClient = client);
                            break;
                          }
                        }
                      },
                      openGroup: _openGroup,
                      onOpenGroup: (key) => setState(() => _openGroup = key),
                      onSelectClient: (client) {
                        setState(() {
                          _focusSection = null;
                          _selectedClient = client;
                        });
                      },
                    )
                  : _buildClientWorkspace(
                      employeeName,
                      employeeId,
                      auth.token ?? '',
                      rawRole,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientWorkspace(
    String employeeName,
    int employeeId,
    String authToken,
    String rawRole,
  ) {
    final client = _selectedClient!;
    final sections = _clientSections(client);
    if (sections.isEmpty) {
      return Center(
        child: _ClientContextHeader(
          client: client,
          role: widget.role.title,
          employeeName: employeeName,
          onBack: () => setState(() => _selectedClient = null),
        ),
      );
    }

    return DefaultTabController(
      key: ValueKey(
        '${client.name}:${client.submissionDate}:${sections.map((item) => item.title).join()}:${_focusSection ?? ''}',
      ),
      length: sections.length,
      initialIndex: _initialClientSectionIndex(sections),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 10),
            child: _ClientContextHeader(
              client: client,
              role: widget.role.title,
              employeeName: employeeName,
              onBack: () => setState(() => _selectedClient = null),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: _CountedTabBar(
                key: ValueKey(
                  'tabs-${client.name}-${client.submissionDate}-${client.additionalDates.join()}',
                ),
                sections: sections,
                clientName: client.name,
                submissionDate: client.submissionDate,
                extraDates: client.additionalDates,
                additionalOpen: client.additionalOpen,
                additionalOpenSameDate: client.additionalSameDateOpen,
                employeeName: employeeName,
                authToken: authToken,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TabBarView(
              children: [
                for (final section in sections)
                  _WorkspaceTabKeepAlive(
                    child: _buildClientSection(
                      section,
                      client,
                      employeeName,
                      employeeId,
                      authToken,
                      rawRole,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientSection(
    _WorkspaceSection section,
    _WorkspaceClient client,
    String employeeName,
    int employeeId,
    String authToken,
    String rawRole,
  ) {
    switch (section.title) {
      case 'My Tasks':
        return WorkspaceMyTasksSection(
          key: ValueKey('my-tasks-${client.name}-${client.submissionDate}'),
          // Additional work lives in its own tab (except on a card that only
          // has additional work).
          view: client.additionalOnly ? null : 'main',
          clientName: client.name,
          submissionDate: client.submissionDate,
          employeeName: employeeName,
          authToken: authToken,
          onOpenDayPlanner: widget.onNavigate == null
              ? null
              : () => widget.onNavigate!('Day Planner'),
        );
      case 'Additional Tasks':
        // No additional task attached to this card → plain list.
        if (client.additionalDates.isEmpty) {
          return _ClientTasksSection(
            client: client,
            includeAdditional: true,
            title: 'Additional tasks',
          );
        }
        // Each additional task keeps its own submit date: its work is loaded
        // (and later reviewed) by that date, never with the whole card.
        return _DateSwitcher(
          key: ValueKey('add-${client.name}-${client.additionalDates.join()}'),
          entries: [
            for (final d in client.additionalDates)
              (label: 'Additional · ${_formatDate(d)}', date: d),
          ],
          builder: (date) => WorkspaceMyTasksSection(
            key: ValueKey('add-tasks-${client.name}-$date'),
            view: 'additional',
            clientName: client.name,
            submissionDate: date,
            employeeName: employeeName,
            authToken: authToken,
            onOpenDayPlanner: widget.onNavigate == null
                ? null
                : () => widget.onNavigate!('Day Planner'),
          ),
        );
      case 'Content Calendar':
        return ContentCalendarScreen(
          key: ValueKey(client.name),
          apiBaseUrl: ApiConfig.baseUrl,
          authToken: authToken,
          currentUserId: employeeId,
          currentUserName: employeeName,
          currentUserRole: _handlerRoleFor(client) ?? rawRole,
          viaAssignment: true,
          initialClient: {
            'client_name': client.name,
            'submission_date': client.submissionDate,
          },
          myTasksMode: true,
        );
      case 'Task Review':
        if (client.additionalDates.isEmpty) {
          return WorkspaceTaskReviewSection(
            key: ValueKey(
              'task-review-${client.name}-${client.submissionDate}',
            ),
            clientName: client.name,
            submissionDate: client.submissionDate,
            employeeName: employeeName,
            authToken: authToken,
          );
        }
        // Main work and each additional task are reviewed separately.
        return _DateSwitcher(
          key: ValueKey('rev-${client.name}-${client.additionalDates.join()}'),
          entries: [
            (
              label: 'Main · ${_formatDate(client.submissionDate)}',
              date: client.submissionDate,
            ),
            for (final d in client.additionalDates)
              if (_dayKey(d) != _dayKey(client.submissionDate))
                (label: 'Additional · ${_formatDate(d)}', date: d),
          ],
          builder: (date) => WorkspaceTaskReviewSection(
            key: ValueKey('task-review-${client.name}-$date'),
            clientName: client.name,
            submissionDate: date,
            employeeName: employeeName,
            authToken: authToken,
          ),
        );
      case 'Team Chat':
        return _WorkspaceTeamChat(
          key: ValueKey('chat-${client.name}'),
          employeeName: employeeName,
          clientName: client.name,
        );
      case 'Live Tracking':
        return _ClientLiveTrackingSection(
          client: client,
          employeeName: employeeName,
          authToken: authToken,
        );
      default:
        return const Center(
          child: Text('This client workspace section is unavailable.'),
        );
    }
  }
}

/// Chips that switch the date a section (Additional Tasks / Task Review)
/// loads its data for.
class _DateSwitcher extends StatefulWidget {
  final List<({String label, String date})> entries;
  final Widget Function(String date) builder;

  const _DateSwitcher({
    super.key,
    required this.entries,
    required this.builder,
  });

  @override
  State<_DateSwitcher> createState() => _DateSwitcherState();
}

class _DateSwitcherState extends State<_DateSwitcher> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final i = _i.clamp(0, widget.entries.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.entries.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (var k = 0; k < widget.entries.length; k++)
                  ChoiceChip(
                    label: Text(widget.entries[k].label),
                    selected: k == i,
                    onSelected: (_) => setState(() => _i = k),
                  ),
              ],
            ),
          ),
        Expanded(child: widget.builder(widget.entries[i].date)),
      ],
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  final String employeeName;
  final String role;
  final VoidCallback? onAddTask;

  const _WorkspaceHeader({
    required this.employeeName,
    required this.role,
    this.onAddTask,
  });

  Widget _addButton(bool compact) {
    return FilledButton.icon(
      onPressed: onAddTask,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0B4CB0),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      icon: const Icon(Icons.add_task_rounded, size: 18),
      label: const Text(
        'Add Additional Task',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        return Container(
          padding: EdgeInsets.all(compact ? 18 : 24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF062B67), Color(0xFF1769D2)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1769D2).withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employeeName.isEmpty
                          ? 'Employee Workspace'
                          : 'Welcome, $employeeName',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 20 : 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Your assigned clients, tasks, calendar and team workspace.',
                      style: TextStyle(color: Color(0xFFDCEBFF), fontSize: 13),
                    ),
                    if (onAddTask != null && compact) ...[
                      const SizedBox(height: 12),
                      _addButton(true),
                    ],
                  ],
                ),
              ),
              if (onAddTask != null && !compact) ...[
                const SizedBox(width: 12),
                _addButton(false),
              ],
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  role,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Workspace tabs with live count badges:
///   My Tasks         → rows still to do (tooltip lists the categories)
///   Additional Tasks → pending rows of the additional tasks on this card
///   Task Review      → team work waiting for this Ads / Page Handler's decision
///                      (main work + additional tasks)
class _CountedTabBar extends StatefulWidget {
  final List<_WorkspaceSection> sections;
  final String clientName;
  final String submissionDate;
  // Own submit dates of additional tasks attached to this card.
  final List<String> extraDates;
  // Open additional rows (all dates) and the part sharing the card's own date.
  final int additionalOpen;
  final int additionalOpenSameDate;
  final String employeeName;
  final String authToken;

  const _CountedTabBar({
    super.key,
    required this.sections,
    required this.clientName,
    required this.submissionDate,
    this.extraDates = const [],
    this.additionalOpen = 0,
    this.additionalOpenSameDate = 0,
    required this.employeeName,
    required this.authToken,
  });

  @override
  State<_CountedTabBar> createState() => _CountedTabBarState();
}

class _CountedTabBarState extends State<_CountedTabBar> {
  int _myPending = 0;
  String _myTooltip = '';
  int _toReview = 0;
  io.Socket? _socket;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _socket = io.io(
      ApiConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuthFn(authenticateSocket)
          .enableForceNew()
          .disableAutoConnect()
          .build(),
    )..connect();
    void refresh(dynamic _) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        if (mounted) _load();
      });
    }

    _socket!
      ..on('task_updated', refresh)
      ..on('calendar:assigned', refresh);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _socket?.dispose();
    super.dispose();
  }

  int _n(dynamic v) => int.tryParse('${v ?? 0}') ?? 0;

  Future<Map?> _counts(String raw) async {
    final date = raw.length >= 10 ? raw.substring(0, 10) : raw;
    final uri = Uri.parse('${ApiConfig.baseUrl}/workspace-tasks/counts').replace(
      queryParameters: {
        'employee': widget.employeeName,
        'client': widget.clientName,
        'date': date,
      },
    );
    final res = await http.get(
      uri,
      headers: {
        if (widget.authToken.isNotEmpty)
          'Authorization': 'Bearer ${widget.authToken}',
      },
    );
    if (res.statusCode != 200) return null;
    return jsonDecode(res.body)['data'] as Map?;
  }

  Future<void> _load() async {
    try {
      final main = await _counts(widget.submissionDate);
      if (main == null || !mounted) return;
      final my = main['my_tasks'] as Map? ?? {};
      var toReview = _n((main['review'] as Map?)?['to_review']);
      for (final d in widget.extraDates) {
        // Same date as the card is already inside the main counts.
        if (_dayKey(d) == _dayKey(widget.submissionDate)) continue;
        final data = await _counts(d);
        if (data == null) continue;
        toReview += _n((data['review'] as Map?)?['to_review']);
      }
      if (!mounted) return;
      final categories = (my['by_category'] as List? ?? [])
          .whereType<Map>()
          .map((c) => '${c['name']}: ${c['pending']}')
          .join('\n');
      setState(() {
        _myPending = _n(my['pending']);
        _myTooltip = categories;
        _toReview = toReview;
      });
    } catch (_) {
      // Badges are optional — keep the last values on a network hiccup.
    }
  }

  Widget _tab(_WorkspaceSection section) {
    final count = switch (section.title) {
      'My Tasks' =>
        _myPending > widget.additionalOpenSameDate
            ? _myPending - widget.additionalOpenSameDate
            : 0,
      'Additional Tasks' => widget.additionalOpen,
      'Task Review' => _toReview,
      _ => 0,
    };
    Widget icon = Icon(section.icon, size: 17);
    if (count > 0) {
      icon = Badge(
        label: Text('$count'),
        backgroundColor: const Color(0xFFDC2626),
        child: icon,
      );
    }
    final tab = Tab(icon: icon, text: section.title);
    final tip = section.title == 'My Tasks' && _myTooltip.isNotEmpty
        ? 'Pending in My Tasks\n$_myTooltip'
        : section.title == 'Task Review' && _toReview > 0
        ? '$_toReview team task(s) waiting for your review'
        : null;
    return tip == null ? tab : Tooltip(message: tip, child: tab);
  }

  @override
  Widget build(BuildContext context) {
    return TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelColor: const Color(0xFF1456C0),
      unselectedLabelColor: const Color(0xFF64748B),
      indicatorColor: const Color(0xFF1456C0),
      tabs: [for (final section in widget.sections) _tab(section)],
    );
  }
}

class _WorkspaceSection {
  final String title;
  final IconData icon;

  const _WorkspaceSection(this.title, this.icon);
}

class _WorkspaceTabKeepAlive extends StatefulWidget {
  final Widget child;

  const _WorkspaceTabKeepAlive({required this.child});

  @override
  State<_WorkspaceTabKeepAlive> createState() => _WorkspaceTabKeepAliveState();
}

class _WorkspaceTabKeepAliveState extends State<_WorkspaceTabKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _ClientContextHeader extends StatefulWidget {
  final _WorkspaceClient client;
  final String role;
  final String employeeName;
  final VoidCallback onBack;

  const _ClientContextHeader({
    required this.client,
    required this.role,
    required this.employeeName,
    required this.onBack,
  });

  @override
  State<_ClientContextHeader> createState() => _ClientContextHeaderState();
}

class _ClientContextHeaderState extends State<_ClientContextHeader> {
  // Remembered while the app is open, so the choice sticks between clients.
  static bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final toggle = TextButton.icon(
      onPressed: () => setState(() => _collapsed = !_collapsed),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF1456C0),
        backgroundColor: const Color(0xFFEFF5FF),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      icon: Icon(
        _collapsed ? Icons.unfold_more_rounded : Icons.unfold_less_rounded,
        size: 17,
      ),
      label: Text(
        _collapsed ? 'Show details' : 'Hide details',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
    final back = TextButton.icon(
      onPressed: widget.onBack,
      icon: const Icon(Icons.arrow_back_rounded, size: 17),
      label: const Text('All clients'),
    );

    if (_collapsed) {
      // Hidden: only the way back (+ the toggle to open it again).
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(children: [back, const Spacer(), toggle]),
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      back,
                      Text(
                        client.name,
                        style: const TextStyle(
                          color: Color(0xFF14213D),
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF2FF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${widget.role} workspace',
                          style: const TextStyle(
                            color: Color(0xFF1456C0),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                toggle,
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (widget.employeeName.isNotEmpty)
                  'Welcome, ${widget.employeeName}',
                'Client workspace',
                'Submit date: ${_formatDate(client.submissionDate)}',
              ].join(' · '),
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
            const SizedBox(height: 14),
            _ClientStatTiles(client: client),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${client.progress}% approved',
                  style: const TextStyle(
                    color: Color(0xFF1456C0),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: client.progress / 100,
                      minHeight: 7,
                      backgroundColor: const Color(0xFFE8EEF8),
                      color: const Color(0xFF1A68D1),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tasks · Pending · Overdue · In review · Rework — used on the client card
/// and in the opened client header.
class _ClientStatTiles extends StatelessWidget {
  final _WorkspaceClient client;
  final bool compact;

  const _ClientStatTiles({required this.client, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final items = <(String, int, Color)>[
      ('Tasks', client.totalRows, const Color(0xFF0757D5)),
      ('Pending', client.pending, const Color(0xFF475569)),
      ('Overdue', client.overdue, const Color(0xFFDC2626)),
      ('In review', client.inReview, const Color(0xFF7C3AED)),
      ('Rework', client.rework, const Color(0xFFC2410C)),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = compact || constraints.maxWidth >= 300 ? 5 : 3;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: compact ? 6 : 8,
            mainAxisSpacing: compact ? 6 : 8,
            mainAxisExtent: compact ? 50 : 58,
          ),
          itemBuilder: (context, index) {
            final (label, value, color) = items[index];
            final highlight =
                value > 0 && label != 'Tasks' && label != 'Pending';
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: highlight
                    ? color.withValues(alpha: 0.07)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: highlight
                      ? color.withValues(alpha: 0.35)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$value',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: compact ? 15 : 16,
                      color: highlight || label == 'Tasks'
                          ? color
                          : const Color(0xFF14213D),
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 9.5 : 10,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ClientTasksSection extends StatelessWidget {
  final _WorkspaceClient? client;
  final bool includeAdditional;
  final bool reviewOnly;
  final String title;

  const _ClientTasksSection({
    required this.client,
    required this.title,
    this.includeAdditional = false,
    this.reviewOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    if (client == null) {
      return const Center(
        child: Text(
          'Open a client card to view its assigned tasks.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      );
    }

    final tasks = client!.tasks.where((task) {
      if (reviewOnly) {
        return task.status == _WorkspaceTaskStatus.inReview ||
            task.status == _WorkspaceTaskStatus.onHold;
      }
      return task.isAdditional == includeAdditional;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF14213D),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        if (tasks.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              reviewOnly
                  ? 'No tasks are waiting for review or rework.'
                  : 'No ${includeAdditional ? 'additional ' : ''}tasks are assigned for this client.',
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          )
        else
          for (final task in tasks) _WorkspaceTaskTile(task: task),
      ],
    );
  }
}

class _WorkspaceTaskTile extends StatelessWidget {
  final _WorkspaceTask task;

  const _WorkspaceTaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(task.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.task_alt_rounded, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF14213D),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${task.role} · ${task.completedCount}/${task.total} complete',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _statusLabel(task.status),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientLiveTrackingSection extends StatefulWidget {
  final _WorkspaceClient client;
  final String employeeName;
  final String authToken;

  const _ClientLiveTrackingSection({
    required this.client,
    required this.employeeName,
    required this.authToken,
  });

  @override
  State<_ClientLiveTrackingSection> createState() =>
      _ClientLiveTrackingSectionState();
}

class _ClientLiveTrackingSectionState
    extends State<_ClientLiveTrackingSection> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  Timer? _ticker;
  Timer? _refreshDebounce;
  io.Socket? _socket;

  @override
  void initState() {
    super.initState();
    _load();
    // Running timers (tasks and Content Calendar categories) tick every second.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      var changed = false;
      for (final row in _rows) {
        if (row['running'] == true) {
          row['duration_secs'] =
              (int.tryParse('${row['duration_secs'] ?? 0}') ?? 0) + 1;
          changed = true;
        }
      }
      if (changed) setState(() {});
    });
    _socket = io.io(
      ApiConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuthFn(authenticateSocket)
          .enableForceNew()
          .disableAutoConnect()
          .build(),
    )..connect();
    _socket!.on('task_updated', (_) {
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted) _load(silent: true);
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _refreshDebounce?.cancel();
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final date = widget.client.submissionDate.length >= 10
          ? widget.client.submissionDate.substring(0, 10)
          : widget.client.submissionDate;
      final uri = Uri.parse('${ApiConfig.baseUrl}/workspace-tasks/live')
          .replace(
            queryParameters: {
              'employee': widget.employeeName,
              'client': widget.client.name,
              'date': date,
            },
          );
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (widget.authToken.isNotEmpty)
            'Authorization': 'Bearer ${widget.authToken}',
        },
      );
      if (response.statusCode != 200)
        throw Exception('Request failed (${response.statusCode})');
      final decoded = jsonDecode(response.body);
      final rows = decoded is Map && decoded['data'] is List
          ? (decoded['data'] as List)
                .whereType<Map>()
                .map((r) => Map<String, dynamic>.from(r))
                .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = 'Unable to load live tracking: $e';
        _loading = false;
      });
    }
  }

  String _duration(dynamic value) {
    final seconds = int.tryParse((value ?? 0).toString()) ?? 0;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(seconds ~/ 3600)}:${two((seconds % 3600) ~/ 60)}:${two(seconds % 60)}';
  }

  String _time(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty || raw == 'null') return '—';
    final parsed = DateTime.tryParse(raw);
    return parsed == null
        ? raw
        : DateFormat('dd MMM, hh:mm a').format(parsed.toLocal());
  }

  final Set<String> _busy = {};

  Map<String, String> get _jsonHeaders => {
    'Content-Type': 'application/json',
    if (widget.authToken.isNotEmpty)
      'Authorization': 'Bearer ${widget.authToken}',
  };

  Future<String?> _askReason(String title, String hint) async {
    final controller = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Reason *',
                hintText: hint,
                errorText: error,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  setD(() => error = 'Reason is required');
                  return;
                }
                Navigator.pop(c, controller.text.trim());
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  /// Start / Hold / Complete / Restart from Live Tracking.
  Future<void> _act(Map<String, dynamic> row, String action) async {
    final key = '${row['key']}';
    if (_busy.contains(key)) return;
    final isCalendar = row['kind'] == 'CONTENT_CALENDAR';
    final body = <String, dynamic>{};
    if (action == 'hold') {
      final reason = await _askReason(
        'Hold ${row['title']}',
        'Why are you putting this on hold?',
      );
      if (reason == null) return;
      body['reason'] = reason;
    }
    if (action == 'complete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Complete ${row['title']}?'),
          content: Text(
            isCalendar
                ? 'The category is marked prepared. Assign it from the Content Calendar.'
                : 'It moves to Task Review and is completed once approved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Complete'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    late final Uri uri;
    if (isCalendar) {
      final sheetAction = action == 'restart' ? 'start' : action;
      uri = Uri.parse(
        '${ApiConfig.baseUrl}/tasks/content-calendar/sheet-$sheetAction',
      );
      body.addAll({
        'source_assignment_id': row['source_assignment_id'],
        'source_role': row['source_role'],
        'source_task_index': row['source_task_index'],
        if (sheetAction == 'start') 'day_planner_confirmed': true,
      });
    } else {
      uri = Uri.parse(
        '${ApiConfig.baseUrl}/tracking-items/${row['task_id']}/$action',
      );
    }
    setState(() => _busy.add(key));
    try {
      var res = await http.post(
        uri,
        headers: _jsonHeaders,
        body: jsonEncode(body),
      );
      if (res.statusCode == 409 &&
          res.body.contains('DAY_PLAN_CONFIRM_REQUIRED')) {
        if (!mounted || !await TaskActions.confirmDayPlan(context, res)) return;
        body['day_planner_confirmed'] = true;
        res = await http.post(
          uri,
          headers: _jsonHeaders,
          body: jsonEncode(body),
        );
      }
      if (res.statusCode == 409 &&
          res.body.contains('AUTO_HOLD_REASON_REQUIRED')) {
        String running = 'Your running task';
        try {
          final list = (jsonDecode(res.body)['running'] as List? ?? [])
              .whereType<Map>();
          if (list.isNotEmpty)
            running = list.map((r) => '${r['title']}').join(', ');
        } catch (_) {}
        final reason = await _askReason(
          'Put the running task on hold?',
          '$running will be held. Why?',
        );
        if (reason == null) return;
        res = await http.post(
          uri,
          headers: _jsonHeaders,
          body: jsonEncode({...body, 'auto_hold_reason': reason}),
        );
      }
      if (!mounted) return;
      if (res.statusCode != 200) {
        String msg = 'Unable to $action';
        try {
          msg = '${jsonDecode(res.body)['message'] ?? msg}';
        } catch (_) {}
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
      await _load(silent: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to $action. Check your connection.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Widget _actionButtons(Map<String, dynamic> row) {
    final status = '${row['status'] ?? ''}'.toUpperCase();
    final busy = _busy.contains('${row['key']}');
    Widget btn(String label, IconData icon, Color color, String action) =>
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color.withValues(alpha: 0.6)),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: busy ? null : () => _act(row, action),
            icon: Icon(icon, size: 15),
            label: Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
    const blue = Color(0xFF004AAD);
    const orange = Color(0xFFEA580C);
    const green = Color(0xFF16A34A);
    const amber = Color(0xFFB45309);
    final buttons = <Widget>[
      if (status == 'IDLE')
        btn('START', Icons.play_arrow_rounded, blue, 'start'),
      if (status == 'IN PROGRESS') ...[
        btn('HOLD', Icons.pause_rounded, orange, 'hold'),
        btn('COMPLETE', Icons.check_rounded, green, 'complete'),
      ],
      if (status == 'ON HOLD' || status == 'REWORK')
        btn('RESTART', Icons.replay_rounded, amber, 'restart'),
    ];
    return Row(mainAxisSize: MainAxisSize.min, children: buttons);
  }

  (String, Color, Color) _statusStyle(String status) => switch (status) {
    'IN PROGRESS' => (
      'IN PROGRESS',
      const Color(0xFFEFF6FF),
      const Color(0xFF004AAD),
    ),
    'ON HOLD' => ('ON HOLD', const Color(0xFFFEF3C7), const Color(0xFF92400E)),
    'COMPLETED' => (
      'PREPARED',
      const Color(0xFFEDE9FE),
      const Color(0xFF6D28D9),
    ),
    'IN REVIEW' => (
      'IN REVIEW',
      const Color(0xFFEDE9FE),
      const Color(0xFF6D28D9),
    ),
    'REWORK' => ('REWORK', const Color(0xFFFFEDD5), const Color(0xFFC2410C)),
    'APPROVED' => (
      'APPROVED',
      const Color(0xFFDCFCE7),
      const Color(0xFF15803D),
    ),
    'ASSIGNED' => (
      'ASSIGNED',
      const Color(0xFFDCFCE7),
      const Color(0xFF15803D),
    ),
    'REJECTED' => (
      'REJECTED',
      const Color(0xFFFEE2E2),
      const Color(0xFFB91C1C),
    ),
    _ => (
      status.isEmpty ? 'IDLE' : status,
      const Color(0xFFF1F5F9),
      const Color(0xFF64748B),
    ),
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nothing is being tracked for this client yet. Start a task in My Tasks or a category in Content Calendar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B)),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final row = _rows[i];
          final isCalendar = row['kind'] == 'CONTENT_CALENDAR';
          final (label, bg, fg) = _statusStyle(
            '${row['status'] ?? ''}'.toUpperCase(),
          );
          final running = row['running'] == true;
          final holdReason = '${row['hold_reason'] ?? ''}'.trim();
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: running
                    ? const Color(0xFF93C5FD)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isCalendar
                        ? const Color(0xFFEAF2FF)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isCalendar
                        ? Icons.calendar_month_rounded
                        : Icons.task_alt_rounded,
                    size: 20,
                    color: isCalendar
                        ? const Color(0xFF004AAD)
                        : const Color(0xFF334155),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row['title'] ?? ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if ('${row['heading'] ?? ''}'.trim().isNotEmpty)
                            '${row['heading']}',
                          if (isCalendar)
                            'Last activity ${_time(row['last_activity_at'])}'
                          else
                            'Started ${_time(row['started_at'])}',
                          if (holdReason.isNotEmpty &&
                              row['status'] == 'ON HOLD')
                            'Hold: $holdReason',
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _duration(row['duration_secs']),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: running
                        ? const Color(0xFF004AAD)
                        : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                ),
                _actionButtons(row),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Team Chat inside a client workspace:
///   • "<CLIENT> group" — everyone assigned on this client
///   • one-to-one chat with a team member (only people on this client)
class _WorkspaceTeamChat extends StatefulWidget {
  final String employeeName;
  final String clientName;
  final String? initialTarget;

  const _WorkspaceTeamChat({
    super.key,
    required this.employeeName,
    required this.clientName,
    this.initialTarget,
  });

  @override
  State<_WorkspaceTeamChat> createState() => _WorkspaceTeamChatState();
}

class _WorkspaceTeamChatState extends State<_WorkspaceTeamChat> {
  static const _group = '__group__';
  final TextEditingController _messageController = TextEditingController();
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _groupMessages = [];
  List<Map<String, dynamic>> _directMessages = [];
  String _selected = _group;
  String? _error;
  bool _loading = true;
  bool _sending = false;
  io.Socket? _socket;

  bool _same(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    if (widget.initialTarget != null &&
        widget.initialTarget!.trim().isNotEmpty) {
      _selected = widget.initialTarget!.trim();
    }
    _loadAll();
    _socket = io.io(
      ApiConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuthFn(authenticateSocket)
          .enableForceNew()
          .disableAutoConnect()
          .build(),
    )..connect();
    _socket!
      ..on('workspace_client_chat', (data) {
        final client = data is Map ? '${data['client'] ?? ''}' : '';
        if (client.isEmpty || _same(client, widget.clientName)) _loadGroup();
      })
      ..on('receive_message', (_) => _loadDirect())
      ..on('messages_seen', (_) => _loadDirect());
  }

  @override
  void dispose() {
    _socket?.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/workspace-tasks/team',
        ).replace(queryParameters: {'client': widget.clientName}),
      );
      if (res.statusCode != 200)
        throw Exception('Request failed (${res.statusCode})');
      final members =
          ((jsonDecode(res.body)['data'] as Map?)?['members'] as List? ?? [])
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .where((m) => !_same('${m['name']}', widget.employeeName))
              .toList();
      if (!mounted) return;
      setState(() => _members = members);
      await Future.wait([_loadGroup(), _loadDirect()]);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load team chat: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadGroup() async {
    try {
      final res = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/workspace-tasks/team/chat',
        ).replace(queryParameters: {'client': widget.clientName}),
      );
      if (res.statusCode != 200 || !mounted) return;
      setState(() {
        _groupMessages = (jsonDecode(res.body)['data'] as List? ?? [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _loadDirect() async {
    try {
      final res = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/chat/${Uri.encodeComponent(widget.employeeName)}',
        ),
      );
      if (res.statusCode != 200 || !mounted) return;
      final body = jsonDecode(res.body);
      setState(() {
        _directMessages = (body is Map ? body['data'] as List? ?? [] : [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .where((m) => !_chatIsGroup(m['isGroup']))
            .toList();
      });
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _conversation {
    if (_selected == _group) {
      // Newest first, like the one-to-one chat feed.
      return [
        for (final m in _groupMessages.reversed)
          {
            'senderName': m['sender_name'],
            'message': m['message'],
            'time': m['created_at'],
          },
      ];
    }
    return _directMessages.where((m) {
      final sender = '${m['senderName'] ?? ''}';
      final target = '${m['recipientName'] ?? ''}';
      return (_same(sender, widget.employeeName) && _same(target, _selected)) ||
          (_same(sender, _selected) && _same(target, widget.employeeName));
    }).toList();
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final http.Response res;
      if (_selected == _group) {
        res = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/workspace-tasks/team/chat'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'client': widget.clientName,
            'employee': widget.employeeName,
            'message': text,
          }),
        );
      } else {
        res = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/chat/send'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'senderName': widget.employeeName,
            'recipientName': _selected,
            'isGroup': 0,
            'message': text,
          }),
        );
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        String msg = 'Message could not be sent (${res.statusCode})';
        try {
          msg = '${jsonDecode(res.body)['message'] ?? msg}';
        } catch (_) {}
        throw Exception(msg);
      }
      _messageController.clear();
      await (_selected == _group ? _loadGroup() : _loadDirect());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _time(dynamic value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    if (parsed == null) return '${value ?? ''}';
    return DateFormat('dd MMM, hh:mm a').format(parsed.toLocal());
  }

  Widget _contact(String id, String title, String subtitle, IconData icon) {
    final selected = _selected == id;
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: const Color(0xFFEAF2FF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: selected
            ? const Color(0xFF1456C0)
            : const Color(0xFFEAF2FF),
        foregroundColor: selected ? Colors.white : const Color(0xFF1456C0),
        child: Icon(icon, size: 16),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      onTap: () => setState(() => _selected = id),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    final conversation = _conversation;
    final isGroup = _selected == _group;
    final contacts = Container(
      width: 260,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          _contact(
            _group,
            '${widget.clientName} group',
            '${_members.length + 1} members',
            Icons.groups_rounded,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 10, 10, 4),
            child: Text(
              'TEAM ON THIS CLIENT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF64748B),
                letterSpacing: 0.6,
              ),
            ),
          ),
          if (_members.isEmpty)
            const Padding(
              padding: EdgeInsets.all(10),
              child: Text(
                'No other employees are assigned to this client.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
            ),
          for (final m in _members)
            _contact(
              '${m['name']}',
              '${m['name']}',
              ((m['roles'] as List?) ?? []).join(', '),
              Icons.person_rounded,
            ),
        ],
      ),
    );

    final chat = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            isGroup ? '${widget.clientName} group' : _selected,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF14213D),
            ),
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: conversation.isEmpty
                ? Center(
                    child: Text(
                      isGroup
                          ? 'Say hello to the ${widget.clientName} team.'
                          : 'Start a conversation.',
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: conversation.length,
                    itemBuilder: (context, index) {
                      final message = conversation[index];
                      final sender = '${message['senderName'] ?? ''}';
                      final isMine = _same(sender, widget.employeeName);
                      return Align(
                        alignment: isMine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 520),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isMine
                                ? const Color(0xFFEAF2FF)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isGroup && !isMine)
                                Text(
                                  sender,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1456C0),
                                  ),
                                ),
                              Text(
                                '${message['message'] ?? ''}',
                                style: const TextStyle(
                                  color: Color(0xFF14213D),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _time(message['time']),
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: isGroup
                      ? 'Message the ${widget.clientName} team…'
                      : 'Write a message…',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send',
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  value: _selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Chat',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: _group,
                      child: Text('${widget.clientName} group'),
                    ),
                    for (final m in _members)
                      DropdownMenuItem(
                        value: '${m['name']}',
                        child: Text('${m['name']}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _selected = v ?? _group),
                ),
                const SizedBox(height: 10),
                Expanded(child: chat),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              contacts,
              const SizedBox(width: 14),
              Expanded(child: chat),
            ],
          );
        },
      ),
    );
  }
}

/// Same client whatever the spacing / punctuation / case.
String _clientKey(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

String _dayKey(String s) => s.length >= 10 ? s.substring(0, 10) : s;

bool _chatIsGroup(dynamic value) =>
    value == true || value == 1 || value?.toString() == '1';

/// One client = one card in the list. Opening it shows ONLY the current card
/// (nearest submit date today or later) and the previous card (latest before
/// today). Older cards are not shown.
class _ClientGroup {
  final String key;
  final String name;
  final _WorkspaceClient? previous;
  final _WorkspaceClient? current;

  const _ClientGroup(this.key, this.name, this.previous, this.current);

  _WorkspaceClient get head => current ?? previous!;

  List<(String, _WorkspaceClient)> get cards => [
    if (current != null) ('CURRENT', current!),
    if (previous != null) ('PREVIOUS', previous!),
  ];
}

/// The server puts additional work on the card of its own submit date. When
/// that card also holds normal work, pull the additional part out so it can
/// be shown in the card's Additional Tasks tab instead of My Tasks.
List<_WorkspaceClient> _splitSameDateCards(List<_WorkspaceClient> cards) {
  bool extra(_WorkspaceTask t) => t.isAdditional || t.handlerAssigned;
  final out = <_WorkspaceClient>[];
  for (final c in cards) {
    final add = c.tasks.where(extra).toList();
    final main = c.tasks.where((t) => !extra(t)).toList();
    if (add.isEmpty || main.isEmpty) {
      out.add(c);
      continue;
    }
    out.add(c.copyWithTasks(main));
    out.add(
      _WorkspaceClient(
        name: c.name,
        submissionDate: c.submissionDate,
        employeeRole: c.employeeRole,
        tasks: add,
        assignedAt: c.assignedAt,
        isAdditional: true,
        additionalBy: c.additionalBy,
        package: c.package,
        maintenanceDay: c.maintenanceDay,
      ),
    );
  }
  return out;
}

/// An additional task NEVER gets its own card. It joins the card of its own
/// submit date; otherwise the client's CURRENT card (nearest submit date today
/// or later), or the latest card when none is upcoming. Only a client with no
/// card at all keeps it standalone.
List<_WorkspaceClient> _attachAdditionalCards(List<_WorkspaceClient> cards) {
  final t = DateTime.now();
  final today = DateTime(t.year, t.month, t.day);
  DateTime d(_WorkspaceClient c) => c.dueDate ?? DateTime(2100);

  final hosts = cards.where((c) => !c.additionalOnly).toList();
  final extras = cards.where((c) => c.additionalOnly);
  final attached = <_WorkspaceClient, List<_WorkspaceClient>>{};
  final standalone = <_WorkspaceClient>[];

  for (final extra in extras) {
    final mine = hosts
        .where((h) => _clientKey(h.name) == _clientKey(extra.name))
        .toList();
    if (mine.isEmpty) {
      standalone.add(extra);
      continue;
    }
    final sameDay = mine
        .where((h) => _dayKey(h.submissionDate) == _dayKey(extra.submissionDate))
        .toList();
    _WorkspaceClient host;
    if (sameDay.isNotEmpty) {
      host = sameDay.first;
    } else {
      mine.sort((a, b) => d(a).compareTo(d(b)));
      final upcoming = mine.where((h) => !d(h).isBefore(today)).toList();
      host = upcoming.isNotEmpty ? upcoming.first : mine.last;
    }
    (attached[host] ??= []).add(extra);
  }
  return [
    for (final h in hosts)
      attached[h] == null ? h : h.withAdditional(attached[h]!),
    ...standalone,
  ];
}

List<_WorkspaceClient> _arrangeCards(List<_WorkspaceClient> cards) =>
    _attachAdditionalCards(_splitSameDateCards(cards));

class _WorkspaceClient {
  final String name;
  final String submissionDate;
  final EmployeeRole employeeRole;
  final List<_WorkspaceTask> tasks;
  // Team work on this client+date waiting for this Ads/Page Handler's review.
  final int toReview;
  // When the admin last assigned work on this card (drives the NEW ribbon).
  final DateTime? assignedAt;
  // Everyone assigned on this client: [{role, employee, tasks:[{name, completed, total}]}]
  final List<Map<String, dynamic>> team;
  // Work given by a Page / Ads Handler (Content Calendar) or an additional
  // task → "ADDITIONAL TASK" ribbon. e.g. ['VIJI (Page Handler)']
  final bool isAdditional;
  final List<String> additionalBy;
  // Own submit dates of additional tasks attached INSIDE this card (instead of
  // showing them as separate cards). Each date is used to load / review only
  // that additional task's work.
  final List<String> additionalDates;
  // Open rows of additional work that shares THIS card's own submit date.
  final int additionalSameDateOpen;
  // From Tasks Assign: the package and the monthly maintain day (e.g. '12').
  final String package;
  final String maintenanceDay;

  const _WorkspaceClient({
    required this.name,
    required this.submissionDate,
    required this.employeeRole,
    required this.tasks,
    this.toReview = 0,
    this.assignedAt,
    this.team = const [],
    this.isAdditional = false,
    this.additionalBy = const [],
    this.additionalDates = const [],
    this.additionalSameDateOpen = 0,
    this.package = '',
    this.maintenanceDay = '',
  });

  DateTime? get dueDate {
    final d = DateTime.tryParse(submissionDate);
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  /// A card that only holds additional / handler-assigned work.
  bool get additionalOnly =>
      tasks.isNotEmpty &&
      tasks.every((t) => t.isAdditional || t.handlerAssigned);

  /// Rows of the additional work on this card (for the card chip).
  int get additionalRows => tasks
      .where((t) => t.isAdditional || t.handlerAssigned)
      .fold(0, (s, t) => s + t.total);

  /// Additional rows still to do (drives the Additional Tasks tab badge).
  int get additionalOpen => tasks
      .where((t) => t.isAdditional || t.handlerAssigned)
      .fold(
        0,
        (s, t) =>
            s + t.pendingCount + t.inProgressCount + t.onHoldCount + t.reworkCount,
      );

  _WorkspaceClient copyWithTasks(List<_WorkspaceTask> newTasks) =>
      _WorkspaceClient(
        name: name,
        submissionDate: submissionDate,
        employeeRole: employeeRole,
        tasks: newTasks,
        toReview: toReview,
        assignedAt: assignedAt,
        team: team,
        package: package,
        maintenanceDay: maintenanceDay,
      );

  /// This card plus the additional-only cards attached to it.
  _WorkspaceClient withAdditional(List<_WorkspaceClient> extra) {
    final mergedTeam = team.map((m) => Map<String, dynamic>.from(m)).toList();
    for (final e in extra) {
      for (final m in e.team) {
        final i = mergedTeam.indexWhere(
          (x) =>
              '${x['employee']}'.toLowerCase() ==
              '${m['employee']}'.toLowerCase(),
        );
        if (i < 0) {
          mergedTeam.add(Map<String, dynamic>.from(m));
        } else {
          mergedTeam[i]['tasks'] = [
            ...(mergedTeam[i]['tasks'] as List? ?? []),
            ...(m['tasks'] as List? ?? []),
          ];
        }
      }
    }
    return _WorkspaceClient(
      name: name,
      submissionDate: submissionDate,
      employeeRole: employeeRole,
      tasks: [...tasks, ...extra.expand((e) => e.tasks)],
      toReview: toReview + extra.fold(0, (s, e) => s + e.toReview),
      assignedAt: assignedAt,
      team: mergedTeam,
      isAdditional: true,
      additionalBy: {
        ...additionalBy,
        ...extra.expand((e) => e.additionalBy),
      }.toList(),
      additionalDates: {...extra.map((e) => e.submissionDate)}.toList(),
      additionalSameDateOpen: extra
          .where((e) => _dayKey(e.submissionDate) == _dayKey(submissionDate))
          .fold(0, (s, e) => s + e.additionalOpen),
      package: package,
      maintenanceDay: maintenanceDay,
    );
  }

  bool get isCompleted => totalRows > 0 && completed >= totalRows;
  bool get hasOpenWork => pending + inProgress + onHold + rework + inReview > 0;

  /// Card ribbon, most urgent first.
  /// Submit date is today.
  bool get isDueToday {
    final d = dueDate;
    if (d == null) return false;
    final now = DateTime.now();
    return d == DateTime(now.year, now.month, now.day);
  }

  String? get ribbon {
    if (isCompleted) return 'COMPLETED';
    if (inProgress > 0) return 'PROCESSING';
    // Submit date today and still something to finish.
    if (isDueToday && pending + onHold + rework > 0) return 'CURRENT';
    if (onHold > 0) return 'HOLD';
    if (rework > 0) return 'REWORK';
    if (overdue > 0) return 'OVERDUE';
    if (inReview > 0) return 'IN REVIEW';
    final started = inProgress + onHold + inReview + completed + rework > 0;
    if (!started &&
        assignedAt != null &&
        DateTime.now().difference(assignedAt!).inDays < 3) {
      return 'NEW';
    }
    return null;
  }

  int _sum(int Function(_WorkspaceTask task) pick) =>
      tasks.fold(0, (sum, task) => sum + pick(task));

  int get totalRows => _sum((t) => t.total);
  int get pending => _sum((t) => t.pendingCount);
  int get inProgress => _sum((t) => t.inProgressCount);
  int get onHold => _sum((t) => t.onHoldCount);
  int get inReview => _sum((t) => t.inReviewCount);
  int get rework => _sum((t) => t.reworkCount);
  // Only manager-approved rows count as completed.
  int get completed => _sum((t) => t.completedCount);
  int get overdue {
    final date = DateTime.tryParse(submissionDate);
    if (date == null) return 0;
    final deadline = DateTime(date.year, date.month, date.day);
    final today = DateTime.now();
    if (!deadline.isBefore(DateTime(today.year, today.month, today.day))) {
      return 0;
    }
    return pending + inProgress + onHold + rework;
  }

  int get progress =>
      totalRows == 0 ? 0 : (completed * 100 / totalRows).round();
}

enum _WorkspaceTaskStatus {
  pending,
  inProgress,
  onHold,
  inReview,
  rework,
  completed,
}

class _WorkspaceTask {
  final String key;
  final String name;
  final String employee;
  final String role;
  final _WorkspaceTaskStatus status;
  final int total;
  final int completedCount;
  final int pendingCount;
  final int inProgressCount;
  final int onHoldCount;
  final int inReviewCount;
  final int reworkCount;
  final bool awaitingHandoff;
  final bool isAdditional;
  // Rows a Page / Ads Handler gave to this employee from the Content Calendar.
  final bool handlerAssigned;
  final String assignedBy;

  const _WorkspaceTask({
    required this.key,
    required this.name,
    required this.employee,
    required this.role,
    required this.status,
    this.total = 1,
    this.completedCount = 0,
    this.pendingCount = 0,
    this.inProgressCount = 0,
    this.onHoldCount = 0,
    this.inReviewCount = 0,
    this.reworkCount = 0,
    this.awaitingHandoff = false,
    this.isAdditional = false,
    this.handlerAssigned = false,
    this.assignedBy = '',
  });
}

class _ClientWorkspace extends StatefulWidget {
  // GODIGITAL_FULL_MOBILE_SCROLL_V2
  final Widget? mobileHeader;
  final String employeeName;
  final EmployeeRole role;
  final bool showAssignedTasks;
  final bool showAdditionalTasks;
  final ValueChanged<List<_WorkspaceClient>> onClientsLoaded;
  final ValueChanged<_WorkspaceClient> onSelectClient;
  final String? openGroup;
  final ValueChanged<String?> onOpenGroup;
  final String searchQuery;

  const _ClientWorkspace({
    super.key,
    this.mobileHeader,
    required this.employeeName,
    required this.role,
    required this.showAssignedTasks,
    required this.showAdditionalTasks,
    required this.onClientsLoaded,
    required this.onSelectClient,
    required this.openGroup,
    required this.onOpenGroup,
    this.searchQuery = '',
  });

  @override
  State<_ClientWorkspace> createState() => _ClientWorkspaceState();
}

class _ClientWorkspaceState extends State<_ClientWorkspace> {
  List<_WorkspaceClient> _clients = [];
  // Card filters
  String _sort = 'date_asc';
  String? _month; // 'yyyy-mm' or null = all months
  String _ribbonFilter = 'ALL';
  bool _showOlder = false;
  bool _loading = true;
  String? _error;
  io.Socket? _socket;

  @override
  void initState() {
    super.initState();
    if (widget.employeeName.isNotEmpty) {
      _loadClients();
      _initSocketListener();
    }
  }

  void _initSocketListener() {
    _socket = io.io(
      ApiConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuthFn(authenticateSocket)
          .enableForceNew()
          .disableAutoConnect()
          .build(),
    );
    _socket!
      ..connect()
      ..on('task_updated', (data) {
        if (mounted) _loadClients();
      })
      ..on('calendar:assigned', (_) {
        if (mounted) _loadClients();
      });
  }

  @override
  void didUpdateWidget(covariant _ClientWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employeeName != widget.employeeName &&
        widget.employeeName.isNotEmpty) {
      _socket?.dispose();
      _loadClients();
      _initSocketListener();
    }
  }

  @override
  void dispose() {
    _socket?.dispose();
    super.dispose();
  }

  // One card per client + submit date, built only from tasks where THIS
  // employee is the assigned person. Counts are per deadline (no carry-over
  // from other dates) and "complete" means manager-approved.
  Future<void> _loadClients() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/workspace-tasks/cards',
      ).replace(queryParameters: {'employee': widget.employeeName});
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Request failed (${response.statusCode})');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['data'] is! List) {
        throw const FormatException(
          'Unexpected response from the task service.',
        );
      }
      int n(dynamic v) => v is int ? v : int.tryParse('${v ?? 0}') ?? 0;

      final loadedClients = <_WorkspaceClient>[];
      for (final raw in (decoded['data'] as List).whereType<Map>()) {
        final card = Map<String, dynamic>.from(raw);
        final tasks = <_WorkspaceTask>[];
        for (final rawTask in (card['tasks'] as List? ?? []).whereType<Map>()) {
          final t = Map<String, dynamic>.from(rawTask);
          final isAdditional = t['is_additional'] == true;
          // Work a Page / Ads Handler gave this employee from the Content
          // Calendar always shows; admin-only additional tasks follow the
          // "Additional Task" page permission.
          if (isAdditional &&
              !widget.showAdditionalTasks &&
              t['handler_assigned'] != true) {
            continue;
          }
          if (!isAdditional && !widget.showAssignedTasks) continue;
          final counts = (
            total: n(t['total']),
            approved: n(t['approved']),
            pending: n(t['pending']),
            inProgress: n(t['in_progress']),
            onHold: n(t['on_hold']),
            inReview: n(t['in_review']),
            rework: n(t['rework']),
          );
          final status = counts.inProgress > 0
              ? _WorkspaceTaskStatus.inProgress
              : counts.rework > 0
              ? _WorkspaceTaskStatus.rework
              : counts.onHold > 0
              ? _WorkspaceTaskStatus.onHold
              : counts.inReview > 0
              ? _WorkspaceTaskStatus.inReview
              : (counts.total > 0 && counts.approved >= counts.total)
              ? _WorkspaceTaskStatus.completed
              : _WorkspaceTaskStatus.pending;
          tasks.add(
            _WorkspaceTask(
              key: '${t['key']}',
              name: '${t['name'] ?? ''}',
              employee: widget.employeeName,
              role: '${t['role'] ?? ''}',
              status: status,
              total: counts.total,
              completedCount: counts.approved,
              pendingCount: counts.pending,
              inProgressCount: counts.inProgress,
              onHoldCount: counts.onHold,
              inReviewCount: counts.inReview,
              reworkCount: counts.rework,
              awaitingHandoff: t['awaiting_handoff'] == true,
              isAdditional: isAdditional,
              handlerAssigned: t['handler_assigned'] == true,
              assignedBy: [
                '${t['assigned_by'] ?? ''}'.trim(),
                if ('${t['assigned_by_role'] ?? ''}'.trim().isNotEmpty)
                  '(${t['assigned_by_role']})',
              ].where((e) => e.isNotEmpty).join(' '),
            ),
          );
        }
        if (tasks.isEmpty) continue;
        tasks.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        loadedClients.add(
          _WorkspaceClient(
            name: '${card['client_name'] ?? ''}',
            submissionDate: '${card['submission_date'] ?? ''}',
            employeeRole: widget.role,
            tasks: tasks,
            toReview: n(card['to_review']),
            assignedAt: DateTime.tryParse(
              '${card['assigned_at'] ?? ''}',
            )?.toLocal(),
            package: '${card['package'] ?? ''}'.trim(),
            maintenanceDay: '${card['maintenance_day'] ?? ''}'.trim(),
            team: (card['team'] as List? ?? [])
                .whereType<Map>()
                .map((t) => Map<String, dynamic>.from(t))
                .toList(),
            isAdditional:
                card['additional'] == true ||
                tasks.any((t) => t.isAdditional || t.handlerAssigned),
            additionalBy: (card['additional_by'] as List? ?? [])
                .map((e) => '$e'.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
          ),
        );
      }

      final merged = _arrangeCards(loadedClients);
      if (!mounted) return;
      setState(() {
        _clients = merged;
        _loading = false;
      });
      widget.onClientsLoaded(merged);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your assigned clients: $error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.employeeName.isEmpty) {
      return const Center(child: Text('Employee name is not available.'));
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: Color(0xFF64748B),
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loadClients,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_clients.isEmpty) {
      return const Center(
        child: Text(
          'No clients are currently assigned to you.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      );
    }

    final groups = _buildGroups(_clients);
    final openGroup = widget.openGroup == null
        ? null
        : groups.where((g) => g.key == widget.openGroup).firstOrNull;
    if (openGroup != null) return _buildGroupView(openGroup);

    // One card per client (its current / latest card represents it).
    final windowed = _windowed(groups.map((g) => g.head).toList());
    final visible = _filtered(windowed);

    // GODIGITAL_PINNED_FILTER_V4
    // Welcome scrolls away; filters stay pinned on mobile.
    if (MediaQuery.sizeOf(context).width < 600) {
      return RefreshIndicator(
        onRefresh: _loadClients,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            if (widget.mobileHeader != null)
              SliverToBoxAdapter(child: widget.mobileHeader!),
            SliverPersistentHeader(
              pinned: true,
              delegate: _WorkspacePinnedFilterDelegate(
                child: _filterBar(windowed),
              ),
            ),
            if (visible.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 48),
                  child: Center(
                    child: Text(
                      'No client cards match these filters.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 24),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final client = visible[index];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: SizedBox(
                        height: 412,
                        child: _RibbonedCard(
                          ribbon: client.ribbon,
                          additional: client.isAdditional,
                          child: _ClientCard(
                            client: client,
                            onOpen: () => widget.onOpenGroup(_clientKey(client.name)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _filterBar(windowed),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadClients,
            child: visible.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 80),
                      Center(
                        child: Text(
                          'No client cards match these filters.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1200
                          ? 3
                          : constraints.maxWidth >= 760
                          ? 2
                          : 1;
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          mainAxisExtent: 352,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (context, index) => _RibbonedCard(
                          ribbon: visible[index].ribbon,
                          additional: visible[index].isAdditional,
                          child: _ClientCard(
                            client: visible[index],
                            onOpen: () => widget.onOpenGroup(_clientKey(visible[index].name)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  /// Per client: ONLY the current card (nearest submit date today or later)
  /// and the previous card (latest before today).
  List<_ClientGroup> _buildGroups(List<_WorkspaceClient> cards) {
    final t = DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    DateTime due(_WorkspaceClient c) => c.dueDate ?? DateTime(2100);
    final byClient = <String, List<_WorkspaceClient>>{};
    for (final c in cards) {
      (byClient[_clientKey(c.name)] ??= []).add(c);
    }
    final out = <_ClientGroup>[];
    byClient.forEach((key, list) {
      list.sort((a, b) => due(a).compareTo(due(b)));
      final upcoming = list.where((c) => !due(c).isBefore(today)).toList();
      final past = list.where((c) => due(c).isBefore(today)).toList();
      out.add(
        _ClientGroup(
          key,
          list.first.name,
          past.isEmpty ? null : past.last,
          upcoming.isEmpty ? null : upcoming.first,
        ),
      );
    });
    return out;
  }

  Widget _metaChip(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF5FF),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFBFDBFE)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF1456C0)),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1456C0),
          ),
        ),
      ],
    ),
  );

  /// Inside a client: previous card, current card and (tagged) additional work.
  Widget _buildGroupView(_ClientGroup g) {
    final cards = g.cards;
    final head = g.head;
    final maint = head.maintenanceDay.isNotEmpty
        ? head.maintenanceDay
        : (head.dueDate == null ? '' : '${head.dueDate!.day}');
    final pkg = cards
        .map((c) => c.$2.package)
        .firstWhere((p) => p.isNotEmpty, orElse: () => '');
    Color labelColor(String l) =>
        l == 'CURRENT' ? const Color(0xFF15803D) : const Color(0xFF475569);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => widget.onOpenGroup(null),
                icon: const Icon(Icons.arrow_back_rounded, size: 17),
                label: const Text('All clients'),
              ),
              Text(
                g.name,
                style: const TextStyle(
                  color: Color(0xFF14213D),
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                ),
              ),
              if (maint.isNotEmpty)
                _metaChip(Icons.build_circle_outlined, 'Maintain date: $maint'),
              if (pkg.isNotEmpty) _metaChip(Icons.inventory_2_outlined, pkg),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth < 440 ? c.maxWidth : 420.0;
            return Wrap(
              spacing: 16,
              runSpacing: 18,
              children: [
                for (final entry in cards)
                  SizedBox(
                    width: w,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 8, left: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: labelColor(entry.$1).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${entry.$1} · ${_formatDate(entry.$2.submissionDate)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                              color: labelColor(entry.$1),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 352,
                          child: _RibbonedCard(
                            ribbon: entry.$2.ribbon,
                            additional: entry.$2.isAdditional,
                            child: _ClientCard(
                              client: entry.$2,
                              showMeta: false,
                              onOpen: () => widget.onSelectClient(entry.$2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  // Last 2 months (and anything upcoming). Older cards only while they still
  // have open work — unless "Show older" is on.
  List<_WorkspaceClient> _windowed(List<_WorkspaceClient> source) {
    if (_showOlder) return source;
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month - 2, now.day);
    return source.where((c) {
      final due = c.dueDate;
      if (due == null || !due.isBefore(cutoff)) return true;
      return c.hasOpenWork;
    }).toList();
  }

  String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  List<_WorkspaceClient> _filtered(List<_WorkspaceClient> source) {
    final q = widget.searchQuery.trim().toLowerCase();
    final list = source.where((c) {
      if (q.isNotEmpty && !c.name.toLowerCase().contains(q)) return false;
      if (_month != null &&
          (c.dueDate == null || _monthKey(c.dueDate!) != _month)) {
        return false;
      }
      if (_ribbonFilter == 'ALL') return true;
      if (_ribbonFilter == 'PENDING') return c.ribbon == null;
      if (_ribbonFilter == 'TO REVIEW') return c.toReview > 0;
      if (_ribbonFilter == 'ADDITIONAL') return c.isAdditional;
      return c.ribbon == _ribbonFilter;
    }).toList();
    int byDate(_WorkspaceClient a, _WorkspaceClient b) {
      final da = a.dueDate ?? DateTime(2100);
      final db = b.dueDate ?? DateTime(2100);
      return da.compareTo(db);
    }

    list.sort((a, b) {
      // Completed cards always go to the end.
      if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
      switch (_sort) {
        case 'date_desc':
          return byDate(b, a);
        case 'name_asc':
          final r = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          return r != 0 ? r : byDate(a, b);
        case 'name_desc':
          final r = b.name.toLowerCase().compareTo(a.name.toLowerCase());
          return r != 0 ? r : byDate(a, b);
        default:
          return byDate(a, b);
      }
    });
    return list;
  }

  static const _ribbonOrder = [
    'ALL',
    'NEW',
    'PROCESSING',
    'CURRENT',
    'HOLD',
    'REWORK',
    'OVERDUE',
    'IN REVIEW',
    'TO REVIEW',
    'ADDITIONAL',
    'PENDING',
    'COMPLETED',
  ];

  // GODIGITAL_RESPONSIVE_FILTER_V3
  // Compact desktop toolbar and mobile Option B.
  Widget _filterBar(List<_WorkspaceClient> windowed) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final monthKeys =
        windowed
            .map((c) => c.dueDate)
            .whereType<DateTime>()
            .map(_monthKey)
            .toSet()
            .toList()
          ..sort();

    int countFor(String f) => switch (f) {
      'ALL' => windowed.length,
      'PENDING' => windowed.where((c) => c.ribbon == null).length,
      'TO REVIEW' => windowed.where((c) => c.toReview > 0).length,
      'ADDITIONAL' => windowed.where((c) => c.isAdditional).length,
      _ => windowed.where((c) => c.ribbon == f).length,
    };

    final ribbons = _ribbonOrder
        .where((f) => f == 'ALL' || countFor(f) > 0)
        .toList();

    InputDecoration decoration(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    );

    final sortField = DropdownButtonFormField<String>(
      key: const ValueKey('workspace-sort-v3'),
      value: _sort,
      isExpanded: true,
      decoration: decoration('Sort'),
      selectedItemBuilder: (context) => const [
        Text('Submit date ↑', overflow: TextOverflow.ellipsis),
        Text('Submit date ↓', overflow: TextOverflow.ellipsis),
        Text('Client A - Z', overflow: TextOverflow.ellipsis),
        Text('Client Z - A', overflow: TextOverflow.ellipsis),
      ],
      items: const [
        DropdownMenuItem(
          value: 'date_asc',
          child: Text('Submit date ↑ (nearest)'),
        ),
        DropdownMenuItem(
          value: 'date_desc',
          child: Text('Submit date ↓ (latest)'),
        ),
        DropdownMenuItem(value: 'name_asc', child: Text('Client name A → Z')),
        DropdownMenuItem(value: 'name_desc', child: Text('Client name Z → A')),
      ],
      onChanged: (value) {
        setState(() => _sort = value ?? 'date_asc');
      },
    );

    final monthField = DropdownButtonFormField<String?>(
      key: ValueKey('workspace-month-v3-${monthKeys.join("-")}'),
      value: monthKeys.contains(_month) ? _month : null,
      isExpanded: true,
      decoration: decoration('Month'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('All months')),
        for (final key in monthKeys)
          DropdownMenuItem<String?>(
            value: key,
            child: Text(
              '${months[int.parse(key.substring(5)) - 1]} '
              '${key.substring(0, 4)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        setState(() => _month = value);
      },
    );

    final olderChip = FilterChip(
      label: const Text(
        'Older 2m',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      tooltip: 'Show older than 2 months',
      selected: _showOlder,
      showCheckmark: true,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      onSelected: (value) {
        setState(() => _showOlder = value);
      },
    );

    final statusChips = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final f in ribbons)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              avatar: f == 'ALL'
                  ? null
                  : CircleAvatar(backgroundColor: _ribbonColor(f), radius: 4),
              label: Text(
                '${f == 'ALL'
                    ? 'All'
                    : f == 'TO REVIEW'
                    ? 'Review'
                    : f[0] + f.substring(1).toLowerCase()} ${countFor(f)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              selected: _ribbonFilter == f,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelPadding: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 3),
              onSelected: (_) {
                setState(() => _ribbonFilter = f);
              },
            ),
          ),
      ],
    );

    // GODIGITAL_EMPLOYEE_TOOLBAR_V9
    // GODIGITAL_EMPLOYEE_MONTH_V12
    // Sort and Month share the first section.
    // Status filters have equal widths on desktop.
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 600;

        if (mobile) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: SizedBox(height: 48, child: sortField)),
                    const SizedBox(width: 8),
                    Expanded(child: SizedBox(height: 48, child: monthField)),
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: statusChips,
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: SizedBox(
            height: 48,
            child: LayoutBuilder(
              builder: (context, desktopConstraints) {
                final minimumWidth = 160.0 * (ribbons.length + 2);
                final toolbarWidth = desktopConstraints.maxWidth < minimumWidth
                    ? minimumWidth
                    : desktopConstraints.maxWidth;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: toolbarWidth,
                    height: 48,
                    child: Row(
                      children: [
                        Expanded(child: SizedBox(height: 44, child: sortField)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(height: 44, child: monthField),
                        ),
                        const SizedBox(width: 10),
                        for (final f in ribbons) ...[
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: Material(
                                color: _ribbonFilter == f
                                    ? const Color(0xFF1456CE)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    setState(() => _ribbonFilter = f);
                                  },
                                  child: Container(
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: _ribbonFilter == f
                                            ? const Color(0xFF1456CE)
                                            : const Color(0xFFD8E1EF),
                                      ),
                                    ),
                                    child: Text(
                                      '${f == 'ALL'
                                          ? 'All'
                                          : f == 'TO REVIEW'
                                          ? 'Review'
                                          : f[0] + f.substring(1).toLowerCase()} ${countFor(f)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _ribbonFilter == f
                                            ? Colors.white
                                            : const Color(0xFF25324A),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

Color _ribbonColor(String ribbon) => switch (ribbon) {
  'NEW' => const Color(0xFF2563EB),
  'PROCESSING' => const Color(0xFF0891B2),
  'CURRENT' => const Color(0xFF15803D),
  'HOLD' => const Color(0xFFD97706),
  'REWORK' => const Color(0xFFC2410C),
  'OVERDUE' => const Color(0xFFDC2626),
  'IN REVIEW' => const Color(0xFF7C3AED),
  'TO REVIEW' => const Color(0xFFDC2626),
  'COMPLETED' => const Color(0xFF16A34A),
  'LATE' => const Color(0xFFB91C1C),
  'ADDITIONAL' => const Color(0xFF7C3AED),
  _ => const Color(0xFF64748B),
};

/// Corner ribbon (NEW / PROCESSING / HOLD / …) on a client card, plus an
/// "ADDITIONAL TASK" tag on the top-left when the work came from a Page /
/// Ads Handler (Content Calendar) or is an additional task.
class _RibbonedCard extends StatelessWidget {
  final String? ribbon;
  final bool additional;
  final Widget child;

  const _RibbonedCard({
    required this.ribbon,
    required this.child,
    this.additional = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!additional) return _corner();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _corner(),
        const Positioned(top: 0, left: 18, child: _AdditionalTag()),
      ],
    );
  }

  Widget _corner() {
    if (ribbon == null) return child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Banner(
        message: ribbon!,
        location: BannerLocation.topEnd,
        color: _ribbonColor(ribbon!),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
        child: child,
      ),
    );
  }
}

/// Purple bookmark tag hanging from the card's top edge.
class _AdditionalTag extends StatelessWidget {
  const _AdditionalTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 3, 9, 4),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x337C3AED),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_task_rounded, size: 11, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'ADDITIONAL TASK',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  final _WorkspaceClient client;
  final VoidCallback onOpen;

  // Show the maintain date + package line (client list); the opened client
  // already shows them in its header.
  final bool showMeta;

  const _ClientCard({
    required this.client,
    required this.onOpen,
    this.showMeta = true,
  });

  static Widget _taskLine(
    String name,
    int done,
    int total, {
    double indent = 0,
  }) => Padding(
    padding: EdgeInsets.only(left: indent, top: 3, bottom: 3),
    child: Row(
      children: [
        Icon(
          Icons.circle,
          size: 7,
          color: total > 0 && done >= total
              ? const Color(0xFF16A34A)
              : done == 0
              ? const Color(0xFF94A3B8)
              : const Color(0xFF2563EB),
        ),

        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF475569), fontSize: 12),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: total > 0 && done >= total
                ? const Color(0xFFDCFCE7)
                : const Color(0xFFEFF5FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$done/$total',
            style: TextStyle(
              color: total > 0 && done >= total
                  ? const Color(0xFF15803D)
                  : const Color(0xFF1456C0),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );

  /// Team · tasks (role, person, each category with completed/total) in a popup.
  // Restored Team actions: reuse the existing Chat widget and employee API.
  static Future<void> _teamWhatsApp(
    BuildContext context,
    Map<String, dynamic> member,
  ) async {
    final name = '${member['employee'] ?? ''}'.trim();
    String phone = '';
    for (final key in [
      'phone_number',
      'phone',
      'mobile',
      'mobile_number',
      'employee_phone',
    ]) {
      final value = '${member[key] ?? ''}'.trim();
      if (value.isNotEmpty && value.toLowerCase() != 'null') {
        phone = value;
        break;
      }
    }
    if (phone.isEmpty) {
      try {
        final token = context.read<AuthService>().token ?? '';
        final response = await http.get(
          Uri.parse('${ApiConfig.baseUrl}/employees'),
          headers: {if (token.isNotEmpty) 'Authorization': 'Bearer $token'},
        );
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          final employees =
              (decoded is Map ? decoded['data'] : decoded) as List? ?? [];
          for (final item in employees.whereType<Map>()) {
            final foundName = '${item['full_name'] ?? item['name'] ?? ''}'
                .trim();
            if (foundName.toLowerCase() == name.toLowerCase()) {
              phone =
                  '${item['phone_number'] ?? item['phone'] ?? item['mobile'] ?? ''}'
                      .trim();
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Team WhatsApp contact lookup error: $e');
      }
    }
    if (!context.mounted) return;
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11 && digits.startsWith('0')) {
      digits = '91${digits.substring(1)}';
    } else if (digits.length == 10) {
      digits = '91$digits';
    }
    if (digits.length < 10 || digits.length > 15) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Valid WhatsApp number unavailable for $name')),
      );
      return;
    }
    try {
      final url = Uri.https('wa.me', '/$digits', {'text': 'Hi $name'});
      if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open WhatsApp')),
        );
      }
    } catch (e) {
      debugPrint('Team WhatsApp launch error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open WhatsApp')),
        );
      }
    }
  }

  static Future<void> _teamDirectChat(
    BuildContext context,
    _WorkspaceClient client,
    Map<String, dynamic> member,
  ) async {
    final target = '${member['employee'] ?? ''}'.trim();
    final auth = context.read<AuthService>();
    final user = auth.user;
    final sender =
        '${user?['fullName'] ?? user?['full_name'] ?? user?['name'] ?? ''}'
            .trim();
    if (target.isEmpty || sender.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Employee identity is unavailable for Chat'),
        ),
      );
      return;
    }
    if (sender.toLowerCase() == target.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select another employee to chat')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFFF4F7FC),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960, maxHeight: 650),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Chat · $target',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _WorkspaceTeamChat(
                  employeeName: sender,
                  clientName: client.name,
                  initialTarget: target,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> showTeam(BuildContext context, _WorkspaceClient client) {
    final taskGroups = _workspaceTaskGroups(client);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PremiumTheme.dialogHeader(
                'Team · tasks',
                icon: Icons.groups_2_rounded,
                subtitle:
                    '${client.name} · Submit ${_formatDate(client.submissionDate)}',
                onClose: () => Navigator.pop(dialogContext),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  children: [
                    if (client.team.isEmpty)
                      for (final group in taskGroups)
                        _taskLine(group.$1, group.$2, group.$3),
                    for (final member in client.team)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FBFF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFDCE6F7)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 13,
                                  backgroundColor: const Color(0xFF0757D5),
                                  child: Text(
                                    _clientInitials(
                                      '${member['employee'] ?? ''}',
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),

                                Expanded(
                                  child: Text(
                                    '${member['employee'] ?? ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF14213D),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEAF2FF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${member['role'] ?? ''}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1456C0),
                                    ),
                                  ),
                                ),
                                // TEAM_COMMUNICATION_ACTIONS_V2
                                const SizedBox(width: 5),
                                Tooltip(
                                  message: 'WhatsApp',
                                  child: IconButton(
                                    onPressed: () =>
                                        _teamWhatsApp(dialogContext, member),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 34,
                                      minHeight: 34,
                                    ),
                                    icon: Image.asset(
                                      'assets/icons/godigital_whatsapp_chat.png',
                                      width: 23,
                                      height: 23,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.call_rounded,
                                        color: Color(0xFF25D366),
                                        size: 23,
                                      ),
                                    ),
                                  ),
                                ),
                                Tooltip(
                                  message: 'Chat',
                                  child: IconButton(
                                    onPressed: () => _teamDirectChat(
                                      dialogContext,
                                      client,
                                      member,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 34,
                                      minHeight: 34,
                                    ),
                                    icon: const Icon(
                                      Icons.forum_rounded,
                                      color: Color(0xFF0757D5),
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            for (final task
                                in (member['tasks'] as List? ?? [])
                                    .whereType<Map>())
                              _taskLine(
                                '${task['name'] ?? ''}',
                                int.tryParse('${task['completed'] ?? 0}') ?? 0,
                                int.tryParse('${task['total'] ?? 0}') ?? 0,
                                indent: 4,
                              ),
                            if ((member['tasks'] as List? ?? []).isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(left: 4, top: 2),
                                child: Text(
                                  'No categories',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teamCount = client.team.length;
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        // Extra top space for the "ADDITIONAL TASK" tag.
        padding: EdgeInsets.fromLTRB(18, client.isAdditional ? 24 : 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              // Leave room for the corner ribbon.
              padding: const EdgeInsets.only(right: 34),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFEAF2FF),
                    foregroundColor: const Color(0xFF1456C0),
                    child: Text(_clientInitials(client.name)),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      client.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF14213D),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Team · tasks',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => showTeam(context, client),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF5FF),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.groups_2_rounded,
                              size: 15,
                              color: Color(0xFF0757D5),
                            ),
                            if (teamCount > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                '$teamCount',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0757D5),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: client.isAdditional ? 6 : 10),
            Row(
              children: [
                Text(
                  'Submit date: ${_formatDate(client.submissionDate)}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
                if (client.additionalBy.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Tooltip(
                      message: 'Assigned by ${client.additionalBy.join(', ')}',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E8FF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFD8B4FE)),
                        ),
                        child: Text(
                          'By ${client.additionalBy.join(', ')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF6D28D9),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (showMeta &&
                (client.package.isNotEmpty ||
                    client.maintenanceDay.isNotEmpty)) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if (client.maintenanceDay.isNotEmpty)
                    'Maintain date: ${client.maintenanceDay}',
                  if (client.package.isNotEmpty) client.package,
                ].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF1456C0),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _ClientStatTiles(client: client, compact: true),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${client.progress}% approved',
                  style: const TextStyle(
                    color: Color(0xFF1456C0),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),

                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: client.progress / 100,
                      minHeight: 7,
                      backgroundColor: const Color(0xFFE8EEF8),
                      color: const Color(0xFF1A68D1),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (client.inProgress > 0)
                  _CountChip(
                    'In progress',
                    client.inProgress,
                    const Color(0xFF2563EB),
                  ),
                if (client.onHold > 0)
                  _CountChip('Hold', client.onHold, const Color(0xFFD97706)),
                if (client.toReview > 0)
                  _CountChip(
                    'To review',
                    client.toReview,
                    const Color(0xFFDC2626),
                  ),
                if (client.additionalRows > 0)
                  _CountChip(
                    'Additional',
                    client.additionalRows,
                    const Color(0xFF7C3AED),
                  ),
                _CountChip(
                  'Complete',
                  client.completed,
                  const Color(0xFF15803D),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1456C0),
                  minimumSize: const Size.fromHeight(38),
                ),
                child: const Text('Open client tasks'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<(String, int, int)> _workspaceTaskGroups(_WorkspaceClient client) {
  final tasks = client.tasks.where((task) => !task.isAdditional).toList();

  (int, int) counts(Iterable<_WorkspaceTask> items) {
    var completed = 0;
    var total = 0;
    for (final task in items) {
      completed += task.completedCount;
      total += task.total;
    }
    return (completed, total);
  }

  (String, int, int) group(String label, Iterable<_WorkspaceTask> items) {
    final result = counts(items);
    return (label, result.$1, result.$2);
  }

  switch (client.employeeRole) {
    case EmployeeRole.adsHandler:
      return [
        group('All ads tasks', tasks),
        group(
          'Meta / Facebook Ads',
          tasks.where(
            (task) =>
                task.name.toLowerCase().contains('meta') ||
                task.name.toLowerCase().contains('facebook'),
          ),
        ),
        group(
          'Google Ads',
          tasks.where((task) => task.name.toLowerCase().contains('google')),
        ),
        group(
          'YouTube Ads',
          tasks.where((task) => task.name.toLowerCase().contains('youtube')),
        ),
      ];
    case EmployeeRole.pageHandler:
      return [
        group('All page tasks', tasks),
        group(
          'Instagram',
          tasks.where(
            (task) =>
                task.name.toLowerCase().contains('instagram') ||
                task.name.toLowerCase().contains('insta'),
          ),
        ),
        group(
          'Google Business Profile',
          tasks.where(
            (task) =>
                task.name.toLowerCase().contains('gmb') ||
                task.name.toLowerCase().contains('google business'),
          ),
        ),
      ];
    case EmployeeRole.designer:
      return [
        group('Creative / Design', tasks),
        for (final task in tasks) (task.name, task.completedCount, task.total),
      ];
    case EmployeeRole.videographer:
      return [
        group('Video Production', tasks),
        for (final task in tasks) (task.name, task.completedCount, task.total),
      ];
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _CountChip(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _clientInitials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  final initials = words.take(2).map((word) => word.characters.first).join();
  return initials.isEmpty ? 'CL' : initials.toUpperCase();
}

String _workspaceRoleLabel(String role) {
  switch (role) {
    case 'designer':
      return 'Designer';
    case 'videographer':
      return 'Videographer';
    case 'video_editor':
      return 'Video Editor';
    case 'ads_handler':
      return 'Ads Handler';
    case 'page_handler':
      return 'Page Handler';
    case 'ui_ux_designer':
      return 'UI/UX Designer';
    case 'developer':
      return 'Developer';
    case 'website_designer':
      return 'Website Designer';
    default:
      return role;
  }
}

String _formatDate(String value) {
  if (value.trim().isEmpty) return 'Not provided';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  return DateFormat('d MMM yyyy').format(parsed.toLocal());
}

Color _statusColor(_WorkspaceTaskStatus status) {
  switch (status) {
    case _WorkspaceTaskStatus.pending:
      return const Color(0xFF64748B);
    case _WorkspaceTaskStatus.inProgress:
      return const Color(0xFF2563EB);
    case _WorkspaceTaskStatus.onHold:
      return const Color(0xFFD97706);
    case _WorkspaceTaskStatus.inReview:
      return const Color(0xFF7C3AED);
    case _WorkspaceTaskStatus.rework:
      return const Color(0xFFC2410C);
    case _WorkspaceTaskStatus.completed:
      return const Color(0xFF15803D);
  }
}

String _statusLabel(_WorkspaceTaskStatus status) {
  switch (status) {
    case _WorkspaceTaskStatus.pending:
      return 'Pending';
    case _WorkspaceTaskStatus.inProgress:
      return 'In progress';
    case _WorkspaceTaskStatus.onHold:
      return 'Hold';
    case _WorkspaceTaskStatus.inReview:
      return 'In review';
    case _WorkspaceTaskStatus.rework:
      return 'Rework';
    case _WorkspaceTaskStatus.completed:
      return 'Complete';
  }
}

// GODIGITAL_PINNED_FILTER_DELEGATE_V4
class _WorkspacePinnedFilterDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _WorkspacePinnedFilterDelegate({required this.child});

  @override
  double get minExtent => 164;

  @override
  double get maxExtent => 164;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: const Color(0xFFF4F7FC),
      elevation: overlapsContent ? 3 : 0,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _WorkspacePinnedFilterDelegate oldDelegate) =>
      true;
}