import 'package:godigital_portal/services/socket_auth.dart';
import 'package:godigital_portal/services/auth_storage.dart';
// lib/screens/employee_dashboard/content_calendar_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:godigital_portal/services/authenticated_http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../../services/api_config.dart';
import 'rich_description.dart';
import 'helpers/calendar_file_save.dart';
import 'helpers/content_calendar_export_template.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette
// ─────────────────────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF004AAD);
const _kInk = Color(0xFF0F172A);
const _kBody = Color(0xFF334155);
const _kMuted = Color(0xFF64748B);
const _kFaint = Color(0xFF94A3B8);
const _kBorder = Color(0xFFE2E8F0);
const _kSurface = Color(0xFFF8FAFC);
const _kTint = Color(0xFFEFF6FF);
const _kTintBorder = Color(0xFFBFDBFE);

const _kGreen = Color(0xFF16A34A);
const _kGreenDark = Color(0xFF15803D);
const _kGreenTint = Color(0xFFDCFCE7);
const _kOrange = Color(0xFFEA580C);
const _kAmberTint = Color(0xFFFEF3C7);
const _kAmberDark = Color(0xFF92400E);
const _kBlue = Color(0xFF2563EB);
const _kPurple = Color(0xFF7C3AED);
const _kRed = Color(0xFFDC2626);
const _kRedTint = Color(0xFFFEE2E2);

const _kMonths = [
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

// ─────────────────────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────────────────────
int _asInt(dynamic v) => v is int
    ? v
    : (v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0);

int? _asIntOrNull(dynamic v) =>
    v is int ? v : int.tryParse(v?.toString() ?? '');

bool _isTrue(dynamic v) => v == 1 || v == true || v?.toString() == '1';

String _str(dynamic v) {
  final s = v?.toString() ?? '';
  return s == 'null' ? '' : s;
}

DateTime? _parseDate(dynamic v) {
  final s = _str(v).trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s.length >= 10 ? s.substring(0, 10) : s);
}

String _dateKey(dynamic value) {
  final parsed = _parseDate(value);
  if (parsed != null) return _fmtIso(parsed);
  final raw = _str(value).trim();
  return raw.length >= 10 ? raw.substring(0, 10) : raw;
}

String _two(int n) => n.toString().padLeft(2, '0');
String _fmtIso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _fmtSlash(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';
String _fmtLong(DateTime d) =>
    '${_two(d.day)} ${_kMonths[d.month - 1]} ${d.year}';

String _fmtTimer(int sec) {
  final s = math.max(0, sec);
  return '${_two(s ~/ 3600)}:${_two((s % 3600) ~/ 60)}:${_two(s % 60)}';
}

String _errorFrom(http.Response res, String fallback) {
  try {
    final body = jsonDecode(res.body);
    final msg = body['message'] ?? body['error'];
    if (msg != null && msg.toString().trim().isNotEmpty) return msg.toString();
  } catch (_) {}
  return fallback;
}

Future<bool> _checkOnLeave(
  String baseUrl,
  Map<String, String> headers,
  String name,
) async {
  final res = await http.get(
    Uri.parse('$baseUrl/tasks/check-leave/${Uri.encodeComponent(name)}'),
    headers: headers,
  );
  if (res.statusCode != 200) {
    throw StateError(_errorFrom(res, 'Unable to check employee leave status'));
  }
  return jsonDecode(res.body)['is_on_leave'] == true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class ContentCalendarScreen extends StatefulWidget {
  final String apiBaseUrl;
  final String authToken;
  final int currentUserId;
  final String currentUserName;
  final String currentUserRole;
  final Map<String, dynamic>? initialClient;
  final bool myTasksMode;

  /// Main admin view: everything is visible, nothing can be changed.
  final bool readOnly;

  /// Opened from a client card where the Tasks Assign screen names this
  /// employee as Page / Ads Handler (role of the employee does not matter).
  final bool viaAssignment;

  const ContentCalendarScreen({
    Key? key,
    required this.apiBaseUrl,
    required this.authToken,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserRole,
    this.initialClient,
    this.myTasksMode = false,
    this.readOnly = false,
    this.viaAssignment = false,
  }) : super(key: key);

  @override
  State<ContentCalendarScreen> createState() => _ContentCalendarScreenState();
}

class _ContentCalendarScreenState extends State<ContentCalendarScreen> {
  String get _baseUrl => widget.apiBaseUrl;

  /// Read-only (main admin): show a short note instead of changing anything.
  bool _blockedReadOnly() {
    if (!widget.readOnly) return false;
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('View only — the Content Calendar cannot be changed from the admin view.')),
      );
    }
    return true;
  }

  String get _normalizedRole => widget.currentUserRole
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s-]+'), '_');

  bool get _isPageOrAdsHandler =>
      _normalizedRole.contains('page_handler') ||
      _normalizedRole.contains('pagehandler') ||
      _normalizedRole.contains('ads_handler') ||
      _normalizedRole.contains('adshandler');

  bool _assignedToCurrentEmployee(Map<String, dynamic> row) {
    if (!_isAssigned(row)) return false;
    final assignedName = _str(
      row['cc_assigned_to_name'] ??
          row['assigned_to_name'] ??
          row['employee_name'] ??
          row['allocated_employee'],
    ).trim();
    if (assignedName.isEmpty) return true;
    return assignedName.toLowerCase() == widget.currentUserName.trim().toLowerCase();
  }

  /// The employee a row belongs to / was given to (first name found), used so
  /// the admin view shows who owns every row.
  String _employeeOf(Map<String, dynamic> r) {
    for (final k in const [
      'task_employee_name',
      'cc_assigned_to_name',
      'assigned_to_name',
      'employee_name',
      'allocated_employee',
    ]) {
      final v = _str(r[k]).trim();
      if (v.isNotEmpty) return v;
    }
    return 'Not assigned';
  }

  bool _loading = true;
  bool _refreshing = false;

  List<Map<String, dynamic>> _clientCards = [];
  Map<String, dynamic>? _selectedClient;
  List<Map<String, dynamic>> _allCalendarRows = [];
  List<String> _categoryTabs = [];
  int _selectedTabIndex = 0;

  final Set<int> _busyRows = {};
  // Calendar rows (category leaders / manual rows) already in today's planner.
  Set<int> _plannerCalIds = {};
  final Map<int, Map<String, dynamic>> _pendingEdits = {};
  final Map<int, Timer> _saveDebouncers = {};
  int _sheetRev = 0;

  final ScrollController _tabScrollController = ScrollController();
  final ScrollController _tableHorizontalController = ScrollController();
  late IO.Socket _socket;
  Timer? _liveTicker;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (widget.authToken.isNotEmpty)
      'Authorization': 'Bearer ${widget.authToken}',
  };

  String? get _currentCategory =>
      _categoryTabs.isNotEmpty && _selectedTabIndex < _categoryTabs.length
      ? _categoryTabs[_selectedTabIndex]
      : null;

  @override
  void initState() {
    super.initState();
    final initialClient = widget.initialClient;
    if (initialClient == null) {
      _fetchClientCards();
    } else {
      _selectedClient = initialClient;
      _fetchClientCalendarRows(_str(initialClient['client_name']));
    }
    _initSocket();

    _liveTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _selectedClient == null) return;
      var hasRunning = false;
      for (final r in _allCalendarRows) {
        if (_ccStatusOf(r) == 'IN PROGRESS' &&
            (widget.myTasksMode || !_isAssigned(r)) &&
            _isSheetLeader(r)) {
          hasRunning = true;
          r['current_cc_secs'] = _asInt(r['current_cc_secs']) + 1;
        }
      }
      if (hasRunning) setState(() {});
    });
  }

  void _initSocket() {
    _socket = IO.io(
      ApiConfig.socketUrl,
      IO.OptionBuilder().setAuthFn(authenticateSocket)
          .setTransports(['websocket'])
          .enableForceNew()
          .disableAutoConnect()
          .build(),
    );
    _socket.connect();
    _socket.on('task_updated', (_) => _silentRefresh());
    _socket.on('calendar:assigned', (_) => _silentRefresh());
  }

  void _silentRefresh() {
    if (!mounted) return;
    final client = _selectedClient;
    if (client != null) {
      _fetchClientCalendarRows(client['client_name'].toString(), silent: true);
    } else {
      _fetchClientCards(silent: true);
    }
  }

  @override
  void dispose() {
    for (final id in _saveDebouncers.keys.toList()) {
      _flushSave(id);
    }
    _liveTicker?.cancel();
    _tabScrollController.dispose();
    _tableHorizontalController.dispose();
    _socket.dispose();
    super.dispose();
  }

  Future<void> _fetchClientCards({bool silent = false}) async {
    if (!silent && !_loading) setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse(
          '$_baseUrl/tasks/assigned-client-cards'
          '?employeeName=${Uri.encodeComponent(widget.currentUserName)}&scope=content-calendar',
        ),
        headers: _headers,
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final cards = List<Map<String, dynamic>>.from(body['data'] ?? [])
            .where((client) {
              final active = client['is_active'];
              return active == null || _isTrue(active);
            })
            .where((client) {
              final summary = client['deliverables_summary'];
              return summary is! List || summary.isNotEmpty;
            })
            .toList();
        setState(() => _clientCards = cards);
      } else if (!silent) {
        _showMessage('Unable to load clients');
      }
    } catch (_) {
      if (!silent) _showMessage('Unable to load clients');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _fetchClientCalendarRows(
    String clientName, {
    bool silent = false,
  }) async {
    if (!silent && !_loading) setState(() => _loading = true);
    _loadPlannerCalIds();
    try {
      // The main admin reads every row through its own route; handlers keep
      // using /tasks/client-tasks.
      // Employees use the normal route first; the admin (and an employee whose
      // role is not Page / Ads Handler but is the handler of this client) use
      // the wide route first. Whichever answers 200 wins, so no access error
      // is shown while the other route can serve the rows.
      final enc = Uri.encodeComponent(clientName);
      final emp = Uri.encodeComponent(widget.currentUserName);
      Future<http.Response> loadFrom(String path) => http.get(
        Uri.parse('$_baseUrl/$path/$enc?employee=$emp'),
        headers: _headers,
      );
      const ownRoute = 'tasks/client-tasks';
      const wideRoute = 'workspace-tasks/admin/content-calendar';
      final routes = widget.readOnly
          ? [wideRoute, ownRoute]
          : widget.viaAssignment
          ? [ownRoute, wideRoute]
          : [ownRoute];
      var res = await loadFrom(routes.first);
      for (final path in routes.skip(1)) {
        if (res.statusCode == 200) break;
        res = await loadFrom(path);
      }
      if (!mounted) return;
      if (_selectedClient == null ||
          _selectedClient!['client_name'].toString() != clientName)
        return;

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        var list = List<Map<String, dynamic>>.from(body['data'] ?? []);

        // When the employee opens a Client + Submit Date card in My Tasks,
        // only load that deadline's deliverables into this calendar. The
        // standalone Content Calendar (without a selected date) stays global.
        final selectedDate = _str(
          _selectedClient?['submission_date'] ??
              _selectedClient?['submit_date'] ??
              _selectedClient?['date'],
        ).trim();
        if (selectedDate.isNotEmpty) {
          final selectedKey = _dateKey(selectedDate);
          list = list.where((row) {
            // Rows from the admin assignment belong to that assignment's
            // deadline (the card), even after the handler moves their own
            // submit date. Hand-added rows still follow their submit date.
            final cardDate = _str(row['source_deadline']).isNotEmpty
                ? row['source_deadline']
                : (row['submit_date'] ?? row['submission_date']);
            return _dateKey(cardDate) == selectedKey;
          }).toList();
        }

        // Content Calendar is a hand-off view for roles other than Page
        // Handler and Ads Handler. Those two roles work from My Tasks instead,
        // so their role assignments must not be duplicated here. For other
        // roles, show only deliverables that have actually been assigned to
        // this employee (not every old/unassigned client calendar row).
        // The main admin (readOnly) sees every row of the card, whoever owns it.
        if (!widget.readOnly) {
          if (!_isPageOrAdsHandler) {
            list = list.where(_assignedToCurrentEmployee).toList();
          } else {
            list = list.where((row) {
              final sourceRole = _str(row['source_role'])
                  .trim()
                  .toLowerCase()
                  .replaceAll(RegExp(r'[\s-]+'), '_');
              return !sourceRole.contains('page_handler') &&
                  !sourceRole.contains('pagehandler') &&
                  !sourceRole.contains('ads_handler') &&
                  !sourceRole.contains('adshandler');
            }).toList();
          }
        }

        for (final r in list) {
          final pending = _pendingEdits[_asInt(r['id'])];
          if (pending != null) r.addAll(pending);
          r['current_cc_secs'] = _asInt(
            r['current_cc_secs'] ?? r['cc_duration_secs'],
          );
        }

        final categories =
            list
                .map((e) => _str(e['deliverable']))
                .where((s) => s.isNotEmpty)
                .toSet()
                .toList()
              ..sort();

        final previous = _currentCategory;
        final nextIndex = previous != null && categories.contains(previous)
            ? categories.indexOf(previous)
            : 0;

        setState(() {
          _allCalendarRows = list;
          _categoryTabs = categories;
          _selectedTabIndex = categories.isEmpty
              ? 0
              : nextIndex.clamp(0, categories.length - 1);
        });
      } else if (!silent) {
        _showMessage(_errorFrom(res, 'Unable to load content calendar'));
      }
    } catch (_) {
      if (!silent) _showMessage('Unable to load content calendar');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _loadPlannerCalIds() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/workspace-tasks/day-plan/rows').replace(
          queryParameters: {'employee': widget.currentUserName.trim()},
        ),
        headers: _headers,
      );
      if (res.statusCode != 200 || !mounted) return;
      final ids = ((jsonDecode(res.body) as Map)['calendar'] as List? ?? [])
          .map((e) => int.tryParse('$e') ?? 0)
          .where((e) => e > 0)
          .toSet();
      setState(() => _plannerCalIds = ids);
    } catch (_) {}
  }

  /// Add this category (or manual row) to today's Day Planner without starting.
  Future<void> _addCalendarToPlanner(List<Map<String, dynamic>> rows) async {
    if (_blockedReadOnly()) return;
    if (rows.isEmpty) return;
    final ids = rows.map((r) => _asInt(r['id'])).toSet();
    if (ids.any(_busyRows.contains)) return;
    setState(() => _busyRows.addAll(ids));
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/tasks/content-calendar/add-to-planner'),
        headers: _headers,
        body: jsonEncode({'calendar_id': rows.first['id']}),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map;
        final id = _asInt(body['calendar_id']);
        if (mounted && id > 0) setState(() => _plannerCalIds.add(id));
        _showMessage('${body['message'] ?? 'Added to today’s Day Planner'}');
      } else {
        _showMessage(_errorFrom(res, 'Could not add this to the Day Planner'));
      }
    } catch (_) {
      _showMessage('Could not add this to the Day Planner');
    } finally {
      if (mounted) setState(() => _busyRows.removeAll(ids));
    }
  }

  Widget _plannerButtonFor(List<Map<String, dynamic>> rows, bool busy) {
    final inPlanner = rows.any((r) => _plannerCalIds.contains(_asInt(r['id'])));
    if (inPlanner) {
      return Tooltip(
        message: 'In today’s Day Planner',
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _kTint,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kTintBorder),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.event_available_rounded, size: 13, color: _kPrimary),
            SizedBox(width: 4),
            Text('In planner',
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: _kPrimary)),
          ]),
        ),
      );
    }
    return _prepActionButton(
      label: 'ADD TO PLANNER',
      color: const Color(0xFF0757D5),
      icon: Icons.playlist_add_rounded,
      onTap: busy ? null : () => _addCalendarToPlanner(rows),
    );
  }

  Future<void> _reloadCurrentClient({bool silent = true}) async {
    final client = _selectedClient;
    if (client == null) return;
    await _fetchClientCalendarRows(
      client['client_name'].toString(),
      silent: silent,
    );
  }

  Future<void> _manualRefresh() async {
    setState(() => _refreshing = true);
    await _reloadCurrentClient(silent: true);
    if (mounted) setState(() => _refreshing = false);
  }

  Map<String, dynamic>? _rowById(int id) {
    for (final r in _allCalendarRows) {
      if (_asInt(r['id']) == id) return r;
    }
    return null;
  }

  void _onFieldChanged(Map<String, dynamic> row, String field, dynamic value) {
    final id = _asInt(row['id']);
    row[field] = value;
    (_pendingEdits[id] ??= {})[field] = value;
    _saveDebouncers[id]?.cancel();
    _saveDebouncers[id] = Timer(
      const Duration(milliseconds: 700),
      () => _flushSave(id),
    );
  }

  Map<String, dynamic> _briefPayload(Map<String, dynamic> source) => {
    'hook_headline': source['hook_headline'],
    'description_points': source['description_points'],
    'caption': source['caption'],
    'cta': source['cta'],
    'publish_date': source['publish_date'],
    'submit_date': source['submit_date'],
    'notes': source['notes'],
    if (source.containsKey('description_rich'))
      'description_rich': source['description_rich'],
  };

  Future<void> _flushSave(int id) async {
    _saveDebouncers.remove(id)?.cancel();
    final edits = _pendingEdits[id];
    if (edits == null) return;
    final source = <String, dynamic>{...?_rowById(id), ...edits};
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/tasks/content-calendar/edit-row/$id'),
        headers: _headers,
        body: jsonEncode(_briefPayload(source)),
      );
      if (res.statusCode == 200 && !_saveDebouncers.containsKey(id)) {
        _pendingEdits.remove(id);
      } else if (res.statusCode != 200) {
        _showMessage(_errorFrom(res, 'Unable to save calendar changes'));
      }
    } catch (_) {
      _showMessage('Unable to save calendar changes. Check your connection.');
    }
  }

  String _ccStatusOf(Map<String, dynamic> row) {
    final s = _str(row['cc_status']).trim().toUpperCase();
    return s.isEmpty ? 'IDLE' : s;
  }

  bool _isAssigned(Map<String, dynamic> row) =>
      _isTrue(row['content_calendar_assigned']);
  bool _isEmergency(Map<String, dynamic> row) => _isTrue(row['is_emergency']);
  bool _isApproved(Map<String, dynamic> row) =>
      _str(row['review_status']).toUpperCase() == 'APPROVED' ||
      _str(row['status']).toUpperCase() == 'APPROVED';

  List<Map<String, dynamic>> _rowsFor(String category) => _allCalendarRows
      .where((r) => _str(r['deliverable']) == category)
      .toList();

  List<Map<String, dynamic>> _sheetRowsFor(Map<String, dynamic> row) {
    if (_asInt(row['source_assignment_id']) == 0) return [row];
    final rows =
        _allCalendarRows
            .where(
              (candidate) =>
                  _asInt(candidate['source_assignment_id']) ==
                      _asInt(row['source_assignment_id']) &&
                  _str(candidate['source_role']) == _str(row['source_role']) &&
                  _asInt(candidate['source_task_index']) ==
                      _asInt(row['source_task_index']),
            )
            .toList()
          ..sort(
            (a, b) => _asInt(
              a['source_row_number'],
            ).compareTo(_asInt(b['source_row_number'])),
          );
    return rows;
  }

  bool _isSheetLeader(Map<String, dynamic> row) {
    if (_asInt(row['source_assignment_id']) == 0) return true;
    final sheet = _sheetRowsFor(row);
    return sheet.isNotEmpty && _asInt(sheet.first['id']) == _asInt(row['id']);
  }

  Future<void> _handleSheetAction(
    List<Map<String, dynamic>> rows,
    String action,
  ) async {
    if (_blockedReadOnly()) return;
    if (rows.isEmpty) return;
    final firstRow = rows.first;
    final rowIds = rows.map((row) => _asInt(row['id'])).toSet();
    if (rowIds.any(_busyRows.contains)) return;

    if (action == 'start') {
      final confirmed = await _confirmAddToDayPlanner(
        firstRow,
        rowCount: rows.length,
      );
      if (!confirmed || !mounted) return;
    }

    String? reason;
    if (action == 'hold') {
      reason = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _HoldReasonDialog(label: '${_str(firstRow['deliverable'])} sheet'),
      );
      if (reason == null || reason.isEmpty || !mounted) return;
    }

    setState(() => _busyRows.addAll(rowIds));
    for (final id in rowIds) {
      await _flushSave(id);
    }
    try {
      Map<String, dynamic> payload() => {
        'source_assignment_id': firstRow['source_assignment_id'],
        'source_role': firstRow['source_role'],
        'source_task_index': firstRow['source_task_index'],
        if (action == 'start') 'day_planner_confirmed': true,
        if (reason != null) 'reason': reason,
      };
      var response = await http.post(
        Uri.parse('$_baseUrl/tasks/content-calendar/sheet-$action'),
        headers: _headers,
        body: jsonEncode(payload()),
      );
      if (!mounted) return;
      final holdReason = await _autoHoldReasonFor(response);
      if (holdReason != null && holdReason.isNotEmpty) {
        response = await http.post(
          Uri.parse('$_baseUrl/tasks/content-calendar/sheet-$action'),
          headers: _headers,
          body: jsonEncode({...payload(), 'auto_hold_reason': holdReason}),
        );
        if (!mounted) return;
      } else if (response.statusCode == 409 &&
          response.body.contains('AUTO_HOLD_REASON_REQUIRED')) {
        return; // cancelled
      }
      if (response.statusCode == 200) {
        await _reloadCurrentClient();
      } else {
        _showMessage(
          _errorFrom(response, 'Unable to $action this deliverable sheet'),
        );
      }
    } catch (_) {
      _showMessage('Unable to $action this deliverable sheet');
    } finally {
      if (mounted) setState(() => _busyRows.removeAll(rowIds));
    }
  }

  /// If the server says something else is running, ask why it should be held.
  /// Returns the reason, or null when the user cancels / it is another error.
  Future<String?> _autoHoldReasonFor(http.Response res) async {
    if (res.statusCode != 409) return null;
    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    } catch (_) {
      return null;
    }
    if (body['code'] != 'AUTO_HOLD_REASON_REQUIRED') return null;
    final running = (body['running'] as List? ?? [])
        .whereType<Map>()
        .map((r) => _str(r['title']))
        .where((t) => t.isNotEmpty)
        .toList();
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _HoldReasonDialog(
        label: running.isEmpty ? 'your running task' : running.join(', '),
        autoHold: true,
      ),
    );
  }

  Future<bool> _runAction(
    Map<String, dynamic> row, {
    required String path,
    Map<String, dynamic> extra = const {},
    required String nextCcStatus,
    required String errorMessage,
  }) async {
    if (_blockedReadOnly()) return false;
    final id = _asInt(row['id']);
    if (_busyRows.contains(id)) return false;
    setState(() => _busyRows.add(id));
    await _flushSave(id);
    var ok = false;
    try {
      var res = await http.post(
        Uri.parse('$_baseUrl$path'),
        headers: _headers,
        body: jsonEncode({'task_item_id': row['id'], ...extra}),
      );
      if (!mounted) return false;
      final holdReason = await _autoHoldReasonFor(res);
      if (holdReason != null && holdReason.isNotEmpty) {
        res = await http.post(
          Uri.parse('$_baseUrl$path'),
          headers: _headers,
          body: jsonEncode({
            'task_item_id': row['id'],
            ...extra,
            'auto_hold_reason': holdReason,
          }),
        );
        if (!mounted) return false;
      } else if (res.statusCode == 409 && res.body.contains('AUTO_HOLD_REASON_REQUIRED')) {
        return false; // user cancelled the reason dialog
      }
      if (res.statusCode == 200) {
        ok = true;
        setState(() => row['cc_status'] = nextCcStatus);
        await _reloadCurrentClient();
      } else {
        _showMessage(_errorFrom(res, errorMessage));
      }
    } catch (_) {
      _showMessage(errorMessage);
    } finally {
      if (mounted) setState(() => _busyRows.remove(id));
    }
    return ok;
  }

  Future<bool> _confirmAddToDayPlanner(
    Map<String, dynamic> row, {
    int rowCount = 1,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add task to today’s Day Planner?'),
        content: Text(
          '${_str(row['client_name'])} - ${_str(row['deliverable'])} '
          '($rowCount rows) will be added as one task before its timer starts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Add and Start'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _handleCalendarStart(Map<String, dynamic> row) async {
    if (_blockedReadOnly()) return;
    if (!await _confirmAddToDayPlanner(row) || !mounted) return;
    await _runAction(
      row,
      path: '/tasks/content-calendar/start',
      extra: {'day_planner_confirmed': true},
      nextCcStatus: 'IN PROGRESS',
      errorMessage: 'Unable to start this calendar row',
    );
  }

  Future<void> _handleCalendarHold(Map<String, dynamic> row) async {
    if (_blockedReadOnly()) return;
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _HoldReasonDialog(
        label: _str(row['hook_headline']).isEmpty
            ? _str(row['deliverable'])
            : _str(row['hook_headline']),
      ),
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    await _runAction(
      row,
      path: '/tasks/content-calendar/hold',
      extra: {'reason': reason},
      nextCcStatus: 'ON HOLD',
      errorMessage: 'Unable to put this calendar row on hold',
    );
  }

  Future<void> _handleCalendarComplete(Map<String, dynamic> row) async {
    if (_blockedReadOnly()) return;
    await _runAction(
      row,
      path: '/tasks/content-calendar/complete',
      nextCcStatus: 'COMPLETED',
      errorMessage: 'Unable to complete this calendar row',
    );
  }

  Future<void> _handleAssignAll(List<Map<String, dynamic>> rows) async {
    if (_blockedReadOnly()) return;
    final unassignedCompleted = rows
        .where((r) => !_isAssigned(r) && _ccStatusOf(r) == 'COMPLETED')
        .toList();
    if (unassignedCompleted.isEmpty) {
      _showMessage('Complete every row before assigning this sheet.');
      return;
    }

    final sourceRows = unassignedCompleted
        .where((r) => _asInt(r['source_assignment_id']) > 0)
        .toList();
    if (sourceRows.isNotEmpty) {
      final sheets = <String, List<Map<String, dynamic>>>{};
      for (final row in sourceRows) {
        final key =
            '${row['source_assignment_id']}:${row['source_role']}:${row['source_task_index']}';
        (sheets[key] ??= []).add(row);
      }
      for (final sheet in sheets.values) {
        if (sheet.any(
          (row) => _ccStatusOf(row) != 'COMPLETED' || _isAssigned(row),
        )) {
          continue;
        }
        final firstRow = sheet.first;
        // assign-sheet shares the entire source sheet, so every row of it
        // must be prepared (completed) first.
        final wholeSheet = _sheetRowsFor(firstRow);
        if (wholeSheet.any((row) =>
            _ccStatusOf(row) != 'COMPLETED' || _isAssigned(row))) {
          _showMessage('Complete every row in this sheet before assigning it.');
          continue;
        }
        final allocated = _str(firstRow['allocated_employee']).trim();
        if (allocated.isEmpty) {
          _showMessage('No employee is allocated to this sheet.');
          continue;
        }
        final shared = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _ShareConfirmDialog(
            baseUrl: _baseUrl,
            headers: _headers,
            row: firstRow,
            employeeName: allocated,
            employeeRole: _str(firstRow['allocated_role']),
          ),
        );
        if (shared == true && mounted) {
          _showMessage('Shared ${sheet.length} rows with $allocated');
        }
      }
      await _reloadCurrentClient();
      return;
    }

    final firstRow = unassignedCompleted.first;
    final allocated = _str(firstRow['allocated_employee']).trim();
    if (allocated.isEmpty) {
      _showMessage(
        'No employee allocated in Assigned Tasks. Use Emergency Assign.',
      );
      return;
    }

    final shared = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ShareConfirmDialog(
        baseUrl: _baseUrl,
        headers: _headers,
        row: firstRow,
        employeeName: allocated,
        employeeRole: _str(firstRow['allocated_role']),
      ),
    );
    if (shared != true || !mounted) return;

    var assignedCount = 1;
    for (final r in unassignedCompleted.skip(1)) {
      try {
        final response = await http.post(
          Uri.parse('$_baseUrl/tasks/content-calendar/assign-row'),
          headers: _headers,
          body: jsonEncode({
            'task_item_id': r['id'],
            'assigned_to_name': allocated,
            'assigned_by_id': widget.currentUserId,
            'assigned_by_name': widget.currentUserName,
          }),
        );
        if (response.statusCode == 200) {
          assignedCount++;
        } else {
          _showMessage(
            _errorFrom(response, 'Could not assign all calendar rows'),
          );
          break;
        }
      } catch (_) {
        _showMessage(
          'Could not assign all calendar rows. Check your connection.',
        );
        break;
      }
    }
    _showMessage(
      'Assigned $assignedCount of ${unassignedCompleted.length} items to $allocated',
    );
    await _reloadCurrentClient();
  }

  Future<void> _handleEmergency(Map<String, dynamic> row) async {
    if (_blockedReadOnly()) return;
    final id = _asInt(row['id']);
    if (_busyRows.contains(id) || _isApproved(row)) return;
    setState(() => _busyRows.add(id));
    await _flushSave(id);

    List<Map<String, dynamic>> team = [];
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/content-calendar/creative-team'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        team = List<Map<String, dynamic>>.from(
          jsonDecode(res.body)['employees'] ?? [],
        );
      } else {
        _showMessage(_errorFrom(res, 'Unable to load employees'));
        if (mounted) setState(() => _busyRows.remove(id));
        return;
      }
    } catch (_) {
      _showMessage('Unable to load employees. Check your connection.');
      if (mounted) setState(() => _busyRows.remove(id));
      return;
    }
    if (!mounted) return;
    setState(() => _busyRows.remove(id));

    final seen = <String>{};
    team = team.where((e) {
      final name = _str(e['full_name']).trim();
      return name.isNotEmpty && seen.add(name);
    }).toList();

    if (team.isEmpty) {
      _showMessage('No active employees available.');
      return;
    }

    final assignedName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EmergencyAssignDialog(
        baseUrl: _baseUrl,
        headers: _headers,
        row: row,
        team: team,
        currentlySharedWith: _isAssigned(row)
            ? _str(row['cc_assigned_to_name'])
            : '',
        assignedById: widget.currentUserId,
        assignedByName: widget.currentUserName,
      ),
    );
    if (assignedName == null || !mounted) return;
    setState(() {
      row['content_calendar_assigned'] = 1;
      row['is_emergency'] = 1;
      row['cc_assigned_to_name'] = assignedName;
    });
    _showMessage('Emergency assigned to $assignedName');
    await _reloadCurrentClient();
  }

  /// The opened card's date (Client + Submit date card), '' for the global view.
  String get _cardDateKey {
    final raw = _str(
      _selectedClient?['submission_date'] ??
          _selectedClient?['submit_date'] ??
          _selectedClient?['date'],
    ).trim();
    return raw.isEmpty ? '' : _dateKey(raw);
  }

  /// Ids of the rows shown on screen for this category (this card only).
  String _visibleIds(String deliverable) => _rowsFor(deliverable)
      .map((r) => _asInt(r['id']))
      .where((id) => id > 0)
      .join(',');

  Future<String?> _pickExportFormat(String deliverable, int count) {
    Widget option(BuildContext ctx, String value, IconData icon, String title, String sub) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(ctx, value),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kTint,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kTintBorder),
              ),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _kPrimary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, color: _kInk, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(sub, style: const TextStyle(color: _kMuted, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: _kPrimary),
              ]),
            ),
          ),
        );
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          const Icon(Icons.file_download_outlined, color: _kPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Export $deliverable · $count row${count == 1 ? '' : 's'}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ),
        ]),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(ctx, 'xls', Icons.table_view_rounded, 'Excel – GoDigital theme (.xls)',
                  'Blue & white sheet like the invoice export. Edit in Excel, save, import back.'),
              option(ctx, 'csv', Icons.description_outlined, 'CSV (.csv)',
                  'Same columns. Edit in Excel / Sheets, save as .csv, import back.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
  }

  Future<void> _exportSheet(String deliverable) async {
    for (final id in _saveDebouncers.keys.toList()) {
      await _flushSave(id);
    }
    final ids = _visibleIds(deliverable);
    if (ids.isEmpty) {
      _showMessage('No $deliverable rows in this card to export');
      return;
    }
    final format = await _pickExportFormat(deliverable, ids.split(',').length);
    if (format == null || !mounted) return;
    final client = _str(_selectedClient?['client_name']);
    final isCsv = format == 'csv';
    // Built here in the app from the rows on screen (this card + category
    // only), then saved straight to Downloads (web / PC) or shared (phone).
    final rows = _rowsFor(deliverable)
        .where((r) => _asInt(r['id']) > 0)
        .toList()
      ..sort((a, b) {
        final r = _asInt(a['s_no']).compareTo(_asInt(b['s_no']));
        return r != 0 ? r : _asInt(a['id']).compareTo(_asInt(b['id']));
      });
    final bytes = isCsv
        ? buildCalendarCsv(rows)
        : buildCalendarXls(
            clientName: client,
            deliverable: deliverable,
            rows: rows,
            cardDate: _cardDateKey,
            exportedBy: widget.currentUserName.trim(),
          );
    final fileName = calendarExportFileName(client, deliverable, _cardDateKey, isCsv ? 'csv' : 'xls');
    String? savedTo;
    try {
      savedTo = await saveCalendarFile(
        bytes,
        fileName,
        mimeType: isCsv ? 'text/csv;charset=utf-8' : 'application/vnd.ms-excel',
      );
    } catch (e) {
      _showMessage('Could not export: $e');
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          const Icon(Icons.check_circle_rounded, color: _kGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${rows.length} row${rows.length == 1 ? '' : 's'} exported',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ]),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _kTint,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kTintBorder),
                ),
                child: Text(
                  savedTo == null ? fileName : '$fileName\nSaved to: $savedTo',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: _kPrimary, fontSize: 12.5),
                ),
              ),
              _GuideStep(n: 1, text: isCsv
                  ? 'Open the .csv in Excel or Google Sheets.'
                  : 'Open the .xls in Excel (if Excel asks "format and extension don\'t match", press Yes).'),
              const _GuideStep(n: 2, text: 'Edit only Submit Date, Hook / Headline, Description, Caption, CTA, Publish Date, Notes. Keep S.No, ID and Deliverable as they are.'),
              const _GuideStep(n: 3, text: 'Dates as YYYY-MM-DD (e.g. 2026-10-29). DD-MM-YYYY also works.'),
              _GuideStep(n: 4, text: isCsv
                  ? 'Save it again as .csv (keep the header row).'
                  : 'Press Save (keep the same file), or Save As .xlsx / .csv – all three import.'),
              const _GuideStep(n: 5, text: 'Open this same card + category, press "Import Sheet" and choose the file.'),
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kPrimary),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _importSheet(String deliverable) async {
    if (_blockedReadOnly()) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xls', 'xlsx', 'csv'],
      withData: true,
    );
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null || !mounted) return;

    final lower = file.name.toLowerCase();
    if (!lower.endsWith('.xls') && !lower.endsWith('.xlsx') && !lower.endsWith('.csv')) {
      _showMessage('Choose the exported .xls, .xlsx or .csv file');
      return;
    }
    // .xls / .xlsx go as base64 — the server detects the GoDigital-theme
    // sheet (.xls), a real .xlsx, or an old Excel 97-2003 file.
    final isXlsx = lower.endsWith('.xlsx') || lower.endsWith('.xls');
    String? csv;
    String? xlsxBase64;
    try {
      if (isXlsx) {
        xlsxBase64 = base64Encode(bytes);
      } else {
        csv = utf8.decode(bytes, allowMalformed: true);
      }
    } catch (_) {
      _showMessage('Could not read that file');
      return;
    }

    for (final id in _saveDebouncers.keys.toList()) {
      await _flushSave(id);
    }
    if (!mounted) return;

    final applied = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImportPreviewDialog(
        baseUrl: _baseUrl,
        headers: _headers,
        clientName: _str(_selectedClient?['client_name']),
        deliverable: deliverable,
        fileName: file.name,
        csv: csv,
        xlsxBase64: xlsxBase64,
        ids: _visibleIds(deliverable),
      ),
    );
    if (applied == null || !mounted) return;
    _pendingEdits.clear();
    await _reloadCurrentClient();
    if (mounted) setState(() => _sheetRev++);
    _showMessage('Imported $applied row${applied == 1 ? '' : 's'}');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openClient(Map<String, dynamic> card) {
    setState(() {
      _selectedClient = card;
      _allCalendarRows = [];
      _categoryTabs = [];
      _selectedTabIndex = 0;
      _loading = true;
    });
    _fetchClientCalendarRows(_str(card['client_name']));
  }

  Future<void> _backToClients() async {
    for (final id in _saveDebouncers.keys.toList()) {
      await _flushSave(id);
    }
    if (!mounted) return;
    setState(() {
      _selectedClient = null;
      _allCalendarRows = [];
      _categoryTabs = [];
      _selectedTabIndex = 0;
    });
    await _fetchClientCards();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(50),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_selectedClient != null) return _buildClientCalendarWorkspace();
    return _buildClientCardsOverview();
  }

  Widget _buildClientCardsOverview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Content Calendar Directory',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: _kInk,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Prepare briefs, manage deliverables, and share them with designers and video editors.',
                      style: TextStyle(fontSize: 13, color: _kMuted),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => _fetchClientCards(),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (_clientCards.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(50),
                child: Text(
                  'No clients where you are the Page Handler or Ads Handler.',
                  style: TextStyle(color: _kMuted),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final cols = w > 1100 ? 3 : (w > 700 ? 2 : 1);
                var maxItems = 1;
                for (final c in _clientCards) {
                  final n = (c['deliverables_summary'] as List<dynamic>? ?? [])
                      .length;
                  if (n > maxItems) maxItems = n;
                }
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                    mainAxisExtent: 190 + maxItems * 22.0,
                  ),
                  itemCount: _clientCards.length,
                  itemBuilder: (context, idx) =>
                      _buildClientCard(_clientCards[idx]),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildClientCard(Map<String, dynamic> card) {
    final clientName = _str(card['client_name']).isEmpty
        ? 'Client'
        : _str(card['client_name']);
    final pending = card['pending_deliverables'] ?? 0;
    final completed = card['completed_deliverables'] ?? 0;
    final deliverables = card['deliverables_summary'] as List<dynamic>? ?? [];

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openClient(card),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _kTint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: _kPrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      clientName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _kInk,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: _kFaint),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (deliverables.isEmpty)
                      const Text(
                        'No assigned creator tasks',
                        style: TextStyle(fontSize: 11, color: _kFaint),
                      )
                    else ...[
                      for (final item in deliverables)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: _kPrimary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${item['task_title']} · ${item['employee_name']}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _kBody,
                                  ),
                                ),
                              ),
                              Tooltip(
                                message:
                                    'Completed by ${item['employee_name']}',
                                child: Text(
                                  '${item['progress']}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: item['is_done'] == true
                                        ? _kGreenDark
                                        : _kMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              Row(
                children: [
                  _countChip('Pending: $pending', _kAmberTint, _kAmberDark),
                  const SizedBox(width: 8),
                  _countChip('Done: $completed', _kGreenTint, _kGreenDark),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _openClient(card),
                  child: const Text(
                    'Open Content Calendar',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countChip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  Widget _buildClientCalendarWorkspace() {
    final clientName = _str(_selectedClient?['client_name']).isEmpty
        ? 'Client'
        : _str(_selectedClient?['client_name']);
    final category = _currentCategory ?? '';
    final rows = _rowsFor(category);
    final done = rows.where((row) => _ccStatusOf(row) == 'COMPLETED').length;
    final pending = rows.length - done;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_categoryTabs.isEmpty)
            _buildEmptyState()
          else ...[
            _sectionLabel('CONTENT CATEGORIES'),
            const SizedBox(height: 8),
            _buildCategoryTabs(),
            const SizedBox(height: 14),
            const SizedBox(height: 4),
            _buildTableHeader(category, pending, done, rows.length),
            const SizedBox(height: 10),
            _buildTable(rows),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.1,
      color: _kMuted,
    ),
  );

  Widget _buildHeader(String clientName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _kPrimary,
              side: const BorderSide(color: _kPrimary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _backToClients,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('All Clients'),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Content Calendar: ',
                    style: TextStyle(
                      color: _kMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: clientName,
                    style: const TextStyle(
                      color: _kInk,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 20),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshing ? null : _manualRefresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, color: _kPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.event_note_outlined, size: 40, color: _kFaint),
          const SizedBox(height: 10),
          const Text(
            'No content deliverables assigned for this client yet.',
            style: TextStyle(
              fontSize: 13,
              color: _kMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (widget.myTasksMode) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _handleAddContent,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add content'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryTab(int i) {
    final name = _categoryTabs[i];
    final isSelected = _selectedTabIndex == i;
    final rows = _rowsFor(name);
    final assigned = rows.where(_isAssigned).length;

    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => setState(() => _selectedTabIndex = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? _kPrimary : Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: isSelected ? _kPrimary : _kTintBorder),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? Colors.white : _kPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$assigned / ${rows.length} assigned',
              maxLines: 1,
              style: TextStyle(
                fontSize: 10.5,
                color: isSelected ? Colors.white70 : _kMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTabs() {
    if (_categoryTabs.length <= 4) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _kTint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kTintBorder),
        ),
        child: Row(
          children: [
            for (var i = 0; i < _categoryTabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: _buildCategoryTab(i)),
            ],
          ],
        ),
      );
    }

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: _kPrimary),
          onPressed: () => _tabScrollController.animateTo(
            math.max(0, _tabScrollController.offset - 180),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 68,
            child: ListView.separated(
              controller: _tabScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _categoryTabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _buildCategoryTab(i),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: _kPrimary),
          onPressed: () => _tabScrollController.animateTo(
            math.min(
              _tabScrollController.position.maxScrollExtent,
              _tabScrollController.offset + 180,
            ),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoAndControlPanel(
    String clientName,
    String category,
    List<Map<String, dynamic>> rows,
  ) {
    String allocatedName = '';
    String allocatedRole = '';
    for (final r in rows) {
      final n = _str(r['allocated_employee']).trim();
      if (n.isNotEmpty) {
        allocatedName = n;
        allocatedRole = _str(r['allocated_role']).trim();
        break;
      }
    }

    DateTime? earliest(Iterable<Map<String, dynamic>> src) {
      DateTime? best;
      for (final r in src) {
        final d = _parseDate(r['submit_date']);
        if (d != null && (best == null || d.isBefore(best))) best = d;
      }
      return best;
    }

    final submit =
        earliest(rows.where((r) => !_isAssigned(r))) ?? earliest(rows);
    String? daysLeft;
    Color daysColor = _kMuted;
    if (submit != null) {
      final diff = DateUtils.dateOnly(
        submit,
      ).difference(DateUtils.dateOnly(DateTime.now())).inDays;
      if (diff > 1) {
        daysLeft = '$diff Days Left';
        daysColor = diff <= 3 ? _kOrange : _kGreen;
      } else if (diff == 1) {
        daysLeft = '1 Day Left';
        daysColor = _kOrange;
      } else if (diff == 0) {
        daysLeft = 'Due Today';
        daysColor = _kOrange;
      } else {
        daysLeft = '${-diff} Day${diff == -1 ? '' : 's'} Overdue';
        daysColor = _kRed;
      }
    }

    var idle = 0, running = 0, held = 0, completed = 0, assigned = 0;
    for (final r in rows) {
      final s = _ccStatusOf(r);
      if (_isAssigned(r)) {
        assigned++;
      } else if (s == 'COMPLETED') {
        completed++;
      } else if (s == 'IN PROGRESS') {
        running++;
      } else if (s == 'ON HOLD') {
        held++;
      } else {
        idle++;
      }
    }

    final sourceSheets = <String, List<Map<String, dynamic>>>{};
    for (final row in rows.where(
      (row) => _asInt(row['source_assignment_id']) > 0,
    )) {
      final key =
          '${row['source_assignment_id']}:${row['source_role']}:${row['source_task_index']}';
      (sourceSheets[key] ??= []).add(row);
    }
    final manualRows = rows
        .where((row) => _asInt(row['source_assignment_id']) == 0)
        .toList();
    final manualRowsReady =
        manualRows.isNotEmpty &&
        manualRows.every(
          (row) => !_isAssigned(row) && _ccStatusOf(row) == 'COMPLETED',
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth > 760;
              final tileWidth = wide
                  ? (c.maxWidth - 36) / 4
                  : (c.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _infoTile(
                    'CLIENT',
                    clientName,
                    Icons.business_rounded,
                    tileWidth,
                  ),
                  _infoTile(
                    'DELIVERABLE',
                    category,
                    Icons.layers_outlined,
                    tileWidth,
                  ),
                  _infoTile(
                    'ASSIGNED EMPLOYEE',
                    allocatedName.isEmpty ? 'Not allocated' : allocatedName,
                    Icons.person_outline_rounded,
                    tileWidth,
                    sub: allocatedName.isEmpty
                        ? 'Allocate in Assigned Tasks'
                        : (allocatedRole.isEmpty ? null : allocatedRole),
                    subColor: allocatedName.isEmpty ? _kOrange : _kPrimary,
                  ),
                  _infoTile(
                    'SUBMIT DATE',
                    submit == null ? 'Not set' : _fmtLong(submit),
                    Icons.event_outlined,
                    tileWidth,
                    sub: daysLeft,
                    subColor: daysColor,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: _kBorder),
          const SizedBox(height: 16),
          Row(
            children: [
              _sectionLabel('ROW PREPARATION'),
              const Spacer(),
              Text(
                '$completed of ${rows.length - assigned} rows prepared',
                style: const TextStyle(
                  color: _kMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (sourceSheets.isNotEmpty || manualRowsReady)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final sheet in sourceSheets.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildSheetControlCard(sheet),
                  ),
                if (manualRowsReady)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _handleAssignAll(manualRows),
                      icon: const Icon(Icons.send, size: 16),
                      label: Text('ASSIGN ${manualRows.length} ROWS'),
                    ),
                  ),
              ],
            )
          else
            const Text(
              'Use the row actions below to prepare this deliverable.',
              style: TextStyle(color: _kMuted, fontSize: 11.5),
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _stageChip('START', idle, _kPrimary),
              _stageArrow(),
              _stageChip('IN PROGRESS', running, _kGreen),
              _stageArrow(),
              _stageChip('HOLD / RESTART', held, _kOrange),
              _stageArrow(),
              _stageChip('COMPLETED', completed, _kPurple),
              _stageArrow(),
              _stageChip('ASSIGN', completed, _kPrimary, outlined: true),
              _stageArrow(),
              _stageChip(
                'ASSIGNED',
                assigned,
                _kGreenDark,
                icon: Icons.check_circle,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSheetControlCard(List<Map<String, dynamic>> sheet) {
    if (sheet.isEmpty) return const SizedBox.shrink();
    final first = sheet.first;
    final statuses = sheet.map(_ccStatusOf).toSet();
    final handedOff = sheet.every(_isAssigned);
    final busy = sheet.any((row) => _busyRows.contains(_asInt(row['id'])));
    final allRunning = statuses.length == 1 && statuses.contains('IN PROGRESS');
    final allCompleted = statuses.length == 1 && statuses.contains('COMPLETED');
    final employee = _str(
      first['cc_assigned_to_name'] ?? first['allocated_employee'],
    ).trim();
    final employeeCanWork = handedOff &&
        (employee.isEmpty ||
            employee.toLowerCase() == widget.currentUserName.trim().toLowerCase());
    final canStart =
        (!handedOff || employeeCanWork) &&
        sheet.every(
          (row) =>
              (!_isAssigned(row) || employeeCanWork) &&
              {'IDLE', 'ON HOLD'}.contains(_ccStatusOf(row)),
        );
    final canShare = !handedOff && allCompleted;
    final prepared = sheet
        .where((row) => _ccStatusOf(row) == 'COMPLETED')
        .length;
    // Category timer: the running time lives on the sheet's leader row and is
    // advanced every second by _liveTicker; held time is kept on each row.
    final sheetSecs = sheet.fold<int>(
      0,
      (sum, row) => sum + _asInt(row['current_cc_secs'] ?? row['cc_duration_secs']),
    );
    final statusLabel = handedOff
        ? (employeeCanWork ? 'ASSIGNED TASK' : 'SHARED')
        : allCompleted
        ? 'READY TO SHARE'
        : allRunning
        ? 'PREPARATION RUNNING'
        : statuses.contains('ON HOLD')
        ? 'ON HOLD'
        : 'NOT STARTED';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_str(first['deliverable'])} · ${sheet.length} rows',
                  style: const TextStyle(
                    color: _kInk,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '$prepared/${sheet.length} prepared · $statusLabel'
                  '${employee.isEmpty ? '' : ' · For $employee'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _kMuted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: allRunning ? _kTint : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: allRunning ? _kPrimary : _kBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  allRunning ? Icons.timer_rounded : Icons.timer_outlined,
                  size: 14,
                  color: allRunning ? _kPrimary : _kMuted,
                ),
                const SizedBox(width: 5),
                Text(
                  _fmtTimer(sheetSecs),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: allRunning ? _kPrimary : _kInk,
                  ),
                ),
              ],
            ),
          ),
          if (!handedOff && !allCompleted) _plannerButtonFor(sheet, busy),
          if (canStart)
            _prepActionButton(
              label: statuses.contains('ON HOLD') ? 'RESTART' : 'START',
              color: _kPrimary,
              icon: Icons.play_arrow_rounded,
              onTap: busy ? null : () => _handleSheetAction(sheet, 'start'),
            ),
          if (allRunning && (!handedOff || employeeCanWork)) ...[
            _prepActionButton(
              label: 'HOLD',
              color: _kOrange,
              icon: Icons.pause_rounded,
              onTap: busy ? null : () => _handleSheetAction(sheet, 'hold'),
            ),
            _prepActionButton(
              label: 'COMPLETED',
              color: _kGreen,
              icon: Icons.check_rounded,
              onTap: busy ? null : () => _handleSheetAction(sheet, 'complete'),
            ),
          ],
          if (canShare)
            _prepActionButton(
              label: 'ASSIGN ALL',
              color: _kPrimary,
              icon: Icons.send_rounded,
              onTap: busy ? null : () => _handleAssignAll(sheet),
            ),
          if (handedOff)
            _badge(
              'SHARED WITH ${employee.toUpperCase()}',
              _kGreenTint,
              _kGreenDark,
              icon: Icons.check_circle_outline,
            ),
        ],
      ),
    );
  }

  Widget _infoTile(
    String label,
    String value,
    IconData icon,
    double width, {
    String? sub,
    Color? subColor,
  }) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: _kFaint),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: _kMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _kInk,
              height: 1.25,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(
              sub,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: subColor ?? _kMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stageChip(
    String label,
    int count,
    Color color, {
    bool outlined = false,
    IconData? icon,
  }) {
    final active = count > 0;
    final fill = outlined ? Colors.white : (active ? color : Colors.white);
    final fg = outlined
        ? color
        : (active ? Colors.white : color.withOpacity(0.55));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: active ? color : color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: fg,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: outlined || !active
                  ? color.withOpacity(0.1)
                  : Colors.white.withOpacity(0.22),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stageArrow() =>
      const Icon(Icons.arrow_forward_rounded, size: 15, color: _kFaint);

  Widget _buildAssignedDeliverablesRows(List<Map<String, dynamic>> rows) {
    const headingStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: _kBody,
      letterSpacing: 0.35,
    );
    final visibleRows = rows;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _sheetGrid),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(_sheetHeader),
          headingRowHeight: 42,
          dataRowMinHeight: 56,
          dataRowMaxHeight: 100,
          columnSpacing: 0,
          horizontalMargin: 0,
          columns: const [
            DataColumn(label: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('DELIVERABLES', style: headingStyle))),
            DataColumn(label: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('SUBMIT DATE', style: headingStyle))),
            DataColumn(label: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('ASSIGNED EMPLOYEE', style: headingStyle))),
            DataColumn(label: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('ACTION', style: headingStyle))),
          ],
          rows: visibleRows.map((row) {
            final assignedName = _employeeOf(row);
            final deliverable = _str(row['deliverable']).isNotEmpty
                ? _str(row['deliverable'])
                : (_str(row['deliverable_name']).isNotEmpty
                    ? _str(row['deliverable_name'])
                : (_str(row['task_title']).isNotEmpty
                    ? _str(row['task_title'])
                    : (_str(row['content_type']).isNotEmpty ? _str(row['content_type']) : (_currentCategory ?? 'Deliverable'))));
            return DataRow(cells: [
              DataCell(Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: SizedBox(width: 180, child: Text(deliverable, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: _kInk))))),
              DataCell(Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _buildDateChip(row, 'submit_date'))),
              DataCell(Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: SizedBox(width: 180, child: Text(assignedName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kBody))))),
              DataCell(Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _buildPreparationCell(row))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _approvedUnassignedRows(
    List<Map<String, dynamic>> rows,
  ) => rows.where((row) =>
      !_isAssigned(row) && _ccStatusOf(row) == 'COMPLETED').toList();

  String _commonAssignedEmployee(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      for (final key in const [
        'allocated_employee',
        'allocated_employee_name',
        'cc_assigned_to_name',
        'assigned_to_name',
        'employee_name',
      ]) {
        final name = _str(row[key]).trim();
        if (name.isNotEmpty && name.toLowerCase() != 'unassigned') {
          return name;
        }
      }
    }
    return 'Not assigned';
  }

  Widget _buildTableHeader(String category, int pending, int done, int total) {
    final rows = _rowsFor(category);
    final selectedDate = _str(
      _selectedClient?['submission_date'] ??
          _selectedClient?['submit_date'] ??
          _selectedClient?['date'],
    ).trim();
    final dateLabel = selectedDate.isNotEmpty
        ? (_parseDate(selectedDate) == null
            ? selectedDate
            : _fmtSlash(_parseDate(selectedDate)!))
        : (rows.isEmpty
            ? '—'
            : (_parseDate(rows.first['submit_date']) == null
                ? _str(rows.first['submit_date'])
                : _fmtSlash(_parseDate(rows.first['submit_date'])!)));
    final assignedEmployee = _commonAssignedEmployee(rows);
    final readyToAssign = _approvedUnassignedRows(rows).isNotEmpty;

    // Group all rows belonging to the same admin-assigned sheet. For example,
    // two MG rows from one assignment get one shared action controller, not
    // duplicate Start/Hold/Restart/Complete buttons on each card.
    final sourceSheets = <String, List<Map<String, dynamic>>>{};
    if (widget.myTasksMode) {
      for (final row in rows.where((r) => _asInt(r['source_assignment_id']) > 0)) {
        // One action group per category in the same admin assignment. For example,
        // two MG deliverables in one assignment share one Start/Hold/Complete/Assign
        // control instead of displaying one set of buttons per row.
        final deliverableKey = _str(
          row['deliverable'] ??
              row['deliverable_name'] ??
              row['content_type'] ??
              category,
        ).trim().toLowerCase();
        final key =
            '${row['source_assignment_id']}:${row['source_role']}:$deliverableKey';
        (sourceSheets[key] ??= []).add(row);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _countChip('Submit Date: $dateLabel', _kTint, _kPrimary),
            _countChip('Assigned Employee: $assignedEmployee', const Color(0xFFF1F5F9), _kBody),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              width: 4,
              height: 22,
              decoration: BoxDecoration(
                color: _kPrimary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              category.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: _kInk,
                letterSpacing: 0.6,
              ),
            ),
            _countChip('Pending: $pending', _kAmberTint, _kAmberDark),
            _countChip('Done: $done', _kGreenTint, _kGreenDark),
            _countChip('Rows: $total', const Color(0xFFF1F5F9), _kBody),
            if (widget.myTasksMode && readyToAssign && sourceSheets.isEmpty)
              _sheetButton(
                'Assign',
                Icons.assignment_turned_in_outlined,
                'Assign approved tasks to the employee allocated by admin.',
                () => _handleAssignAll(rows),
                filled: true,
              ),
            if (widget.myTasksMode)
              for (final sheet in sourceSheets.values)
                _buildSheetControlCard(sheet),
            if (widget.myTasksMode)
              _sheetButton(
                'Add content',
                Icons.add_rounded,
                'Add new content rows — pick the deliverable from the list.',
                _handleAddContent,
                filled: true,
              ),
            _sheetButton(
              'Export Template',
              Icons.file_download_outlined,
              'Download this card\'s rows as an Excel sheet (GoDigital theme) or CSV — edit and import back.',
              () => _exportSheet(category),
            ),
            _sheetButton(
              'Import Sheet',
              Icons.file_upload_outlined,
              'Upload the exported file after editing (.xls, .xlsx or .csv).',
              () => _importSheet(category),
              filled: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _sheetButton(
    String label,
    IconData icon,
    String tip,
    VoidCallback onTap, {
    bool filled = false,
  }) {
    const sheetsGreen = Color(0xFF188038);
    return Tooltip(
      message: tip,
      child: filled
          ? ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: sheetsGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: onTap,
              icon: Icon(icon, size: 16),
              label: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: sheetsGreen,
                side: const BorderSide(color: sheetsGreen),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: onTap,
              icon: Icon(icon, size: 16),
              label: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }

  static const _sheetHeader = Color(0xFFF1F3F4);
  static const _sheetGrid = Color(0xFFDADCE0);
  static const _sheetFocus = Color(0xFF1A73E8);

  Widget _buildTable(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _sheetGrid),
        ),
        child: const Text(
          'No rows in this category.',
          style: TextStyle(color: _kMuted),
        ),
      );
    }

    return Column(
      children: rows.map((row) {
        final assignedName = _employeeOf(row);
        final deliverable = _str(row['deliverable']).isNotEmpty
            ? _str(row['deliverable'])
            : (_str(row['deliverable_name']).isNotEmpty
                ? _str(row['deliverable_name'])
                : (_str(row['task_title']).isNotEmpty
                    ? _str(row['task_title'])
                    : (_str(row['content_type']).isNotEmpty
                        ? _str(row['content_type'])
                        : (_currentCategory ?? 'Deliverable'))));
        final approved = _isApproved(row);
        final emergency = _isEmergency(row);

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: approved
                ? const Color(0xFFF0FDF4)
                : (emergency ? const Color(0xFFFFF7F7) : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: approved
                  ? const Color(0xFFBBF7D0)
                  : (emergency ? const Color(0xFFFECACA) : _sheetGrid),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: _kTint,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'S.No ${row['s_no'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _kPrimary,
                      ),
                    ),
                  ),
                  Text(
                    deliverable,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _kInk,
                    ),
                  ),
                  _buildDateChip(row, 'submit_date'),
                  if (widget.myTasksMode &&
                      _asInt(row['source_assignment_id']) == 0 &&
                      !_isAssigned(row) &&
                      _ccStatusOf(row) == 'IDLE')
                    IconButton(
                      tooltip: 'Remove this row',
                      onPressed: () => _deleteManualRow(row),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: _kRed),
                      visualDensity: VisualDensity.compact,
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_outline, size: 15, color: _kPrimary),
                      const SizedBox(width: 4),
                      Text(
                        assignedName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _kBody,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, gridConstraints) {
                  final gridWidth = gridConstraints.maxWidth;
                  final contentColumns = gridWidth >= 1000
                      ? 4
                      : (gridWidth >= 560 ? 2 : 1);
                  final contentFieldWidth =
                      (gridWidth - (contentColumns - 1) * 14) /
                          contentColumns;
                  final showAction =
                      _asInt(row['source_assignment_id']) == 0;
                  final detailsColumns = gridWidth >= 1000
                      ? (showAction ? 5 : 4)
                      : (gridWidth >= 560 ? 2 : 1);
                  final detailFieldWidth =
                      (gridWidth - (detailsColumns - 1) * 14) /
                          detailsColumns;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isWebsiteRow(row))
                        _calendarCardField(
                          'DESCRIPTION',
                          RichDescription.preview(
                            deltaJson: _str(row['description_rich']),
                            fallbackPlain: _str(row['description_points']),
                            editable: !_isAssigned(row),
                            width: gridWidth >= 460 ? 440 : gridWidth - 10,
                            emptyLabel: 'Click to write the website content…',
                            onOpen: () => _openRichDescription(row),
                          ),
                          width: gridWidth,
                        )
                      else
                        Wrap(
                          spacing: 14,
                          runSpacing: 12,
                          children: [
                            _calendarCardField(
                              'HOOK / HEADLINE',
                              _sheetTextCell(row, 'hook_headline',
                                  'Type headline...', contentFieldWidth - 10),
                              width: contentFieldWidth,
                            ),
                            _calendarCardField(
                              'DESCRIPTION',
                              _sheetTextCell(row, 'description_points',
                                  'Type description...', contentFieldWidth - 10),
                              width: contentFieldWidth,
                            ),
                            _calendarCardField(
                              'CAPTION',
                              _sheetTextCell(row, 'caption',
                                  'Type caption...', contentFieldWidth - 10),
                              width: contentFieldWidth,
                            ),
                            _calendarCardField(
                              'CTA',
                              _sheetTextCell(row, 'cta',
                                  'Type CTA...', contentFieldWidth - 10),
                              width: contentFieldWidth,
                            ),
                          ],
                        ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 14,
                        runSpacing: 12,
                        children: [
                          if (!_isWebsiteRow(row))
                            _calendarCardField(
                              'POST DATE',
                              _buildDateChip(row, 'publish_date'),
                              width: detailFieldWidth,
                            ),
                          _calendarCardField(
                            'NOTES',
                            _sheetTextCell(row, 'notes',
                                'Add notes...', detailFieldWidth - 10),
                            width: detailFieldWidth,
                          ),
                          if (showAction)
                            _calendarCardField(
                              'ACTION',
                              _buildPreparationCell(row),
                              width: detailFieldWidth,
                            ),
                          _calendarCardField(
                            _isAssigned(row) ? 'EMPLOYEE STATUS' : 'STATUS',
                            _buildStatusCell(row),
                            width: detailFieldWidth,
                          ),
                          _calendarCardField(
                            _isAssigned(row)
                                ? 'EDIT ASSIGNMENT'
                                : 'EMERGENCY ASSIGN',
                            _buildEmergencyCell(row),
                            width: detailFieldWidth,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _calendarCardField(String label, Widget child, {double width = 220}) {
    // GD_CALENDAR_HEADING_STYLE_V1: style only; preserve existing field behavior.
    final isStatus = label == 'STATUS' || label == 'EMPLOYEE STATUS';
    final isEmergency = label == 'EMERGENCY ASSIGN' ||
        label == 'EDIT ASSIGNMENT';
    final accent = isEmergency
        ? const Color(0xFFDC2626)
        : (isStatus ? const Color(0xFF15803D) : const Color(0xFF0052CC));
    final lightBackground = isEmergency
        ? const Color(0xFFFFF1F2)
        : (isStatus ? const Color(0xFFF0FDF4) : const Color(0xFFEFF6FF));

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: lightBackground,
              border: Border(left: BorderSide(color: accent, width: 3)),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.45,
                color: accent,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
DataColumn _sheetColumn(
    String label,
    TextStyle style, {
    bool center = false,
  }) => DataColumn(
    label: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: center
          ? SizedBox(
              width: 32,
              child: Center(child: Text(label, style: style)),
            )
          : Text(label, style: style),
    ),
  );

  Widget _sheetPad(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: child,
  );

  Widget _prepActionButton({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback? onTap,
  }) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      minimumSize: const Size(0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    ),
    onPressed: onTap,
    icon: Icon(icon, size: 13),
    label: Text(
      label,
      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800),
    ),
  );

  // Keep per-row preparation actions for the standalone Content Calendar.
  // Employee Workspace uses the category-level controls in _buildTableHeader.
  Widget _buildPreparationCell(Map<String, dynamic> row) {
    final status = _ccStatusOf(row);
    final isTimerOwner = _isSheetLeader(row);
    final seconds = isTimerOwner ? _asInt(row['current_cc_secs']) : 0;
    final busy = _busyRows.contains(_asInt(row['id']));
    final actions = <Widget>[];
    if (!_isAssigned(row) || widget.myTasksMode) {
      if (status == 'IN PROGRESS') {
        actions.add(
          _prepActionButton(
            label: 'HOLD',
            color: _kOrange,
            icon: Icons.pause,
            onTap: busy ? null : () => _handleCalendarHold(row),
          ),
        );
        actions.add(
          _prepActionButton(
            label: 'COMPLETE',
            color: _kGreen,
            icon: Icons.check,
            onTap: busy ? null : () => _handleCalendarComplete(row),
          ),
        );
      } else if (status == 'IDLE' || status == 'ON HOLD') {
        actions.add(
          _prepActionButton(
            label: status == 'ON HOLD'
                ? (widget.myTasksMode ? 'RESTART' : 'RESUME')
                : 'START',
            color: _kPrimary,
            icon: status == 'ON HOLD' ? Icons.play_arrow : Icons.add_task,
            onTap: busy ? null : () => _handleCalendarStart(row),
          ),
        );
      }
    }

    return SizedBox(
      width: 190,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _badge(
                _isAssigned(row)
                    ? 'HANDED OFF'
                    : status == 'COMPLETED'
                    ? 'PREPARED'
                    : status,
                _isAssigned(row)
                    ? _kGreenTint
                    : status == 'COMPLETED'
                    ? const Color(0xFFEDE9FE)
                    : status == 'IN PROGRESS'
                    ? _kTint
                    : status == 'ON HOLD'
                    ? _kAmberTint
                    : _kSurface,
                _isAssigned(row)
                    ? _kGreenDark
                    : status == 'COMPLETED'
                    ? _kPurple
                    : status == 'IN PROGRESS'
                    ? _kPrimary
                    : status == 'ON HOLD'
                    ? _kAmberDark
                    : _kMuted,
              ),
              const SizedBox(width: 7),
              Text(
                _fmtTimer(seconds),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _kInk,
                ),
              ),
            ],
          ),
          if (_str(row['cc_hold_reason']).isNotEmpty && status == 'ON HOLD')
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                _str(row['cc_hold_reason']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9.5, color: _kMuted),
              ),
            ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Wrap(spacing: 4, runSpacing: 4, children: actions),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusCell(Map<String, dynamic> row) {
    if (!_isAssigned(row)) {
      return const SizedBox(
        width: 140,
        child: Text('Not shared', style: TextStyle(color: _kFaint)),
      );
    }
    final name = _str(row['task_employee_name']).isNotEmpty
        ? _str(row['task_employee_name'])
        : _str(row['cc_assigned_to_name']);
    if (_str(row['task_status']).isNotEmpty) {
      return _employeeProgressCell(row, name);
    }

    if (_isApproved(row)) {
      return SizedBox(
        width: 140,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _badge(
              'ASSIGNED',
              _kGreenTint,
              _kGreenDark,
              icon: Icons.verified_rounded,
            ),
            if (name.isNotEmpty) _caption('to $name', _kGreenDark),
          ],
        ),
      );
    }

    return SizedBox(
      width: 140,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_rounded, size: 14, color: _kPrimary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  name.isEmpty ? 'Employee' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                  ),
                ),
              ),
            ],
          ),
          _caption('Assigned', _kGreenDark),
        ],
      ),
    );
  }

  Widget _badge(
    String text,
    Color bg,
    Color fg, {
    IconData? icon,
    Color? border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border ?? fg.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _caption(String text, Color color) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
    ),
  );

  Widget _buildEmergencyCell(Map<String, dynamic> row) {
    if (_isAssigned(row) && _asInt(row['source_assignment_id']) > 0 &&
        _employeeState(row) != 'APPROVED') {
      final id = _asInt(row['id']);
      return SizedBox(
        width: 150,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: _kPrimary,
            side: const BorderSide(color: _kPrimary),
            minimumSize: const Size(84, 30),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          onPressed: _busyRows.contains(id) ? null : () => _handleEditAssigned(row),
          icon: const Icon(Icons.edit_rounded, size: 14),
          label: const Text(
            'EDIT',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ),
      );
    }
    if (_isApproved(row) || _isAssigned(row)) {
      return const SizedBox(
        width: 150,
        child: Text('—', style: TextStyle(color: _kFaint)),
      );
    }
    final emergency = _isEmergency(row);
    final id = _asInt(row['id']);

    return SizedBox(
      width: 150,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _kRed,
              backgroundColor: emergency ? _kRedTint : Colors.white,
              side: const BorderSide(color: _kRed),
              minimumSize: const Size(84, 30),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: _busyRows.contains(id)
                ? null
                : () => _handleEmergency(row),
            icon: const Icon(Icons.bolt_rounded, size: 14),
            label: const Text(
              'ASSIGN',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ),
          if (emergency)
            Tooltip(
              message: _str(row['cc_emergency_reason']),
              child: _caption('⚡ ${_str(row['cc_assigned_to_name'])}', _kRed),
            ),
        ],
      ),
    );
  }

  /// "Add content": choose a deliverable (from the client's assigned work),
  /// how many rows, and the submit date → blank rows in the same card format.
  Future<void> _handleAddContent() async {
    if (_blockedReadOnly()) return;
    final client = _str(_selectedClient?['client_name']);
    if (client.isEmpty) return;
    List<Map<String, dynamic>> options = [];
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/tasks/content-calendar/deliverable-options/${Uri.encodeComponent(client)}'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        options = List<Map<String, dynamic>>.from(jsonDecode(res.body)['data'] ?? []);
      } else {
        _showMessage(_errorFrom(res, 'Unable to load deliverables'));
      }
    } catch (_) {
      _showMessage('Unable to load deliverables. Check your connection.');
    }
    if (!mounted) return;

    String? deliverable = _currentCategory;
    if (deliverable != null && !options.any((o) => _str(o['name']) == deliverable)) {
      options.insert(0, {'name': deliverable, 'group': 'Calendar'});
    }
    deliverable ??= options.isNotEmpty ? _str(options.first['name']) : null;
    final otherController = TextEditingController();
    var useOther = options.isEmpty;
    var count = 1;
    final initialDate = _parseDate(_selectedClient?['submission_date']);
    String submit = initialDate == null ? '' : _fmtIso(initialDate);
    String? error;

    // A submit date must be today or later, and not after this card's
    // submit date (the client deadline). Checked as soon as it is picked.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cardDay = _parseDate(_cardDateKey);
    String? dateProblem(String value) {
      final d = _parseDate(value);
      if (d == null) return null; // no date → the card's date is used
      final day = DateTime(d.year, d.month, d.day);
      if (day.isBefore(today)) {
        return 'Invalid submit date ${_fmtSlash(day)} — it is already past. '
            'Pick today (${_fmtSlash(today)}) or later. Rows will not be added with this date.';
      }
      if (cardDay != null && !cardDay.isBefore(today) && day.isAfter(cardDay)) {
        return 'Invalid submit date ${_fmtSlash(day)} — it is after this card\'s submit date '
            '${_fmtSlash(cardDay)}. Pick a date up to ${_fmtSlash(cardDay)}. Rows will not be added with this date.';
      }
      return null;
    }
    String? dateError = dateProblem(submit);

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setD) => AlertDialog(
          title: const Text('Add content'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (options.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: useOther ? '__other__' : deliverable,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Deliverable',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final o in options)
                        DropdownMenuItem(
                          value: _str(o['name']),
                          child: Text('${_str(o['name'])}   ·   ${_str(o['group'])}'),
                        ),
                      const DropdownMenuItem(value: '__other__', child: Text('Other…')),
                    ],
                    onChanged: (v) => setD(() {
                      useOther = v == '__other__';
                      if (!useOther) deliverable = v;
                    }),
                  ),
                if (useOther) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: otherController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'New deliverable name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text('Rows', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 10),
                    IconButton(
                      onPressed: count > 1 ? () => setD(() => count--) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('$count', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    IconButton(
                      onPressed: count < 50 ? () => setD(() => count++) : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: _parseDate(submit) ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setD(() {
                            submit = _fmtIso(picked);
                            dateError = dateProblem(submit);
                          });
                        }
                      },
                      style: dateError == null
                          ? null
                          : OutlinedButton.styleFrom(
                              foregroundColor: _kRed,
                              side: const BorderSide(color: _kRed),
                            ),
                      icon: Icon(
                        dateError == null ? Icons.calendar_month_outlined : Icons.error_outline_rounded,
                        size: 15,
                      ),
                      label: Text(_parseDate(submit) == null
                          ? 'Submit date'
                          : 'Submit ${_fmtSlash(_parseDate(submit)!)}'),
                    ),
                  ],
                ),
                if (dateError != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kRedTint,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kRed.withOpacity(0.35)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.event_busy_rounded, color: _kRed, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            dateError!,
                            style: const TextStyle(color: _kRed, fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_parseDate(submit) != null &&
                    cardDay != null &&
                    _fmtIso(_parseDate(submit)!) != _fmtIso(cardDay))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Rows stay in this card (${_fmtSlash(cardDay)}) with submit date '
                      '${_fmtSlash(_parseDate(submit)!)}.',
                      style: const TextStyle(color: _kMuted, fontSize: 12),
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(error!, style: const TextStyle(color: _kRed, fontSize: 12)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              // Blocked while the submit date is invalid.
              onPressed: dateError != null ? null : () {
                final name = useOther ? otherController.text.trim() : (deliverable ?? '');
                if (name.isEmpty) {
                  setD(() => error = 'Choose or type a deliverable');
                  return;
                }
                deliverable = name;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Add rows'),
            ),
          ],
        ),
      ),
    );
    otherController.dispose();
    if (ok != true || !mounted || deliverable == null) return;

    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/tasks/content-calendar/add-row'),
        headers: _headers,
        body: jsonEncode({
          'client_name': client,
          'deliverable': deliverable,
          'count': count,
          if (_parseDate(submit) != null) 'submit_date': _fmtIso(_parseDate(submit)!),
          // Keep the rows on the card they were added in, whatever submit date.
          if (_cardDateKey.isNotEmpty) 'card_date': _cardDateKey,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 201 || res.statusCode == 200) {
        final picked = _parseDate(submit);
        _showMessage(picked == null
            ? '$count $deliverable row(s) added'
            : '$count $deliverable row(s) added · Submit ${_fmtSlash(picked)}');
        await _reloadCurrentClient();
        final index = _categoryTabs.indexOf(deliverable!);
        if (index >= 0 && mounted) setState(() => _selectedTabIndex = index);
      } else {
        _showMessage(_errorFrom(res, 'Unable to add rows'));
      }
    } catch (_) {
      _showMessage('Unable to add rows. Check your connection.');
    }
  }

  Future<void> _deleteManualRow(Map<String, dynamic> row) async {
    if (_blockedReadOnly()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove this row?'),
        content: Text('${_str(row['deliverable'])} · S.No ${_str(row['s_no'])} will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/tasks/content-calendar/row/${_asInt(row['id'])}'),
        headers: _headers,
      );
      if (!mounted) return;
      _showMessage(res.statusCode == 200 ? 'Row removed' : _errorFrom(res, 'Unable to remove this row'));
      await _reloadCurrentClient();
    } catch (_) {
      _showMessage('Unable to remove this row. Check your connection.');
    }
  }

  bool _isWebsiteRow(Map<String, dynamic> row) =>
      _str(row['source_role']) == 'website_designer';

  Future<void> _openRichDescription(Map<String, dynamic> row) async {
    final title = '${_str(row['deliverable'])} · S.No ${_str(row['s_no'])}';
    if (_isAssigned(row)) {
      await RichDescription.view(
        context,
        title: title,
        deltaJson: _str(row['description_rich']),
        fallbackPlain: _str(row['description_points']),
      );
      return;
    }
    final result = await RichDescription.edit(
      context,
      title: title,
      deltaJson: _str(row['description_rich']),
      fallbackPlain: _str(row['description_points']),
    );
    if (result == null || !mounted) return;
    final (json, plain) = result;
    setState(() {
      _onFieldChanged(row, 'description_rich', json);
      _onFieldChanged(row, 'description_points', plain);
    });
    await _flushSave(_asInt(row['id']));
  }

  /// Status of the employee's work on an assigned row.
  String _employeeState(Map<String, dynamic> row) {
    final status = _str(row['task_status']).toUpperCase();
    final review = _str(row['review_status']).toUpperCase();
    if (review == 'APPROVED') return 'APPROVED';
    if (status == 'REWORK' || (review == 'REWORK' && status != 'IN PROGRESS' && status != 'ON HOLD')) {
      return 'REWORK';
    }
    if (status == 'COMPLETED') return review == 'REJECTED' ? 'REJECTED' : 'IN REVIEW';
    return status.isEmpty ? 'IDLE' : status;
  }

  Widget _employeeProgressCell(Map<String, dynamic> row, String name) {
    final state = _employeeState(row);
    final (label, bg, fg) = switch (state) {
      'IN PROGRESS' => ('WORKING', _kTint, _kPrimary),
      'ON HOLD' => ('ON HOLD', _kAmberTint, _kAmberDark),
      'IN REVIEW' => ('COMPLETED · IN REVIEW', const Color(0xFFEDE9FE), _kPurple),
      'REWORK' => ('REWORK', const Color(0xFFFFEDD5), const Color(0xFFC2410C)),
      'APPROVED' => ('APPROVED', _kGreenTint, _kGreenDark),
      'REJECTED' => ('REJECTED', _kRedTint, _kRed),
      _ => ('NOT STARTED', _kSurface, _kMuted),
    };
    final secs = _asInt(row['task_duration_secs']);
    return SizedBox(
      width: 240,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_rounded, size: 14, color: _kPrimary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  name.isEmpty ? 'Employee' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _kInk),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _badge(label, bg, fg),
              Text(
                state == 'IN PROGRESS' ? 'running' : _fmtTimer(secs),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _kInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => _showWorkDetails(row, name),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'View work details',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: _kPrimary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtStamp(dynamic value) {
    final parsed = DateTime.tryParse(_str(value));
    if (parsed == null) return '—';
    final d = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(h)}:${two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  void _showWorkDetails(Map<String, dynamic> row, String name) {
    final lines = <(String, String)>[
      ('Employee', name.isEmpty ? '—' : name),
      ('Status', _employeeState(row)),
      ('Started', _fmtStamp(row['task_start_time'])),
    ];
    for (var i = 1; i <= 10; i++) {
      final hold = row['hold_time_$i'];
      final restart = row['restart_time_$i'];
      if (_str(hold).isEmpty && _str(restart).isEmpty) continue;
      if (_str(hold).isNotEmpty) lines.add(('Hold $i', _fmtStamp(hold)));
      if (_str(restart).isNotEmpty) lines.add(('Restart $i', _fmtStamp(restart)));
    }
    lines.addAll([
      ('Completed', _fmtStamp(row['task_complete_time'])),
      ('Duration', _fmtTimer(_asInt(row['task_duration_secs']))),
      ('Performance', _str(row['task_performance']).isEmpty ? 'N/A' : _str(row['task_performance'])),
      ('Review', _str(row['task_review_action']).isEmpty ? '—' : _str(row['task_review_action'])),
      if (_str(row['task_review_comment']).isNotEmpty) ('Review comment', _str(row['task_review_comment'])),
      if (_str(row['task_comment']).isNotEmpty) ('Hold reasons / log', _str(row['task_comment'])),
      if (_str(row['task_employee_notes']).isNotEmpty) ('Employee notes', _str(row['task_employee_notes'])),
    ]);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${_str(row['deliverable'])} · S.No ${_str(row['s_no'])} — work details'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (label, value) in lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 150,
                          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        Expanded(child: SelectableText(value)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
        ],
      ),
    );
  }

  /// Edit on an assigned row: correct its content (until the employee
  /// completes it) or move it to another employee.
  Future<void> _handleEditAssigned(Map<String, dynamic> row) async {
    final state = _employeeState(row);
    final canCorrect = state != 'IN REVIEW' && state != 'APPROVED';
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Edit · ${_str(row['deliverable'])} S.No ${_str(row['s_no'])}'),
        children: [
          SimpleDialogOption(
            onPressed: canCorrect ? () => Navigator.pop(dialogContext, 'content') : null,
            child: ListTile(
              enabled: canCorrect,
              leading: const Icon(Icons.edit_note_rounded, color: _kPrimary),
              title: const Text('Correct content'),
              subtitle: Text(
                canCorrect
                    ? 'Fix the headline, description, caption, CTA, dates or notes. The employee sees the change in My Tasks.'
                    : 'The employee has completed this row — send it for rework in Task Review first.',
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'move'),
            child: const ListTile(
              leading: Icon(Icons.swap_horiz_rounded, color: _kPrimary),
              title: Text('Move to another employee'),
              subtitle: Text('Normal or emergency reassignment of this row.',
                  style: TextStyle(fontSize: 11.5)),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'content') await _handleCorrectContent(row);
    if (choice == 'move') await _handleReassign(row);
  }

  Future<void> _handleCorrectContent(Map<String, dynamic> row) async {
    if (_blockedReadOnly()) return;
    final id = _asInt(row['id']);
    final website = _isWebsiteRow(row);
    final controllers = {
      for (final f in ['hook_headline', 'description_points', 'caption', 'cta', 'notes'])
        f: TextEditingController(text: _str(row[f])),
    };
    String submit = _str(row['submit_date']);
    String post = _str(row['publish_date']);
    String rich = _str(row['description_rich']);
    String richPlain = _str(row['description_points']);

    Widget field(String key, String label, {int lines = 2}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controllers[key],
        minLines: 1,
        maxLines: lines,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      ),
    );

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setD) {
          Future<void> pickDate(bool isSubmit) async {
            final current = _parseDate(isSubmit ? submit : post);
            final picked = await showDatePicker(
              context: dialogContext,
              initialDate: current ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
            );
            if (picked == null) return;
            setD(() {
              if (isSubmit) {
                submit = _fmtIso(picked);
              } else {
                post = _fmtIso(picked);
              }
            });
          }

          Widget dateButton(String label, String value, bool isSubmit) => OutlinedButton.icon(
            onPressed: () => pickDate(isSubmit),
            icon: const Icon(Icons.calendar_month_outlined, size: 15),
            label: Text('$label: ${_parseDate(value) == null ? 'Select' : _fmtSlash(_parseDate(value)!)}'),
          );

          return AlertDialog(
            title: Text('Correct content · ${_str(row['deliverable'])} S.No ${_str(row['s_no'])}'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (website) ...[
                      RichDescription.preview(
                        deltaJson: rich,
                        fallbackPlain: richPlain,
                        editable: true,
                        width: 540,
                        emptyLabel: 'Click to write the website content…',
                        onOpen: () async {
                          final result = await RichDescription.edit(
                            dialogContext,
                            title: '${_str(row['deliverable'])} · S.No ${_str(row['s_no'])}',
                            deltaJson: rich,
                            fallbackPlain: richPlain,
                          );
                          if (result == null) return;
                          setD(() {
                            rich = result.$1;
                            richPlain = result.$2;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      field('hook_headline', 'Hook / Headline'),
                      field('description_points', 'Description', lines: 5),
                      field('caption', 'Caption', lines: 3),
                      field('cta', 'CTA'),
                    ],
                    field('notes', 'Notes', lines: 3),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        dateButton('Submit date', submit, true),
                        if (!website) dateButton('Post date', post, false),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save changes')),
            ],
          );
        },
      ),
    );
    final values = {for (final e in controllers.entries) e.key: e.value.text.trim()};
    for (final c in controllers.values) {
      c.dispose();
    }
    if (saved != true || !mounted) return;

    setState(() => _busyRows.add(id));
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/tasks/content-calendar/edit-row/$id'),
        headers: _headers,
        body: jsonEncode({
          if (!website) ...{
            'hook_headline': values['hook_headline'],
            'description_points': values['description_points'],
            'caption': values['caption'],
            'cta': values['cta'],
            'publish_date': post.isEmpty ? null : post,
          } else ...{
            'description_points': richPlain,
            'description_rich': rich.isEmpty ? null : rich,
          },
          'notes': values['notes'],
          'submit_date': submit.isEmpty ? null : submit,
        }),
      );
      if (!mounted) return;
      _showMessage(res.statusCode == 200
          ? 'Content updated — the employee sees the change in My Tasks'
          : _errorFrom(res, 'Unable to update this row'));
      await _reloadCurrentClient();
    } catch (_) {
      _showMessage('Unable to update this row. Check your connection.');
    } finally {
      if (mounted) setState(() => _busyRows.remove(id));
    }
  }

  /// Move an assigned row to another employee (normal, or emergency
  /// with a reason).
  Future<void> _handleReassign(Map<String, dynamic> row) async {
    if (_blockedReadOnly()) return;
    final id = _asInt(row['id']);
    if (_busyRows.contains(id)) return;
    List<Map<String, dynamic>> team = [];
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/content-calendar/creative-team'),
        headers: _headers,
      );
      if (res.statusCode != 200) {
        _showMessage(_errorFrom(res, 'Unable to load employees'));
        return;
      }
      final seen = <String>{};
      team = List<Map<String, dynamic>>.from(jsonDecode(res.body)['employees'] ?? [])
          .where((e) => _str(e['full_name']).trim().isNotEmpty && seen.add(_str(e['full_name']).trim()))
          .toList();
    } catch (_) {
      _showMessage('Unable to load employees. Check your connection.');
      return;
    }
    if (!mounted) return;
    final current = _str(row['task_employee_name']).isNotEmpty
        ? _str(row['task_employee_name'])
        : _str(row['cc_assigned_to_name']);
    final started = _employeeState(row) != 'IDLE';

    int? selectedId;
    var emergency = started;
    final reasonController = TextEditingController();
    String? error;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setD) => AlertDialog(
          title: Text('Edit assignment · ${_str(row['deliverable'])} S.No ${_str(row['s_no'])}'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Currently with: ${current.isEmpty ? '—' : current} (${_employeeState(row)})',
                    style: const TextStyle(color: _kMuted, fontSize: 12)),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Move this row to',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final e in team)
                      if (_str(e['full_name']).trim().toLowerCase() != current.trim().toLowerCase())
                        DropdownMenuItem(
                          value: _asInt(e['id']),
                          child: Text('${_str(e['full_name'])}  ·  ${_str(e['role'])}'),
                        ),
                  ],
                  onChanged: (v) => setD(() => selectedId = v),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: emergency,
                  onChanged: started ? null : (v) => setD(() => emergency = v ?? false),
                  title: const Text('Emergency assign'),
                  subtitle: Text(
                    started
                        ? 'Work has started on this row, so it can only be moved as an emergency.'
                        : 'Goes to the new employee as an Additional Task.',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                if (emergency)
                  TextField(
                    controller: reasonController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Emergency reason *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: const TextStyle(color: _kRed, fontSize: 12)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (selectedId == null) {
                  setD(() => error = 'Select an employee');
                  return;
                }
                if (emergency && reasonController.text.trim().isEmpty) {
                  setD(() => error = 'Emergency reason is required');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Move row'),
            ),
          ],
        ),
      ),
    );
    final reason = reasonController.text.trim();
    reasonController.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _busyRows.add(id));
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/tasks/content-calendar/reassign-row'),
        headers: _headers,
        body: jsonEncode({
          'task_item_id': id,
          'assigned_to_id': selectedId,
          'emergency': emergency,
          if (emergency) 'reason': reason,
        }),
      );
      if (!mounted) return;
      _showMessage(res.statusCode == 200
          ? _errorFrom(res, 'Row moved')
          : _errorFrom(res, 'Unable to move this row'));
      await _reloadCurrentClient();
    } catch (_) {
      _showMessage('Unable to move this row. Check your connection.');
    } finally {
      if (mounted) setState(() => _busyRows.remove(id));
    }
  }

  Widget _sheetTextCell(
    Map<String, dynamic> row,
    String field,
    String hint,
    double width,
  ) {
    return SizedBox(
      width: width,
      child: TextFormField(
        key: ValueKey('cc-${row['id']}-$field-$_sheetRev'),
        initialValue: _str(row[field]),
        readOnly: _isAssigned(row),
        enableInteractiveSelection: true,
        keyboardType: TextInputType.multiline,
        minLines: 1,
        maxLines: 4,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF202124),
          height: 1.3,
        ),
        cursorColor: _sheetFocus,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 11.5, color: Color(0xFFBDC1C6)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: _sheetFocus, width: 2),
          ),
          filled: true,
          fillColor: Colors.transparent,
          hoverColor: const Color(0xFFF8F9FA),
        ),
        onChanged: (v) => _onFieldChanged(row, field, v),
      ),
    );
  }

  Widget _buildDateChip(Map<String, dynamic> row, String field) {
    final date = _parseDate(row[field]);

    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: _isAssigned(row) ? null : () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        if (picked == null || !mounted) return;
        setState(() => _onFieldChanged(row, field, _fmtIso(picked)));
        await _flushSave(_asInt(row['id']));
        if (mounted) {
          _showMessage(field == 'submit_date'
              ? 'Submit date changed to ${_fmtSlash(picked)}'
              : 'Date saved');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: _kTint,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: _kTintBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_month_outlined,
              size: 13,
              color: _kPrimary,
            ),
            const SizedBox(width: 5),
            Text(
              date == null ? 'Select Date' : _fmtSlash(date),
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: _kPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoldReasonDialog extends StatefulWidget {
  final String label;
  // true when another task is being put on hold automatically because a new
  // one is starting.
  final bool autoHold;
  const _HoldReasonDialog({required this.label, this.autoHold = false});

  @override
  State<_HoldReasonDialog> createState() => _HoldReasonDialogState();
}

class _HoldReasonDialogState extends State<_HoldReasonDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Hold reason is required');
      return;
    }
    Navigator.pop(context, reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.pause_circle_outline, color: _kOrange),
          SizedBox(width: 8),
          Text('Hold Task', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.autoHold
                  ? '${widget.label} is running. It will be put on hold so the new '
                      'task can start — enter the reason.'
                  : 'Enter the reason for putting ${widget.label} on hold.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 4,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: 'Reason *',
                hintText: 'Enter hold reason...',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _kOrange,
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          child: const Text('HOLD'),
        ),
      ],
    );
  }
}

class _ShareConfirmDialog extends StatefulWidget {
  final String baseUrl;
  final Map<String, String> headers;
  final Map<String, dynamic> row;
  final String employeeName;
  final String employeeRole;

  const _ShareConfirmDialog({
    required this.baseUrl,
    required this.headers,
    required this.row,
    required this.employeeName,
    required this.employeeRole,
  });

  @override
  State<_ShareConfirmDialog> createState() => _ShareConfirmDialogState();
}

class _ShareConfirmDialogState extends State<_ShareConfirmDialog> {
  bool _checking = true;
  bool _onLeave = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkLeave();
  }

  Future<void> _checkLeave() async {
    try {
      final away = await _checkOnLeave(
        widget.baseUrl,
        widget.headers,
        widget.employeeName,
      );
      if (!mounted) return;
      setState(() {
        _onLeave = away;
        _checking = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Bad state: ', '');
        _checking = false;
      });
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final sourceAssignmentId = _asInt(widget.row['source_assignment_id']);
      final isSheet = sourceAssignmentId > 0;
      final res = await http.post(
        Uri.parse(
          '${widget.baseUrl}/tasks/content-calendar/'
          '${isSheet ? 'assign-sheet' : 'assign-row'}',
        ),
        headers: widget.headers,
        body: jsonEncode({
          if (isSheet) ...{
            'source_assignment_id': sourceAssignmentId,
            'source_role': widget.row['source_role'],
            'source_task_index': widget.row['source_task_index'],
          } else ...{
            'task_item_id': widget.row['id'],
            'assigned_to_name': widget.employeeName,
          },
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => _error = _errorFrom(res, 'Could not share this row'));
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Could not share this row. Check your connection.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.send_rounded, color: _kPrimary),
          SizedBox(width: 8),
          Text(
            'Confirm Assignment',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 470,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'All approved and completed content tasks will be assigned to ${widget.employeeName}:',
              style: const TextStyle(fontSize: 12, color: _kBody),
            ),
            const SizedBox(height: 10),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
          ),
          onPressed: _saving || _checking || _onLeave || _error != null
              ? null
              : _confirm,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 16),
          label: const Text('CONFIRM & SHARE ALL'),
        ),
      ],
    );
  }
}

class _EmergencyAssignDialog extends StatefulWidget {
  final String baseUrl;
  final Map<String, String> headers;
  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> team;
  final String currentlySharedWith;
  final int assignedById;
  final String assignedByName;

  const _EmergencyAssignDialog({
    required this.baseUrl,
    required this.headers,
    required this.row,
    required this.team,
    required this.currentlySharedWith,
    required this.assignedById,
    required this.assignedByName,
  });

  @override
  State<_EmergencyAssignDialog> createState() => _EmergencyAssignDialogState();
}

class _EmergencyAssignDialogState extends State<_EmergencyAssignDialog> {
  final _reason = TextEditingController();
  String? _selectedName;
  int? _selectedId;
  bool _checkingLeave = false;
  bool? _onLeave;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _select(String name) async {
    final match = widget.team.firstWhere(
      (e) => _str(e['full_name']) == name,
      orElse: () => <String, dynamic>{},
    );
    setState(() {
      _selectedName = name;
      _selectedId = _asIntOrNull(match['id']);
      _onLeave = null;
      _checkingLeave = true;
      _error = null;
    });
    try {
      final away = await _checkOnLeave(widget.baseUrl, widget.headers, name);
      if (!mounted || _selectedName != name) return;
      setState(() {
        _onLeave = away;
        _checkingLeave = false;
      });
    } catch (error) {
      if (!mounted || _selectedName != name) return;
      setState(() {
        _error = error.toString().replaceFirst('Bad state: ', '');
        _checkingLeave = false;
      });
    }
  }

  Future<void> _submit() async {
    final reason = _reason.text.trim();
    if (_selectedName == null) {
      setState(() => _error = 'Select an employee');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _error = 'Emergency reason is required');
      return;
    }
    if (_onLeave == true) {
      setState(() => _error = 'This employee is on approved leave today');
      return;
    }
    if (_checkingLeave || _onLeave == null || _error != null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/tasks/content-calendar/emergency-assign'),
        headers: widget.headers,
        body: jsonEncode({
          'task_item_id': widget.row['id'],
          'assigned_to_name': _selectedName,
          'assigned_to_id': _selectedId,
          'reason': reason,
          'assigned_by_id': widget.assignedById,
          'assigned_by_name': widget.assignedByName,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.pop(context, _selectedName);
        return;
      }
      setState(() => _error = _errorFrom(res, 'Emergency assignment failed'));
    } catch (_) {
      if (mounted) setState(() => _error = 'Emergency assignment failed.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.team]
      ..sort((a, b) => _str(a['full_name']).compareTo(_str(b['full_name'])));

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Emergency Assign',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 470,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedName,
              isExpanded: true,
              hint: const Text('Select employee'),
              items: sorted.map((emp) {
                final name = _str(emp['full_name']);
                final role = _str(emp['role']);
                return DropdownMenuItem<String>(
                  value: name,
                  child: Text(role.isEmpty ? name : '$name ($role)'),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) _select(v);
              },
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            if (widget.currentlySharedWith.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Currently assigned to ${widget.currentlySharedWith}',
                style: const TextStyle(fontSize: 12, color: _kMuted),
              ),
            ],
            if (_checkingLeave) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ] else if (_onLeave == true) ...[
              const SizedBox(height: 8),
              const Text(
                'This employee is on approved leave today.',
                style: TextStyle(color: _kRed, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _reason,
              maxLines: 3,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: const InputDecoration(
                hintText: 'Emergency reason...',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: _kRed, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _kRed,
            foregroundColor: Colors.white,
          ),
          onPressed:
              _saving || _checkingLeave || _onLeave != false || _error != null
              ? null
              : _submit,
          child: const Text('ASSIGN'),
        ),
      ],
    );
  }
}

class _ImportPreviewDialog extends StatefulWidget {
  final String baseUrl;
  final Map<String, String> headers;
  final String clientName;
  final String deliverable;
  final String fileName;
  final String? csv;
  final String? xlsxBase64;
  /// Rows of the card open on screen — other rows in the file are skipped.
  final String ids;

  const _ImportPreviewDialog({
    required this.baseUrl,
    required this.headers,
    required this.clientName,
    required this.deliverable,
    required this.fileName,
    this.csv,
    this.xlsxBase64,
    this.ids = '',
  });

  @override
  State<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<_ImportPreviewDialog> {
  static const _deep = Color(0xFF0A3D91);
  static const _blue = Color(0xFF0757D5);

  bool _loading = true;
  bool _applying = false;
  int _updateCount = 0;
  List<String> _columns = [];
  List<Map<String, dynamic>> _skipped = [];
  String? _error;

  Map<String, dynamic> get _payload => {
        'client_name': widget.clientName,
        'deliverable': widget.deliverable,
        if (widget.ids.isNotEmpty) 'ids': widget.ids,
        if (widget.xlsxBase64 != null) 'xlsx_base64': widget.xlsxBase64,
        if (widget.xlsxBase64 == null) 'csv': widget.csv ?? '',
      };

  @override
  void initState() {
    super.initState();
    _preview();
  }

  String _message(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      return (body['message'] ?? fallback).toString();
    } catch (_) {
      return res.statusCode == 413
          ? 'The file is too large for the server (raise express.json limit).'
          : fallback;
    }
  }

  Future<void> _preview() async {
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/tasks/content-calendar/import-preview'),
        headers: widget.headers,
        body: jsonEncode(_payload),
      );
      if (res.statusCode != 200) throw StateError(_message(res, 'Could not read this file'));
      final body = jsonDecode(res.body);
      if (!mounted) return;
      setState(() {
        _updateCount = (body['update_count'] as num?)?.toInt() ?? 0;
        _columns = List<String>.from(body['columns'] ?? const []);
        _skipped = List<Map<String, dynamic>>.from(
          (body['skipped'] as List? ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)),
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Bad state: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _applyImport() async {
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/tasks/content-calendar/import'),
        headers: widget.headers,
        body: jsonEncode(_payload),
      );
      if (res.statusCode != 200) throw StateError(_message(res, 'Could not import this file'));
      final body = jsonDecode(res.body);
      if (mounted) Navigator.pop(context, (body['applied_count'] as num?)?.toInt() ?? 0);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Bad state: ', '');
          _applying = false;
        });
      }
    }
  }

  Widget _stat(String label, String value, Color color, IconData icon) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
              Text(label, style: const TextStyle(fontSize: 11, color: _kMuted, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isXlsx = widget.xlsxBase64 != null;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [_deep, _blue, Color(0xFF1E88E5)]),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.upload_file_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Import sheet',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                    Text('${widget.clientName} · ${widget.deliverable}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
                  ]),
                ),
                IconButton(
                  onPressed: _applying ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: _kTint,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _kTintBorder),
                          ),
                          child: Row(children: [
                            Icon(isXlsx ? Icons.grid_on_rounded : Icons.description_outlined,
                                size: 18, color: _blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(widget.fileName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, color: _kInk)),
                            ),
                            Text(isXlsx ? 'EXCEL' : 'CSV',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _blue)),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        if (_error != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1F2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFECACA)),
                            ),
                            child: Text(_error!, style: const TextStyle(color: _kRed, fontSize: 12.5)),
                          )
                        else ...[
                          Row(children: [
                            _stat('rows will update', '$_updateCount', _blue, Icons.sync_rounded),
                            const SizedBox(width: 10),
                            _stat('rows skipped', '${_skipped.length}',
                                _skipped.isEmpty ? _kGreen : const Color(0xFFD97706),
                                _skipped.isEmpty ? Icons.check_circle_outline : Icons.warning_amber_rounded),
                          ]),
                          const SizedBox(height: 12),
                          if (_updateCount == 0)
                            const Text('Nothing changed compared with the calendar.',
                                style: TextStyle(color: _kMuted, fontSize: 12.5))
                          else
                            Wrap(spacing: 6, runSpacing: 6, children: [
                              for (final c in _columns)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _kTint,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(c,
                                      style: const TextStyle(fontSize: 11, color: _blue, fontWeight: FontWeight.w700)),
                                ),
                            ]),
                          if (_skipped.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            const Text('Skipped rows',
                                style: TextStyle(fontWeight: FontWeight.w800, color: _kInk, fontSize: 12.5)),
                            const SizedBox(height: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 160),
                              child: ListView(
                                shrinkWrap: true,
                                children: [
                                  for (final row in _skipped)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text('Row ${row['line']}: ${row['reason']}',
                                          style: const TextStyle(color: _kMuted, fontSize: 12)),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _applying ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading || _applying || _error != null || _updateCount == 0
                        ? null
                        : _applyImport,
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      minimumSize: const Size.fromHeight(44),
                    ),
                    icon: _applying
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(_updateCount > 0 ? 'Apply $_updateCount update${_updateCount == 1 ? '' : 's'}' : 'Apply import'),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  final int n;
  final String text;
  const _GuideStep({required this.n, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: _kPrimary, shape: BoxShape.circle),
            child: Text('$n',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: _kBody, height: 1.35))),
        ]),
      );
}