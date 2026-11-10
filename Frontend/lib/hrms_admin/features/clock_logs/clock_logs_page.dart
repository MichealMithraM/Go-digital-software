import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/widgets/admin_top_nav.dart';
import '../../shared/widgets/admin_page_scroll_view.dart';
import '../../../services/hrms_clock_logs_api.dart';
import 'employee_clock_calendar_drawer.dart';
import '../employees/employee_profile_page.dart';

const _blue = Color(0xFF1264F5);
const _navy = Color(0xFF081C67);
const _page = Color(0xFFF7F9FD);
const _line = Color(0xFFD8E1F0);

String _attendanceMethodLabel(dynamic value) {
  switch ('${value ?? ''}'.trim().toLowerCase()) {
    case 'ios_mobile':
      return 'iOS Mobile';
    case 'manual':
      return 'Manual';
    case 'android_mobile':
    case 'mobile': // Historical Android APK records.
    case 'wifi': // Historical mobile records saved through office Wi-Fi.
      return 'Android Mobile';
    default:
      return 'Manual';
  }
}

class ClockLogsPage extends StatefulWidget {
  const ClockLogsPage({super.key});
  static Widget builder(BuildContext context) => const ClockLogsPage();
  @override
  State<ClockLogsPage> createState() => _ClockLogsPageState();
}

class _MobileClockLogs extends StatelessWidget {
  const _MobileClockLogs({
    required this.searchController,
    required this.logs,
    required this.date,
    required this.monthly,
    required this.loading,
    required this.error,
    required this.onSearch,
    required this.onPeriodChanged,
    required this.onPickDate,
    required this.onRetry,
    required this.onEdit,
    required this.onOpenCalendar,
  });

  final TextEditingController searchController;
  final List<Map<String, dynamic>> logs;
  final DateTime date;
  final bool monthly, loading;
  final String? error;
  final VoidCallback onSearch, onPickDate, onRetry;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final VoidCallback onOpenCalendar;
  final ValueChanged<bool> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final present = logs
        .where((item) => _lower(item['status']) == 'present')
        .length;
    final late = logs
        .where((item) => _lower(item['status']).contains('late'))
        .length;
    final absent = logs
        .where((item) => _lower(item['status']).contains('absent'))
        .length;
    return Scaffold(
      backgroundColor: _page,
      bottomNavigationBar: const AdminMobileBottomNav(
        activeRoute: '/admin/clock-logs',
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Image.asset('assets/images/godigital_logo.png', height: 38),
        actions: [
          const AdminNotificationBell(mobile: true),
          const SizedBox(width: 4),
          const SizedBox(width: 8),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : AdminPageScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Clock Logs',
                    style: TextStyle(
                      color: _navy,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Track employee attendance and working hours',
                    style: TextStyle(color: Color(0xFF52638E), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _MobileMetric(
                        label: 'Present',
                        value: '$present',
                        color: const Color(0xFF149B2B),
                        background: const Color(0xFFE8F6EA),
                      ),
                      const SizedBox(width: 8),
                      _MobileMetric(
                        label: 'Late',
                        value: '$late',
                        color: const Color(0xFFFF6A00),
                        background: const Color(0xFFFFF0E6),
                      ),
                      const SizedBox(width: 8),
                      _MobileMetric(
                        label: 'Absent',
                        value: '$absent',
                        color: const Color(0xFFF0182A),
                        background: const Color(0xFFFDEBED),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchController,
                    onChanged: (_) => onSearch(),
                    decoration: InputDecoration(
                      hintText: 'Search employee or ID',
                      hintStyle: const TextStyle(color: Color(0xFF50649E)),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: _navy,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 17),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _blue, width: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onOpenCalendar,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Employee attendance calendar'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MobilePeriodToggle(
                          monthly: monthly,
                          onChanged: onPeriodChanged,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onPickDate,
                          icon: const Icon(
                            Icons.calendar_month_outlined,
                            size: 20,
                          ),
                          label: Text(
                            monthly ? _monthLabel(date) : _dayLabel(date),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _navy,
                            side: const BorderSide(color: _line),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 15,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (logs.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(30),
                        child: Text('No clock logs found for this period.'),
                      ),
                    )
                  else if (searchController.text.trim().isEmpty)
                    _MobileDateHistory(logs: logs, onEdit: onEdit)
                  else
                    _MobileEmployeeHistory(logs: logs, onEdit: onEdit),
                ],
              ),
            ),
    );
  }

  static String _lower(dynamic value) => value?.toString().toLowerCase() ?? '';
  static String _monthLabel(DateTime value) =>
      '${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][value.month - 1]} ${value.year}';
  static String _dayLabel(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')} ${_monthLabel(value).split(' ').first} ${value.year}';
}

class _MobileMetric extends StatelessWidget {
  const _MobileMetric({
    required this.label,
    required this.value,
    required this.color,
    required this.background,
  });
  final String label, value;
  final Color color, background;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 70,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color.withValues(alpha: .22)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF50649E), fontSize: 11),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 25,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MobilePeriodToggle extends StatelessWidget {
  const _MobilePeriodToggle({required this.monthly, required this.onChanged});
  final bool monthly;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    height: 52,
    decoration: BoxDecoration(
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: Row(
      children: [
        _periodButton('Month', monthly, () => onChanged(true)),
        _periodButton('Day', !monthly, () => onChanged(false)),
      ],
    ),
  );
  Widget _periodButton(String label, bool active, VoidCallback onTap) =>
      Expanded(
        child: InkWell(
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            color: active ? _blue : Colors.white,
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : _navy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
}

class _MobileLogCard extends StatelessWidget {
  const _MobileLogCard({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final name = item['employeeName']?.toString() ?? 'Former employee';
    final id =
        item['staffId']?.toString() ??
        item['employeeId']?.toString() ??
        'Unassigned';
    final status = item['status']?.toString() ?? 'Absent';
    final lower = status.toLowerCase();
    final color = lower.contains('absent')
        ? const Color(0xFFF04438)
        : (lower.contains('late') || lower.replaceAll('_', ' ') == 'early exit')
        ? const Color(0xFFFF9200)
        : lower == 'no record'
        ? const Color(0xFF667085)
        : const Color(0xFF149B2B);
    final bg = lower.contains('absent')
        ? const Color(0xFFFFEBEB)
        : (lower.contains('late') || lower.replaceAll('_', ' ') == 'early exit')
        ? const Color(0xFFFFF1DB)
        : const Color(0xFFE9F6EC);
    final minutes = item['workingMinutes'] is int
        ? item['workingMinutes'] as int
        : int.tryParse('${item['workingMinutes']}') ?? 0;
    final worked =
        '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
    final breakMinutes = item['breakMinutes'] is int
        ? item['breakMinutes'] as int
        : int.tryParse('${item['breakMinutes']}') ?? 0;
    final breakTime =
        '${breakMinutes ~/ 60}h ${(breakMinutes % 60).toString().padLeft(2, '0')}m';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08071A72),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFEAF1FF),
                child: Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      id,
                      style: const TextStyle(
                        color: Color(0xFF52638E),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _title(status),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _LogTime(
                label: 'Check in',
                value: item['checkIn']?.toString() ?? '-',
              ),
              _divider(),
              _LogTime(
                label: 'Break Begins',
                value: item['breakStart']?.toString() ?? '-',
              ),
              _divider(),
              _LogTime(
                label: 'Break Ends',
                value: item['breakEnd']?.toString() ?? '-',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _LogTime(
                label: 'Check out',
                value: item['checkOut']?.toString() ?? '-',
              ),
              _divider(),
              _LogTime(label: 'Break time', value: breakTime),
              _divider(),
              _LogTime(label: 'Worked', value: worked),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${item['date']?.toString() ?? ''} · ${item['workMode']?.toString() ?? 'Not set'}',
              style: const TextStyle(color: Color(0xFF52638E), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 30, color: _line);
  static String _title(String value) => value
      .replaceAll('_', ' ')
      .split(' ')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

class _LogTime extends StatelessWidget {
  const _LogTime({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF52638E), fontSize: 10),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _navy,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MobileDateHistory extends StatelessWidget {
  const _MobileDateHistory({required this.logs, required this.onEdit});
  final List<Map<String, dynamic>> logs;
  final ValueChanged<Map<String, dynamic>> onEdit;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final log in logs) {
      final date = log['date']?.toString() ?? 'Unknown date';
      groups.putIfAbsent(date, () => []).add(log);
    }
    final entries = groups.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'All clock logs',
          style: TextStyle(
            color: _navy,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        ...entries.expand(
          (entry) => [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 7, top: 4),
              child: Text(
                _displayDate(entry.key),
                style: const TextStyle(
                  color: Color(0xFF52638E),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            ...entry.value.asMap().entries.map(
              (e) => _MobileDailyLogRow(
                item: e.value,
                index: e.key + 1,
                onEdit: onEdit,
              ),
            ),
            const SizedBox(height: 5),
          ],
        ),
      ],
    );
  }

  static String _displayDate(String raw) {
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
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
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }
}

class _MobileEmployeeHistory extends StatelessWidget {
  const _MobileEmployeeHistory({required this.logs, required this.onEdit});
  final List<Map<String, dynamic>> logs;
  final ValueChanged<Map<String, dynamic>> onEdit;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final log in logs) {
      final key =
          log['staffId']?.toString() ??
          log['employeeId']?.toString() ??
          log['employeeName']?.toString() ??
          'unknown';
      groups.putIfAbsent(key, () => []).add(log);
    }
    return Column(
      children: groups.values
          .map(
            (records) =>
                _MobileEmployeeHistoryCard(records: records, onEdit: onEdit),
          )
          .toList(),
    );
  }
}

class _MobileEmployeeHistoryCard extends StatelessWidget {
  const _MobileEmployeeHistoryCard({
    required this.records,
    required this.onEdit,
  });
  final List<Map<String, dynamic>> records;
  final ValueChanged<Map<String, dynamic>> onEdit;

  @override
  Widget build(BuildContext context) {
    final first = records.first;
    final name = first['employeeName']?.toString() ?? 'Former employee';
    final id =
        first['staffId']?.toString() ??
        first['employeeId']?.toString() ??
        'Unassigned';
    final present = records
        .where(
          (item) =>
              (item['status']?.toString().toLowerCase() ?? '') == 'present',
        )
        .length;
    final late = records
        .where(
          (item) =>
              (item['status']?.toString().toLowerCase() ?? '').contains('late'),
        )
        .length;
    final absent = records
        .where(
          (item) => (item['status']?.toString().toLowerCase() ?? '').contains(
            'absent',
          ),
        )
        .length;
    final sorted = [...records]
      ..sort(
        (a, b) => (b['date']?.toString() ?? '').compareTo(
          a['date']?.toString() ?? '',
        ),
      );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: const Color(0xFFEAF1FF),
                child: Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      id,
                      style: const TextStyle(
                        color: Color(0xFF52638E),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _HistoryCount(
                label: 'Present',
                value: present,
                color: const Color(0xFF149B2B),
              ),
              const SizedBox(width: 8),
              _HistoryCount(
                label: 'Late',
                value: late,
                color: const Color(0xFFFF6A00),
              ),
              const SizedBox(width: 8),
              _HistoryCount(
                label: 'Absent',
                value: absent,
                color: const Color(0xFFF0182A),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: _line),
          ),
          const Text(
            'Attendance history',
            style: TextStyle(
              color: _navy,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          ...sorted.map(
            (item) => _MobileHistoryRow(item: item, onEdit: onEdit),
          ),
        ],
      ),
    );
  }
}

class _HistoryCount extends StatelessWidget {
  const _HistoryCount({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF52638E), fontSize: 10),
          ),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MobileDailyLogRow extends StatelessWidget {
  const _MobileDailyLogRow({
    required this.item,
    required this.index,
    required this.onEdit,
  });
  final Map<String, dynamic> item;
  final int index;
  final ValueChanged<Map<String, dynamic>> onEdit;
  @override
  Widget build(BuildContext context) {
    final name = item['employeeName']?.toString() ?? 'Former employee';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFEAF1FF),
                child: Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      item['staffId']?.toString() ??
                          item['employeeId']?.toString() ??
                          '',
                      style: const TextStyle(
                        color: Color(0xFF52638E),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: item['status']?.toString() ?? 'Absent'),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => onEdit(item),
                icon: const Icon(
                  Icons.calendar_month_outlined,
                  color: _blue,
                  size: 22,
                ),
                tooltip: 'Open employee calendar',
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ClockValues(item: item),
        ],
      ),
    );
  }
}

class _MobileHistoryRow extends StatelessWidget {
  const _MobileHistoryRow({required this.item, required this.onEdit});
  final Map<String, dynamic> item;
  final ValueChanged<Map<String, dynamic>> onEdit;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _MobileDateHistory._displayDate(item['date']?.toString() ?? ''),
                style: const TextStyle(
                  color: _navy,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            _StatusBadge(status: item['status']?.toString() ?? 'Absent'),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => onEdit(item),
              icon: const Icon(
                Icons.calendar_month_outlined,
                color: _blue,
                size: 22,
              ),
              tooltip: 'Open employee calendar',
            ),
          ],
        ),
        const SizedBox(height: 9),
        _ClockValues(item: item),
      ],
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final lower = status.toLowerCase();
    final color = lower.contains('absent')
        ? const Color(0xFFF04438)
        : (lower.contains('late') || lower.replaceAll('_', ' ') == 'early exit')
        ? const Color(0xFFFF9200)
        : lower == 'no record'
        ? const Color(0xFF667085)
        : const Color(0xFF149B2B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        _MobileLogCard._title(status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ClockValues extends StatelessWidget {
  const _ClockValues({required this.item});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) {
    final minutes = item['workingMinutes'] is int
        ? item['workingMinutes'] as int
        : int.tryParse('${item['workingMinutes']}') ?? 0;
    final worked =
        '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
    return Row(
      children: [
        _LogTime(label: 'Check in', value: item['checkIn']?.toString() ?? '-'),
        Container(width: 1, height: 28, color: _line),
        _LogTime(
          label: 'Break Begins',
          value: item['breakStart']?.toString() ?? '-',
        ),
        Container(width: 1, height: 28, color: _line),
        _LogTime(
          label: 'Break Ends',
          value: item['breakEnd']?.toString() ?? '-',
        ),
        Container(width: 1, height: 28, color: _line),
        _LogTime(
          label: 'Check out',
          value: item['checkOut']?.toString() ?? '-',
        ),
        Container(width: 1, height: 28, color: _line),
        _LogTime(label: 'Worked', value: worked),
      ],
    );
  }
}

class _IosWebAccessDialog extends StatefulWidget {
  const _IosWebAccessDialog();

  @override
  State<_IosWebAccessDialog> createState() => _IosWebAccessDialogState();
}

class _IosWebAccessDialogState extends State<_IosWebAccessDialog> {
  late Future<List<Map<String, dynamic>>> _devices;

  @override
  void initState() {
    super.initState();
    _devices = HrmsClockLogsApi.iosWebDevices();
  }

  Future<void> _update(int id, String status) async {
    try {
      await HrmsClockLogsApi.updateIosWebDevice(id, status);
      if (mounted) {
        setState(() => _devices = HrmsClockLogsApi.iosWebDevices());
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('iPhone web attendance access'),
    content: SizedBox(
      width: 620,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _devices,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) return Text('${snapshot.error}');
          final devices = snapshot.data ?? const [];
          if (devices.isEmpty) return const Text('No iPhone web access requests yet.');
          return ListView.separated(
            shrinkWrap: true,
            itemCount: devices.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final device = devices[index];
              final id = (device['id'] as num?)?.toInt();
              final status = '${device['status'] ?? 'pending'}';
              return ListTile(
                leading: const Icon(Icons.phone_iphone_rounded, color: _blue),
                title: Text('${device['full_name'] ?? 'Employee'}'),
                subtitle: Text('Status: $status\nRequested: ${device['created_at'] ?? '--'}'),
                isThreeLine: true,
                trailing: id == null ? null : Wrap(
                  spacing: 4,
                  children: [
                    if (status != 'approved')
                      IconButton(
                        tooltip: 'Approve',
                        onPressed: () => _update(id, 'approved'),
                        icon: const Icon(Icons.check_circle_outline, color: Color(0xFF149B2B)),
                      ),
                    if (status != 'revoked')
                      IconButton(
                        tooltip: 'Revoke',
                        onPressed: () => _update(id, 'revoked'),
                        icon: const Icon(Icons.block_outlined, color: Color(0xFFF0182A)),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
  );
}

class _ClockLogsPageState extends State<ClockLogsPage> {
  final _employeeSearchController = TextEditingController();
  final _tableHeaderScrollCtrl = ScrollController();
  final _tableBodyScrollCtrl = ScrollController();
  DateTime _date = DateTime.now();
  // Open Clock Logs on today's attendance by default. Users can still select
  // Month from the existing period control when they need historical totals.
  bool _monthly = false;
  int? _employeeId;
  List<Map<String, dynamic>> _employees = const [];
  List<Map<String, dynamic>> _logs = const [];
  bool _loading = true;
  String? _error;
  String? _expandedLogKey;
  Timer? _refreshTimer;
  int _loadRequest = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _load(silent: true),
    );
    _tableBodyScrollCtrl.addListener(() {
      if (_tableHeaderScrollCtrl.hasClients &&
          (_tableHeaderScrollCtrl.offset - _tableBodyScrollCtrl.offset).abs() >
              0.5) {
        _tableHeaderScrollCtrl.jumpTo(_tableBodyScrollCtrl.offset);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _employeeSearchController.dispose();
    _tableHeaderScrollCtrl.dispose();
    _tableBodyScrollCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _visibleLogs {
    final query = _employeeSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return _logs;
    return _logs.where((item) {
      final name = item['employeeName']?.toString().toLowerCase() ?? '';
      final id =
          item['staffId']?.toString().toLowerCase() ??
          item['employeeId']?.toString().toLowerCase() ??
          '';
      return name.contains(query) || id.contains(query);
    }).toList();
  }

  Future<void> _load({bool silent = false}) async {
    final request = ++_loadRequest;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await HrmsClockLogsApi.list(
        date: _date,
        monthly: _monthly,
        employeeId: _employeeId,
      );
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _employees = (data['employees'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _logs = (data['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
        if (silent) _error = null;
      });
    } catch (error) {
      if (mounted && request == _loadRequest && !silent) {
        setState(() {
          _loading = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (chosen != null) {
      setState(() => _date = chosen);
      _load();
    }
  }

  void _movePeriod(int amount) {
    setState(() {
      _date = _monthly
          ? DateTime(_date.year, _date.month + amount, 1)
          : _date.add(Duration(days: amount));
    });
    _load();
  }

  void _openEmployeeCalendar(Map<String, dynamic> employee) {
    final id =
        (employee['employeeId'] as num?)?.toInt() ??
        (employee['id'] as num?)?.toInt();
    if (id == null) return;
    final name = employee['employeeName']?.toString() ?? 'Employee';
    final staffId = employee['staffId']?.toString() ?? '$id';
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close employee calendar',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, _) => Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: MediaQuery.sizeOf(dialogContext).width < 600
              ? MediaQuery.sizeOf(dialogContext).width
              : 530,
          height: MediaQuery.sizeOf(dialogContext).height,
          child: EmployeeClockCalendarDrawer(
            employeeId: id,
            employeeName: name,
            staffId: staffId,
            initialMonth: _date,
            onSaved: () => _load(silent: true),
          ),
        ),
      ),
      transitionBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    );
  }

  Future<void> _chooseEmployeeCalendar() async {
    if (_employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active employees are available.')),
      );
      return;
    }
    final query = _employeeSearchController.text.trim().toLowerCase();
    final matches = _employees.where((employee) {
      if (query.isEmpty) return true;
      return (employee['employeeName']?.toString().toLowerCase() ?? '')
              .contains(query) ||
          (employee['staffId']?.toString().toLowerCase() ?? '').contains(query);
    }).toList();
    final choices = matches.isEmpty ? _employees : matches;
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierColor: const Color(0x990D1D35),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.all(16),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE1EDFF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                color: _blue,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select employee',
                    style: TextStyle(
                      color: Color(0xFF0A203D),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Choose an employee to open their calendar.',
                    style: TextStyle(color: Color(0xFF596783), fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.close_rounded, color: Color(0xFF596783)),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 44),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 520,
          height: (choices.length * 77.0 + 16).clamp(
            0.0,
            MediaQuery.sizeOf(dialogContext).height * .45,
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border.symmetric(horizontal: BorderSide(color: _line)),
            ),
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: _line),
              itemCount: choices.length,
              itemBuilder: (context, index) {
                final person = choices[index];
                final mobile = MediaQuery.sizeOf(context).width < 600;
                final name = person['employeeName']?.toString() ?? 'Employee';
                final words = name
                    .trim()
                    .split(RegExp(r'\s+'))
                    .where((word) => RegExp(r'[a-zA-Z0-9]').hasMatch(word));
                final initials = words
                    .take(2)
                    .map((word) => word[0])
                    .join()
                    .toUpperCase();
                const colors = [
                  Color(0xFF0963FF),
                  Color(0xFF009572),
                  Color(0xFFBC500D),
                  Color(0xFF8542ED),
                  Color(0xFFCB2452),
                ];
                final color = colors[index % colors.length];
                return ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  hoverColor: const Color(0xFFEAF3FF),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: mobile ? 8 : 12,
                    vertical: 6,
                  ),
                  leading: Container(
                    width: 40,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      initials.isEmpty ? 'E' : initials,
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    name,
                    style: TextStyle(
                      color: const Color(0xFF101747),
                      fontSize: mobile ? 15 : 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'ID: ${person['staffId'] ?? person['employeeId'] ?? person['id'] ?? ''}',
                    style: TextStyle(
                      color: const Color(0xFF536280),
                      fontSize: 13,
                    ),
                  ),
                  trailing: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F8FF),
                      border: Border.all(color: const Color(0xFFBCD7FF)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.calendar_month_outlined,
                      color: _blue,
                      size: 24,
                    ),
                  ),
                  onTap: () => Navigator.pop(dialogContext, person),
                );
              },
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.all(12),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF53607C),
              side: const BorderSide(color: Color(0xFFB6C1D4)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected != null && mounted) _openEmployeeCalendar(selected);
  }

  Future<void> _manageIosWebAccess() async {
    await showDialog<void>(
      context: context,
      builder: (context) => const _IosWebAccessDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 600) {
      return _MobileClockLogs(
        searchController: _employeeSearchController,
        logs: _visibleLogs,
        date: _date,
        monthly: _monthly,
        loading: _loading,
        error: _error,
        onSearch: () => setState(() {}),
        onPeriodChanged: (monthly) {
          if (_monthly != monthly) {
            setState(() => _monthly = monthly);
            _load();
          }
        },
        onPickDate: _pickDate,
        onRetry: _load,
        onEdit: _openEmployeeCalendar,
        onOpenCalendar: _chooseEmployeeCalendar,
      );
    }
    final narrow = MediaQuery.sizeOf(context).width < 1150;
    return Scaffold(
      backgroundColor: _page,
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 600
          ? const AdminMobileBottomNav(activeRoute: '/admin/clock-logs')
          : null,
      body: Column(
        children: [
          const AdminTopNav(activeRoute: '/admin/clock-logs'),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = narrow ? 16.0 : 38.0;
                final contentWidth = (constraints.maxWidth - side * 2).clamp(
                  0.0,
                  1900.0,
                );
                final inset = (constraints.maxWidth - contentWidth) / 2;
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(inset, 18, inset, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _desktopHeader(),
                            const SizedBox(height: 20),
                            _filters(narrow),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                    if (!_loading && _error == null)
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _ClockLogsHeaderDelegate(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: inset),
                            child: Container(
                              color: Colors.white,
                              child: _tableHeader(
                                contentWidth < 1280 ? 1280 : contentWidth,
                              ),
                            ),
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(inset, 0, inset, 28),
                      sliver: SliverToBoxAdapter(
                        child: _loading
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(42),
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            : _error != null
                            ? _message(_error!, retry: _load)
                            : _table(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopHeader() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'ATTENDANCE  /  CLOCK LOGS',
        style: TextStyle(
          color: Color(0xFF64749A),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Employee Clock Logs',
                  style: TextStyle(
                    color: Color(0xFF071540),
                    fontSize: 29,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Review employee attendance and work sessions.',
                  style: TextStyle(color: Color(0xFF62739C), fontSize: 14),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _chooseEmployeeCalendar,
            icon: const Icon(Icons.calendar_month_outlined, size: 21),
            label: const Text('Employee calendar'),
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _manageIosWebAccess,
            icon: const Icon(Icons.phone_iphone_rounded, size: 20),
            label: const Text('iPhone web access'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      const Divider(height: 1, color: _line),
    ],
  );

  Widget _filters(bool narrow) {
    final search = TextField(
      controller: _employeeSearchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Search by name, employee ID or email',
        hintStyle: const TextStyle(color: Color(0xFF50649E), fontSize: 14),
        prefixIcon: const Icon(Icons.search_rounded, color: _navy),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: _blue),
        ),
      ),
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _toggle(),
        const SizedBox(width: 22),
        _periodArrow(Icons.chevron_left_rounded, () => _movePeriod(-1)),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: _pickDate,
          style: _fieldStyle(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_month_outlined, size: 21),
              const SizedBox(width: 14),
              Text(_monthly ? _monthLabel(_date) : _dayLabel(_date)),
              const SizedBox(width: 44),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 21),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _periodArrow(Icons.chevron_right_rounded, () => _movePeriod(1)),
      ],
    );
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: controls,
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: search),
        const SizedBox(width: 26),
        Container(width: 1, height: 42, color: _line),
        const SizedBox(width: 24),
        controls,
      ],
    );
  }

  Widget _periodArrow(IconData icon, VoidCallback onPressed) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: _navy,
      side: const BorderSide(color: _line),
      minimumSize: const Size(46, 46),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    ),
    child: Icon(icon, size: 25),
  );

  Widget _summary() {
    final logs = _visibleLogs;
    final present = logs
        .where((item) => item['status']?.toString().toLowerCase() == 'present')
        .length;
    final late = logs
        .where(
          (item) =>
              item['status']?.toString().toLowerCase().contains('late') == true,
        )
        .length;
    final absent = logs
        .where(
          (item) =>
              item['status']?.toString().toLowerCase().contains('absent') ==
              true,
        )
        .length;

    return LayoutBuilder(
      builder: (_, constraints) {
        final columns = 3;
        final spacing = constraints.maxWidth < 700 ? 8.0 : 16.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: 8,
          children: [
            SizedBox(
              width: width,
              child: _compactMetric(
                'Present',
                present,
                const Color(0xFF149B2B),
              ),
            ),
            SizedBox(
              width: width,
              child: _compactMetric('Late', late, const Color(0xFFFF6A00)),
            ),
            SizedBox(
              width: width,
              child: _compactMetric('Absent', absent, const Color(0xFFF0182A)),
            ),
          ],
        );
      },
    );
  }

  Widget _compactMetric(String label, int value, Color color) => Container(
    height: 80,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: color.withValues(alpha: .25)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF50649E), fontSize: 11),
        ),
        const Spacer(),
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 25,
          ),
        ),
      ],
    ),
  );

  Widget _metric(
    String label,
    int value,
    String subtitle,
    IconData icon,
    Color color, [
    Color background = const Color(0xFFEAF1FF),
  ]) => Container(
    height: 104,
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: color.withValues(alpha: 0.28)),
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A000000),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      children: [
        Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 29),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _navy, fontSize: 13),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$value',
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 27,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF50649E),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Spacer(),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 55,
            height: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _toggle() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _toggleButton('Day', !_monthly),
      const SizedBox(width: 28),
      _toggleButton('Month', _monthly),
    ],
  );

  Widget _toggleButton(String label, bool active) => InkWell(
    onTap: () {
      final monthly = label == 'Month';
      if (_monthly != monthly) {
        setState(() => _monthly = monthly);
        _load();
      }
    },
    child: Container(
      padding: const EdgeInsets.fromLTRB(7, 11, 7, 9),
      decoration: BoxDecoration(
        border: active
            ? const Border(bottom: BorderSide(color: _blue, width: 2.5))
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? const Color(0xFF071540) : const Color(0xFF66749A),
          fontSize: 14,
          fontWeight: active ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    ),
  );

  ButtonStyle _fieldStyle() => OutlinedButton.styleFrom(
    foregroundColor: const Color(0xFF273754),
    side: const BorderSide(color: _line),
    minimumSize: const Size(245, 46),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    textStyle: const TextStyle(fontSize: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );

  Widget _tableHeader(double tableWidth) => SingleChildScrollView(
    controller: _tableHeaderScrollCtrl,
    scrollDirection: Axis.horizontal,
    physics: const NeverScrollableScrollPhysics(),
    child: SizedBox(
      width: tableWidth,
      child: _row(const [
        'S.No',
        'Employee',
        'Date',
        'Check-in',
        'Check-out',
        'Break time',
        'Worked',
        'Status',
        'Work location',
        'Details',
        'Action',
      ], header: true),
    ),
  );

  Widget _table() => LayoutBuilder(
    builder: (_, constraints) {
      final tableWidth = constraints.maxWidth < 1280
          ? 1280.0
          : constraints.maxWidth;
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // The page owns vertical scrolling; the table only scrolls sideways.
            SingleChildScrollView(
              controller: _tableBodyScrollCtrl,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Column(
                  children: [
                    if (_visibleLogs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Text(
                          'No clock logs found for the selected period.',
                        ),
                      ),
                    ..._visibleLogs.asMap().entries.map(
                      (e) => _logEntry(e.value, e.key + 1, tableWidth),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  String _logKey(Map<String, dynamic> item, int index) =>
      '${item['attendanceId'] ?? item['id'] ?? item['employeeId'] ?? index}-${item['date'] ?? index}';

  Widget _logEntry(Map<String, dynamic> item, int index, double tableWidth) {
    final key = _logKey(item, index);
    final expanded = _expandedLogKey == key;
    return Column(
      children: [
        _logRow(item, index, key, expanded),
        if (expanded) _expandedDetails(item, tableWidth),
      ],
    );
  }

  Widget _logRow(
    Map<String, dynamic> item,
    int index,
    String key,
    bool expanded,
  ) {
    final name = item['employeeName']?.toString() ?? 'Former employee';
    final staffId =
        item['staffId']?.toString() ??
        item['employeeId']?.toString() ??
        'Unassigned';
    // profileId = HRMS profiles table id; employeeUserId = fallback for staff not yet in HRMS
    final profileId = item['profileId'] is num
        ? (item['profileId'] as num).toInt()
        : 0;
    final employeeUserId = item['employeeId'] is num
        ? (item['employeeId'] as num).toInt()
        : null;
    return _row([
      '$index',
      _employeeCellTappable(name, staffId, profileId, employeeUserId),
      item['date']?.toString() ?? '-',
      item['checkIn']?.toString() ?? '-',
      item['checkOut']?.toString() ?? '-',
      _worked(item['breakMinutes']),
      _worked(item['workingMinutes']),
      _status(item['status']?.toString() ?? 'Absent'),
      item['workMode']?.toString() ?? 'Not set',
      IconButton(
        onPressed: () =>
            setState(() => _expandedLogKey = expanded ? null : key),
        icon: Icon(
          expanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_right_rounded,
          size: 24,
          color: const Color(0xFF071540),
        ),
        tooltip: expanded ? 'Hide details' : 'Show details',
      ),
      IconButton(
        onPressed: () => _openEmployeeCalendar(item),
        icon: const Icon(Icons.edit_calendar_outlined, size: 22),
        tooltip: 'Edit attendance',
        style: IconButton.styleFrom(
          foregroundColor: _blue,
          backgroundColor: const Color(0xFFF2F7FF),
          side: const BorderSide(color: Color(0xFFB8D3FF)),
          minimumSize: const Size(36, 36),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ]);
  }

  Widget _expandedDetails(Map<String, dynamic> item, double tableWidth) =>
      Container(
        width: tableWidth,
        padding: const EdgeInsets.fromLTRB(84, 0, 16, 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _line)),
        ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFF),
            border: Border.all(color: const Color(0xFFD9E5F6)),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Container(width: 4, height: 44, color: _blue),
              const SizedBox(width: 20),
              Expanded(
                child: _detailValue(
                  'Break begins',
                  item['breakStart']?.toString() ?? '-',
                ),
              ),
              _detailDivider(),
              Expanded(
                child: _detailValue(
                  'Break ends',
                  item['breakEnd']?.toString() ?? '-',
                ),
              ),
              _detailDivider(),
              Expanded(child: _breakDetail(item)),
              _detailDivider(),
              Expanded(
                child: _detailValue(
                  'Method',
                  _attendanceMethodLabel(item['method']),
                  emphasized: true,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _breakDetail(Map<String, dynamic> item) {
    final breaks = (item['breaks'] as List? ?? const []).whereType<Map>();
    final reasons = breaks
        .map((entry) => entry['employeeReason']?.toString().trim() ?? '')
        .where((reason) => reason.isNotEmpty)
        .toList();
    final hasOverdue = breaks.any(
      (entry) => ((entry['overdueMinutes'] as num?)?.toInt() ?? 0) > 0,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Break reason',
          style: TextStyle(color: Color(0xFF65759B), fontSize: 12),
        ),
        const SizedBox(height: 6),
        if (hasOverdue)
          _breakReview(item)
        else
          Text(
            reasons.isEmpty ? '-' : reasons.join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF071540),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  Widget _detailDivider() => Container(
    width: 1,
    height: 38,
    margin: const EdgeInsets.symmetric(horizontal: 24),
    color: _line,
  );

  Widget _detailValue(String label, String value, {bool emphasized = false}) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF65759B), fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFF071540),
              fontSize: 13,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      );

  Widget _row(List<dynamic> values, {bool header = false}) => Container(
    height: header ? 48 : 64,
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: Row(
      children: List.generate(
        values.length,
        (i) => Expanded(
          flex: const [5, 19, 12, 11, 11, 11, 11, 14, 13, 8, 8][i],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: values[i] is Widget
                  ? values[i]
                  : Text(
                      '${values[i]}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: header
                            ? const Color(0xFF1B1D25)
                            : const Color(0xFF283956),
                        fontSize: header ? 13 : 13,
                        fontWeight: header ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _breakReview(Map<String, dynamic> item) {
    final breaks = (item['breaks'] as List? ?? const []);
    var overdue = 0;
    for (final entry in breaks) {
      if (entry is Map) {
        overdue += (entry['overdueMinutes'] as num?)?.toInt() ?? 0;
      }
    }
    if (overdue == 0) return const Text('-');
    final overdueBreaks = breaks
        .whereType<Map>()
        .where((e) => ((e['overdueMinutes'] as num?)?.toInt() ?? 0) > 0)
        .toList();
    if (overdueBreaks.isEmpty) return const Text('-');
    final entry = overdueBreaks.first;
    final breakId = (entry['id'] as num?)?.toInt();
    final isReviewed = entry['reviewedAt'] != null;
    return InkWell(
      onTap: breakId == null
          ? null
          : () => _showBreakReviewPanel(context, breakId, entry, overdue),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: isReviewed ? const Color(0xFFE6F4EA) : const Color(0xFFFFEBEB),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          isReviewed ? 'Reviewed · ${overdue}m' : 'Extended · ${overdue}m',
          style: TextStyle(
            color: isReviewed
                ? const Color(0xFF1A7F37)
                : const Color(0xFFF04438),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  void _showBreakReviewPanel(
    BuildContext context,
    int breakId,
    Map entry,
    int overdue,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => _BreakReviewDialog(
        breakId: breakId,
        entry: entry,
        overdue: overdue,
        onReviewed: () => setState(() {}),
      ),
    );
  }

  Widget _employeeCell(String name, String id) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFEAF0FA),
            shape: BoxShape.circle,
          ),
          child: Text(
            initial,
            style: const TextStyle(
              color: _navy,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF17264A),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF52638E), fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _employeeCellTappable(
    String name,
    String id,
    int profileId,
    int? employeeUserId,
  ) {
    final cell = _employeeCell(name, id);
    // Always tappable — even if not in HRMS profiles yet, we use employeeUserId fallback
    if (profileId == 0 && employeeUserId == null) return cell;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EmployeeProfilePage(
            profileId: profileId,
            initialName: name,
            employeeUserId: employeeUserId,
          ),
        ),
      ),
      child: Tooltip(message: 'View full profile', child: cell),
    );
  }

  Widget _status(String value) {
    final lower = value.toLowerCase();
    final color = lower.contains('absent')
        ? const Color(0xFFF04438)
        : (lower.contains('late') || lower.replaceAll('_', ' ') == 'early exit')
        ? const Color(0xFFFF9200)
        : lower == 'no record'
        ? const Color(0xFF667085)
        : const Color(0xFF3BB95A);
    final bg = lower.contains('absent')
        ? const Color(0xFFFFEBEB)
        : (lower.contains('late') || lower.replaceAll('_', ' ') == 'early exit')
        ? const Color(0xFFFFF1DB)
        : lower == 'no record'
        ? const Color(0xFFF1F3F5)
        : const Color(0xFFE9F6EC);

    return Container(
      width: 112,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        value
            .replaceAll('_', ' ')
            .split(' ')
            .map(
              (p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}',
            )
            .join(' '),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _message(String text, {required VoidCallback retry}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(42),
      child: Column(
        children: [
          Text(text),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: retry, child: const Text('Retry')),
        ],
      ),
    ),
  );

  int _asInt(dynamic value) =>
      value is int ? value : int.tryParse('$value') ?? 0;
  String _worked(dynamic minutes) {
    final value = _asInt(minutes);
    return '${value ~/ 60}h ${(value % 60).toString().padLeft(2, '0')}m';
  }

  String _monthLabel(DateTime date) =>
      '${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][date.month - 1]} ${date.year}';
  String _dayLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')} ${_monthLabel(date).split(' ').first} ${date.year}';
}

class _BreakReviewDialog extends StatefulWidget {
  final int breakId;
  final Map entry;
  final int overdue;
  final VoidCallback onReviewed;
  const _BreakReviewDialog({
    required this.breakId,
    required this.entry,
    required this.overdue,
    required this.onReviewed,
  });
  @override
  State<_BreakReviewDialog> createState() => _BreakReviewDialogState();
}

class _BreakReviewDialogState extends State<_BreakReviewDialog> {
  bool _submitting = false;
  String? _error;
  final _clarificationController = TextEditingController();
  bool _showClarificationField = false;
  bool _done = false;
  String _doneMessage = '';

  @override
  void dispose() {
    _clarificationController.dispose();
    super.dispose();
  }

  Future<void> _submit(String action) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await HrmsClockLogsApi.reviewBreak(
        widget.breakId,
        action: action,
        clarification: _clarificationController.text.trim().isEmpty
            ? null
            : _clarificationController.text.trim(),
      );
      widget.onReviewed();
      if (mounted) {
        setState(() {
          _done = true;
          _doneMessage = action == 'reviewed'
              ? 'Break marked as reviewed.'
              : 'Clarification requested from employee.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final allowed = (entry['allowedMinutes'] as num?)?.toInt() ?? 0;
    final actual = (entry['durationMinutes'] as num?)?.toInt() ?? 0;
    final overdue = widget.overdue;
    final reason = entry['employeeReason']?.toString() ?? '';
    final reviewedAt = entry['reviewedAt']?.toString();
    final isAlreadyReviewed = reviewedAt != null;

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _done
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF1A7F37),
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _doneMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.timer_off_outlined,
                          color: Color(0xFFF04438),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Extended Break Review',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    _reviewRow('Allowed break', '$allowed min'),
                    _reviewRow('Actual break', '$actual min'),
                    _reviewRow(
                      'Overdue',
                      '$overdue min',
                      valueColor: const Color(0xFFF04438),
                      bold: true,
                    ),
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Employee reason',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFD8E1F0)),
                        ),
                        child: Text(
                          reason,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ] else
                      _reviewRow(
                        'Employee reason',
                        'No reason provided',
                        valueColor: const Color(0xFF94A3B8),
                      ),
                    if (isAlreadyReviewed) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6F4EA),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Color(0xFF1A7F37),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Reviewed on ${reviewedAt.substring(0, 10)}',
                              style: const TextStyle(
                                color: Color(0xFF1A7F37),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_showClarificationField) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _clarificationController,
                        autofocus: true,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Clarification message to employee',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFF04438),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (!_showClarificationField) ...[
                          OutlinedButton.icon(
                            onPressed: _submitting
                                ? null
                                : () => setState(
                                    () => _showClarificationField = true,
                                  ),
                            icon: const Icon(
                              Icons.chat_bubble_outline,
                              size: 16,
                            ),
                            label: const Text('Request clarification'),
                          ),
                          const SizedBox(width: 10),
                        ] else ...[
                          OutlinedButton(
                            onPressed: _submitting
                                ? null
                                : () => setState(() {
                                    _showClarificationField = false;
                                    _clarificationController.clear();
                                  }),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: _submitting
                                ? null
                                : () => _submit('clarification_requested'),
                            child: const Text('Send'),
                          ),
                          const SizedBox(width: 10),
                        ],
                        const Spacer(),
                        if (!_showClarificationField)
                          FilledButton.icon(
                            onPressed: _submitting
                                ? null
                                : () => _submit('reviewed'),
                            icon: _submitting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check, size: 16),
                            label: const Text('Mark reviewed'),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _reviewRow(
    String label,
    String value, {
    Color? valueColor,
    bool bold = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: valueColor,
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}

class _ClockLogsHeaderDelegate extends SliverPersistentHeaderDelegate {
  _ClockLogsHeaderDelegate({required this.child});
  final Widget child;

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;
  @override
  bool shouldRebuild(covariant _ClockLogsHeaderDelegate oldDelegate) => true;
}
