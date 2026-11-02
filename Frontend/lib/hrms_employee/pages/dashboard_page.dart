// ignore_for_file: use_build_context_synchronously
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:godigital_portal/services/authenticated_http.dart' as http;
import 'package:provider/provider.dart';

import '../attendance/attendance_dashboard_section.dart';
import '../shared/employee_ui.dart';
import '../../services/api_config.dart';
import '../../services/auth_service.dart';
import '../../services/auth_storage.dart';
import '../../services/hrms_payslip_api.dart';
import '../../services/calendar_notifications_api.dart';

class EmployeeDashboardPage extends StatefulWidget {
  const EmployeeDashboardPage({super.key});
  @override
  State<EmployeeDashboardPage> createState() => _EmployeeDashboardPageState();
}

class _EmployeeDashboardPageState extends State<EmployeeDashboardPage> {
  bool menuOpen = false;
  static const routes = <String>{
    '/employee/dashboard',
    '/employee/attendance',
    '/employee/clock-log',
    '/employee/leave',
    '/employee/permission',
    '/employee/extra-hours',
    '/employee/salary',
    '/employee/tracking',
  };
  void go(String route) {
    setState(() => menuOpen = false);
    if (routes.contains(route)) {
      Navigator.pushNamed(context, route);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This page is not available yet.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      bottomNavigationBar: mobile
          ? const EmployeeMobileBottomNav(route: '/employee/dashboard')
          : null,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _Header(
                  mobile: mobile,
                  open: menuOpen,
                  onMenu: () => setState(() => menuOpen = !menuOpen),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      mobile ? 18 : 36,
                      mobile ? 24 : 34,
                      mobile ? 18 : 36,
                      mobile ? 110 : 40,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: const _Content(),
                    ),
                  ),
                ),
              ],
            ),
            if (menuOpen)
              _Menu(
                onClose: () => setState(() => menuOpen = false),
                onSelect: go,
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatefulWidget {
  const _Header({
    required this.mobile,
    required this.open,
    required this.onMenu,
  });
  final bool mobile, open;
  final VoidCallback onMenu;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  String _fullName = 'Employee';
  String _staffId = '';
  String _initials = 'E';
  int _calendarUnread = 0;
  List<Map<String, String>> _calendarNotifications = const [];

  @override
  void initState() {
    super.initState();
    _loadStoredIdentity();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfile();
      _loadEmployee();
      _loadCalendarNotifications();
    });
  }

  Future<void> _loadCalendarNotifications() async {
    try {
      final data = await CalendarNotificationsApi.mine();
      final rawItems = (data['items'] as List? ?? const []).whereType<Map>().toList();
      final items = rawItems.map((item) {
        final map = Map<String, dynamic>.from(item);
        return <String, String>{
          'id': map['id'].toString(),
          'title': map['title']?.toString() ?? 'Calendar update',
          'message': map['message']?.toString() ?? '',
          'isRead': map['isRead']?.toString() ?? '0',
        };
      }).toList();
      if (mounted) {
        setState(() {
          _calendarUnread = (data['unreadCount'] as num?)?.toInt() ?? 0;
          _calendarNotifications = items;
        });
        // Show popup for unread holiday notifications (one-time per notification)
        final unreadHolidays = items.where((n) =>
          n['isRead'] == '0' &&
          (n['title']?.toLowerCase().contains('holiday') == true ||
           n['message']?.toLowerCase().contains('holiday') == true)).toList();
        if (unreadHolidays.isNotEmpty) {
          await _showHolidayPopup(unreadHolidays);
        }
      }
    } catch (_) {}
  }

  Future<void> _showHolidayPopup(List<Map<String, String>> holidays) async {
    if (!mounted) return;
    // Play notification sound
    try {
      final player = AudioPlayer();
      await player.play(AssetSource('sounds/notification.mp3'));
    } catch (_) {}
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _HolidayAnnouncementDialog(
        holidays: holidays,
        onDone: () async {
          // Mark all shown holidays as read
          for (final h in holidays) {
            final id = int.tryParse(h['id'] ?? '');
            if (id != null) {
              try { await CalendarNotificationsApi.markRead(id); } catch (_) {}
            }
          }
          if (mounted) setState(() => _calendarUnread = 0);
        },
      ),
    );
  }

  void _setIdentity(String? name, String? staffId) {
    final resolved = (name ?? '').trim();
    if (resolved.isEmpty) return;
    final words = resolved.split(RegExp(r'\s+'));
    setState(() {
      _fullName = resolved;
      _staffId = (staffId ?? '').trim();
      _initials = words
          .take(2)
          .where((word) => word.isNotEmpty)
          .map((word) => word[0].toUpperCase())
          .join();
      if (_initials.isEmpty) _initials = 'E';
    });
  }

  Future<void> _loadStoredIdentity() async {
    try {
      final raw = await AuthStorage.getString('user_data');
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw);
      if (data is Map && mounted) {
        _setIdentity(
          data['fullName']?.toString() ??
              data['full_name']?.toString() ??
              data['name']?.toString(),
          data['staffId']?.toString() ??
              data['staff_id']?.toString() ??
              data['employee_id']?.toString(),
        );
      }
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    final token =
        context.read<AuthService>().token ??
        await AuthStorage.getString('auth_token');
    if (token == null || token.isEmpty) return;
    try {
      final response = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/auth/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 5));
      final body = jsonDecode(response.body);
      if (response.statusCode != 200 ||
          body is! Map ||
          body['success'] != true ||
          body['data'] is! Map ||
          !mounted) {
        return;
      }
      final profile = Map<String, dynamic>.from(body['data'] as Map);
      _setIdentity(
        profile['fullName']?.toString() ?? profile['full_name']?.toString(),
        profile['staffId']?.toString() ?? profile['staff_id']?.toString(),
      );
    } catch (_) {}
  }

  Future<void> _loadEmployee() async {
    final auth = context.read<AuthService>();
    final token = auth.token ?? await AuthStorage.getString('auth_token');
    if (token == null || token.isEmpty) return;

    try {
      final response = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/attendance/header-status'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return;
      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true || body['data'] is! Map) {
        return;
      }

      final data = Map<String, dynamic>.from(body['data'] as Map);
      final name = (data['full_name']?.toString() ?? '').trim();
      final staffId = (data['staff_id']?.toString() ?? '').trim();
      if (!mounted || name.isEmpty) return;

      _setIdentity(name, staffId);
    } catch (_) {
      // Keep the neutral placeholder if the profile endpoint is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    height: widget.mobile ? 78 : 88,
    padding: EdgeInsets.symmetric(horizontal: widget.mobile ? 18 : 36),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE7EDF7))),
      boxShadow: [
        BoxShadow(
          color: Color(0x0D102C5A),
          blurRadius: 14,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        Image.asset(
          'assets/images/godigital_logo.png',
          height: widget.mobile ? 45 : 53,
          width: widget.mobile ? 136 : 164,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
        ),
        if (!widget.mobile) ...[
          const SizedBox(width: 24),
          const Expanded(child: Center(child: _DashboardTopNav())),
        ] else
          const Spacer(),
        if (!widget.mobile) ...[
          const Text('Employee Portal', style: TextStyle(color: employeeMuted)),
          const SizedBox(width: 24),
        ],
        EmployeeNotificationButton(
          unreadCount: _calendarUnread,
          notifications: _calendarNotifications,
          onOpened: () async {
            for (final notification in _calendarNotifications) {
              final id = int.tryParse(notification['id'] ?? '');
              if (id != null) {
                try {
                  await CalendarNotificationsApi.markRead(id);
                } catch (_) {}
              }
            }
            if (mounted) setState(() => _calendarUnread = 0);
          },
        ),
        const SizedBox(width: 18),
        EmployeeProfileMenu(
          radius: 25,
          initials: _initials,
          fullName: _fullName,
          staffId: _staffId,
        ),
      ],
    ),
  );
}

class _DashboardTopNav extends StatelessWidget {
  const _DashboardTopNav();

  static const _items = <(String, String)>[
    ('Dashboard', '/employee/dashboard'),
    ('Attendance', '/employee/attendance'),
    ('Check In / Out', '/employee/clock-log'),
    ('Leave', '/employee/leave'),
    ('Permission', '/employee/permission'),
    ('Extra Hours', '/employee/extra-hours'),
    ('Salary', '/employee/salary'),
    ('Tracking', '/employee/tracking'),
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFE7ECF4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _items.map((item) {
          final active = item.$2 == '/employee/dashboard';
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: active ? employeeBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(26),
              child: InkWell(
                borderRadius: BorderRadius.circular(26),
                onTap: active
                    ? null
                    : () => Navigator.pushNamed(context, item.$2),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Text(
                    item.$1,
                    style: TextStyle(
                      color: active ? Colors.white : employeeMuted,
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ),
  );
}

class _Content extends StatelessWidget {
  const _Content();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const AttendanceDashboardSection(),
      const SizedBox(height: 18),
      const _Actions(
        'ATTENDANCE',
        employeeBlue,
        Icons.calendar_month_outlined,
        [
          ('Calendar', Icons.calendar_today_outlined, '/employee/attendance'),
          ('Clock Log', Icons.history_rounded, '/employee/clock-log'),
        ],
      ),
      const SizedBox(height: 12),
      const _Actions('LEAVE', Color(0xFF6C36E8), Icons.eco_outlined, [
        ('Apply Leave', Icons.note_add_outlined, '/employee/leave'),
        ('My Requests', Icons.assignment_outlined, '/employee/leave'),
      ]),
      const SizedBox(height: 12),
      const _Actions(
        'PERMISSION',
        Color(0xFF5B35D5),
        Icons.verified_user_outlined,
        [
          (
            'Apply Permission',
            Icons.verified_user_outlined,
            '/employee/permission',
          ),
          ('View Log', Icons.history_rounded, '/employee/permission'),
        ],
      ),
      const SizedBox(height: 12),
      const _Actions('EXTRA HOURS', employeeOrange, Icons.more_time_rounded, [
        ('Log Hours', Icons.more_time_rounded, '/employee/extra-hours'),
        ('0h', Icons.timelapse_rounded, null),
      ]),
      const SizedBox(height: 12),
      const _DynamicSalaryAction(),
      const SizedBox(height: 12),
      const _Actions(
        'TRACKING',
        Color(0xFF079B9B),
        Icons.location_on_outlined,
        [
          ('Live Tracking', Icons.location_on_outlined, '/employee/tracking'),
          ('Route History', Icons.map_outlined, '/employee/tracking'),
        ],
      ),
    ],
  );
}

class _DynamicSalaryAction extends StatefulWidget {
  const _DynamicSalaryAction();
  @override
  State<_DynamicSalaryAction> createState() => _DynamicSalaryActionState();
}

class _DynamicSalaryActionState extends State<_DynamicSalaryAction> {
  late final Future<Map<String, dynamic>> _summary = HrmsPayslipApi.summary();

  String _money(dynamic value) {
    final amount = value is num ? value : num.tryParse('$value');
    if (amount == null) return 'Not Set';
    return '₹${amount.round().toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+$)'), (_) => ',')}';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _summary,
    builder: (_, snapshot) {
      final payroll = snapshot.data?['payroll'];
      final live = snapshot.data?['livePayroll'];
      final map = payroll is Map ? payroll : const <String, dynamic>{};
      final liveMap = live is Map ? live : const <String, dynamic>{};
      final updatedSalary = liveMap['netPay'] ?? map['net_pay'];
      return _Actions(
        'SALARY',
        const Color(0xFF07368D),
        Icons.currency_rupee_rounded,
        [
          ('Updated Salary ${_money(updatedSalary)}', Icons.currency_rupee_rounded, null),
          ('Earned to Date ${_money(liveMap['earnedToDate'] ?? map['earned_to_date'])}', Icons.currency_rupee_rounded, null),
          ('View Payslip', Icons.description_outlined, '/employee/salary'),
        ],
      );
    },
  );
}

class _Actions extends StatelessWidget {
  const _Actions(this.title, this.color, this.icon, this.actions);
  final String title;
  final Color color;
  final IconData icon;
  final List<(String, IconData, String?)> actions;
  @override
  Widget build(BuildContext context) => EmployeeCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 14),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _ActionTile(action: actions[i], color: color),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.color});
  final (String, IconData, String?) action;
  final Color color;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: action.$3 == null
        ? null
        : () => Navigator.pushNamed(
            context,
            action.$3!,
            arguments: switch (action.$1) {
              'Route History' => 'history',
              'View Log' => 'log',
              'My Requests' => 'requests',
              _ => null,
            },
          ),
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: employeeLine),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(action.$2, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              action.$1,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: employeeNavy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (action.$3 != null)
            const Icon(Icons.chevron_right_rounded, color: employeeNavy),
        ],
      ),
    ),
  );
}

class _Menu extends StatelessWidget {
  const _Menu({required this.onClose, required this.onSelect});
  final VoidCallback onClose;
  final ValueChanged<String> onSelect;
  static const items = [
    ('Dashboard', Icons.grid_view_rounded, '/employee/dashboard'),
    ('Attendance', Icons.calendar_month_outlined, '/employee/attendance'),
    ('Check In / Out', Icons.schedule_rounded, '/employee/clock-log'),
    ('Leave', Icons.description_outlined, '/employee/leave'),
    ('Permission', Icons.verified_user_outlined, '/employee/permission'),
    ('Extra Hours', Icons.more_time_rounded, '/employee/extra-hours'),
    ('Salary', Icons.currency_rupee_rounded, '/employee/salary'),
    ('Tracking', Icons.location_on_outlined, '/employee/tracking'),
  ];
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      GestureDetector(
        onTap: onClose,
        child: Container(color: const Color(0x4A07143F)),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.white,
          elevation: 24,
          child: SafeArea(
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width.clamp(280.0, 350.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 19, 12, 15),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Menu',
                            style: TextStyle(
                              color: employeeNavy,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: onClose,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: employeeNavy,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: employeeLine),
                  const SizedBox(height: 8),
                  ...items.map(
                    (item) => InkWell(
                      onTap: () => onSelect(item.$3),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 23,
                          vertical: 15,
                        ),
                        child: Row(
                          children: [
                            Icon(item.$2, color: employeeBlue, size: 22),
                            const SizedBox(width: 16),
                            Text(
                              item.$1,
                              style: const TextStyle(
                                color: employeeNavy,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _HolidayAnnouncementDialog extends StatelessWidget {
  const _HolidayAnnouncementDialog({
    required this.holidays,
    required this.onDone,
  });
  final List<Map<String, String>> holidays;
  final Future<void> Function() onDone;

  // Parse "2026-10-12 is marked Holiday. reason text" → (dateLabel, reason)
  static (String date, String reason) _parse(String message) {
    final dateMatch = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(message);
    String date = '';
    if (dateMatch != null) {
      try {
        final d = DateTime.parse(dateMatch.group(1)!);
        date = '${d.day} ${_month(d.month)} ${d.year}';
      } catch (_) {
        date = dateMatch.group(1)!;
      }
    }
    // Extract reason after the period
    final dotIdx = message.indexOf('.');
    final reason = dotIdx >= 0 && dotIdx < message.length - 1
        ? message.substring(dotIdx + 1).trim()
        : '';
    return (date, reason);
  }

  static String _month(int m) => const [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ][m - 1];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.celebration_outlined, color: Color(0xFFB45309), size: 30),
              ),
              const SizedBox(height: 14),
              const Text(
                'Holiday Announcement',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF061457)),
              ),
              const SizedBox(height: 5),
              Text(
                holidays.length == 1
                    ? 'You have a holiday this month'
                    : 'You have ${holidays.length} holidays this month',
                style: const TextStyle(color: Color(0xFF63718F), fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Holiday status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0C2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFF5C842)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF92610A),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text('Holiday',
                      style: TextStyle(
                        color: Color(0xFF92610A),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Holiday cards
              ...holidays.map((h) {
                final msg = h['message'] ?? '';
                final (date, reason) = _parse(msg);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFD8E1F1)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      // Card header: title + date chip
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                h['title'] ?? 'Holiday',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: Color(0xFF061457),
                                ),
                              ),
                            ),
                            if (date.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF3FF),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFC3D4FD)),
                                ),
                                child: Text(
                                  date,
                                  style: const TextStyle(
                                    color: Color(0xFF075EF7),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Highlighted reason row
                      if (reason.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEEF3FF),
                            border: Border(
                              top: BorderSide(
                                color: Color(0xFFC3D4FD),
                                width: 1.5,
                                style: BorderStyle.solid,
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'REASON',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF075EF7),
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  reason,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF1E3A8A),
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await onDone();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF075EF7),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  child: const Text('Got it!',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
