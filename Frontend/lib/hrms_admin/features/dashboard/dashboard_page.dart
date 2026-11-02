import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../screens/admin_dashboard/helpers/csv_export.dart';
import '../../../services/hrms_dashboard_api.dart';
import '../../shared/widgets/admin_top_nav.dart';
import 'widgets/attendance_grid.dart';
import 'widgets/manage_calendar_dialog.dart';
import 'widgets/manage_time_dialog.dart';

const _navy = Color(0xFF07186F);
const _blue = Color(0xFF0767F2);
const _green = Color(0xFF008A32);
const _red = Color(0xFFE00012);
const _orange = Color(0xFFFF6A00);
const _purple = Color(0xFF7E20E8);
const _line = Color(0xFFD9E2F1);
const _muted = Color(0xFF52638E);

String _fullMonthName(String month) =>
    const {
      'Jan': 'January',
      'Feb': 'February',
      'Mar': 'March',
      'Apr': 'April',
      'May': 'May',
      'Jun': 'June',
      'Jul': 'July',
      'Aug': 'August',
      'Sep': 'September',
      'Oct': 'October',
      'Nov': 'November',
      'Dec': 'December',
    }[month] ??
    month;

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  static Widget builder(BuildContext context) => const DashboardPage();

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final ScrollController _tableScrollController = ScrollController();
  final ScrollController _tableHeaderScrollController = ScrollController();
  bool _monthly = true;
  bool _showSummary = true;
  late String _month;
  late int _year;
  int _weekIndex = 0;
  String _search = '';
  String _dept = '';
  final _searchCtrl = TextEditingController();
  int _weeklyOffDay = DateTime.sunday;
  List<_EmployeeAttendance> _employees = [];
  int _kpiTotal = 0;
  int _kpiPresent = 0;
  int _kpiAbsent = 0;
  int _kpiLate = 0;
  int _kpiWorkingDays = 0;
  int _loadRequest = 0;
  bool _loading = true;
  String? _error;

  static const _monthCodes = [
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

  @override
  void initState() {
    super.initState();
    _tableScrollController.addListener(() {
      if (_tableHeaderScrollController.hasClients &&
          (_tableHeaderScrollController.offset - _tableScrollController.offset).abs() > 0.5) {
        _tableHeaderScrollController.jumpTo(_tableScrollController.offset);
      }
    });
    final today = DateTime.now();
    _year = today.year;
    _month = _monthCodes[today.month - 1];
    _weekIndex = (today.day - 1) ~/ 7;
    _boot();
  }

  Future<void> _boot() async {
    await _loadCalendarSettings();
    await _loadDashboard();
  }

  Future<void> _loadCalendarSettings() async {
    final weeklyOff = await CalendarStore.loadWeeklyOff();
    if (!mounted) return;
    setState(() {
      _weeklyOffDay = weeklyOff;
    });
  }

  void _changePeriod(bool monthly) {
    if (_monthly == monthly) return;
    setState(() => _monthly = monthly);
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    final request = ++_loadRequest;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = _monthly
          ? await HrmsDashboardApi.month(
              year: _year,
              month: _monthCodes.indexOf(_month) + 1,
            )
          : await HrmsDashboardApi.year(year: _year);
      final kpis = Map<String, dynamic>.from(data['kpis'] as Map? ?? {});
      final items = (data['employees'] as List? ?? [])
          .whereType<Map>()
          .map(
            (item) =>
                _EmployeeAttendance.fromApi(Map<String, dynamic>.from(item)),
          )
          .toList();
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _employees = items;
        _kpiTotal = _asInt(kpis['totalEmployees']);
        _kpiPresent = _asInt(kpis['present']);
        _kpiAbsent = _asInt(kpis['absent']);
        _kpiLate = _asInt(kpis['late']);
        _kpiWorkingDays = _asInt(kpis['workingDays']);
        _loading = false;
      });
    } catch (err) {
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _error = err.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  int _asInt(dynamic value) =>
      value is int ? value : int.tryParse('$value') ?? 0;

  static String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).substring(2)}';

  String _dayMarkColor(String code) {
    switch (code) {
      case 'P':
        return _hex(_green);
      case 'A':
        return _hex(_red);
      case 'LT':
        return _hex(_orange);
      case 'OFF':
        return _hex(_muted);
      case '–':
      case '':
        return _hex(_muted);
      // Any other code (HL, H, or a leave abbreviation like CL/EL/SL) = leave colour
      default:
        return _hex(_purple);
    }
  }

  Future<void> _exportAttendanceCsv() async {
    if (_loading || _error != null) return;
    if (!_monthly) {
      final rows = <List<String>>[
        [
          'Employee Name',
          'Designation',
          'Present',
          'Absent',
          'Late',
          'Leave',
          'Half Leave',
          'Earned Leave',
          'Annual Salary',
        ],
        for (final employee in _filteredEmployees)
          [
            employee.name,
            employee.designation,
            '${employee.present}',
            '${employee.unexcused}',
            '${employee.late}',
            '${employee.approvedLeave}',
            '${employee.halfLeave}',
            '${employee.earnedLeave}',
            _YearlyEmployeeRow._annualSalary(employee.salary),
          ],
      ];
      final csv = rows
          .map(
            (row) => row
                .map((value) => '"${value.replaceAll('"', '""')}"')
                .join(','),
          )
          .join('\r\n');
      await saveAndShareCsv([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(csv),
      ], 'GoDigital_Attendance_${_year}_Yearly.csv');
      return;
    }
    final month = _monthCodes.indexOf(_month) + 1;
    final dayCount = DateTime(_year, month + 1, 0).day;
    const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final monthLabel = '${_fullMonthName(_month)} $_year';
    final logoBytes = (await rootBundle.load(
      'assets/images/godigital_logo.png',
    )).buffer.asUint8List();
    final logoData = base64Encode(logoBytes);

    final html = StringBuffer();
    html.writeln('''
      <html>
      <head>
      <meta charset="utf-8">
      <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 18px; color: ${_hex(_navy)}; }
        .brand { border-bottom: 2px solid #0767F2; padding-bottom: 12px; margin-bottom: 10px; }
        .brand img { width: 110px; height: auto; vertical-align: middle; margin-right: 16px; }
        .brand-title { display: inline-block; vertical-align: middle; font-size: 18px; font-weight: bold; color: ${_hex(_navy)}; }
        .brand-subtitle { display: block; font-size: 11px; font-weight: normal; color: ${_hex(_muted)}; margin-top: 3px; }
        .title { font-size: 16px; font-weight: bold; color: ${_hex(_navy)}; padding: 8px 4px; }
        .legend td { font-size: 10px; font-weight: bold; padding: 4px 8px; color: ${_hex(_navy)}; }
        table.data { border-collapse: collapse; margin-top: 6px; }
        table.data th { background-color: #EAF1FF; font-size: 10px; font-weight: 700; padding: 7px 6px; border: 1px solid ${_hex(_line)}; color: ${_hex(_navy)}; text-align: center; white-space: nowrap; }
        table.data td { font-size: 10px; padding: 7px 6px; border: 1px solid ${_hex(_line)}; text-align: center; color: ${_hex(_navy)}; }
        td.name { text-align: left; font-weight: 700; }
        td.designation { text-align: left; color: ${_hex(_muted)}; font-weight: 400; }
      </style>
      </head>
      <body>
      <table class="brand"><tr><td><img src="data:image/png;base64,$logoData"><span class="brand-title">GO DIGITAL<span class="brand-subtitle">Employee Attendance Directory</span></span></td><td style="text-align:right; color:${_hex(_muted)}; font-size:10px;">Generated ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}</td></tr></table>
      <table>
        <tr><td class="title">$monthLabel Attendance</td></tr>
      </table>
      <table class="legend">
        <tr>
          <td style="color:${_hex(_green)}">● Present</td>
          <td style="color:${_hex(_red)}">● Absent</td>
          <td style="color:${_hex(_orange)}">● Late</td>
          <td style="color:${_hex(_purple)}">● Holiday</td>
          <td style="color:${_hex(_purple)}">● Leave</td>
          <td style="color:${_hex(_purple)}">● Half Leave</td>
          <td style="color:${_hex(_muted)}">○ Weekly Off</td>
        </tr>
      </table>
      <table class="data">
        <tr>
          <th>Employee Name</th>
          <th>Designation</th>
    ''');
    for (var day = 1; day <= dayCount; day++) {
      html.write(
        '<th>$day<br>${weekdayNames[DateTime(_year, month, day).weekday - 1]}</th>',
      );
    }
    html.writeln('''
          <th style="color:${_hex(_green)}">Present</th>
          <th style="color:${_hex(_red)}">Absent</th>
          <th style="color:${_hex(_orange)}">Late</th>
          <th style="color:${_hex(_purple)}">Leave</th>
          <th style="color:${_hex(_purple)}">Half Leave</th>
          <th style="color:${_hex(_blue)}">Earned Leave</th>
          <th>Paid Leave</th>
          <th>Unpaid LOP Leave</th>
          <th>Salary Per Month</th>
          <th>Per Day Salary</th>
          <th>Deduction</th>
          <th>Deducted Days</th>
          <th>Updated Salary</th>
          <th>Earned to Date</th>
          <th>Credited Days</th>
        </tr>
    ''');

    for (final employee in _employees) {
      html.write(
        '<tr><td class="name">${employee.name}</td>'
        '<td class="designation">${employee.designation}</td>',
      );
      for (var i = 0; i < dayCount; i++) {
        final mark = i < employee.days.length ? employee.days[i] : '';
        final display = mark.isEmpty ? '–' : (mark == 'LV' ? 'L' : mark);
        html.write('<td style="color:${_dayMarkColor(mark)}">$display</td>');
      }
      html.writeln('''
          <td style="color:${_hex(_green)}; font-weight:700;">${employee.present}</td>
          <td style="color:${_hex(_red)}; font-weight:700;">${employee.unexcused}</td>
          <td style="color:${_hex(_orange)}; font-weight:700;">${employee.late}</td>
          <td style="color:${_hex(_purple)}; font-weight:700;">${employee.approvedLeave}</td>
          <td style="color:${_hex(_purple)}; font-weight:700;">${employee.halfLeave}</td>
          <td style="color:${_hex(_blue)}; font-weight:700;">${employee.earnedLeave}</td>
          <td>${employee.paidLeaveDays}</td>
          <td>${employee.lopLeaveDays}</td>
          <td>${employee.salary}</td>
          <td>${employee.dailySalary}</td>
          <td>${employee.afterLeaves}</td>
          <td>${employee.deductedDays ?? '–'}</td>
          <td>${employee.updatedSalary}</td>
          <td>${employee.earnedToDate}</td>
          <td>${employee.creditedDays ?? '–'}</td>
        </tr>
      ''');
    }

    html.writeln('</table></body></html>');

    final fileName =
        'GoDigital_Attendance_$_month${_year}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xls';
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(html.toString())];
    await saveAndShareCsv(bytes, fileName);
  }

  Future<void> _openManageTime() async {
    final saved = await showManageTimeDialog(context);
    if (saved && mounted) await _loadDashboard();
  }

  Future<void> _openManageCalendar() async {
    final saved = await showManageCalendarDialog(context);
    if (saved) {
      await _loadCalendarSettings();
      await _loadDashboard();
    }
  }

  int get _daysInMonth =>
      DateTime(_year, _monthCodes.indexOf(_month) + 2, 0).day;
  int get _weeksInMonth => (_daysInMonth / 7).ceil();
  List<int> get _weekDays {
    final start = _weekIndex * 7 + 1;
    final end = (start + 6).clamp(1, _daysInMonth);
    return List.generate(end - start + 1, (i) => start + i);
  }

  List<_EmployeeAttendance> get _filteredEmployees => _employees.where((e) {
    if (_dept.isNotEmpty && e.department != _dept) return false;
    if (_search.isNotEmpty &&
        !e.name.toLowerCase().contains(_search.toLowerCase())) {
      return false;
    }
    return true;
  }).toList();

  List<String> get _departments => [
    ...{
      for (final e in _employees)
        if (e.department.isNotEmpty) e.department,
    },
  ]..sort();

  @override
  void dispose() {
    _tableScrollController.dispose();
    _tableHeaderScrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) {
      return _MobileDashboard(
        monthly: _monthly,
        onMonthlyChanged: _changePeriod,
        year: _year,
        onYearChanged: (value) {
          setState(() => _year = value);
          _loadDashboard();
        },
        onManageTime: _openManageTime,
        onManageCalendar: _openManageCalendar,
        onExport: _exportAttendanceCsv,
        month: _month,
        employees: _employees,
        total: _kpiTotal,
        present: _kpiPresent,
        absent: _kpiAbsent,
        late: _kpiLate,
        loading: _loading,
        error: _error,
        onRetry: _loadDashboard,
      );
    }
    final hpad = width < 1100 ? 20.0 : 32.0;
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: _monthly ? _monthBarFixed() : null,
      body: Column(
        children: [
          const AdminTopNav(activeRoute: '/admin/dashboard'),
          Expanded(child: _desktopScrollBody(hpad)),
        ],
      ),
    );
  }

  // ── Month bar fixed to bottom of screen ─────────────────────────────────────
  Widget _monthBarFixed() => Container(
    height: 46,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: _line)),
      boxShadow: [
        BoxShadow(
          color: Color(0x12000000),
          blurRadius: 8,
          offset: Offset(0, -2),
        ),
      ],
    ),
    child: _monthSelector(),
  );

  // ── Desktop body (handles loading / error / view modes) ──────────────────────
  Widget _desktopScrollBody(double hpad) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
            FilledButton(onPressed: _loadDashboard, child: const Text('Retry')),
          ],
        ),
      );
    }
    // Full-page scroll with sticky header for the main monthly+summary week view.
    if (_monthly && _showSummary) return _desktopFullPageScroll(hpad);
    // Fall back to original fixed-height panel layout for other views.
    return Padding(
      padding: EdgeInsets.fromLTRB(hpad, 14, hpad, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pageHeading(),
          const SizedBox(height: 10),
          SizedBox(
            height: 80,
            child: _KpiRow(
              monthly: _monthly,
              total: _kpiTotal,
              present: _kpiPresent,
              absent: _kpiAbsent,
              late: _kpiLate,
              workingDays: _kpiWorkingDays,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: _attendancePanel()),
        ],
      ),
    );
  }

  // ── Full-page scroll layout ───────────────────────────────────────────────────
  Widget _desktopFullPageScroll(double hpad) {
    final monthNum = _monthCodes.indexOf(_month) + 1;
    const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dayLabels = [
      for (final day in _weekDays)
        weekdayNames[DateTime(_year, monthNum, day).weekday - 1],
    ];
    final today = DateTime.now();
    final todayKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    int? todayIndex;
    for (var i = 0; i < _weekDays.length; i++) {
      final dk =
          '$_year-${monthNum.toString().padLeft(2, '0')}-${_weekDays[i].toString().padLeft(2, '0')}';
      if (dk == todayKey) {
        todayIndex = i;
        break;
      }
    }

    return CustomScrollView(
      slivers: [
        // ── Heading + KPIs + panel toolbar + legend ──
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hpad, 14, hpad, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _pageHeading(),
                const SizedBox(height: 10),
                SizedBox(
                  height: 80,
                  child: _KpiRow(
                    monthly: _monthly,
                    total: _kpiTotal,
                    present: _kpiPresent,
                    absent: _kpiAbsent,
                    late: _kpiLate,
                    workingDays: _kpiWorkingDays,
                  ),
                ),
                const SizedBox(height: 10),
                // Panel top: toolbar + legend (scrolls away)
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(color: Color(0xFFBFD2F2)),
                      left: BorderSide(color: Color(0xFFBFD2F2)),
                      right: BorderSide(color: Color(0xFFBFD2F2)),
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(13),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x09193B75),
                        blurRadius: 24,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _panelToolbar(),
                      const Divider(height: 1, color: _line),
                      _panelLegend(),
                      const Divider(height: 1, color: _line),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Sticky column header ──
        SliverPersistentHeader(
          pinned: true,
          delegate: AttendanceHeaderDelegate(
            horizontalController: _tableHeaderScrollController,
            days: _weekDays,
            dayLabels: dayLabels,
            showSummary: true,
            todayIndex: todayIndex,
            horizontalPadding: hpad,
          ),
        ),

        // ── Employee rows ──
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: hpad),
          sliver: _filteredEmployees.isEmpty
              ? const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No employees to show.')),
                  ),
                )
              : SliverToBoxAdapter(
                  child: _AttendanceTable(
                    horizontalController: _tableScrollController,
                    year: _year,
                    month: monthNum,
                    weekDays: _weekDays,
                    weeklyOffDay: _weeklyOffDay,
                    employees: _filteredEmployees,
                    showSummary: true,
                    showHeader: false,
                  ),
                ),
        ),

        // ── Panel bottom border + footer ──
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hpad, 0, hpad, 14),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Color(0xFFBFD2F2)),
                  left: BorderSide(color: Color(0xFFBFD2F2)),
                  right: BorderSide(color: Color(0xFFBFD2F2)),
                ),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(13),
                ),
              ),
              child: Column(
                children: [
                  const Divider(height: 1, color: _line),
                  _panelFooter(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pageHeading() => AdminPageHeader(
    title: 'Admin Dashboard',
    breadcrumb: 'Dashboard',
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PeriodToggle(monthly: _monthly, onChanged: _changePeriod),
        const SizedBox(width: 14),
        _YearSelector(
          value: _year,
          onChanged: (value) {
            setState(() => _year = value);
            _loadDashboard();
          },
        ),
      ],
    ),
  );

  Widget _attendancePanel() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFBFD2F2)),
      borderRadius: BorderRadius.circular(13),
      boxShadow: const [
        BoxShadow(
          color: Color(0x09193B75),
          blurRadius: 24,
          offset: Offset(0, 4),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        _panelToolbar(),
        const Divider(height: 1, color: _line),
        if (_monthly) ...[
          _panelLegend(),
          const Divider(height: 1, color: _line),
        ],
        Expanded(child: _panelBody()),
        const Divider(height: 1, color: _line),
        if (_monthly) _panelFooter(),
      ],
    ),
  );

  Widget _panelToolbar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
    child: Row(
      children: [
        const Icon(Icons.calendar_month_outlined, color: _blue, size: 22),
        const SizedBox(width: 10),
        Text(
          _monthly
              ? '${_monthName(_month)} $_year Attendance'
              : '$_year Yearly Attendance',
          style: const TextStyle(
            color: _navy,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (_monthly) ...[
          const SizedBox(width: 16),
          // Position 1: Search + dept filter
          SizedBox(
            width: 180,
            height: 36,
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search employee…',
                hintStyle: const TextStyle(color: _muted, fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 16, color: _muted),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _blue),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (val) => setState(() => _search = val),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: DropdownButtonHideUnderline(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: _line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: _dept.isEmpty ? null : _dept,
                  hint: const Text(
                    'All departments',
                    style: TextStyle(color: _muted, fontSize: 11),
                  ),
                  style: const TextStyle(color: _navy, fontSize: 11),
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: _navy,
                    size: 16,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text(
                        'All departments',
                        style: TextStyle(color: _muted),
                      ),
                    ),
                    for (final d in _departments)
                      DropdownMenuItem<String>(value: d, child: Text(d)),
                  ],
                  onChanged: (val) => setState(() => _dept = val ?? ''),
                ),
              ),
            ),
          ),
          if (_showSummary) ...[
            const SizedBox(width: 16),
            // Position 2: Week navigation (hidden in full-month mode)
            _weekNavRow(),
          ],
        ],
        const Spacer(),
        if (_monthly) ...[
          _panelBtn(
            _showSummary ? Icons.view_column : Icons.view_column_outlined,
            _showSummary ? 'Hide Summary' : 'Summary',
            () => setState(() => _showSummary = !_showSummary),
            active: _showSummary,
          ),
          const SizedBox(width: 8),
        ],
        _panelBtn(Icons.file_download_outlined, 'Export', _exportAttendanceCsv),
      ],
    ),
  );

  Widget _panelBtn(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool active = false,
    bool accent = false,
  }) => OutlinedButton.icon(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: accent
          ? _blue
          : active
          ? _blue
          : _navy,
      backgroundColor: active ? const Color(0xFFEAF2FF) : Colors.white,
      side: BorderSide(
        color: accent || active ? _blue : const Color(0xFFBFD2F2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    icon: Icon(icon, size: 18),
    label: Text(
      label,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
    ),
  );

  Widget _weekNavRow() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _weekNavBtn(
        Icons.chevron_left_rounded,
        _weekIndex > 0,
        () => setState(() => _weekIndex--),
      ),
      const SizedBox(width: 6),
      Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(9),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _weekIndex.clamp(0, _weeksInMonth - 1),
            style: const TextStyle(
              color: _navy,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: _navy,
              size: 18,
            ),
            borderRadius: BorderRadius.circular(10),
            items: List.generate(_weeksInMonth, (i) {
              final s = i * 7 + 1;
              final e = (s + 6).clamp(1, _daysInMonth);
              return DropdownMenuItem<int>(
                value: i,
                child: Text('Week ${i + 1} · $s–$e $_month'),
              );
            }),
            onChanged: (val) {
              if (val != null) setState(() => _weekIndex = val);
            },
          ),
        ),
      ),
      const SizedBox(width: 6),
      _weekNavBtn(
        Icons.chevron_right_rounded,
        _weekIndex < _weeksInMonth - 1,
        () => setState(() => _weekIndex++),
      ),
      const SizedBox(width: 8),
      OutlinedButton(
        onPressed: () {
          final today = DateTime.now();
          if (_year == today.year &&
              _monthCodes.indexOf(_month) + 1 == today.month) {
            setState(() => _weekIndex = (today.day - 1) ~/ 7);
          }
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: _blue,
          side: const BorderSide(color: Color(0xFFBFD2F2)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: const Text(
          'This week',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );

  Widget _weekNavBtn(
    IconData icon,
    bool enabled,
    VoidCallback onTap,
  ) => SizedBox(
    width: 40,
    height: 40,
    child: OutlinedButton(
      onPressed: enabled ? onTap : null,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        side: BorderSide(color: enabled ? _line : _line.withValues(alpha: .5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: Icon(icon, size: 20, color: enabled ? _navy : _muted),
    ),
  );

  Widget _panelLegend() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    child: Wrap(
      spacing: 16,
      runSpacing: 6,
      children: const [
        _LegendChip(code: 'P', label: 'Present'),
        _LegendChip(code: 'A', label: 'Absent'),
        _LegendChip(code: 'LT', label: 'Late'),
        _LegendChip(code: 'L', label: 'Leave'),
        _LegendChip(code: 'HL', label: 'Half Leave'),
        _LegendChip(code: 'EL', label: 'Earned Leave'),
        _LegendChip(code: 'H', label: 'Holiday'),
        _LegendChip(code: 'OFF', label: 'Weekly Off'),
      ],
    ),
  );

  Widget _panelBody() => _loading
      ? const Center(child: CircularProgressIndicator())
      : _error != null
      ? Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
              FilledButton(
                onPressed: _loadDashboard,
                child: const Text('Retry'),
              ),
            ],
          ),
        )
      : _monthly
      ? _showSummary
            // ── Week view with summary columns ──────────────────────────────
            ? _AttendanceTable(
                horizontalController: _tableScrollController,
                year: _year,
                month: _monthCodes.indexOf(_month) + 1,
                weekDays: _weekDays,
                weeklyOffDay: _weeklyOffDay,
                employees: _filteredEmployees,
                showSummary: true,
              )
            // ── Full month view (no summary) ─────────────────────────────────
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _tableScrollController,
                child: SizedBox(
                  // 230 frozen + 44px per day (fits ~23 days at 1280px, scrolls rest)
                  width: 230 + _daysInMonth * 44.0,
                  child: _AttendanceTable(
                    horizontalController: _tableScrollController,
                    year: _year,
                    month: _monthCodes.indexOf(_month) + 1,
                    weekDays: List.generate(_daysInMonth, (i) => i + 1),
                    weeklyOffDay: _weeklyOffDay,
                    employees: _filteredEmployees,
                    showSummary: false,
                  ),
                ),
              )
      : _YearlyAttendanceSummary(employees: _filteredEmployees);

  Widget _panelFooter() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
    child: Row(
      children: [
        Text(
          'Showing ${_filteredEmployees.length} of ${_employees.length} employees',
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
        const Spacer(),
        Text(
          'Total: ${_employees.length} employees',
          style: const TextStyle(
            color: _blue,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  void _openEditDialog(
    _EmployeeAttendance employee,
    int dayIndex,
    int day,
    String dateKey,
  ) {
    String selectedStatus = '';
    final timeCtrl1 = TextEditingController();
    final timeCtrl2 = TextEditingController();
    final remarksCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(22, 20, 16, 0),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.name,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      dateKey,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close_rounded, color: _muted),
              ),
            ],
          ),
          contentPadding: const EdgeInsets.all(22),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Attendance Status',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in [
                      ('P', 'Present'),
                      ('A', 'Absent'),
                      ('LT', 'Late'),
                      ('L', 'Leave'),
                      ('HL', 'Half Leave'),
                      ('EL', 'Earned Leave'),
                      ('H', 'Holiday'),
                      ('OFF', 'Weekly Off'),
                    ])
                      _StatusOption(
                        code: entry.$1,
                        label: entry.$2,
                        selected: selectedStatus == entry.$1,
                        onTap: () => setS(() => selectedStatus = entry.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _timeField('Check In', timeCtrl1)),
                    const SizedBox(width: 12),
                    Expanded(child: _timeField('Check Out', timeCtrl2)),
                  ],
                ),
                const SizedBox(height: 12),
                _remarksField(remarksCtrl),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: selectedStatus.isEmpty
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _loadDashboard();
                    },
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeField(String label, TextEditingController ctrl) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: _navy,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        decoration: InputDecoration(
          hintText: '09:30',
          hintStyle: const TextStyle(color: _muted),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: _line),
          ),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    ],
  );

  Widget _remarksField(TextEditingController ctrl) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Remarks',
        style: TextStyle(
          color: _navy,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        maxLines: 2,
        decoration: InputDecoration(
          hintText: 'Optional note…',
          hintStyle: const TextStyle(color: _muted),
          contentPadding: const EdgeInsets.all(12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: _line),
          ),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    ],
  );

  Widget _monthSelector() {
    const months = _monthCodes;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (final month in months)
            Expanded(
              child: InkWell(
                onTap: () {
                  final today = DateTime.now();
                  final newMonthNum = _monthCodes.indexOf(month) + 1;
                  setState(() {
                    _month = month;
                    _weekIndex =
                        (_year == today.year && newMonthNum == today.month)
                        ? (today.day - 1) ~/ 7
                        : 0;
                  });
                  _loadDashboard();
                },
                child: Container(
                  height: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: month == _month ? _blue : Colors.white,
                    border: const Border(left: BorderSide(color: _line)),
                    borderRadius: month == _month
                        ? BorderRadius.circular(7)
                        : BorderRadius.zero,
                  ),
                  child: Text(
                    '$month $_year',
                    style: TextStyle(
                      color: month == _month ? Colors.white : _navy,
                      fontSize: 12,
                      fontWeight: month == _month
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _monthName(String month) => const {
    'Jan': 'January',
    'Feb': 'February',
    'Mar': 'March',
    'Apr': 'April',
    'May': 'May',
    'Jun': 'June',
    'Jul': 'July',
    'Aug': 'August',
    'Sep': 'September',
    'Oct': 'October',
    'Nov': 'November',
    'Dec': 'December',
  }[month]!;
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.monthly,
    required this.total,
    required this.present,
    required this.absent,
    required this.late,
    required this.workingDays,
  });

  final bool monthly;
  final int total, present, absent, late, workingDays;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _KpiCard(
          label: 'Total Employees',
          value: '$total',
          subtitle: 'Current',
          color: _blue,
          icon: Icons.groups_2_outlined,
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: _KpiCard(
          label: 'Working Days',
          value: '$workingDays',
          subtitle: monthly ? 'This Month' : 'Selected Year',
          color: const Color(0xFF0891B2),
          icon: Icons.calendar_today_outlined,
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: _KpiCard(
          label: 'Present',
          value: '$present',
          subtitle: monthly ? 'Today' : 'Selected Year',
          color: _green,
          icon: Icons.check_rounded,
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: _KpiCard(
          label: 'Absent',
          value: '$absent',
          subtitle: monthly ? 'Today' : 'Selected Year',
          color: _red,
          icon: Icons.person_off_outlined,
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: _KpiCard(
          label: 'Late',
          value: '$late',
          subtitle: monthly ? 'Today' : 'Selected Year',
          color: _orange,
          icon: Icons.schedule_rounded,
        ),
      ),
    ],
  );
}

class _AttendanceTable extends StatelessWidget {
  const _AttendanceTable({
    required this.horizontalController,
    required this.year,
    required this.month,
    required this.weekDays,
    required this.weeklyOffDay,
    required this.employees,
    required this.showSummary,
    this.showHeader = true,
  }) : onCellTap = null;

  final ScrollController horizontalController;
  final int year;
  final int month;
  final List<int> weekDays;
  final int weeklyOffDay;
  final List<_EmployeeAttendance> employees;
  final bool showSummary;
  final bool showHeader;
  final void Function(
    _EmployeeAttendance,
    int dayIndex,
    int day,
    String dateKey,
  )?
  onCellTap;

  @override
  Widget build(BuildContext context) {
    const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = DateTime.now();
    final todayKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    int? todayIndex;
    for (var i = 0; i < weekDays.length; i++) {
      final dk =
          '$year-${month.toString().padLeft(2, '0')}-${weekDays[i].toString().padLeft(2, '0')}';
      if (dk == todayKey) {
        todayIndex = i;
        break;
      }
    }

    if (employees.isEmpty) {
      return const Center(child: Text('No employees to show.'));
    }
    return AttendanceGrid(
      horizontalController: showSummary ? horizontalController : null,
      showSummary: showSummary,
      showHeader: showHeader,
      days: weekDays,
      dayLabels: [
        for (final day in weekDays)
          weekdayNames[DateTime(year, month, day).weekday - 1],
      ],
      todayIndex: todayIndex,
      onCellTap: onCellTap == null
          ? null
          : (row, dayIndex) {
              final emp = employees.firstWhere(
                (e) => e.name == row.name,
                orElse: () => employees.first,
              );
              final day = weekDays[dayIndex];
              final dk =
                  '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
              onCellTap!(emp, dayIndex, day, dk);
            },
      rows: [
        for (final employee in employees)
          AttendanceRowData(
            employeeId: employee.employeeId,
            name: employee.name,
            designation: employee.designation,
            days: [
              for (var i = 0; i < weekDays.length; i++)
                AttendanceDayMark(
                  _markForDay(
                    weekDays[i] - 1,
                    employee,
                    year,
                    month,
                    weeklyOffDay,
                  ),
                ),
            ],
            present: employee.present,
            late: employee.late,
            excused: employee.excused,
            unexcused: employee.unexcused,
            halfLeave: employee.halfLeave,
            earnedLeave: employee.earnedLeave,
            approvedLeave: employee.approvedLeave,
            salaryPerMonth: employee.salary,
            salaryPerDay: employee.dailySalary,
            totalSalaryAfterLeaves: employee.afterLeaves,
            deductedDays: employee.deductedDays,
            updatedSalary: employee.updatedSalary,
            earnedToDate: employee.earnedToDate,
            creditedDays: employee.creditedDays,
          ),
      ],
    );
  }

  String _markForDay(
    int index,
    _EmployeeAttendance employee,
    int year,
    int month,
    int weeklyOffDay,
  ) {
    final day = index + 1;
    // `employee.days` comes from the server's employee-specific calendar
    // resolver. Never overwrite it with the admin's global override list:
    // that list also contains department and selected-employee rules.
    if (index < employee.days.length) return employee.days[index];
    if (DateTime(year, month, day).weekday == weeklyOffDay) return 'OFF';
    return '';
  }
}

class _YearlyAttendanceSummary extends StatelessWidget {
  const _YearlyAttendanceSummary({required this.employees});
  final List<_EmployeeAttendance> employees;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const headerHeight = 52.0;
      if (employees.isEmpty) {
        return const Center(child: Text('No employees to show.'));
      }
      return SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(constraints.maxWidth, 1050),
            child: Column(
              children: [
                const SizedBox(height: headerHeight, child: _YearlyHeaderRow()),
                for (final employee in employees)
                  SizedBox(
                    height: 42,
                    child: _YearlyEmployeeRow(employee: employee),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _EmployeeAttendance {
  const _EmployeeAttendance({
    required this.employeeId,
    required this.name,
    required this.designation,
    required this.department,
    required this.present,
    required this.late,
    required this.halfLeave,
    required this.earnedLeave,
    required this.approvedLeave,
    required this.excused,
    required this.unexcused,
    required this.salary,
    required this.dailySalary,
    required this.deductedDays,
    required this.paidLeaveDays,
    required this.lopLeaveDays,
    required this.afterLeaves,
    required this.updatedSalary,
    required this.earnedToDate,
    required this.creditedDays,
    required this.days,
  });

  final String employeeId;
  final String name;
  final String designation;
  final String department;
  final num present;
  final num late;
  final num halfLeave;
  final num earnedLeave;
  final num approvedLeave;
  final num excused;
  final num unexcused;
  final String salary;
  final String dailySalary;
  final num? deductedDays;
  final num paidLeaveDays;
  final num lopLeaveDays;
  final String afterLeaves;
  final String updatedSalary;
  final String earnedToDate;
  final num? creditedDays;
  final List<String> days;

  factory _EmployeeAttendance.fromApi(Map<String, dynamic> json) {
    num asNum(dynamic value) =>
        value is num ? value : num.tryParse('$value') ?? 0;
    final dailyRate = num.tryParse('${json['dailySalary']}');
    final creditedDays = num.tryParse('${json['creditedDays']}');
    // Older dashboard responses called total LOP days "daysPaid".
    final deductedDays = num.tryParse(
      '${json['deductedDays'] ?? json['lopDays'] ?? json['daysPaid']}',
    );
    return _EmployeeAttendance(
      employeeId: (json['employeeId'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      designation: (json['designation'] ?? '').toString(),
      department: (json['department'] ?? '').toString(),
      present: asNum(json['present']),
      late: asNum(json['late']),
      halfLeave: asNum(json['halfLeave']),
      earnedLeave: asNum(json['earnedLeave']),
      approvedLeave: asNum(json['approvedLeave']),
      excused: asNum(json['excused']),
      unexcused: asNum(json['unexcused']),
      salary: (json['salary'] ?? 'Not Set').toString(),
      dailySalary: dailyRate != null && dailyRate.isFinite
          ? '₹${NumberFormat('#,##,##0.##', 'en_IN').format(dailyRate)}'
          : '–',
      deductedDays: deductedDays != null && deductedDays.isFinite && deductedDays >= 0
          ? deductedDays
          : null,
      paidLeaveDays: asNum(json['paidLeaveDays']),
      lopLeaveDays: asNum(json['lopLeaveDays']),
      afterLeaves: (json['afterLeaves'] ?? '–').toString(),
      updatedSalary: (json['updatedSalary'] ?? 'Not Set').toString(),
      earnedToDate: (json['earnedToDate'] ?? '–').toString(),
      creditedDays: creditedDays != null && creditedDays.isFinite && creditedDays >= 0
          ? creditedDays
          : null,
      days: (json['days'] as List? ?? [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String code;
  final String label;
  const _LegendChip({required this.code, required this.label});

  @override
  Widget build(BuildContext context) {
    final mark = AttendanceDayMark(code);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: mark.chipBg,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            code,
            style: TextStyle(
              color: mark.color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
      ],
    );
  }
}

class _StatusOption extends StatelessWidget {
  final String code;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _StatusOption({
    required this.code,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final mark = AttendanceDayMark(code);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? mark.chipBg : Colors.white,
          border: Border.all(
            color: selected ? mark.color : const Color(0xFFDDE6F5),
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: mark.chipBg,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                code,
                style: TextStyle(
                  color: mark.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected ? mark.color : _muted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileDashboard extends StatelessWidget {
  const _MobileDashboard({
    required this.monthly,
    required this.onMonthlyChanged,
    required this.year,
    required this.onYearChanged,
    required this.onManageTime,
    required this.onManageCalendar,
    required this.onExport,
    required this.month,
    required this.employees,
    required this.total,
    required this.present,
    required this.absent,
    required this.late,
    required this.loading,
    required this.error,
    required this.onRetry,
  }) : workingDays = 0;
  final bool monthly;
  final ValueChanged<bool> onMonthlyChanged;
  final int year;
  final ValueChanged<int> onYearChanged;
  final VoidCallback onManageTime;
  final VoidCallback onManageCalendar;
  final VoidCallback onExport;
  final String month;
  final List<_EmployeeAttendance> employees;
  final int total, present, absent, late, workingDays;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8FAFF),
    bottomNavigationBar: const AdminMobileBottomNav(
      activeRoute: '/admin/dashboard',
    ),
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      title: Image.asset('assets/images/godigital_logo.png', height: 38),
      actions: [
        const Icon(Icons.notifications_none_rounded, color: _navy),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'Workspace',
          onSelected: (value) {
            if (value == 'workspace') {
              Navigator.of(
                context,
                rootNavigator: true,
              ).pushNamedAndRemoveUntil('/home', (route) => false);
            } else {
              Navigator.of(
                context,
                rootNavigator: true,
              ).pushNamedAndRemoveUntil('/home', (route) => false);
            }
          },
          icon: const CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFFEAF0FA),
            child: Icon(Icons.grid_view_rounded, color: _navy, size: 20),
          ),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'workspace',
              child: ListTile(
                leading: Icon(Icons.grid_view_rounded),
                title: Text('Workspace'),
              ),
            ),
            PopupMenuItem(
              value: 'logout',
              child: ListTile(
                leading: Icon(Icons.logout_rounded, color: _red),
                title: Text('Logout', style: TextStyle(color: _red)),
              ),
            ),
          ],
        ),
        const SizedBox(width: 6),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(error!, textAlign: TextAlign.center),
                ),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Admin Dashboard',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Employee attendance and payroll overview',
                  style: TextStyle(color: _muted),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _PeriodToggle(
                        width: null,
                        monthly: monthly,
                        onChanged: onMonthlyChanged,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _YearSelector(
                        compact: true,
                        value: year,
                        onChanged: onYearChanged,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _MobileDashboardMetric(
                      label: 'Employees',
                      value: '$total',
                      color: _blue,
                    ),
                    SizedBox(width: 8),
                    _MobileDashboardMetric(
                      label: 'Work Days',
                      value: '$workingDays',
                      color: const Color(0xFF0891B2),
                    ),
                    SizedBox(width: 8),
                    _MobileDashboardMetric(
                      label: 'Present',
                      value: '$present',
                      color: _green,
                    ),
                    SizedBox(width: 8),
                    _MobileDashboardMetric(
                      label: 'Late',
                      value: '$late',
                      color: _orange,
                    ),
                    SizedBox(width: 8),
                    _MobileDashboardMetric(
                      label: 'Absent',
                      value: '$absent',
                      color: _red,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _MobileAttendanceRecords(
                  monthly: monthly,
                  month: month,
                  year: year,
                  employees: employees,
                  onManageTime: onManageTime,
                  onManageCalendar: onManageCalendar,
                  onExport: onExport,
                ),
              ],
            ),
          ),
  );
}

class _MobileDashboardMetric extends StatelessWidget {
  const _MobileDashboardMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 72,
      padding: const EdgeInsets.all(8),
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
            style: const TextStyle(color: _muted, fontSize: 11),
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
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
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

class _MobileAdminDrawer extends StatelessWidget {
  const _MobileAdminDrawer({required this.onManageCalendar});

  final VoidCallback onManageCalendar;

  static const _routes = <(String, IconData, String)>[
    ('Dashboard', Icons.dashboard_outlined, '/admin/dashboard'),
    ('Employees', Icons.groups_outlined, '/admin/employees'),
    ('Clock Logs', Icons.history_rounded, '/admin/clock-logs'),
    ('Approvals', Icons.task_alt_rounded, '/admin/approvals'),
    ('Payroll', Icons.account_balance_wallet_outlined, '/admin/payroll'),
    ('Tracking', Icons.location_on_outlined, '/admin/tracking'),
  ];

  void _open(BuildContext context, String route) {
    Navigator.pop(context);
    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) => Drawer(
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
            child: Row(
              children: [
                Expanded(
                  child: Image.asset(
                    'assets/images/godigital_logo.png',
                    height: 40,
                    alignment: Alignment.centerLeft,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),
          Expanded(
            child: ListView(
              children: [
                for (final item in _routes)
                  ListTile(
                    leading: Icon(item.$2, color: _navy),
                    title: Text(
                      item.$1,
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () => _open(context, item.$3),
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.calendar_month_outlined,
                    color: _navy,
                  ),
                  title: const Text(
                    'Calendar',
                    style: TextStyle(color: _navy, fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onManageCalendar();
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.person_outline_rounded,
                    color: _navy,
                  ),
                  title: const Text(
                    'Profile',
                    style: TextStyle(color: _navy, fontWeight: FontWeight.w600),
                  ),
                  onTap: () => _open(context, '/admin/settings'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: _red),
            title: const Text(
              'Logout',
              style: TextStyle(color: _red, fontWeight: FontWeight.w700),
            ),
            onTap: () => Navigator.of(
              context,
              rootNavigator: true,
            ).pushNamedAndRemoveUntil('/home', (route) => false),
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

class _MobileAttendanceRecords extends StatelessWidget {
  const _MobileAttendanceRecords({
    required this.monthly,
    required this.month,
    required this.year,
    required this.employees,
    required this.onManageTime,
    required this.onManageCalendar,
    required this.onExport,
  });

  final bool monthly;
  final String month;
  final int year;
  final List<_EmployeeAttendance> employees;
  final VoidCallback onManageTime;
  final VoidCallback onManageCalendar;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFBFD2F2)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.calendar_month_outlined, color: _blue, size: 22),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                monthly
                    ? '${_fullMonthName(month)} $year Attendance'
                    : '$year Yearly Attendance',
                style: const TextStyle(
                  color: _navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              onPressed: onExport,
              icon: const Icon(Icons.file_download_outlined, color: _navy),
              tooltip: 'Export',
            ),
            IconButton(
              onPressed: onManageTime,
              icon: const Icon(Icons.schedule_rounded, color: _navy),
              tooltip: 'Manage Time',
            ),
            IconButton(
              onPressed: onManageCalendar,
              icon: const Icon(Icons.edit_calendar_outlined, color: _blue),
              tooltip: 'Manage Calendar',
            ),
          ],
        ),
        const SizedBox(height: 8),
        const _MobileLegend(),
        const SizedBox(height: 8),
        if (employees.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: Text('No attendance records found.')),
          )
        else if (monthly)
          _MobileCalendarScroll(month: month, year: year, employees: employees)
        else
          _MobileYearlySummary(employees: employees),
      ],
    ),
  );
}

class _MobileYearlySummary extends StatelessWidget {
  const _MobileYearlySummary({required this.employees});
  final List<_EmployeeAttendance> employees;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 220,
    child: SingleChildScrollView(
      child: Column(
        children: [
          Container(
            height: 38,
            color: const Color(0xFFF6F8FC),
            child: const Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Text(
                      'Employee',
                      style: TextStyle(
                        color: _navy,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'P',
                      style: TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'L',
                      style: TextStyle(
                        color: _orange,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Leave',
                      style: TextStyle(
                        color: _purple,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Half\nLv',
                      style: TextStyle(
                        color: _purple,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Earn\nLv',
                      style: TextStyle(
                        color: _blue,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text(
                      'Salary',
                      style: TextStyle(
                        color: _navy,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final employee in employees)
            Container(
              height: 42,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Text(
                        employee.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${employee.present}',
                        style: const TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${employee.late}',
                        style: const TextStyle(
                          color: _orange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${employee.approvedLeave}',
                        style: const TextStyle(
                          color: _purple,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${employee.halfLeave}',
                        style: const TextStyle(
                          color: _purple,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${employee.earnedLeave}',
                        style: const TextStyle(
                          color: _blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Text(
                        '${employee.updatedSalary} · Earned: ${employee.earnedToDate}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _MobileCalendarScroll extends StatelessWidget {
  const _MobileCalendarScroll({
    required this.month,
    required this.year,
    required this.employees,
  });

  final String month;
  final int year;
  final List<_EmployeeAttendance> employees;

  @override
  Widget build(BuildContext context) {
    const codes = [
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
    final monthNumber = codes.indexOf(month) + 1;
    final dayCount = DateTime(year, monthNumber + 1, 0).day;
    const employeeWidth = 142.0;
    const dayWidth = 38.0;
    const summaryWidths = [
      46.0,
      46.0,
      40.0,
      56.0,
      48.0,
      52.0,
      82.0,
      82.0,
      82.0,
      82.0,
    ];
    const summaryLabels = [
      'Present',
      'Absent',
      'Late',
      'Leave',
      'Half\nLeave',
      'Earned\nLeave',
      'Salary\nper month',
      'Per day\nsalary',
      'Deduction',
      'Updated\nsalary',
    ];
    final weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final tableWidth =
        employeeWidth +
        dayCount * dayWidth +
        summaryWidths.reduce((a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 7),
          child: Text(
            'Swipe sideways to view all days',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 220,
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    children: [
                      Container(
                        height: 48,
                        color: const Color(0xFFF6F8FC),
                        child: Row(
                          children: [
                            _headerCell('Employee', employeeWidth, left: true),
                            for (var day = 1; day <= dayCount; day++)
                              _headerCell(
                                '$day\n${weekday[DateTime(year, monthNumber, day).weekday - 1].substring(0, 1)}',
                                dayWidth,
                              ),
                            for (
                              var index = 0;
                              index < summaryLabels.length;
                              index++
                            )
                              _headerCell(
                                summaryLabels[index],
                                summaryWidths[index],
                              ),
                          ],
                        ),
                      ),
                      for (final employee in employees)
                        SizedBox(
                          height: 38,
                          child: Row(
                            children: [
                              SizedBox(
                                width: employeeWidth,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 10),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      employee.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _navy,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              for (var index = 0; index < dayCount; index++)
                                SizedBox(
                                  width: dayWidth,
                                  child: Center(
                                    child: _CalendarMark(
                                      value: index < employee.days.length
                                          ? employee.days[index]
                                          : '',
                                    ),
                                  ),
                                ),
                              _summaryCell(
                                '${employee.present}',
                                _green,
                                summaryWidths[0],
                              ),
                              _summaryCell(
                                '${employee.unexcused}',
                                _red,
                                summaryWidths[1],
                              ),
                              _summaryCell(
                                '${employee.late}',
                                _orange,
                                summaryWidths[2],
                              ),
                              _summaryCell(
                                '${employee.approvedLeave}',
                                _purple,
                                summaryWidths[3],
                              ),
                              _summaryCell(
                                '${employee.halfLeave}',
                                _purple,
                                summaryWidths[4],
                              ),
                              _summaryCell(
                                '${employee.earnedLeave}',
                                _blue,
                                summaryWidths[5],
                              ),
                              _summaryCell(
                                employee.salary,
                                _navy,
                                summaryWidths[6],
                              ),
                              _summaryCell(
                                employee.dailySalary,
                                _navy,
                                summaryWidths[7],
                              ),
                              SizedBox(
                                width: summaryWidths[8],
                                child: Center(
                                  child: AttendanceDeductionValue(
                                    amount: employee.afterLeaves,
                                    days: employee.deductedDays,
                                    compact: true,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: summaryWidths[9],
                                child: Center(
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [Text(employee.updatedSalary, style: const TextStyle(fontSize: 10)), AttendanceDeductionValue(
                                    amount: 'Earned: ${employee.earnedToDate}',
                                    days: employee.creditedDays,
                                    compact: true,
                                    daysSuffix: 'credited',
                                  )]),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerCell(String label, double width, {bool left = false}) =>
      SizedBox(
        width: width,
        child: Padding(
          padding: EdgeInsets.only(left: left ? 10 : 2),
          child: Align(
            alignment: left ? Alignment.centerLeft : Alignment.center,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _navy,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );

  Widget _summaryCell(String value, Color color, double width) => SizedBox(
    width: width,
    child: Center(
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _CalendarMark extends StatelessWidget {
  const _CalendarMark({required this.value});
  final String value;

  Color get _color {
    final mark = value.toUpperCase();
    if (mark == 'P') return _green;
    if (mark == 'L') return _orange;
    if (mark == 'A') return _red;
    if (mark == 'H' || mark.contains('LEAVE')) return _purple;
    return const Color(0xFF9BA8BC);
  }

  @override
  Widget build(BuildContext context) => Text(
    value.isEmpty ? '–' : value,
    style: TextStyle(color: _color, fontSize: 10, fontWeight: FontWeight.w700),
  );
}

class _MobileLegend extends StatelessWidget {
  const _MobileLegend();
  @override
  Widget build(BuildContext context) => const Wrap(
    spacing: 10,
    runSpacing: 6,
    children: [
      _LegendDot(label: 'Present', color: _green),
      _LegendDot(label: 'Absent', color: _red),
      _LegendDot(label: 'Late', color: _orange),
      _LegendDot(label: 'Leave', color: _purple),
    ],
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
    ],
  );
}

class _MobileEmployeeRecord extends StatelessWidget {
  const _MobileEmployeeRecord({required this.employee});
  final _EmployeeAttendance employee;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFFEAF0FA),
          child: Text(
            employee.name.isEmpty ? '?' : employee.name[0].toUpperCase(),
            style: const TextStyle(color: _navy, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                employee.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                employee.designation,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
        _RecordCount(
          label: 'P',
          value: employee.present.toString(),
          color: _green,
        ),
        const SizedBox(width: 10),
        _RecordCount(
          label: 'L',
          value: employee.late.toString(),
          color: _orange,
        ),
      ],
    ),
  );
}

class _RecordCount extends StatelessWidget {
  const _RecordCount({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
      Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
    ],
  );
}

class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({
    required this.monthly,
    required this.onChanged,
    this.width = 224,
  });

  final bool monthly;
  final ValueChanged<bool> onChanged;
  final double? width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 48,
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFC9D9F3)),
      borderRadius: BorderRadius.circular(8),
    ),
    clipBehavior: Clip.antiAlias,
    child: Row(
      children: [
        _PeriodButton(
          label: 'Monthly',
          active: monthly,
          onTap: () => onChanged(true),
        ),
        _PeriodButton(
          label: 'Yearly',
          active: !monthly,
          onTap: () => onChanged(false),
        ),
      ],
    ),
  );
}

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: Container(
        height: double.infinity,
        alignment: Alignment.center,
        color: active ? _blue : Colors.white,
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : _navy,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

class _YearSelector extends StatelessWidget {
  const _YearSelector({
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFC9D9F3)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.calendar_month_outlined,
          color: _blue,
          size: compact ? 20 : 23,
        ),
        SizedBox(width: compact ? 6 : 14),
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: value,
            borderRadius: BorderRadius.circular(10),
            icon: Padding(
              padding: EdgeInsets.only(left: compact ? 4 : 14),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _navy,
                size: 20,
              ),
            ),
            style: TextStyle(
              color: _navy,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 13 : 14,
            ),
            items: List.generate(7, (index) => DateTime.now().year - 3 + index)
                .map(
                  (year) =>
                      DropdownMenuItem<int>(value: year, child: Text('$year')),
                )
                .toList(),
            onChanged: (year) {
              if (year != null) onChanged(year);
            },
          ),
        ),
      ],
    ),
  );
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    this.subtitle = 'Today',
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 245;
      final iconSize = compact ? 44.0 : 54.0;
      return Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: color.withValues(alpha: .27)),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: .22),
                    blurRadius: 0,
                    spreadRadius: compact ? 5 : 8,
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: compact ? 24 : 30),
            ),
            SizedBox(width: compact ? 12 : 18),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: compact ? 11 : 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      color: _navy,
                      fontSize: compact ? 20 : 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: _navy, fontSize: compact ? 10 : 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _YearlyHeaderRow extends StatelessWidget {
  const _YearlyHeaderRow();

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Color(0xFFFBFCFE),
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: const Row(
      children: [
        _YearHeaderCell('Employee Name', flex: 22),
        _YearHeaderCell('Designation', flex: 20),
        _YearHeaderCell('Present', flex: 11, color: _green),
        _YearHeaderCell('Absent', flex: 11, color: _red),
        _YearHeaderCell('Late', flex: 11, color: _orange),
        _YearHeaderCell('Leave', flex: 11, color: _purple),
        _YearHeaderCell('Half Leave', flex: 11, color: _purple),
        _YearHeaderCell('Earned Leave', flex: 11, color: _blue),
        _YearHeaderCell('Annual Salary', flex: 14),
      ],
    ),
  );
}

class _YearlyEmployeeRow extends StatelessWidget {
  const _YearlyEmployeeRow({required this.employee});

  final _EmployeeAttendance employee;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: Row(
      children: [
        _YearBodyCell(
          flex: 22,
          alignment: Alignment.centerLeft,
          child: Text(
            employee.name,
            style: const TextStyle(
              color: _navy,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _YearBodyCell(
          flex: 20,
          alignment: Alignment.centerLeft,
          child: Text(
            employee.designation,
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
        ),
        _YearStatCell('${employee.present}', _green, 11),
        _YearStatCell('${employee.unexcused}', _red, 11),
        _YearStatCell('${employee.late}', _orange, 11),
        _YearStatCell('${employee.approvedLeave}', _purple, 11),
        _YearStatCell('${employee.halfLeave}', _purple, 11),
        _YearStatCell('${employee.earnedLeave}', _blue, 11),
        _YearBodyCell(
          flex: 14,
          child: Text(
            _annualSalary(employee.salary),
            style: const TextStyle(
              color: _navy,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );

  static String _annualSalary(String salary) {
    final amount = int.tryParse(salary.replaceAll(RegExp(r'[^0-9]'), ''));
    if (amount == null) return '–';
    final text = (amount * 12).toString();
    final buffer = StringBuffer();
    for (var index = 0; index < text.length; index++) {
      if (index > 0 && (text.length - index) % 3 == 0) buffer.write(',');
      buffer.write(text[index]);
    }
    return '₹$buffer';
  }
}

class _YearHeaderCell extends StatelessWidget {
  const _YearHeaderCell(this.text, {required this.flex, this.color = _navy});

  final String text;
  final int flex;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _YearBodyCell extends StatelessWidget {
  const _YearBodyCell({
    required this.flex,
    required this.child,
    this.alignment = Alignment.center,
  });

  final int flex;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Container(
      height: double.infinity,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: _line)),
      ),
      child: child,
    ),
  );
}

class _YearStatCell extends StatelessWidget {
  const _YearStatCell(this.value, this.color, this.flex);

  final String value;
  final Color color;
  final int flex;

  @override
  Widget build(BuildContext context) => _YearBodyCell(
    flex: flex,
    child: Text(
      value,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );
}
