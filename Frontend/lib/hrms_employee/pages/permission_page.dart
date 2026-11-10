import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:godigital_portal/services/authenticated_http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/api_config.dart';
import '../../services/attendance_client_identity.dart';
import '../../services/auth_service.dart';
import '../../services/attendance_location.dart';
import '../../services/hrms_tracking_api.dart';
import '../shared/employee_ui.dart';

class EmployeePermissionPage extends StatefulWidget {
  const EmployeePermissionPage({super.key});

  @override
  State<EmployeePermissionPage> createState() => _EmployeePermissionPageState();
}

class _EmployeePermissionPageState extends State<EmployeePermissionPage> {
  List<dynamic> _history = [];
  bool _historyLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchHistory());
  }

  Future<void> _fetchHistory() async {
    final token = context.read<AuthService>().token;
    if (token == null) return;
    setState(() => _historyLoading = true);
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/attendance/permissions/mine'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 12));
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true && mounted) {
        setState(
          () => _history = List<dynamic>.from(body['data'] as List? ?? []),
        );
      }
    } catch (_) {}
    if (mounted) setState(() => _historyLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final logOnly = ModalRoute.of(context)?.settings.arguments == 'log';
    return EmployeeScaffold(
      route: '/employee/permission',
      title: 'Permission',
      subtitle: logOnly
          ? 'Review your permission history'
          : 'Request short personal permission and review your history',
      desktopHeaderAction: logOnly
          ? null
          : GestureDetector(
              onTap: () => _showPermissionHistoryDialog(
                context,
                _history,
                _historyLoading,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F5FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFD0E1FF)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 13,
                      color: Color(0xFF0B72F5),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'View History',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF0B72F5),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      desktop: _PermissionContent(
        logOnly: logOnly,
        history: _history,
        historyLoading: _historyLoading,
        onSubmitted: _fetchHistory,
      ),
      mobile: _PermissionContent(
        mobile: true,
        logOnly: logOnly,
        history: _history,
        historyLoading: _historyLoading,
        onSubmitted: _fetchHistory,
      ),
    );
  }
}

void _showPermissionHistoryDialog(
  BuildContext context,
  List<dynamic> history,
  bool loading,
) {
  String fmtDate(String? v) {
    final dt = DateTime.tryParse(v ?? '');
    return dt == null ? (v ?? '--') : DateFormat('dd/MM/yyyy').format(dt);
  }

  String fmtTime(String? start, String? end) {
    String fmt(String? v) {
      if (v == null || v.isEmpty) return '';
      final parts = v.split(':');
      if (parts.length < 2) return v;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) return v;
      final now = DateTime.now();
      final dt = DateTime(now.year, now.month, now.day, h, m);
      return DateFormat('hh:mm a').format(dt);
    }

    final from = fmt(start);
    final to = fmt(end);
    return from.isEmpty || to.isEmpty ? 'Time not recorded' : '$from – $to';
  }

  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 540),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    color: employeePurple,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Permission History',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF4F6FB),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Past and pending permission requests',
                style: TextStyle(fontSize: 12, color: employeeMuted),
              ),
              const SizedBox(height: 16),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No permission requests recorded.',
                      style: TextStyle(color: employeeMuted),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: history.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = history[i];
                      final status = r['status']?.toString() ?? 'Pending';
                      final normalizedStatus = status.toUpperCase();
                      final color = normalizedStatus == 'APPROVED'
                          ? employeeGreen
                          : (normalizedStatus == 'REJECTED'
                                ? const Color(0xFFF12B46)
                                : employeeOrange);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.shield_outlined,
                              color: employeePurple,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fmtDate(r['date']?.toString()),
                                    style: const TextStyle(
                                      color: employeeNavy,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '${r['reason'] ?? ''} · ${fmtTime(r['start_time']?.toString(), r['end_time']?.toString())}',
                                    style: const TextStyle(
                                      color: employeeMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PermissionContent extends StatefulWidget {
  const _PermissionContent({
    this.mobile = false,
    this.logOnly = false,
    this.history = const [],
    this.historyLoading = false,
    this.onSubmitted,
  });
  final bool mobile;
  final bool logOnly;
  final List<dynamic> history;
  final bool historyLoading;
  final VoidCallback? onSubmitted;

  @override
  State<_PermissionContent> createState() => _PermissionContentState();
}

class _PermissionContentState extends State<_PermissionContent> {
  final _reasonCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _endDateCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  DateTime _selectedEndDate = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 14, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 16, minute: 0);

  // 'permission' = short time-off, 'wfh' = work from home all day
  String _requestType = 'permission';

  bool _submitting = false;
  bool _homeLoading = false;
  bool _hasApprovedHome = false;
  Position? _capturedHomePosition;
  bool _capturingHome = false;
  bool _isIosWeb = false;
  bool _iosRequesting = false;

  Widget _buildMobileRequest(BuildContext context) {
    InputDecoration input(String hint, IconData icon) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: employeeMuted, fontSize: 16),
      prefixIcon: Icon(icon, color: const Color(0xFF657493), size: 24),
      filled: true,
      fillColor: const Color(0xFFFCFDFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFE0E7F2), width: 1.4),
        borderRadius: BorderRadius.circular(16),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: employeeBlue, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MobileEmployeeHeader(showGreeting: true),
        const SizedBox(height: 12),
        const Text(
          'Permission',
          style: TextStyle(
            color: employeeNavy,
            fontSize: 36,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 32),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6B27EC), Color(0xFF0875EF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0x26FFFFFF),
                  border: Border.all(color: const Color(0x55FFFFFF)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  color: Colors.white,
                  size: 42,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Permission\nRequest',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Select your time away\nand send it for approval.',
                      style: TextStyle(
                        color: Color(0xD9FFFFFF),
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x22FFFFFF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'MANAGER APPROVAL',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        EmployeeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Request type toggle
              Row(
                children: [
                  Expanded(
                    child: _TypeToggleButton(
                      label: 'Permission',
                      icon: Icons.verified_user_outlined,
                      selected: _requestType == 'permission',
                      onTap: () => setState(() => _requestType = 'permission'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TypeToggleButton(
                      label: 'Work From Home',
                      icon: Icons.home_work_outlined,
                      selected: _requestType == 'wfh',
                      onTap: () => setState(() => _requestType = 'wfh'),
                    ),
                  ),
                ],
              ),
              if (_isIosWeb) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: _TypeToggleButton(
                    label: 'iPhone Request Permission',
                    icon: Icons.phone_iphone_rounded,
                    selected: false,
                    onTap: _showIosRequestDialog,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Text(
                _requestType == 'wfh' ? 'WFH Date Range' : 'Permission Date',
                style: const TextStyle(
                  color: employeeNavy,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _dateCtrl,
                readOnly: true,
                onTap: _pickDate,
                style: const TextStyle(
                  color: employeeNavy,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                decoration: input('Select date', Icons.calendar_today_outlined),
              ),
              if (_requestType == 'wfh') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _endDateCtrl,
                  readOnly: true,
                  onTap: _pickEndDate,
                  style: const TextStyle(
                    color: employeeNavy,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: input('End date', Icons.event_available_outlined),
                ),
                _wfhHomeCapture(),
              ],
              if (_requestType == 'permission') ...[
                const SizedBox(height: 22),
                const Text(
                  'Time Away',
                  style: TextStyle(
                    color: employeeNavy,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _timeCtrl,
                  readOnly: true,
                  onTap: _pickTimeRange,
                  style: const TextStyle(
                    color: employeeNavy,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: input('Select time', Icons.schedule_outlined),
                ),
              ],
              const SizedBox(height: 22),
              const Text(
                'Reason',
                style: TextStyle(
                  color: employeeNavy,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _reasonCtrl,
                minLines: 4,
                maxLines: 4,
                style: const TextStyle(color: employeeNavy, fontSize: 16),
                decoration: input(
                  _requestType == 'wfh'
                      ? 'Why do you need to work from home?'
                      : 'Briefly describe the reason…',
                  Icons.edit_outlined,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_outlined, size: 27),
                  label: Text(_submitting ? 'Submitting…' : 'Submit Request'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: employeeBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    textStyle: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _dateCtrl.text = DateFormat('dd/MM/yyyy').format(_selectedDate);
    _endDateCtrl.text = DateFormat('dd/MM/yyyy').format(_selectedEndDate);
    _updateTimeText();
    _loadHomeStatus();
    _loadIosWebAccess();
  }

  Future<void> _loadIosWebAccess() async {
    final available = await AttendanceClientIdentity.isIosWeb;
    if (mounted) setState(() => _isIosWeb = available);
  }

  Future<void> _requestIosWebAccess() async {
    final token = context.read<AuthService>().token;
    if (token == null) return;
    setState(() => _iosRequesting = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/attendance/ios-web-devices/register'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          ...await AttendanceClientIdentity.headers(),
        },
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body);
      final message = body is Map
          ? body['message']?.toString() ?? 'Unable to send iPhone request.'
          : 'Unable to send iPhone request.';
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to send iPhone request. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _iosRequesting = false);
    }
  }

  void _showIosRequestDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('iPhone Request Permission'),
        content: const Text('Send a request to use Check In / Check Out from this iPhone Safari browser.'),
        actions: [
          TextButton(onPressed: _iosRequesting ? null : () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: _iosRequesting ? null : _requestIosWebAccess,
            child: Text(_iosRequesting ? 'Sending…' : 'Send Request'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _dateCtrl.dispose();
    _endDateCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  void _updateTimeText() {
    final startStr = _formatTimeOfDay(_startTime);
    final endStr = _formatTimeOfDay(_endTime);
    _timeCtrl.text = '$startStr – $endStr';
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    return DateFormat('hh:mm a').format(dt);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025),
      lastDate: DateTime(2028),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        if (_selectedEndDate.isBefore(picked)) _selectedEndDate = picked;
        _dateCtrl.text = DateFormat('dd/MM/yyyy').format(picked);
        _endDateCtrl.text = DateFormat('dd/MM/yyyy').format(_selectedEndDate);
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedEndDate.isBefore(_selectedDate)
          ? _selectedDate
          : _selectedEndDate,
      firstDate: _selectedDate,
      lastDate: DateTime(2028),
    );
    if (picked != null)
      setState(() {
        _selectedEndDate = picked;
        _endDateCtrl.text = DateFormat('dd/MM/yyyy').format(picked);
      });
  }

  Future<void> _loadHomeStatus() async {
    setState(() => _homeLoading = true);
    try {
      final home = await HrmsTrackingApi.myHomeLocation();
      if (mounted)
        setState(
          () => _hasApprovedHome = home?['approval_status'] == 'approved',
        );
    } catch (_) {}
    if (mounted) setState(() => _homeLoading = false);
  }

  Future<void> _captureHome() async {
    setState(() => _capturingHome = true);
    try {
      final position = await AttendanceLocation.currentPosition();
      if (mounted) setState(() => _capturedHomePosition = position);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
    if (mounted) setState(() => _capturingHome = false);
  }

  Widget _wfhHomeCapture() {
    if (_hasApprovedHome) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(
          'Your approved Home Location will be used for this request.',
          style: TextStyle(color: employeeGreen, fontWeight: FontWeight.w600),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Home Location is required for WFH approval. Capture it below; this request will be sent to Admin once.',
            style: TextStyle(color: employeeMuted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _capturingHome || _homeLoading ? null : _captureHome,
            icon: const Icon(Icons.my_location_outlined),
            label: Text(
              _capturingHome ? 'Capturing Home GPS…' : 'Capture Home GPS',
            ),
          ),
          if (_capturedHomePosition != null)
            Text(
              'Captured GPS: ${_capturedHomePosition!.latitude.toStringAsFixed(6)}, ${_capturedHomePosition!.longitude.toStringAsFixed(6)} · accuracy ${_capturedHomePosition!.accuracy.toStringAsFixed(0)} m',
              style: const TextStyle(color: employeeGreen, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Future<void> _pickTimeRange() async {
    final pickedStart = await showTimePicker(
      context: context,
      initialTime: _startTime,
      helpText: 'SELECT START TIME',
    );
    if (pickedStart == null || !mounted) return;

    final pickedEnd = await showTimePicker(
      context: context,
      initialTime: _endTime,
      helpText: 'SELECT END TIME',
    );
    if (pickedEnd == null || !mounted) return;

    setState(() {
      _startTime = pickedStart;
      _endTime = pickedEnd;
      _updateTimeText();
    });
  }

  Future<void> _submit() async {
    final token = context.read<AuthService>().token;
    if (token == null) return;

    if (_reasonCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a reason for your permission.'),
        ),
      );
      return;
    }
    if (_requestType == 'wfh' &&
        !_hasApprovedHome &&
        _capturedHomePosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Capture your Home GPS before submitting a WFH request.',
          ),
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    if (_requestType == 'permission' &&
        _startTime.hour == _endTime.hour &&
        _startTime.minute == _endTime.minute) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose an end time later than the start time.'),
        ),
      );
      return;
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final Map<String, dynamic> payload = _requestType == 'wfh'
        ? {
            'type': 'wfh',
            'date': dateStr,
            'end_date': DateFormat('yyyy-MM-dd').format(_selectedEndDate),
            'reason': _reasonCtrl.text.trim(),
            if (_capturedHomePosition != null) ...{
              'latitude': _capturedHomePosition!.latitude,
              'longitude': _capturedHomePosition!.longitude,
              'accuracy': _capturedHomePosition!.accuracy,
              'capturedAt': _capturedHomePosition!.timestamp
                  .toUtc()
                  .toIso8601String(),
            },
          }
        : {
            'type': 'permission',
            'date': dateStr,
            'start_time':
                '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
            'end_time':
                '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
            'reason': _reasonCtrl.text.trim(),
          };

    var ok = false;
    try {
      final res = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/attendance/permissions'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));
      ok = res.statusCode == 200 && (jsonDecode(res.body)['success'] == true);
    } catch (_) {}

    if (mounted) {
      setState(() => _submitting = false);
      if (ok) {
        setState(() {
          _reasonCtrl.clear();
          _capturedHomePosition = null;
        });
        widget.onSubmitted?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _requestType == 'wfh'
                  ? 'WFH request submitted for one Admin approval.'
                  : 'Permission request submitted successfully!',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to submit permission request.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mobile && !widget.logOnly) return _buildMobileRequest(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.mobile) ...[
          const MobileEmployeeHeader(showGreeting: false),
          const SizedBox(height: 18),
          const Text(
            'Permission',
            style: TextStyle(
              color: employeeNavy,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (!widget.logOnly)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: EmployeeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6637E8), Color(0xFF3558D8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x333558D8),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0x33FFFFFF),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0x55FFFFFF),
                              ),
                            ),
                            child: const Icon(
                              Icons.verified_user_outlined,
                              color: Colors.white,
                              size: 27,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Permission request',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Select your time away and send it for approval.',
                                  style: TextStyle(
                                    color: Color(0xD1FFFFFF),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x2AFFFFFF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'MANAGER APPROVAL',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    // Request type toggle
                    Row(
                      children: [
                        Expanded(
                          child: _TypeToggleButton(
                            label: 'Permission',
                            icon: Icons.verified_user_outlined,
                            selected: _requestType == 'permission',
                            onTap: () =>
                                setState(() => _requestType = 'permission'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TypeToggleButton(
                            label: 'Work From Home',
                            icon: Icons.home_work_outlined,
                            selected: _requestType == 'wfh',
                            onTap: () => setState(() => _requestType = 'wfh'),
                          ),
                        ),
                      ],
                    ),
                    if (_isIosWeb) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: _TypeToggleButton(
                          label: 'iPhone Request Permission',
                          icon: Icons.phone_iphone_rounded,
                          selected: false,
                          onTap: _showIosRequestDialog,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final dateField = InkWell(
                          onTap: _pickDate,
                          child: IgnorePointer(
                            child: TextField(
                              controller: _dateCtrl,
                              decoration: InputDecoration(
                                labelText: _requestType == 'wfh'
                                    ? 'WFH date'
                                    : 'Permission date',
                                prefixIcon: const Icon(
                                  Icons.calendar_today_outlined,
                                ),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                        );
                        if (_requestType == 'wfh') {
                          final endDateField = InkWell(
                            onTap: _pickEndDate,
                            child: IgnorePointer(
                              child: TextField(
                                controller: _endDateCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'WFH end date',
                                  prefixIcon: Icon(
                                    Icons.event_available_outlined,
                                  ),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          );
                          if (constraints.maxWidth < 620)
                            return Column(
                              children: [
                                dateField,
                                const SizedBox(height: 14),
                                endDateField,
                              ],
                            );
                          return Row(
                            children: [
                              Expanded(child: dateField),
                              const SizedBox(width: 14),
                              Expanded(child: endDateField),
                            ],
                          );
                        }
                        final timeField = InkWell(
                          onTap: _pickTimeRange,
                          child: IgnorePointer(
                            child: TextField(
                              controller: _timeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Time away',
                                prefixIcon: Icon(Icons.schedule_outlined),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        );
                        if (constraints.maxWidth < 620) {
                          return Column(
                            children: [
                              dateField,
                              const SizedBox(height: 14),
                              timeField,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: dateField),
                            const SizedBox(width: 14),
                            Expanded(child: timeField),
                          ],
                        );
                      },
                    ),
                    if (_requestType == 'wfh') _wfhHomeCapture(),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _reasonCtrl,
                      minLines: 3,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Reason',
                        hintText: _requestType == 'wfh'
                            ? 'Why do you need to work from home?'
                            : 'Briefly describe your request...',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_outlined, size: 16),
                        label: Text(
                          _submitting ? 'Submitting…' : 'Submit Request',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0B72F5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (widget.logOnly) ...[
          const SizedBox(height: 18),
          EmployeeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(
                  'Permission Log',
                  subtitle: 'Past and pending permission requests',
                ),
                const SizedBox(height: 12),
                if (widget.historyLoading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (widget.history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No permission requests recorded.',
                        style: TextStyle(color: employeeMuted),
                      ),
                    ),
                  )
                else
                  ...widget.history.map((r) {
                    final status = r['status']?.toString() ?? 'Pending';
                    final normalizedStatus = status.toUpperCase();
                    final color = normalizedStatus == 'APPROVED'
                        ? employeeGreen
                        : (normalizedStatus == 'REJECTED'
                              ? const Color(0xFFF12B46)
                              : employeeOrange);
                    final type = r['type']?.toString() ?? '';
                    final isWfh = type == 'wfh';
                    final timeLabel = isWfh
                        ? 'Work From Home'
                        : _formatStoredTime(
                            r['start_time']?.toString(),
                            r['end_time']?.toString(),
                          );
                    return _row(
                      _formatHistoryDateRange(
                        r['date']?.toString() ?? '',
                        r['end_date']?.toString(),
                      ),
                      r['reason']?.toString() ?? '',
                      timeLabel,
                      status,
                      color,
                      isWfh: isWfh,
                    );
                  }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _formatHistoryDate(String value) {
    final date = DateTime.tryParse(value);
    return date == null ? value : DateFormat('dd/MM/yyyy').format(date);
  }

  String _formatHistoryDateRange(String start, String? end) {
    final first = _formatHistoryDate(start);
    final last = end == null || end.isEmpty ? first : _formatHistoryDate(end);
    return first == last ? first : '$first – $last';
  }

  String _formatStoredTime(String? start, String? end) {
    String format(String? value) {
      if (value == null || value.isEmpty) return '';
      final parts = value.split(':');
      if (parts.length < 2) return value;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) return value;
      return _formatTimeOfDay(TimeOfDay(hour: hour, minute: minute));
    }

    final from = format(start);
    final to = format(end);
    return from.isEmpty || to.isEmpty ? 'Time not recorded' : '$from – $to';
  }

  Widget _typeToggle() => Row(
    children: [
      Expanded(
        child: _TypeToggleButton(
          label: 'Permission',
          icon: Icons.verified_user_outlined,
          selected: _requestType == 'permission',
          onTap: () => setState(() => _requestType = 'permission'),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _TypeToggleButton(
          label: 'Work From Home',
          icon: Icons.home_work_outlined,
          selected: _requestType == 'wfh',
          onTap: () => setState(() => _requestType = 'wfh'),
        ),
      ),
    ],
  );

  Widget _row(
    String date,
    String reason,
    String time,
    String status,
    Color color, {
    bool isWfh = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Icon(
          isWfh ? Icons.home_work_outlined : Icons.shield_outlined,
          color: employeePurple,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    date,
                    style: const TextStyle(
                      color: employeeNavy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (isWfh) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F4FF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'WFH',
                        style: TextStyle(
                          color: Color(0xFF0767F2),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                '$reason · $time',
                style: const TextStyle(color: employeeMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        StatusPill(status, color),
      ],
    ),
  );
}

class _TypeToggleButton extends StatelessWidget {
  const _TypeToggleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: selected ? employeeBlue : const Color(0xFFF4F6FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? employeeBlue : const Color(0xFFDDE3EF),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: selected ? Colors.white : employeeMuted),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : employeeNavy,
            ),
          ),
        ],
      ),
    ),
  );
}
