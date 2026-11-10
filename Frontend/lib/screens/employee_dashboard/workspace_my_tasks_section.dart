import 'package:godigital_portal/services/socket_auth.dart';
import 'package:godigital_portal/services/auth_storage.dart';
// lib/screens/employee_dashboard/workspace_my_tasks_section.dart
//
// Employee Workspace → Client → "My Tasks" / "Additional Tasks".
// Shows only this employee's tasks for the selected client + submit date,
// one category (deliverable) at a time.
//
//  • Page Handler  : assigned rows only, no + button.
//  • Ads Handler   : + beside S.No adds nested rows 1.1, 1.2 … (each with its
//                    own Start / Hold / Complete and timer). Only Description
//                    and Submit Date are editable on a nested row.
//  • Other roles   : rows appear only after the Page/Ads Handler completes the
//                    Content Calendar sheet and assigns it.
//
// `view` picks which groups are listed:
//   null          → everything for the date
//   'main'        → normal assigned work only (My Tasks tab)
//   'additional'  → additional / reassigned work only (Additional Tasks tab)
//
// Complete → row moves to Task Review (status "IN REVIEW").
// Approved → COMPLETED and locked. Rework → RESTART continues the same timer.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:godigital_portal/services/authenticated_http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../services/api_config.dart';
import 'rich_description.dart';
import 'task_actions.dart';

const _kPrimary = Color(0xFF004AAD);
const _kInk = Color(0xFF0F172A);
const _kBody = Color(0xFF334155);
const _kMuted = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);
const _kSubRow = Color(0xFFF8FAFC);

int _asInt(dynamic v) => v is int
    ? v
    : (v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0);

String _str(dynamic v) {
  final s = v?.toString() ?? '';
  return s == 'null' ? '' : s;
}

String _two(int n) => n.toString().padLeft(2, '0');

String _fmtTimer(int sec) {
  final s = sec < 0 ? 0 : sec;
  return '${_two(s ~/ 3600)}:${_two((s % 3600) ~/ 60)}:${_two(s % 60)}';
}

DateTime? _parseDay(dynamic v) {
  final s = _str(v).trim();
  if (s.length < 10) return null;
  return DateTime.tryParse(s.substring(0, 10));
}

String _fmtDay(dynamic v) {
  final d = _parseDay(v);
  return d == null ? '—' : '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

String _isoDay(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

class WorkspaceMyTasksSection extends StatefulWidget {
  final String clientName;
  final String submissionDate;
  final String employeeName;
  final String authToken;
  /// Opens the Day Planner page (wired by the dashboard that hosts the
  /// Employee Workspace). When null the button explains where to go.
  final VoidCallback? onOpenDayPlanner;

  /// 'main' hides additional / reassigned work, 'additional' shows only it,
  /// null shows everything for the date.
  final String? view;

  const WorkspaceMyTasksSection({
    super.key,
    required this.clientName,
    required this.submissionDate,
    required this.employeeName,
    required this.authToken,
    this.onOpenDayPlanner,
    this.view,
  });

  @override
  State<WorkspaceMyTasksSection> createState() =>
      _WorkspaceMyTasksSectionState();
}

class _WorkspaceMyTasksSectionState extends State<WorkspaceMyTasksSection> {
  static const double _wDescription = 240;
  static const double _wNotes = 230;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _groups = [];
  int _selected = 0;
  final Set<int> _busy = {};
  // Task rows already in today's Day Planner (row-based planner button).
  Set<int> _plannerIds = {};
  // Deadline-rule status (Admin → Task Deadline Rules) for this client/date.
  List<Map<String, dynamic>> _late = [];
  final Map<String, Timer> _fieldSavers = {};
  Timer? _ticker;
  Timer? _refreshDebounce;
  io.Socket? _socket;

  String get _base => ApiConfig.baseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (widget.authToken.isNotEmpty)
          'Authorization': 'Bearer ${widget.authToken}',
      };

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _socket = io.io(
      ApiConfig.socketUrl,
      io.OptionBuilder().setAuthFn(authenticateSocket)
          .setTransports(['websocket'])
          .enableForceNew()
          .disableAutoConnect()
          .build(),
    )..connect();
    _socket!
      ..on('task_updated', (_) => _scheduleRefresh())
      ..on('calendar:assigned', (_) => _scheduleRefresh());
  }

  @override
  void didUpdateWidget(covariant WorkspaceMyTasksSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view ||
        oldWidget.clientName != widget.clientName ||
        oldWidget.submissionDate != widget.submissionDate ||
        oldWidget.employeeName != widget.employeeName) {
      _load();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _refreshDebounce?.cancel();
    for (final t in _fieldSavers.values) {
      t.cancel();
    }
    _socket?.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    var changed = false;
    for (final g in _groups) {
      for (final row in (g['rows'] as List<Map<String, dynamic>>)) {
        if (row['state'] == 'IN PROGRESS') {
          row['current_secs'] = _asInt(row['current_secs']) + 1;
          changed = true;
        }
      }
    }
    if (changed) setState(() {});
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load(silent: true);
    });
  }

  String _messageFrom(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      final msg = body['message'] ?? body['error'];
      if (msg != null && msg.toString().trim().isNotEmpty) return '$msg';
    } catch (_) {}
    return fallback;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final uri = Uri.parse('$_base/workspace-tasks/my-tasks').replace(
        queryParameters: {
          'employee': widget.employeeName,
          'client': widget.clientName,
          'date': widget.submissionDate.length >= 10
              ? widget.submissionDate.substring(0, 10)
              : widget.submissionDate,
        },
      );
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode != 200) {
        throw Exception(_messageFrom(res, 'Unable to load your tasks'));
      }
      _loadPlannerIds();
      _loadLate();
      final body = jsonDecode(res.body);
      final groups = (body['data'] as List? ?? [])
          .whereType<Map>()
          .map((g) {
            final group = Map<String, dynamic>.from(g);
            group['rows'] = (group['rows'] as List? ?? [])
                .whereType<Map>()
                .map((r) => Map<String, dynamic>.from(r))
                .toList();
            return group;
          })
          .toList();
      if (!mounted) return;

      // Additional / reassigned work has its own tab.
      bool isExtra(Map<String, dynamic> g) {
        final k = '${g['key']}';
        return k.startsWith('additional:') || k.startsWith('reassigned:');
      }

      final shown = widget.view == 'additional'
          ? groups.where(isExtra).toList()
          : widget.view == 'main'
              ? groups.where((g) => !isExtra(g)).toList()
              : groups;

      final previousKey = _groups.isNotEmpty && _selected < _groups.length
          ? _groups[_selected]['key']
          : null;
      setState(() {
        _groups = shown;
        final index = shown.indexWhere((g) => g['key'] == previousKey);
        _selected = index < 0 ? 0 : index;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadLate() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/workspace-tasks/compliance').replace(queryParameters: {
          'employee': widget.employeeName,
          'client': widget.clientName,
          'date': widget.submissionDate.length >= 10
              ? widget.submissionDate.substring(0, 10)
              : widget.submissionDate,
          'late': '1',
        }),
        headers: _headers,
      );
      if (res.statusCode != 200 || !mounted) return;
      final items = (jsonDecode(res.body)['data'] as List? ?? [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      setState(() => _late = items);
    } catch (_) {}
  }

  bool _isLate(Map<String, dynamic> group) =>
      _late.any((i) => i['key'] == group['key']);

  /// Red banner: tasks that are past the admin's start / complete deadline.
  Widget _lateBanner() {
    if (_late.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFB91C1C), size: 18),
            SizedBox(width: 8),
            Text('Late — please start / finish these now',
                style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFB91C1C), fontSize: 13)),
          ]),
          const SizedBox(height: 6),
          for (final i in _late)
            for (final issue in (i['issues'] as List? ?? []).whereType<Map>())
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 3),
                child: Text(
                  '${i['task']}${'${i['role_key']}' == 'content_calendar' ? ' (Content Calendar)' : ''}: ${issue['message']}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7F1D1D), fontWeight: FontWeight.w600),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _loadPlannerIds() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/workspace-tasks/day-plan/rows')
            .replace(queryParameters: {'employee': widget.employeeName}),
        headers: _headers,
      );
      if (res.statusCode != 200 || !mounted) return;
      final ids = (jsonDecode(res.body)['data'] as List? ?? [])
          .map((e) => int.tryParse('$e') ?? 0)
          .where((e) => e > 0)
          .toSet();
      setState(() => _plannerIds = ids);
    } catch (_) {}
  }

  /// Adds THIS row (not the whole category) to today's Day Planner.
  Future<void> _addRowToPlanner(Map<String, dynamic> row) async {
    final id = _asInt(row['id']);
    if (id == 0 || _busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      final res = await http.post(
        Uri.parse('$_base/workspace-tasks/day-plan/add'),
        headers: _headers,
        body: jsonEncode({'employee': widget.employeeName, 'task_id': id}),
      );
      if (res.statusCode == 200) {
        setState(() => _plannerIds.add(id));
        _snack(_messageFrom(res, 'Added to today’s Day Planner'));
      } else {
        _snack(_messageFrom(res, 'Could not add this row to the Day Planner'));
      }
    } catch (_) {
      _snack('Could not add this row to the Day Planner');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Widget _plannerButton(Map<String, dynamic> row, bool busy) {
    final inPlanner = _plannerIds.contains(_asInt(row['id']));
    if (inPlanner) {
      return Tooltip(
        message: 'This row is in today’s Day Planner',
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.event_available_rounded, size: 14, color: _kPrimary),
            SizedBox(width: 4),
            Text('In planner',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _kPrimary)),
          ]),
        ),
      );
    }
    return _actionButton('ADD TO PLANNER', const Color(0xFF0757D5), Icons.playlist_add_rounded,
        busy ? null : () => _addRowToPlanner(row));
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  Future<void> _runAction(Map<String, dynamic> row, String action) async {
    final id = _asInt(row['id']);
    if (_busy.contains(id)) return;
    final body = <String, dynamic>{};
    if (action == 'hold') {
      final reason = await _askText(
        title: 'Hold row ${row['display_no']}',
        label: 'Reason *',
        hint: 'Why are you putting this on hold?',
        required: true,
      );
      if (reason == null) return;
      body['reason'] = reason;
    }
    if (action == 'complete') {
      final ok = await _confirm(
        'Complete row ${row['display_no']}?',
        'It will move to Task Review. It is marked completed only after it '
            'is approved. If rework is requested you can restart it.',
      );
      if (!ok) return;
    }
    setState(() => _busy.add(id));
    try {
      var res = await http.post(
        Uri.parse('$_base/tracking-items/$id/$action'),
        headers: _headers,
        body: jsonEncode(body),
      );
      // Not in today's Day Planner yet → ask to add it, then retry.
      if (res.statusCode == 409 && res.body.contains('DAY_PLAN_CONFIRM_REQUIRED')) {
        if (!mounted || !await TaskActions.confirmDayPlan(context, res)) return;
        body['day_planner_confirmed'] = true;
        res = await http.post(
          Uri.parse('$_base/tracking-items/$id/$action'),
          headers: _headers,
          body: jsonEncode(body),
        );
      }
      // Something else is running → ask why it should be held, then retry.
      if (res.statusCode == 409 && (action == 'start' || action == 'restart')) {
        Map<String, dynamic>? err;
        try {
          err = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
        } catch (_) {}
        if (err?['code'] == 'AUTO_HOLD_REASON_REQUIRED') {
          final running = (err!['running'] as List? ?? [])
              .whereType<Map>()
              .map((r) => _str(r['title']))
              .where((t) => t.isNotEmpty)
              .join(', ');
          final reason = await _askText(
            title: 'Put the running task on hold?',
            label: 'Hold reason *',
            hint: '${running.isEmpty ? 'Your running task' : running} will be put on hold so row '
                '${row['display_no']} can start. Why?',
            required: true,
          );
          if (reason == null) return;
          res = await http.post(
            Uri.parse('$_base/tracking-items/$id/$action'),
            headers: _headers,
            body: jsonEncode({...body, 'auto_hold_reason': reason}),
          );
        }
      }
      if (res.statusCode != 200) {
        _snack(_messageFrom(res, 'Unable to $action this row'));
      } else if (action == 'complete') {
        _snack('Row ${row['display_no']} sent to Task Review');
      }
      await _load(silent: true);
    } catch (_) {
      _snack('Unable to $action this row. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _addSubRow(Map<String, dynamic> row) async {
    final id = _asInt(row['id']);
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      final res = await http.post(
        Uri.parse('$_base/workspace-tasks/my-tasks/$id/sub-rows'),
        headers: _headers,
        body: jsonEncode({'employee': widget.employeeName}),
      );
      if (res.statusCode != 201 && res.statusCode != 200) {
        _snack(_messageFrom(res, 'Unable to add a nested row'));
      }
      await _load(silent: true);
    } catch (_) {
      _snack('Unable to add a nested row. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _patchSubRow(
    Map<String, dynamic> row,
    Map<String, dynamic> changes,
  ) async {
    final id = _asInt(row['id']);
    try {
      final res = await http.patch(
        Uri.parse('$_base/workspace-tasks/my-tasks/$id'),
        headers: _headers,
        body: jsonEncode({...changes, 'employee': widget.employeeName}),
      );
      if (res.statusCode != 200) {
        _snack(_messageFrom(res, 'Unable to save this row'));
      }
      await _load(silent: true);
    } catch (_) {
      _snack('Unable to save this row. Check your connection.');
    }
  }

  // Inline text box for rows the employee owns (Page/Ads Handler, Developer…).
  // Saves 800 ms after typing stops, without reloading the list.
  Widget _inlineEditor(Map<String, dynamic> row, String field, String hint, {int maxLines = 4}) {
    final locked = {'APPROVED', 'IN REVIEW'}.contains(_str(row['state']));
    return TextFormField(
      key: ValueKey('inline-${row['id']}-$field'),
      initialValue: _str(row[field]),
      readOnly: locked,
      minLines: 1,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 12, color: _kBody, height: 1.3),
      decoration: InputDecoration(
        isDense: true,
        hintText: locked ? '—' : hint,
        hintStyle: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
        filled: true,
        fillColor: locked ? _kSubRow : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        suffixIcon: _str(row[field]).trim().isEmpty
            ? null
            : IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded, size: 14),
                onPressed: () => _copy(field == 'hook_headline' ? 'Headline' : 'Description', _str(row[field])),
              ),
      ),
      onChanged: (value) {
        row[field] = value;
        final key = '${row['id']}:$field';
        _fieldSavers[key]?.cancel();
        _fieldSavers[key] = Timer(const Duration(milliseconds: 800), () => _saveField(row, field, value));
      },
    );
  }

  Future<void> _saveField(Map<String, dynamic> row, String field, dynamic value) async {
    try {
      final res = await http.patch(
        Uri.parse('$_base/workspace-tasks/my-tasks/${_asInt(row['id'])}'),
        headers: _headers,
        body: jsonEncode({field: value, 'employee': widget.employeeName}),
      );
      if (res.statusCode != 200) _snack(_messageFrom(res, 'Unable to save'));
    } catch (_) {
      _snack('Unable to save. Check your connection.');
    }
  }

  // Submit date chip (editable) + start date once the row has started.
  Widget _submitDateCell(Map<String, dynamic> row, bool locked) {
    final started = _str(row['start_time']);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: locked ? null : () => _editSubmitDate(row),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_month_outlined, size: 13, color: _kPrimary),
                const SizedBox(width: 4),
                Text(
                  'Submit ${_fmtDay(row['submit_date'])}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kPrimary),
                ),
                if (!locked) ...[
                  const SizedBox(width: 3),
                  const Icon(Icons.edit_rounded, size: 11, color: _kPrimary),
                ],
              ],
            ),
          ),
        ),
        if (started.isNotEmpty)
          Text('Started ${_fmtDay(started)}', style: const TextStyle(fontSize: 10.5, color: _kMuted)),
      ],
    );
  }

  Future<void> _editDescription(Map<String, dynamic> row) async {
    final text = await _askText(
      title: 'Description · row ${row['display_no']}',
      label: 'Description',
      hint: 'Describe this row…',
      initial: _str(row['description_points']),
    );
    if (text == null) return;
    await _patchSubRow(row, {'description_points': text});
  }

  Future<void> _editSubmitDate(Map<String, dynamic> row) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _parseDay(row['submit_date']) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    await _patchSubRow(row, {'submit_date': _isoDay(picked)});
  }

  Future<String?> _askText({
    required String title,
    required String label,
    required String hint,
    String initial = '',
    bool required = false,
  }) async {
    final controller = TextEditingController(text: initial);
    String? error;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                errorText: error,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (required && value.isEmpty) {
                  setDialogState(() => error = '$label is required');
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<bool> _confirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (_groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.view == 'additional'
                ? 'No additional tasks for this client and submit date.'
                : 'No tasks are assigned to you for this client and submit date.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _kMuted),
          ),
        ),
      );
    }

    final group = _groups[_selected < _groups.length ? _selected : 0];
    final rows = group['rows'] as List<Map<String, dynamic>>;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        children: [
          _lateBanner(),
          _categoryChips(),
          const SizedBox(height: 14),
          _groupHeader(group, rows),
          const SizedBox(height: 10),
          if (group['awaiting_handoff'] == true)
            _infoBox(
              'Waiting for the Page / Ads Handler to prepare and assign this '
              'content. The rows appear here as soon as they are assigned.',
            )
          else if (rows.isEmpty)
            _infoBox('No rows in this category yet.')
          else
            _table(group, rows),
        ],
      ),
    );
  }

  Widget _categoryChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < _groups.length; i++) _categoryChip(i),
      ],
    );
  }

  Widget _categoryChip(int index) {
    final group = _groups[index];
    final rows = group['rows'] as List<Map<String, dynamic>>;
    final approved = rows.where((r) => r['state'] == 'APPROVED').length;
    final total = rows.isEmpty ? _asInt(group['assigned_count']) : rows.length;
    final selected = index == _selected;
    const openStates = {'IDLE', 'IN PROGRESS', 'ON HOLD', 'REWORK'};
    final pending = rows.where((r) => openStates.contains(r['state'])).length;
    final late = _isLate(group);
    final chip = InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => setState(() => _selected = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _kPrimary : (late ? const Color(0xFFFFF1F2) : Colors.white),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: late ? const Color(0xFFDC2626) : (selected ? _kPrimary : const Color(0xFFBFDBFE)),
            width: late ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _str(group['deliverable']).toUpperCase(),
              style: TextStyle(
                color: selected ? Colors.white : _kPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$approved / $total approved',
              style: TextStyle(
                fontSize: 10.5,
                color: selected ? Colors.white70 : _kMuted,
              ),
            ),
            if (late)
              Text(
                'LATE',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : const Color(0xFFB91C1C),
                ),
              ),
          ],
        ),
      ),
    );
    if (pending == 0) return chip;
    // Red badge: rows still to do in this category (drops as they complete).
    return Badge(
      label: Text('$pending'),
      backgroundColor: const Color(0xFFDC2626),
      offset: const Offset(-4, 2),
      child: chip,
    );
  }

  Widget _groupHeader(Map<String, dynamic> group, List<Map<String, dynamic>> rows) {
    int count(String state) => rows.where((r) => r['state'] == state).length;
    return Wrap(
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
          _str(group['deliverable']).toUpperCase(),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: _kInk,
          ),
        ),
        _chip(_str(group['role_label']), const Color(0xFFEAF2FF), _kPrimary),
        _chip('Submit: ${_fmtDay(group['submission_date'])}',
            const Color(0xFFF1F5F9), _kBody),
        _chip('Rows: ${rows.length}', const Color(0xFFF1F5F9), _kBody),
        _chip('In review: ${count('IN REVIEW')}',
            const Color(0xFFEDE9FE), const Color(0xFF6D28D9)),
        _chip('Rework: ${count('REWORK')}',
            const Color(0xFFFEF3C7), const Color(0xFF92400E)),
        _chip('Completed: ${count('APPROVED')}',
            const Color(0xFFDCFCE7), const Color(0xFF15803D)),
      ],
    );
  }

  Widget _chip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
        ),
      );

  Widget _infoBox(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: _kMuted, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(color: _kMuted))),
          ],
        ),
      );

  bool _isRichGroup(Map<String, dynamic> group) =>
      group['rich'] == true || group['role'] == 'website_designer';

  // Open work first (in S.No order); finished work sinks to the bottom.
  static int _rank(String state) => switch (state) {
        'IN REVIEW' => 1,
        'REJECTED' => 2,
        'APPROVED' => 3,
        _ => 0, // IDLE / IN PROGRESS / ON HOLD / REWORK
      };

  List<Map<String, dynamic>> _orderedRows(List<Map<String, dynamic>> rows) {
    final children = <int, List<Map<String, dynamic>>>{};
    final parents = <Map<String, dynamic>>[];
    for (final row in rows) {
      final parentId = _asInt(row['parent_item_id']);
      if (parentId > 0) {
        (children[parentId] ??= []).add(row);
      } else {
        parents.add(row);
      }
    }
    int byRankThenNo(Map<String, dynamic> a, Map<String, dynamic> b) {
      final r = _rank(_str(a['state'])).compareTo(_rank(_str(b['state'])));
      if (r != 0) return r;
      final s = _asInt(a['s_no']).compareTo(_asInt(b['s_no']));
      return s != 0 ? s : _asInt(a['sub_no']).compareTo(_asInt(b['sub_no']));
    }

    parents.sort(byRankThenNo);
    final ordered = <Map<String, dynamic>>[];
    final placed = <int>{};
    for (final parent in parents) {
      ordered.add(parent);
      placed.add(_asInt(parent['id']));
      final kids = children[_asInt(parent['id'])] ?? [];
      kids.sort(byRankThenNo);
      ordered.addAll(kids);
      placed.addAll(kids.map((k) => _asInt(k['id'])));
    }
    // Nested rows whose main row is not in this list.
    ordered.addAll(rows.where((r) => !placed.contains(_asInt(r['id']))));
    return ordered;
  }

  Widget _table(Map<String, dynamic> group, List<Map<String, dynamic>> rows) {
    final ordered = _orderedRows(rows);
    final firstDone = ordered.indexWhere(
      (r) => _rank(_str(r['state'])) > 0 && _asInt(r['parent_item_id']) == 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < ordered.length; i++) ...[
          if (i == firstDone && firstDone > 0)
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 10),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'COMPLETED',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: _kMuted,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
            ),
          _row(group, ordered[i]),
        ],
      ],
    );
  }

  Widget _field(String label, Widget child, {double width = 260}) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: _kMuted,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  Color _stateAccent(String state) => switch (state) {
        'IN PROGRESS' => _kPrimary,
        'ON HOLD' => const Color(0xFFD97706),
        'REWORK' => const Color(0xFFC2410C),
        'IN REVIEW' => const Color(0xFF7C3AED),
        'APPROVED' => const Color(0xFF16A34A),
        'REJECTED' => const Color(0xFFDC2626),
        _ => const Color(0xFFCBD5E1),
      };

  Widget _textCell(String text, double width, {Color color = _kBody}) {
    final value = text.trim().isEmpty ? '—' : text.trim();
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Tooltip(
          message: value,
          waitDuration: const Duration(milliseconds: 500),
          child: Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: color, height: 1.3),
          ),
        ),
      ),
    );
  }

  // One card per row (nested Ads rows are indented under their main row).
  Widget _row(Map<String, dynamic> group, Map<String, dynamic> row) {
    final isSub = _asInt(row['sub_no']) > 0;
    final state = _str(row['state']);
    final approved = state == 'APPROVED';
    final busy = _busy.contains(_asInt(row['id']));
    final canAddSub = group['nested'] == true && !isSub && !approved;
    final rich = _isRichGroup(group);
    final direct = group['editable_content'] == true && !rich;
    final locked = approved || state == 'IN REVIEW';
    final accent = _stateAccent(state);
    final richPlain = _str(row['description_points']).isNotEmpty
        ? _str(row['description_points'])
        : _str(row['task_description']);

    return Container(
      margin: EdgeInsets.only(left: isSub ? 32 : 0, bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: approved
                ? const Color(0xFFF7FEF9)
                : (isSub ? _kSubRow : Colors.white),
            border: Border(
              left: BorderSide(color: accent, width: 4),
              top: const BorderSide(color: _kBorder),
              right: const BorderSide(color: _kBorder),
              bottom: const BorderSide(color: _kBorder),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── header ─────────────────────────────────────────────
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSub)
                                const Padding(
                                  padding: EdgeInsets.only(right: 3),
                                  child: Icon(Icons.subdirectory_arrow_right_rounded,
                                      size: 13, color: _kPrimary),
                                ),
                              Text(
                                'S.No ${_str(row['display_no'])}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: _kPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (canAddSub)
                          Tooltip(
                            message: 'Add nested row ${_str(row['s_no'])}.x',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: busy ? null : () => _addSubRow(row),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: _kPrimary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add, size: 13, color: Colors.white),
                                    SizedBox(width: 3),
                                    Text('Row',
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        _statusCell(row, state),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: state == 'IN PROGRESS' ? const Color(0xFFEFF6FF) : _kSubRow,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: _kBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_outlined, size: 13, color: accent),
                              const SizedBox(width: 4),
                              Text(
                                _fmtTimer(_asInt(row['current_secs'])),
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: state == 'IN PROGRESS' ? _kPrimary : _kInk,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (direct || isSub)
                          _submitDateCell(row, locked)
                        else if (rich)
                          Text('Submit ${_fmtDay(row['submit_date'])}',
                              style: const TextStyle(fontSize: 11.5, color: _kBody, fontWeight: FontWeight.w600))
                        else
                          _postDateCell(row, isSub, approved),
                        if (_str(row['performance']).isNotEmpty && _str(row['performance']) != 'N/A')
                          Text(
                            _str(row['performance']),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: _performanceColor(_str(row['performance'])),
                            ),
                          ),
                        _actionCell(row, state, busy),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // ── content ────────────────────────────────────────────
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        if (rich)
                          _field(
                            'DESCRIPTION',
                            RichDescription.preview(
                              deltaJson: _str(row['description_rich']),
                              fallbackPlain: richPlain,
                              emptyLabel: 'No description',
                              width: 520,
                              onOpen: () => RichDescription.view(
                                context,
                                title: '${_str(group['deliverable'])} · Row ${_str(row['display_no'])}',
                                deltaJson: _str(row['description_rich']),
                                fallbackPlain: richPlain,
                              ),
                            ),
                            width: 520,
                          )
                        else if (direct) ...[
                          // Employee writes these; no caption / CTA here.
                          _field('HEADLINE', _inlineEditor(row, 'hook_headline', 'Type headline…', maxLines: 2), width: 300),
                          _field('DESCRIPTION', _inlineEditor(row, 'description_points', 'Type description…', maxLines: 6), width: 420),
                        ]
                        else ...[
                          _field('HEADLINE', _copyCell('Headline', _str(row['hook_headline']), 250)),
                          _field('DESCRIPTION', _descriptionCell(row, isSub, approved), width: 300),
                          _field('CAPTION', _copyCell('Caption', _str(row['caption']), 250)),
                          _field('CTA', _copyCell('CTA', _str(row['cta']), 200), width: 200),
                        ],
                        _field('NOTES', _notesCell(row, approved), width: _wNotes + 10),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _postDateCell(Map<String, dynamic> row, bool isSub, bool approved) {
    final post = _str(row['publish_date']);
    if (!isSub) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            post.isNotEmpty ? 'Post ${_fmtDay(post)}' : 'Post —',
            style: const TextStyle(fontSize: 11.5, color: _kBody, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            'Submit ${_fmtDay(row['submit_date'])}',
            style: const TextStyle(fontSize: 10.5, color: _kMuted),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: approved ? null : () => _editSubmitDate(row),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_month_outlined, size: 12, color: _kPrimary),
                const SizedBox(width: 4),
                Text(
                  'Submit ${_fmtDay(row['submit_date'])}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: _kPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (post.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('Post ${_fmtDay(post)}',
                style: const TextStyle(fontSize: 10, color: _kMuted)),
          ),
      ],
    );
  }

  Widget _descriptionCell(Map<String, dynamic> row, bool isSub, bool approved) {
    final text = _str(row['description_points']);
    if (!isSub || approved) return _copyCell('Description', text, _wDescription);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: () => _editDescription(row),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text.isEmpty ? 'Add description…' : text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: text.isEmpty ? const Color(0xFF94A3B8) : _kBody,
                  ),
                ),
              ),
              const Icon(Icons.edit, size: 12, color: _kMuted),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copy(String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _snack('$label copied');
  }

  // Selectable text + copy button (Headline / Description / Caption / CTA).
  Widget _copyCell(String label, String text, double width) {
    final value = text.trim();
    if (value.isEmpty) return _textCell('', width);
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                value,
                maxLines: 3,
                style: const TextStyle(fontSize: 11.5, color: _kBody, height: 1.3),
              ),
            ),
            IconButton(
              tooltip: 'Copy $label',
              onPressed: () => _copy(label, value),
              icon: const Icon(Icons.copy_rounded, size: 14),
              color: _kMuted,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  // Handler's note (copyable) + the employee's own editable note.
  Widget _notesCell(Map<String, dynamic> row, bool approved) {
    final handlerNote = _str(row['notes']).trim();
    final mine = _str(row['employee_notes']).trim();
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (handlerNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _copyCell('Note', handlerNote, _wNotes - 10),
            ),
          InkWell(
            borderRadius: BorderRadius.circular(5),
            onTap: approved ? null : () => _editNotes(row),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: approved ? _kSubRow : Colors.white,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      mine.isEmpty ? (approved ? '—' : 'Add my notes…') : mine,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: mine.isEmpty ? const Color(0xFF94A3B8) : _kBody,
                      ),
                    ),
                  ),
                  if (!approved) const Icon(Icons.edit_note_rounded, size: 14, color: _kMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editNotes(Map<String, dynamic> row) async {
    final text = await _askText(
      title: 'My notes · row ${row['display_no']}',
      label: 'Notes',
      hint: 'Type your notes for this row…',
      initial: _str(row['employee_notes']),
    );
    if (text == null) return;
    await _patchSubRow(row, {'employee_notes': text});
  }

  Widget _actionButton(String label, Color color, IconData icon, VoidCallback? onTap) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.6)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }

  Widget _actionCell(Map<String, dynamic> row, String state, bool busy) {
    final actions = <Widget>[];
    switch (state) {
      case 'IDLE':
        actions.add(_actionButton('START', _kPrimary, Icons.play_arrow_rounded,
            busy ? null : () => _runAction(row, 'start')));
        break;
      case 'IN PROGRESS':
        actions.add(_actionButton('HOLD', const Color(0xFFEA580C), Icons.pause_rounded,
            busy ? null : () => _runAction(row, 'hold')));
        actions.add(_actionButton('COMPLETE', const Color(0xFF16A34A), Icons.check_rounded,
            busy ? null : () => _runAction(row, 'complete')));
        break;
      case 'ON HOLD':
        actions.add(_actionButton('RESTART', const Color(0xFFD97706), Icons.replay_rounded,
            busy ? null : () => _runAction(row, 'restart')));
        break;
      case 'REWORK':
        // Continues the same timer from where it stopped at completion.
        actions.add(_actionButton('RESTART', const Color(0xFFB45309), Icons.replay_rounded,
            busy ? null : () => _runAction(row, 'restart')));
        break;
      case 'IN REVIEW':
        return const Text('Waiting for review',
            style: TextStyle(fontSize: 11, color: Color(0xFF6D28D9), fontWeight: FontWeight.w700));
      case 'APPROVED':
        return const Row(children: [
          Icon(Icons.verified_rounded, size: 14, color: Color(0xFF15803D)),
          SizedBox(width: 4),
          Text('Approved',
              style: TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.w700)),
        ]);
      default:
        return Text(state, style: const TextStyle(fontSize: 11, color: _kMuted));
    }
    // Row based Day Planner: each open row can be added on its own.
    actions.add(_plannerButton(row, busy));
    return Wrap(spacing: 6, runSpacing: 6, children: actions);
  }

  Widget _statusCell(Map<String, dynamic> row, String state) {
    final (label, bg, fg) = switch (state) {
      'IN PROGRESS' => ('IN PROGRESS', const Color(0xFFEFF6FF), _kPrimary),
      'ON HOLD' => ('ON HOLD', const Color(0xFFFEF3C7), const Color(0xFF92400E)),
      'IN REVIEW' => ('PENDING REVIEW', const Color(0xFFEDE9FE), const Color(0xFF6D28D9)),
      'REWORK' => ('REWORK', const Color(0xFFFFEDD5), const Color(0xFFC2410C)),
      'APPROVED' => ('COMPLETED', const Color(0xFFDCFCE7), const Color(0xFF15803D)),
      'REJECTED' => ('REJECTED', const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
      _ => ('PENDING', const Color(0xFFF1F5F9), _kMuted),
    };
    final comment = _str(row['manager_comment']);
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg)),
    );
    if (comment.isEmpty || (state != 'REWORK' && state != 'REJECTED')) {
      return Align(alignment: Alignment.centerLeft, child: badge);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        badge,
        const SizedBox(height: 3),
        Tooltip(
          message: comment,
          child: Text(
            comment,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: fg),
          ),
        ),
      ],
    );
  }

  Color _performanceColor(String perf) {
    switch (perf) {
      case 'Achieved':
        return const Color(0xFF00812B);
      case 'Before In':
        return const Color(0xFF1D4ED8);
      case 'Delay Out':
        return const Color(0xFFC40000);
      default:
        return _kMuted;
    }
  }
}