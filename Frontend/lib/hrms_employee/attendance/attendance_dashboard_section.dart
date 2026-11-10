import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:godigital_portal/services/authenticated_http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/api_config.dart';
import '../../services/attendance_location.dart';
import '../../services/auth_service.dart';
import '../../services/auth_storage.dart';
import '../../services/hrms_attendance_tracker.dart';
import '../shared/employee_ui.dart';

/// Attendance on the employee home screen. Other modules retain their own state.
class AttendanceDashboardSection extends StatefulWidget {
  const AttendanceDashboardSection({super.key, this.client});
  final http.Client? client;

  @override
  State<AttendanceDashboardSection> createState() =>
      _AttendanceDashboardSectionState();
}

class _AttendanceDashboardSectionState extends State<AttendanceDashboardSection>
    with WidgetsBindingObserver {
  late final http.Client _client;
  Timer? _timer;
  String? _token;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _punching = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? http.Client();
    WidgetsBinding.instance.addObserver(this);
    // This redraws only the local attendance card for elapsed work and break
    // countdowns. It deliberately makes no HTTP request, preventing UI flicker.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _data?['status'] != 'checked_in') return;
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthService>();
    // Wait for the persisted session to finish loading. Without this guard,
    // the first attendance render could mistake a still-loading session for a
    // logged-out employee.
    if (!auth.isInitialized) return;

    final token = auth.token;
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
    final cacheBuster = endpoint == 'check-in-policy'
        ? '?_=${DateTime.now().microsecondsSinceEpoch}'
        : '';
    final url = Uri.parse('${ApiConfig.baseUrl}/attendance/$endpoint$cacheBuster');
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (post) 'Content-Type': 'application/json',
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
      throw const _AttendanceError('Attendance is unavailable. Please retry.');
    }
    if (response.statusCode != 200 || body['success'] != true) {
      throw _AttendanceError(
        body['message']?.toString() ?? 'Attendance is unavailable.',
      );
    }
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  String _message(Object error) => error is _AttendanceError
      ? error.message
      : error is AttendanceLocationError
      ? error.message
      : 'Could not reach attendance. Check your connection and retry.';

  String _durationLabel(int minutes) =>
      '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';

  void _showCorrectionRequestDialog(BuildContext context, {String checkIn = '--', String checkOut = '--'}) {
    final reasonController = TextEditingController();
    bool submitting = false;
    String? submitError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Checkout correction request',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            SizedBox(height: 2),
                            Text('Admin will review and restore your session if approved.',
                                style: TextStyle(fontSize: 12, color: employeeMuted)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, size: 18),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFF4F6FB),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      _InfoChip(label: 'Check in', value: checkIn),
                      _InfoChip(label: 'Checked out at', value: checkOut),
                      _InfoChip(label: 'Date', value: DateFormat('d MMM yyyy').format(DateTime.now())),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Reason', style: TextStyle(fontSize: 12, color: employeeMuted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Explain why you need the checkout corrected…',
                      hintStyle: const TextStyle(fontSize: 13, color: employeeMuted),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  if (submitError != null) ...[
                    const SizedBox(height: 8),
                    Text(submitError!, style: const TextStyle(fontSize: 12, color: Colors.red)),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: submitting
                            ? null
                            : () async {
                                final reason = reasonController.text.trim();
                                if (reason.isEmpty) {
                                  setS(() => submitError = 'Please enter a reason.');
                                  return;
                                }
                                setS(() { submitting = true; submitError = null; });
                                try {
                                  final token = _token ?? '';
                                  final response = await http.post(
                                    Uri.parse('${ApiConfig.baseUrl}/attendance/checkout/correction-request'),
                                    headers: {
                                      'Authorization': 'Bearer $token',
                                      'Content-Type': 'application/json',
                                    },
                                    body: jsonEncode({'reason': reason}),
                                  ).timeout(const Duration(seconds: 15));
                                  final body = jsonDecode(response.body) as Map<String, dynamic>;
                                  if (!ctx.mounted) return;
                                  if (response.statusCode == 200 && body['success'] == true) {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Correction request submitted. Admin will review it.')),
                                    );
                                    _load();
                                  } else {
                                    setS(() { submitting = false; submitError = body['message']?.toString() ?? 'Failed to submit. Try again.'; });
                                  }
                                } catch (_) {
                                  if (!ctx.mounted) return;
                                  setS(() { submitting = false; submitError = 'Could not connect. Check your connection.'; });
                                }
                              },
                        child: submitting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Submit request'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _load({bool background = false}) async {
    var token = _token;
    final request = ++_request;
    if (token == null || token.isEmpty) {
      // The session token is written during login. Read the persisted value
      // once as a fallback before showing a sign-in error.
      token = await AuthStorage.getString('auth_token');
      if (token != null && token.isNotEmpty) {
        _token = token;
      }
    }
    if (token == null || token.isEmpty) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _data = null;
        _error = 'Please sign in to view attendance.';
      });
      return;
    }
    if (!background) setState(() => _loading = true);
    try {
      final data = await _call('dashboard', token);
      if (!mounted || request != _request || token != _token) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (error) {
      if (!mounted || request != _request || token != _token) return;
      setState(() => _error = _message(error));
    } finally {
      if (!background && mounted && request == _request && token == _token) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _punch() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Check In / Check Out is only available on the mobile app.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    final token = _token;
    if (token == null || _loading || _punching || _error != null) return;
    final clockOut = _data?['status'] == 'checked_in';
    if (clockOut) {
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
          };
        } catch (_) {
          payload = <String, dynamic>{};
        }
      } else {
        payload = await AttendanceLocation.checkInPayload(
          client: _client,
          token: token,
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
    // Also reconcile after a timeout: the server may have saved the punch.
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

  Future<void> _toggleBreak() async {
    final token = _token;
    if (token == null || _loading || _punching || _error != null) return;
    final active = (_data?['break'] as Map?)?['active'] == true;
    setState(() => _punching = true);
    try {
      final payload = active
          ? await AttendanceLocation.checkInPayload(client: _client, token: token)
          : <String, dynamic>{};
      if (active) {
        final breakInfo = _data?['break'] as Map? ?? const {};
        final policy = _data?['break_policy'] as Map? ?? const {};
        final started = DateTime.tryParse('${breakInfo['started_at'] ?? ''}'.replaceFirst(' ', 'T'));
        final allowed = (policy['max_break_minutes'] as num?)?.toInt() ?? 60;
        final overdue = started == null ? 0 : DateTime.now().difference(started.toLocal()).inMinutes - allowed;
        if (overdue > 0) {
          final controller = TextEditingController();
          final reason = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: const Text('Reason for extended break'), content: TextField(controller: controller, autofocus: true, maxLength: 500, decoration: InputDecoration(hintText: 'Break overdue by $overdue min. Enter reason.')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('End Break'))]));
          if (reason == null || reason.trim().isEmpty) return;
          payload['reason'] = reason.trim();
        }
      }
      await _call(active ? 'break-out' : 'break-in', token, post: true, payload: payload);
      if (mounted) await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(active ? 'Break ended.' : 'Break started.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(error))));
    } finally {
      if (mounted) setState(() => _punching = false);
    }
  }

  String _formatPunchTime(dynamic rawTimestamp) {
    if (rawTimestamp == null || rawTimestamp.toString().trim().isEmpty) {
      return '--:--';
    }
    try {
      final str = rawTimestamp.toString();
      DateTime dt;
      if (str.contains('T') || str.contains('-')) {
        dt = DateTime.parse(str).toLocal();
      } else {
        return str; // Return as-is if already formatted like "09:30 AM"
      }
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return rawTimestamp.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return EmployeeCard(
        child: Column(
          children: [
            if (_loading)
              const CircularProgressIndicator()
            else ...[
              Text(_error ?? 'Attendance is unavailable.'),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ],
        ),
      );
    }
    final employee = data['employee'] as Map;
    final session = data['session'] as Map?;
    final overview = data['month_overview'] as Map;
    final workTime = overview['work_time'] as Map? ?? const {};
    final actualMinutes = (workTime['actual_minutes'] as num?)?.toInt() ?? 0;
    final targetMinutes = (workTime['target_minutes'] as num?)?.toInt() ?? 0;
    final overtimeMinutes = (workTime['overtime_minutes'] as num?)?.toInt() ?? 0;
    final progress = targetMinutes == 0
        ? 0.0
        : (actualMinutes / targetMinutes).clamp(0.0, 1.0);
    final actions = data['actions'] as Map;
    final checkedIn = data['status'] == 'checked_in';
    final checkedOut = data['status'] == 'checked_out';
    final hasPendingCorrection = actions['has_pending_correction'] == true;
    final breakInfo = data['break'] as Map? ?? const <String, dynamic>{};
    final onBreak = breakInfo['active'] == true;
    final breakPolicy = data['break_policy'] as Map? ?? const <String, dynamic>{};
    final breakLimit = (breakPolicy['break_calculation_mode'] == 'fixed_schedule'
            ? breakPolicy['fixed_break_minutes']
            : breakPolicy['max_break_minutes']) as num? ?? 60;
    final breakStarted = DateTime.tryParse('${breakInfo['started_at'] ?? ''}'.replaceFirst(' ', 'T'));
    final breakElapsed = breakStarted == null ? 0 : DateTime.now().difference(breakStarted.toLocal()).inMinutes;
    final breakRemaining = (breakLimit.toInt() - breakElapsed).clamp(0, breakLimit.toInt());
    final breakOverdue = breakElapsed - breakLimit.toInt();
    final workedSeconds = (session?['worked_seconds'] as num?)?.toInt() ?? 0;
    // The circle is an elapsed-day clock, so it keeps running during a break.
    // Payroll and monthly "Worked" totals continue to come from the server and
    // exclude recorded break duration.
    final elapsedStart = DateTime.tryParse(
      '${session?['punch_in'] ?? session?['clock_in_at'] ?? ''}'
          .replaceFirst(' ', 'T'),
    );
    final elapsedEnd = checkedOut
        ? DateTime.tryParse(
            '${session?['punch_out'] ?? session?['clock_out_at'] ?? ''}'
                .replaceFirst(' ', 'T'),
          )
        : DateTime.now();
    final elapsedSeconds = elapsedStart == null || elapsedEnd == null
        ? workedSeconds
        : elapsedEnd.difference(elapsedStart).inSeconds.clamp(0, 1 << 31);
    final today = DateTime.parse(data['date'] as String);
    final overnight = session != null && session['work_date'] != data['date'];

    final punchInDisplay = _formatPunchTime(
      session?['punch_in'] ?? session?['clock_in'] ?? session?['check_in'],
    );
    final punchOutDisplay = _formatPunchTime(
      session?['punch_out'] ?? session?['clock_out'] ?? session?['check_out'],
    );

    final workday = EmployeeCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            overnight ? 'Current Work Session' : "Today's Workday",
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 130,
            height: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Decorative ring indicator
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: employeeBlue, width: 8),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${elapsedSeconds ~/ 3600}h ${(elapsedSeconds % 3600) ~/ 60}m',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'Elapsed',
                      style: TextStyle(color: employeeMuted, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Divider(color: employeeLine),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  const Text(
                    'Check In',
                    style: TextStyle(color: employeeMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    punchInDisplay,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: employeeNavy,
                    ),
                  ),
                ],
              ),
              Container(height: 26, width: 1, color: employeeLine),
              Column(
                children: [
                  const Text(
                    'Check Out',
                    style: TextStyle(color: employeeMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    punchOutDisplay,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: employeeNavy,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    final month = EmployeeCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${DateFormat('MMMM').format(DateTime.parse('${overview['month']}-01'))} Overview',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 13),
          const Text('Monthly Work Time',
              style: TextStyle(color: employeeMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(_durationLabel(actualMinutes),
              style: const TextStyle(
                  color: employeeNavy, fontSize: 27, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            tween: Tween(begin: 0, end: progress),
            builder: (context, value, child) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 7,
                backgroundColor: employeeLine,
                valueColor: AlwaysStoppedAnimation<Color>(
                    overtimeMinutes > 0 ? const Color(0xFF11A55B) : employeeBlue),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            targetMinutes > 0
                ? 'Target ${_durationLabel(targetMinutes)}${overtimeMinutes > 0 ? '  +${_durationLabel(overtimeMinutes)} extra' : ''}'
                : 'Attendance target is not configured',
            style: const TextStyle(color: employeeMuted, fontSize: 12),
          ),
          const SizedBox(height: 13),
          _count('Working Days', overview['working_days'], const Color(0xFF0891B2)),
          const Divider(color: employeeLine),
          _count('Present', overview['present_days'], const Color(0xFF11A55B)),
          const Divider(color: employeeLine),
          _count('Absent', overview['absent_days'], const Color(0xFFE34646)),
          const Divider(color: employeeLine),
          _count('Late', overview['late_days'], const Color(0xFFFF8B17)),
          if (overview['absent_days'] == null ||
              overview['late_days'] == null) ...[
            const SizedBox(height: 10),
            const Text(
              'Late and absent totals will appear once working hours and days are set.',
              style: TextStyle(color: employeeMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Hello, '),
              TextSpan(
                text: (employee['name'] ?? employee['full_name'] ?? employee['fullName'] ?? employee['employee_name'] ?? employee['username'] ?? '').toString(),
                style: const TextStyle(color: employeeBlue),
              ),
            ],
          ),
          style: const TextStyle(
            color: employeeNavy,
            fontSize: 27,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${employee['staff_id']}  •  ${DateFormat('EEEE, d MMM yyyy').format(today)}',
          style: const TextStyle(color: employeeMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Text('Attendance may be out of date. $_error'),
          TextButton(
            onPressed: _loading || _punching ? null : _load,
            child: const Text('Retry'),
          ),
        ],
        if (_loading) const LinearProgressIndicator(),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF0B72F5), Color(0xFF073B9D)],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      checkedIn
                          ? 'Checked In'
                          : checkedOut
                          ? 'Checked Out'
                          : 'Not Checked In',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    if (checkedIn && punchInDisplay != '--:--') ...[
                      const SizedBox(height: 3),
                      Text(
                        'Since $punchInDisplay',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (onBreak) ...[
                      const SizedBox(height: 3),
                      Text(
                        breakOverdue > 0
                            ? 'Break overdue by $breakOverdue min · Return and end break'
                            : breakRemaining == 0
                                ? 'Break limit reached · Return and end break'
                                : 'Break active · $breakRemaining min remaining',
                        style: TextStyle(color: breakOverdue > 0 ? const Color(0xFFFFB4B4) : Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (checkedIn) ...[
                OutlinedButton.icon(
                  onPressed: _loading || _punching || _error != null ? null : _toggleBreak,
                  icon: Icon(onBreak ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 18),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, disabledForegroundColor: Colors.white70, side: const BorderSide(color: Colors.white)),
                  label: Text(onBreak ? 'End Break' : 'Break'),
                ),
                const SizedBox(width: 10),
              ],
              OutlinedButton(
                onPressed:
                    _loading ||
                        _punching ||
                        _error != null ||
                        !(actions['can_clock_in'] == true ||
                            actions['can_clock_out'] == true)
                    ? null
                    : _punch,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white),
                ),
                child: Text(
                  _punching
                      ? 'Saving…'
                      : checkedIn
                      ? 'Check Out'
                      : checkedOut
                      ? 'Completed'
                      : 'Check In',
                ),
              ),
            ],
          ),
        ),
        if (checkedOut) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                hasPendingCorrection ? Icons.hourglass_top_rounded : Icons.info_outline_rounded,
                size: 13,
                color: hasPendingCorrection ? const Color(0xFFF59E0B) : employeeMuted,
              ),
              const SizedBox(width: 5),
              if (hasPendingCorrection)
                const Text(
                  'Correction request sent — awaiting admin review.',
                  style: TextStyle(fontSize: 11, color: Color(0xFFF59E0B), fontWeight: FontWeight.w600),
                )
              else ...[
                const Text(
                  'Checked out by mistake? ',
                  style: TextStyle(fontSize: 11, color: employeeMuted),
                ),
                GestureDetector(
                  onTap: () => _showCorrectionRequestDialog(context, checkIn: punchInDisplay, checkOut: punchOutDisplay),
                  child: const Text(
                    'Raise a correction request',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF0B72F5),
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFF0B72F5),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 520
              ? Column(children: [workday, const SizedBox(height: 14), month])
              : SizedBox(
                  height: 352,
                  child: Row(
                    children: [
                      Expanded(child: workday),
                      const SizedBox(width: 18),
                      Expanded(child: month),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _count(String label, dynamic value, Color color) => Row(
    children: [
      Expanded(child: Text(label)),
      Text(
        value?.toString() ?? '—',
        style: TextStyle(
          color: color,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _AttendanceError implements Exception {
  const _AttendanceError(this.message);
  final String message;
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6FB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE3E8F4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: employeeMuted)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
