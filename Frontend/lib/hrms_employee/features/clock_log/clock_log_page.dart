import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:godigital_portal/services/authenticated_http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../services/api_config.dart';
import '../../../services/attendance_location.dart';
import '../../../services/auth_service.dart';
import '../../shared/employee_ui.dart';

class ClockLogPage extends StatelessWidget {
  const ClockLogPage({super.key});

  static Widget builder(BuildContext context) => const ClockLogPage();

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
  const _ClockView({required this.mobile});
  final bool mobile;

  @override
  State<_ClockView> createState() => _ClockViewState();
}

class _ClockViewState extends State<_ClockView> {
  bool _loading = false;
  bool _actionLoading = false;

  bool _isCheckedIn = false;
  String? _workMode;
  String? _clockInTimeStr;
  String? _clockOutTimeStr;
  int _elapsedSeconds = 0;
  int _extraSeconds = 0;
  bool _isOnBreak = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchTodayStatus();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isCheckedIn && !_isOnBreak) {
        setState(() {
          _elapsedSeconds++;
          if (_elapsedSeconds > 28800) {
            _extraSeconds = _elapsedSeconds - 28800;
          }
        });
      }
    });
  }

  String _formatDuration(int totalSecs) {
    final h = (totalSecs ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSecs % 3600) ~/ 60).toString().padLeft(2, '0');
    return '${h}h ${m}m';
  }

  String? _getToken() {
    try {
      final auth = context.read<AuthService>();
      return auth.token;
    } catch (_) {
      return null;
    }
  }

  List<String> _getBaseUrls() {
    return [ApiConfig.baseUrl];
  }

  Future<void> _fetchTodayStatus() async {
    final token = _getToken();
    setState(() => _loading = true);

    final now = DateTime.now();
    final monthQuery = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final candidateUrls = _getBaseUrls();

    for (final base in candidateUrls) {
      try {
        final url = Uri.parse('$base/attendance/dashboard?month=$monthQuery');
        final headers = <String, String>{
          'Accept': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        };

        final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          final data = body['data'] ?? body;
          final session = data['session'] as Map?;

          final isCheckedIn = (data['status'] == 'checked_in') ||
              (session != null && session['clock_out_at'] == null && (session['clock_in_at'] != null || session['punch_in'] != null || session['clock_in'] != null));

          final clockInRaw = session?['clock_in_at'] ?? session?['punch_in'] ?? session?['clock_in'];
          final clockOutRaw = session?['clock_out_at'] ?? session?['punch_out'] ?? session?['clock_out'];
          final activeBreak = data['active_break'];

          String? inFormatted;
          String? outFormatted;

          if (clockInRaw != null) {
            try {
              final dt = DateTime.parse(clockInRaw.toString().replaceAll(' ', 'T')).toLocal();
              inFormatted = DateFormat('hh:mm a').format(dt);
            } catch (_) {
              inFormatted = clockInRaw.toString();
            }
          }

          if (clockOutRaw != null) {
            try {
              final dt = DateTime.parse(clockOutRaw.toString().replaceAll(' ', 'T')).toLocal();
              outFormatted = DateFormat('hh:mm a').format(dt);
            } catch (_) {
              outFormatted = clockOutRaw.toString();
            }
          }

          int elapsed = 0;
          if (session != null && session['worked_seconds'] != null) {
            elapsed = (session['worked_seconds'] as num).toInt();
          } else if (clockInRaw != null) {
            try {
              final inDt = DateTime.parse(clockInRaw.toString().replaceAll(' ', 'T')).toLocal();
              final endDt = clockOutRaw != null
                  ? DateTime.parse(clockOutRaw.toString().replaceAll(' ', 'T')).toLocal()
                  : DateTime.now();
              elapsed = endDt.difference(inDt).inSeconds;
              if (elapsed < 0) elapsed = 0;
            } catch (_) {}
          }

          int extra = 0;
          if (elapsed > 28800) {
            extra = elapsed - 28800;
          }

          if (mounted) {
            setState(() {
              _isCheckedIn = isCheckedIn;
              _workMode = session?['work_mode']?.toString();
              _clockInTimeStr = inFormatted;
              _clockOutTimeStr = outFormatted;
              _elapsedSeconds = elapsed;
              _extraSeconds = extra;
              _isOnBreak = activeBreak != null;
            });
            if (_isCheckedIn && !_isOnBreak) {
              _startTimer();
            }
          }
          break;
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleClock() async {
    final token = _getToken();
    if (_actionLoading) return;
    if (token == null || token.isEmpty) return;
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Check In / Check Out is only available on the mobile app.'),
        ),
      );
      return;
    }
    final clockOut = _isCheckedIn;
    setState(() => _actionLoading = true);
    final endpoint = _isCheckedIn ? '/attendance/clock-out' : '/attendance/clock-in';
    final client = http.Client();
    try {
      Map<String, dynamic> payload;
      if (_isCheckedIn) {
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
        payload = await AttendanceLocation.checkInPayload(client: client, token: token);
      }
      if (!mounted || token != _getToken()) return;
      final response = await client.post(
        Uri.parse('${ApiConfig.baseUrl}$endpoint'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body);
      if (response.statusCode != 200 || body is! Map || body['success'] != true) {
        throw AttendanceLocationError(body is Map
            ? body['message']?.toString() ?? 'Check In failed.' : 'Check In failed.');
      }
      if (!mounted || token != _getToken()) return;
      await _fetchTodayStatus();
      if (mounted && token == _getToken() && !clockOut &&
          _isCheckedIn && _workMode == 'Hybrid') {
        await offerHybridFieldTracking(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error is AttendanceLocationError ? error.message
            : 'Could not reach attendance. Refresh attendance before retrying.')),
      );
      }
    } finally {
      client.close();
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _toggleBreak() async {
    final token = _getToken();
    if (_actionLoading) return;

    setState(() => _actionLoading = true);
    final endpoint = _isOnBreak ? '/attendance/break-out' : '/attendance/break-in';
    final candidateUrls = _getBaseUrls();

    for (final base in candidateUrls) {
      try {
        final url = Uri.parse('$base$endpoint');
        final headers = <String, String>{
          'Accept': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        };

        final response = await http.post(url, headers: headers).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          await _fetchTodayStatus();
          break;
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _actionLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final todayFormatted = DateFormat('dd MMM yyyy').format(DateTime.now()).toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loading) const LinearProgressIndicator(),
        const SizedBox(height: 12),
        EmployeeCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(builder: (context, constraints) {
                final isWide = constraints.maxWidth > 700;
                final metrics = [
                  _SessionMetric(
                    title: "TODAY'S SESSION — $todayFormatted",
                    value: _clockInTimeStr ?? '—:—',
                    caption: _isCheckedIn
                        ? 'Check In'
                        : (_clockOutTimeStr != null ? 'Ended at $_clockOutTimeStr' : 'Not checked in'),
                  ),
                  _SessionMetric(
                    title: 'ELAPSED TODAY',
                    value: _formatDuration(_elapsedSeconds),
                    caption: _isOnBreak
                        ? 'On Break'
                        : (_isCheckedIn ? 'Still checked in' : 'Session closed'),
                    valueColor: employeeBlue,
                  ),
                  _SessionMetric(
                    title: 'EXTRA HOURS (BEYOND 8H SHIFT)',
                    value: _formatDuration(_extraSeconds),
                    caption: '⚠ Not compensated',
                    valueColor: _extraSeconds > 0 ? employeeOrange : employeeNavy,
                    captionColor: employeeOrange,
                  ),
                ];

                final actionButtons = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isCheckedIn) ...[
                      OutlinedButton.icon(
                        onPressed: _actionLoading ? null : _toggleBreak,
                        icon: Icon(_isOnBreak ? Icons.play_arrow : Icons.pause, size: 18),
                        label: Text(_isOnBreak ? 'Resume Work' : 'Take Break'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _isOnBreak ? Colors.green : employeeOrange,
                          side: BorderSide(color: _isOnBreak ? Colors.green : employeeOrange),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    ElevatedButton.icon(
                      onPressed: _actionLoading ? null : _toggleClock,
                      icon: _actionLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Icon(_isCheckedIn ? Icons.logout : Icons.login, size: 18),
                      label: Text(_isCheckedIn ? 'Check Out' : 'Check In'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isCheckedIn ? const Color(0xFF0668F5) : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: metrics[0]),
                      Expanded(child: metrics[1]),
                      Expanded(child: metrics[2]),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          actionButtons,
                          const SizedBox(height: 6),
                          const Text(
                            'Standard shift: 09:00 AM - 05:00 PM',
                            style: TextStyle(color: employeeMuted, fontSize: 11),
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
                      const SizedBox(height: 18),
                      actionButtons,
                    ],
                  );
                }
              }),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8EE),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFECC8)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: employeeOrange, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Policy: Extra hours beyond the 8-hour shift are recorded on your attendance log for visibility only. They do not add to salary or generate compensation.',
                        style: TextStyle(color: employeeNavy, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
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
          Text(title,
              style: const TextStyle(
                  color: employeeMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: valueColor, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(caption,
              style: TextStyle(
                  color: captionColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      );
}
