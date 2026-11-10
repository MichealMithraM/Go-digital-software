import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:godigital_portal/services/authenticated_http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/api_config.dart';
import '../../services/attendance_client_identity.dart';
import '../../services/attendance_location.dart';
import '../../services/auth_service.dart';
import '../../services/hrms_attendance_tracker.dart';
import '../../services/hrms_tracking_api.dart';
import '../shared/employee_ui.dart';

class EmployeeClockPage extends StatelessWidget {
  const EmployeeClockPage({super.key});

  @override
  Widget build(BuildContext context) => const EmployeeScaffold(
    route: '/employee/clock-log',
    title: 'Check In / Check Out',
    subtitle: 'Track your daily working hours in real time',
    desktop: _ClockView(mobile: false),
    mobile: _ClockView(mobile: true),
  );
}

class _ClockView extends StatefulWidget {
  const _ClockView({required this.mobile}) : client = null;
  final bool mobile;
  final http.Client? client;

  @override
  State<_ClockView> createState() => _ClockViewState();
}

class _ClockViewState extends State<_ClockView> with WidgetsBindingObserver {
  late final http.Client _client;
  final _elapsed = Stopwatch();
  Timer? _timer;
  String? _token;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _punching = false;
  int _request = 0;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? http.Client();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_data?['status'] == 'checked_in') setState(() {});
      if (++_ticks % 60 == 0 && !_loading && !_punching) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final token = context.watch<AuthService>().token;
    if (_token != token || (_loading && _request == 0)) {
      _token = token;
      _data = null;
      _punching = false;
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_punching) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _client.close();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(
    String endpoint,
    String token, {
    bool post = false,
    Map<String, dynamic>? payload,
  }) async {
    // Use the configured backend for both validation and the attendance write.
    // Retrying a denied punch against an older server could bypass the rule.
    final cacheBuster = endpoint == 'check-in-policy'
        ? '?_=${DateTime.now().microsecondsSinceEpoch}'
        : '';
    final url = Uri.parse('${ApiConfig.baseUrl}/attendance/$endpoint$cacheBuster');
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (post) ...await AttendanceClientIdentity.headers(),
    };
    final response =
        await (post
                ? _client.post(
                    url,
                    headers: headers,
                    body: jsonEncode(payload ?? {}),
                  )
                : _client.get(url, headers: headers))
            .timeout(const Duration(seconds: 15));

    if (response.statusCode == 401) {
      throw const _AttendanceError(
        'Your session expired. Please sign in again.',
      );
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const _AttendanceError('Invalid response from server.');
    }

    if (response.statusCode != 200 || body['success'] != true) {
      throw _AttendanceError(
        body['message']?.toString() ?? 'Attendance request failed.',
      );
    }

    return Map<String, dynamic>.from(body['data'] as Map);
  }

  String _message(Object error) => error is _AttendanceError
      ? error.message
      : error is AttendanceLocationError
      ? error.message
      : 'Could not reach attendance. Check your connection and retry.';

  Future<void> _load() async {
    final token = _token;
    final request = ++_request;
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _data = null;
        _error = 'Please sign in to view attendance.';
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final data = await _call('dashboard', token);
      if (!mounted || request != _request || token != _token) return;
      setState(() {
        _data = data;
        _error = null;
        _elapsed
          ..reset()
          ..start();
      });
    } catch (error) {
      if (!mounted || request != _request || token != _token) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted && request == _request && token == _token) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _punch() async {
    if (kIsWeb) {
      if (!await AttendanceClientIdentity.isIosWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Check In / Check Out is available only in the Android app or an approved iPhone browser.'),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
    }
    final token = _token;
    if (token == null || _loading || _punching || _error != null) return;
    final clockOut = _data?['status'] == 'checked_in';

    // ── Hybrid checkout: warn if field tracking is still active ───────────────
    if (clockOut) {
      final session = _data?['session'] as Map?;
      final workMode = session?['work_mode']?.toString() ?? '';
      if (workMode == 'Hybrid') {
        final shouldProceed = await _checkHybridBeforeCheckout();
        if (!mounted || token != _token) return;
        if (!shouldProceed) return;
      } else {
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('End your shift now?'),
            content: const Text('Your checkout time and worked hours will be recorded.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Check Out'))],
          ),
        );
        if (confirmed != true) return;
      }
    }

    setState(() => _punching = true);
    String message;
    bool punchSucceeded = false;
    try {
      Map<String, dynamic> payload;
      if (clockOut) {
        try {
          final pos = await AttendanceLocation.currentPosition();
          payload = {
            'latitude': pos.latitude,
            'longitude': pos.longitude,
            'accuracy': pos.accuracy,
            'capturedAt': pos.timestamp.toUtc().toIso8601String(),
          };
        } catch (_) {
          if (kIsWeb) rethrow;
          payload = <String, dynamic>{};
        }
      } else {
        payload = await AttendanceLocation.checkInPayload(
          client: _client,
          token: token,
          forceLocation: kIsWeb,
        );
      }
      if (!mounted || token != _token) return;
      await _call(
        clockOut ? 'clock-out' : 'clock-in',
        token,
        post: true,
        payload: payload,
      );
      message = clockOut
          ? 'You have been checked out.'
          : 'You are now checked in.';
      punchSucceeded = true;
    } catch (error) {
      message = '${_message(error)} Refresh attendance before trying again.';
    }

    if (!mounted || token != _token) return;
    await _load();
    if (!mounted || token != _token) return;
    if (punchSucceeded) {
      if (clockOut) {
        unawaited(HrmsAttendanceTracker.instance.stopTracking());
      } else {
        unawaited(HrmsAttendanceTracker.instance.startTracking());
      }
    }
    setState(() => _punching = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    if (punchSucceeded && !clockOut &&
        (_data?['session'] as Map?)?['work_mode'] == 'Hybrid') {
      await offerHybridFieldTracking(context);
    }
  }

  // Returns true if checkout should proceed, false to cancel.
  // For Hybrid: if tracking is active, shows stop+checkout dialog.
  Future<bool> _checkHybridBeforeCheckout() async {
    bool trackingActive = false;
    try {
      final session = await HrmsTrackingApi.hybridSession();
      trackingActive = session['is_active'] == 1 || session['is_active'] == true || session['isActive'] == true;
    } catch (_) {}

    if (!mounted) return false;

    if (trackingActive) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tracking Still Active'),
          content: const Text('Your field tracking is still running. Stop it before checking out.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'stop_and_checkout'),
              child: const Text('Stop Tracking & Check Out'),
            ),
          ],
        ),
      );
      if (choice != 'stop_and_checkout') return false;
      // Stop the field tracking session
      try {
        final pos = await AttendanceLocation.currentPosition();
        await HrmsTrackingApi.stopHybridSession(
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
        );
      } catch (_) {
        await HrmsTrackingApi.stopHybridSession();
      }
      return true;
    }

    // Tracking not active — show normal checkout confirmation
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End your shift now?'),
        content: const Text('Your checkout time and worked hours will be recorded.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Check Out')),
        ],
      ),
    );
    return confirmed == true;
  }

  String _formatPunchTime(dynamic rawTimestamp) {
    if (rawTimestamp == null || rawTimestamp.toString().trim().isEmpty) {
      return '—:—';
    }
    try {
      final str = rawTimestamp.toString();
      DateTime dt;
      if (str.contains('T') || str.contains('-')) {
        dt = DateTime.parse(str).toLocal();
      } else {
        return str;
      }
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return rawTimestamp.toString();
    }
  }

  String _formatDuration(int totalSecs) {
    final h = (totalSecs ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSecs % 3600) ~/ 60).toString().padLeft(2, '0');
    return '${h}h ${m}m';
  }

  int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

  String _formatScheduledTime(dynamic value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch('${value ?? ''}');
    if (match == null) return 'Not set';
    final hour = int.tryParse(match.group(1)!) ?? -1;
    final minute = int.tryParse(match.group(2)!) ?? -1;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return 'Not set';
    return DateFormat('hh:mm a').format(DateTime(2000, 1, 1, hour, minute));
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final session = data?['session'] as Map?;
    final actions = data?['actions'] as Map? ?? {};
    final checkedIn = data?['status'] == 'checked_in';
    final checkedOut = data?['status'] == 'checked_out';
    final workTime = (data?['month_overview'] as Map?)?['work_time'] as Map?;
    final dailyTargetMinutes = _asInt(workTime?['daily_target_minutes']);
    final dailyTargetSeconds = dailyTargetMinutes * 60;
    final hasSchedule = dailyTargetSeconds > 0;
    final shiftStart = _formatScheduledTime(workTime?['shift_start']);
    final shiftEnd = _formatScheduledTime(workTime?['shift_end']);

    final seconds = (session?['worked_seconds'] as num?)?.toInt() ?? 0;
    final workedSeconds =
        seconds + (checkedIn ? _elapsed.elapsed.inSeconds : 0);
    final savedBreakSeconds = (session?['break_seconds'] as num?)?.toInt() ?? 0;
    final breakSeconds =
        savedBreakSeconds +
        (checkedIn && (data?['break'] as Map?)?['active'] == true
            ? _elapsed.elapsed.inSeconds
            : 0);
    final extraSeconds = hasSchedule && workedSeconds > dailyTargetSeconds
        ? workedSeconds - dailyTargetSeconds
        : 0;

    final punchInDisplay = _formatPunchTime(
      session?['punch_in'] ?? session?['clock_in'] ?? session?['clock_in_at'],
    );
    final punchOutDisplay = _formatPunchTime(
      session?['punch_out'] ??
          session?['clock_out'] ??
          session?['clock_out_at'],
    );

    final todayFormatted = DateFormat(
      'dd MMM yyyy',
    ).format(DateTime.now()).toUpperCase();
    final recentRecords =
        ((data?['month_records'] as List?) ?? const [])
            .whereType<Map>()
            .map((record) => Map<String, dynamic>.from(record))
            .toList()
          ..sort(
            (left, right) => (right['work_date']?.toString() ?? '').compareTo(
              left['work_date']?.toString() ?? '',
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Attendance error: $_error',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        EmployeeCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 1000;
                  final metrics = [
                    _SessionMetric(
                      title: "TODAY'S SESSION — $todayFormatted",
                      value: punchInDisplay,
                      caption: checkedIn
                          ? 'Check In · ${session?['work_mode'] ?? 'Not set'}'
                          : (checkedOut
                                ? 'Ended at $punchOutDisplay'
                                : 'Not checked in'),
                    ),
                    _SessionMetric(
                      title: 'ELAPSED TODAY',
                      value: _formatDuration(workedSeconds),
                      caption: checkedIn
                          ? 'Still checked in'
                          : 'Session closed',
                      valueColor: employeeBlue,
                    ),
                    _SessionMetric(
                      title: 'BREAK TIME',
                      value: _formatDuration(breakSeconds),
                      caption: (data?['break'] as Map?)?['active'] == true
                          ? 'Break in progress'
                          : 'Break recorded today',
                      valueColor: employeePurple,
                    ),
                    _SessionMetric(
                      title: hasSchedule
                          ? 'EXTRA HOURS (BEYOND ${_formatDuration(dailyTargetSeconds)} SHIFT)'
                          : 'EXTRA HOURS',
                      value: _formatDuration(extraSeconds),
                      caption: hasSchedule
                          ? '⚠ Not compensated'
                          : 'Schedule not configured',
                      valueColor: extraSeconds > 0
                          ? employeeOrange
                          : employeeNavy,
                      captionColor: employeeOrange,
                    ),
                  ];

                  final actionButton = ElevatedButton.icon(
                    onPressed:
                        _loading ||
                            _punching ||
                            !(actions['can_clock_in'] == true ||
                                actions['can_clock_out'] == true)
                        ? null
                        : _punch,
                    icon: _punching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(
                            checkedIn ? Icons.logout : Icons.login,
                            size: 18,
                          ),
                    label: Text(
                      _punching
                          ? 'Saving…'
                          : checkedIn
                          ? 'Check Out'
                          : checkedOut
                          ? 'Completed'
                          : 'Check In',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: checkedIn
                          ? const Color(0xFF0668F5)
                          : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: metrics[0]),
                        Expanded(child: metrics[1]),
                        Expanded(child: metrics[2]),
                        Expanded(child: metrics[3]),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            actionButton,
                            const SizedBox(height: 6),
                            Text(
                              'Scheduled shift: $shiftStart - $shiftEnd',
                              style: const TextStyle(
                                color: employeeMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        metrics[0],
                        const SizedBox(height: 14),
                        metrics[1],
                        const SizedBox(height: 14),
                        metrics[2],
                        const SizedBox(height: 14),
                        metrics[3],
                        const SizedBox(height: 18),
                        actionButton,
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8EE),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFECC8)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: employeeOrange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasSchedule
                            ? 'Policy: Extra hours beyond the ${_formatDuration(dailyTargetSeconds)} scheduled shift are recorded on your attendance log for visibility only. They do not add to salary or generate compensation.'
                            : 'Policy: Admin must configure the attendance schedule before extra hours can be calculated.',
                        style: const TextStyle(color: employeeNavy, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _RecentClockRecords(records: recentRecords.take(5).toList()),
      ],
    );
  }
}

class _RecentClockRecords extends StatelessWidget {
  const _RecentClockRecords({required this.records});

  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) => EmployeeCard(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.history_rounded, color: employeeBlue, size: 22),
            SizedBox(width: 9),
            Text(
              'Recent Clock Records',
              style: TextStyle(
                color: employeeNavy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Your latest check-in and check-out sessions',
          style: TextStyle(color: employeeMuted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        if (records.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 26),
            child: Center(
              child: Text(
                'No clock records yet.',
                style: TextStyle(color: employeeMuted),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 650;
              return Column(
                children: [
                  if (!compact) const _RecentRecordHeader(),
                  ...records.map(
                    (record) =>
                        _RecentRecordRow(record: record, compact: compact),
                  ),
                ],
              );
            },
          ),
      ],
    ),
  );
}

class _RecentRecordHeader extends StatelessWidget {
  const _RecentRecordHeader();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(12, 0, 12, 7),
    child: Row(
      children: [
        Expanded(flex: 3, child: Text('DATE', style: _recordHeaderStyle)),
        Expanded(flex: 2, child: Text('CHECK IN', style: _recordHeaderStyle)),
        Expanded(flex: 2, child: Text('CHECK OUT', style: _recordHeaderStyle)),
        Expanded(flex: 2, child: Text('BREAK IN', style: _recordHeaderStyle)),
        Expanded(flex: 2, child: Text('BREAK OUT', style: _recordHeaderStyle)),
        Expanded(flex: 2, child: Text('BREAK TIME', style: _recordHeaderStyle)),
        Expanded(flex: 2, child: Text('WORKED', style: _recordHeaderStyle)),
        Expanded(
          flex: 2,
          child: Text('WORK LOCATION', style: _recordHeaderStyle),
        ),
        Expanded(flex: 2, child: Text('STATUS', style: _recordHeaderStyle)),
      ],
    ),
  );
}

const _recordHeaderStyle = TextStyle(
  color: employeeMuted,
  fontSize: 10,
  fontWeight: FontWeight.w700,
  letterSpacing: .5,
);

class _RecentRecordRow extends StatelessWidget {
  const _RecentRecordRow({required this.record, required this.compact});

  final Map<String, dynamic> record;
  final bool compact;

  DateTime? _timestamp(dynamic value) => value == null
      ? null
      : DateTime.tryParse(value.toString().replaceFirst(' ', 'T'))?.toLocal();

  String _dateLabel() {
    final raw = record['work_date']?.toString() ?? '';
    final value = raw.length >= 10 ? raw.substring(0, 10) : raw;
    final date = DateTime.tryParse(value);
    return date == null ? '—' : DateFormat('EEE, dd MMM').format(date);
  }

  String _timeLabel(dynamic value) {
    final date = _timestamp(value);
    return date == null ? '—' : DateFormat('hh:mm a').format(date);
  }

  String _duration() {
    final start = _timestamp(record['clock_in_at']);
    final end = _timestamp(record['clock_out_at']);
    if (start == null) return '—';
    if (end == null) return 'In progress';
    final minutes = end.difference(start).inMinutes.clamp(0, 1440);
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  String _breakDuration() {
    final minutes = record['break_minutes'] is num
        ? (record['break_minutes'] as num).toInt()
        : int.tryParse('${record['break_minutes']}') ?? 0;
    return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
  }

  String _workLocation() {
    final value = record['work_mode']?.toString().trim() ?? '';
    return value.isEmpty ? 'Not set' : value;
  }

  @override
  Widget build(BuildContext context) {
    final late = record['is_late'] == true || record['is_late'] == 1;
    final active = record['clock_out_at'] == null;
    final status = late
        ? 'Late'
        : active
        ? 'Active'
        : 'Present';
    final color = late
        ? employeeOrange
        : active
        ? employeeBlue
        : const Color(0xFF0AA85A);
    final background = late
        ? const Color(0xFFFFF3E9)
        : active
        ? const Color(0xFFEAF2FF)
        : const Color(0xFFEAF8F0);
    final statusChip = Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          status,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    final overdue = (record['break_overdue_minutes'] as num?)?.toInt() ?? 0;
    final breakInLabel = _timeLabel(record['break_in_at']);
    final breakOutLabel = _timeLabel(record['break_out_at']);
    final breakColor = overdue > 0 ? const Color(0xFFF04438) : employeeNavy;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFF),
        border: Border.all(color: const Color(0xFFE5EBF5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [_value(_dateLabel(), bold: true), statusChip],
                ),
                const SizedBox(height: 5),
                _compactValue('Work location', _workLocation()),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _compactValue(
                        'Check in',
                        _timeLabel(record['clock_in_at']),
                      ),
                    ),
                    Expanded(
                      child: _compactValue(
                        'Check out',
                        _timeLabel(record['clock_out_at']),
                      ),
                    ),
                    Expanded(child: _compactValue('Worked', _duration())),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _compactValue(
                        'Break in',
                        breakInLabel,
                        valueColor: breakColor,
                      ),
                    ),
                    Expanded(
                      child: _compactValue(
                        'Break out',
                        breakOutLabel,
                        valueColor: breakColor,
                      ),
                    ),
                    Expanded(
                      child: _compactValue(
                        'Break time',
                        _breakDuration(),
                        valueColor: breakColor,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 3, child: _value(_dateLabel(), bold: true)),
                Expanded(
                  flex: 2,
                  child: _value(_timeLabel(record['clock_in_at'])),
                ),
                Expanded(
                  flex: 2,
                  child: _value(_timeLabel(record['clock_out_at'])),
                ),
                Expanded(
                  flex: 2,
                  child: _value(breakInLabel, color: breakColor),
                ),
                Expanded(
                  flex: 2,
                  child: _value(
                    breakOutLabel,
                    color: overdue > 0 ? breakColor : null,
                    suffix: overdue > 0 ? ' +${overdue}m' : null,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _value(_breakDuration(), color: breakColor),
                ),
                Expanded(flex: 2, child: _value(_duration())),
                Expanded(flex: 2, child: _value(_workLocation())),
                Expanded(flex: 2, child: statusChip),
              ],
            ),
    );
  }

  Widget _value(
    String value, {
    bool bold = false,
    Color? color,
    String? suffix,
  }) {
    if (suffix != null && suffix.isNotEmpty) {
      return Row(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color ?? employeeNavy,
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            suffix,
            style: const TextStyle(
              color: Color(0xFFF04438),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }
    return Text(
      value,
      style: TextStyle(
        color: color ?? employeeNavy,
        fontSize: 13,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  Widget _compactValue(String label, String value, {Color? valueColor}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _recordHeaderStyle),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? employeeNavy,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
}

class _SessionMetric extends StatelessWidget {
  const _SessionMetric({
    required this.title,
    required this.value,
    required this.caption,
    this.valueColor = employeeNavy,
    this.captionColor = employeeMuted,
  });

  final String title;
  final String value;
  final String caption;
  final Color valueColor;
  final Color captionColor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: employeeMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        value,
        style: TextStyle(
          color: valueColor,
          fontSize: 26,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        caption,
        style: TextStyle(
          color: captionColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _AttendanceError implements Exception {
  const _AttendanceError(this.message);
  final String message;
}
