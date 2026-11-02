import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const _gridLine = Color(0xFFE2E8F2);
const _todayBg = Color(0xFFEEF4FF);
const _chipBlue = Color(0xFF0767F2);

class AttendanceDayMark {
  final String code;
  const AttendanceDayMark(this.code);

  // Fixed system codes that always have a specific meaning.
  static const _systemCodes = {'P', 'A', 'LT', 'H', 'HL', 'OFF', 'L', 'LV'};

  bool get _isLeave =>
      !_systemCodes.contains(code) || code == 'L' || code == 'LV' || code == 'HL' || code == 'H';

  Color get color {
    switch (code) {
      case 'P':   return const Color(0xFF078C42);
      case 'A':   return const Color(0xFFD62545);
      case 'LT':  return const Color(0xFFE8770C);
      case 'OFF': return const Color(0xFF9CA3AF);
      default:    return _isLeave ? const Color(0xFF7C3CF2) : const Color(0xFF9CA3AF);
    }
  }

  Color get chipBg {
    switch (code) {
      case 'P':   return const Color(0xFFE8F7EE);
      case 'A':   return const Color(0xFFFFF0F2);
      case 'LT':  return const Color(0xFFFFF4E8);
      case 'OFF': return const Color(0xFFF1F3F8);
      default:    return _isLeave ? const Color(0xFFF2ECFF) : Colors.transparent;
    }
  }
}

class AttendanceRowData {
  final String employeeId;
  final String name;
  final String designation;
  final List<AttendanceDayMark> days;
  final num present;
  final num late;
  final num excused;
  final num unexcused;
  final num halfLeave;
  final num earnedLeave;
  final num approvedLeave;
  final String salaryPerMonth;
  final String salaryPerDay;
  final String totalSalaryAfterLeaves;
  final num? deductedDays;
  final String updatedSalary;
  final String earnedToDate;
  final num? creditedDays;

  const AttendanceRowData({
    this.employeeId = '',
    required this.name,
    required this.designation,
    required this.days,
    required this.present,
    required this.late,
    required this.excused,
    required this.unexcused,
    required this.halfLeave,
    required this.earnedLeave,
    required this.approvedLeave,
    required this.salaryPerMonth,
    this.salaryPerDay = '–',
    required this.totalSalaryAfterLeaves,
    this.deductedDays,
    required this.updatedSalary,
    this.earnedToDate = '–',
    this.creditedDays,
  });
}

class AttendanceGrid extends StatelessWidget {
  final List<int> days;
  final List<String> dayLabels;
  final List<AttendanceRowData> rows;
  final bool showSummary;
  final bool showHeader;
  final int? todayIndex;
  final ScrollController? horizontalController;
  final void Function(AttendanceRowData row, int dayIndex)? onCellTap;

  const AttendanceGrid({
    super.key,
    required this.days,
    required this.dayLabels,
    required this.rows,
    this.showSummary = true,
    this.showHeader = true,
    this.todayIndex,
    this.horizontalController,
    this.onCellTap,
  });

  // Layout constants
  static const double _headH  = 54;
  static const double _rowH   = 50;
  static const double _frozenW = 230;
  static const double _minDayW = 38;
  static const double _maxDayW = 80;

  // Summary columns
  static const List<double> _sW = [80, 82, 64, 64, 96, 110, 120, 120, 130, 120];
  static const List<String> _sLabel = [
    'Present', 'Absent', 'Late', 'Leave', 'Half Leave',
    'Earned Leave', 'Salary / Month', 'Per Day Salary', 'Deduction', 'Updated Salary',
  ];
  static const List<Color> _sColor = [
    Color(0xFF078C42), Color(0xFFD62545), Color(0xFFE8770C),
    Color(0xFF7C3CF2), Color(0xFF7C3CF2),
    _chipBlue,
    Color(0xFF07186F), Color(0xFF07186F), Color(0xFF07186F), Color(0xFF07186F),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, box) {
        final layout = _AttendanceColumnLayout(
          box.maxWidth,
          days.length,
          showSummary,
        );
        final dayW = layout.dayWidth;
        final summaryWidths = layout.summaryWidths;

        final bodyRows = [
          for (final row in rows)
            SizedBox(
              height: _rowH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _empCell(row, layout.employeeWidth),
                  for (var i = 0; i < row.days.length; i++)
                    _dayCell(
                      dayW,
                      row.days[i],
                      today: todayIndex == i,
                      onTap: onCellTap != null
                          ? () => onCellTap!(row, i)
                          : null,
                    ),
                  if (showSummary) ...[
                    _bCell(
                      summaryWidths[0],
                      _stat('${row.present}', _sColor[0]),
                    ),
                    _bCell(
                      summaryWidths[1],
                      _stat('${row.unexcused}', _sColor[1]),
                    ),
                    _bCell(summaryWidths[2], _stat('${row.late}', _sColor[2])),
                    _bCell(
                      summaryWidths[3],
                      _stat('${row.approvedLeave}', _sColor[3]),
                    ),
                    _bCell(
                      summaryWidths[4],
                      _stat('${row.halfLeave}', _sColor[4]),
                    ),
                    _bCell(
                      summaryWidths[5],
                      _stat('${row.earnedLeave}', _sColor[5]),
                    ),
                    _bCell(summaryWidths[6], _money(row.salaryPerMonth)),
                    _bCell(summaryWidths[7], _money(row.salaryPerDay)),
                    _bCell(
                      summaryWidths[8],
                      AttendanceDeductionValue(
                        amount: row.totalSalaryAfterLeaves,
                        days: row.deductedDays,
                      ),
                    ),
                    _bCell(
                      summaryWidths[9],
                      Column(mainAxisSize: MainAxisSize.min, children: [Text(row.updatedSalary, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)), AttendanceDeductionValue(
                        amount: 'Earned: ${row.earnedToDate}',
                        days: row.creditedDays,
                        daysSuffix: 'credited',
                      )]),
                    ),
                  ],
                ],
              ),
            ),
        ];

        // When showHeader=false the grid is hosted inside a SliverToBoxAdapter —
        // render rows in a plain Column (no Expanded / internal scroll needed).
        if (!showHeader) {
          return SingleChildScrollView(
            controller: horizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: layout.width,
              child: Column(children: bodyRows),
            ),
          );
        }

        return SingleChildScrollView(
          controller: horizontalController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: layout.width,
            child: Column(
              children: [
                // ── FROZEN HEADER (never scrolls) ───────────────────────────────
                SizedBox(
                  height: _headH,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _hCell(
                        'Employee / Designation',
                        '',
                        layout.employeeWidth,
                        align: Alignment.centerLeft,
                        hpad: 14,
                      ),
                      for (var i = 0; i < days.length; i++)
                        _hCell(
                          '${days[i]}',
                          dayLabels[i],
                          dayW,
                          today: todayIndex == i,
                        ),
                      if (showSummary)
                        for (var i = 0; i < _sLabel.length; i++)
                          _hCell(
                            _sLabel[i],
                            i == 7 ? 'Daily' : 'Monthly',
                            summaryWidths[i],
                            color: _sColor[i],
                          ),
                    ],
                  ),
                ),
                // ── SCROLLABLE BODY ─────────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: Column(children: bodyRows),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Cell builders ─────────────────────────────────────────────────────────

  Widget _hCell(String label, String sub, double w, {
    Color? color, bool today = false,
    Alignment align = Alignment.center, double hpad = 6,
  }) {
    final fg = today ? _chipBlue : (color ?? const Color(0xFF07186F));
    return Container(
      width: w,
      alignment: align,
      padding: EdgeInsets.symmetric(horizontal: hpad),
      decoration: BoxDecoration(
        color: today ? _todayBg : const Color(0xFFF6F8FE),
        border: const Border(
          right: BorderSide(color: _gridLine, width: .7),
          bottom: BorderSide(color: _gridLine, width: .7),
        ),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: fg)),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(sub,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, color: Color(0xFF8599C4))),
        ],
      ]),
    );
  }

  Widget _empCell(AttendanceRowData row, double w) => Container(
    width: w,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(
      border: Border(
        right: BorderSide(color: _gridLine, width: .7),
        bottom: BorderSide(color: _gridLine, width: .7),
      ),
    ),
    alignment: Alignment.centerLeft,
    child: Row(children: [
      _Avatar(name: row.name),
      const SizedBox(width: 10),
      Expanded(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.name,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF07186F), fontSize: 13)),
          const SizedBox(height: 3),
          Text(
            row.employeeId.isNotEmpty
                ? '${row.designation} · ${row.employeeId}'
                : row.designation,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF53688F), fontSize: 10)),
        ],
      )),
    ]),
  );

  Widget _dayCell(double w, AttendanceDayMark mark, {
    bool today = false, VoidCallback? onTap,
  }) =>
      InkWell(
        onTap: onTap,
        child: Container(
          width: w,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: today ? _todayBg : null,
            border: const Border(
              right: BorderSide(color: _gridLine, width: .7),
              bottom: BorderSide(color: _gridLine, width: .7),
            ),
          ),
          child: _MarkChip(mark: mark),
        ),
      );

  Widget _bCell(double w, Widget child) => Container(
    width: w,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: const BoxDecoration(
      border: Border(
        right: BorderSide(color: _gridLine, width: .7),
        bottom: BorderSide(color: _gridLine, width: .7),
      ),
    ),
    child: child,
  );

  Widget _stat(String v, Color c) => Text(v,
      style: TextStyle(color: c, fontSize: 14, fontWeight: FontWeight.w700));

  Widget _money(String v) => Text(v,
      maxLines: 1,
      style: const TextStyle(
          color: Color(0xFF07186F), fontSize: 11, fontWeight: FontWeight.w600));
}

class AttendanceDeductionValue extends StatelessWidget {
  const AttendanceDeductionValue({
    super.key,
    required this.amount,
    this.days,
    this.compact = false,
    this.daysSuffix = '',
  });

  final String amount;
  final num? days;
  final bool compact;
  final String daysSuffix;

  @override
  Widget build(BuildContext context) {
    final count = days;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          amount,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xFF07186F),
            fontSize: compact ? 10 : 11,
            fontWeight: compact ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        if (count != null && count.isFinite && count >= 0) ...[
          const SizedBox(height: 3),
          Text(
            '${NumberFormat('#,##0.##', 'en_IN').format(count)} ${count == 1 ? 'day' : 'days'}${daysSuffix.isEmpty ? '' : ' $daysSuffix'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF53688F), fontSize: 9),
          ),
        ],
      ],
    );
  }
}

// Header and employee rows share the same widths at every window size.
class _AttendanceColumnLayout {
  _AttendanceColumnLayout(
    double availableWidth,
    int dayCount,
    bool showSummary,
  ) {
    final minimumDayWidth = showSummary ? 56.0 : AttendanceGrid._minDayW;
    if (!showSummary) {
      width = availableWidth;
      employeeWidth = AttendanceGrid._frozenW;
      summaryWidths = const [];
    } else {
      const minimumEmployeeWidth = 190.0;
      const minimumSummaryWidths = [
        50.0,
        50.0,
        40.0,
        44.0,
        60.0,
        70.0,
        94.0,
        94.0,
        94.0,
        94.0,
      ];
      final daySpace = dayCount * minimumDayWidth;
      final preferredWidth =
          AttendanceGrid._frozenW +
          AttendanceGrid._sW.fold(0.0, (a, b) => a + b) +
          daySpace;
      final minimumWidth =
          minimumEmployeeWidth +
          minimumSummaryWidths.fold(0.0, (a, b) => a + b) +
          daySpace;
      width = availableWidth < minimumWidth ? minimumWidth : availableWidth;
      final compression =
          ((preferredWidth - width) / (preferredWidth - minimumWidth)).clamp(
            0.0,
            1.0,
          );
      employeeWidth =
          AttendanceGrid._frozenW -
          (AttendanceGrid._frozenW - minimumEmployeeWidth) * compression;
      summaryWidths = List.generate(
        AttendanceGrid._sW.length,
        (i) =>
            AttendanceGrid._sW[i] -
            (AttendanceGrid._sW[i] - minimumSummaryWidths[i]) * compression,
      );
    }
    final calendarWidth =
        (width - employeeWidth - summaryWidths.fold(0.0, (a, b) => a + b))
            .clamp(0.0, double.infinity);
    dayWidth = dayCount == 0
        ? minimumDayWidth
        : (calendarWidth / dayCount).clamp(
            minimumDayWidth,
            AttendanceGrid._maxDayW,
          );
  }

  late final double width;
  late final double employeeWidth;
  late final double dayWidth;
  late final List<double> summaryWidths;
}

// ── Avatar ────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});

  String get _initials {
    final parts = name.trim().split(' ').where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: 34, height: 34,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFEDF3FF),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(_initials,
        style: const TextStyle(
            color: _chipBlue, fontSize: 13, fontWeight: FontWeight.w700)),
  );
}

// ── Mark chip ─────────────────────────────────────────────────────────────────

class _MarkChip extends StatelessWidget {
  final AttendanceDayMark mark;
  const _MarkChip({required this.mark});

  @override
  Widget build(BuildContext context) {
    if (mark.code.isEmpty) {
      return const Text('–',
          style: TextStyle(color: Color(0xFFB0BCCC), fontSize: 13));
    }
    final label = mark.code == 'LV' ? 'L' : mark.code;
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: mark.chipBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: mark.color, fontWeight: FontWeight.w800, fontSize: 11)),
    );
  }
}

// ── Sticky column-header delegate ─────────────────────────────────────────────
// Used in dashboard's full-page-scroll mode (SliverPersistentHeader, pinned).
// Renders the same header row as AttendanceGrid but as a sliver that pins
// just below the top nav while the user scrolls through employee rows.

class AttendanceHeaderDelegate extends SliverPersistentHeaderDelegate {
  const AttendanceHeaderDelegate({
    required this.days,
    required this.dayLabels,
    required this.showSummary,
    this.todayIndex,
    this.horizontalPadding = 0,
    this.horizontalController,
  });

  final List<int> days;
  final List<String> dayLabels;
  final bool showSummary;
  final int? todayIndex;
  final double horizontalPadding;
  final ScrollController? horizontalController;

  static const double height = AttendanceGrid._headH;

  @override double get minExtent => height;
  @override double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: LayoutBuilder(
        builder: (ctx, box) {
          final layout = _AttendanceColumnLayout(
            box.maxWidth,
            days.length,
            showSummary,
          );
          final dayW = layout.dayWidth;

          return SingleChildScrollView(
            controller: horizontalController,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: SizedBox(
              width: layout.width,
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _hCell(
                    'Employee / Designation',
                    '',
                    layout.employeeWidth,
                    align: Alignment.centerLeft,
                    hpad: 14,
                  ),
                  for (var i = 0; i < days.length; i++)
                    _hCell(
                      '${days[i]}',
                      dayLabels[i],
                      dayW,
                      today: todayIndex == i,
                    ),
                  if (showSummary)
                    for (var i = 0; i < AttendanceGrid._sLabel.length; i++)
                      _hCell(
                        AttendanceGrid._sLabel[i],
                        i == 7 ? 'Daily' : 'Monthly',
                        layout.summaryWidths[i],
                        color: AttendanceGrid._sColor[i],
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _hCell(String label, String sub, double w, {
    Color? color, bool today = false,
    Alignment align = Alignment.center, double hpad = 6,
  }) {
    final fg = today ? _chipBlue : (color ?? const Color(0xFF07186F));
    return Container(
      width: w,
      alignment: align,
      padding: EdgeInsets.symmetric(horizontal: hpad),
      decoration: BoxDecoration(
        color: today ? _todayBg : const Color(0xFFF6F8FE),
        border: const Border(
          right: BorderSide(color: _gridLine, width: .7),
          bottom: BorderSide(color: _gridLine, width: .7),
        ),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: fg)),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(sub,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, color: Color(0xFF8599C4))),
        ],
      ]),
    );
  }

  @override
  bool shouldRebuild(covariant AttendanceHeaderDelegate old) =>
      old.days != days ||
      old.dayLabels != dayLabels ||
      old.showSummary != showSummary ||
      old.todayIndex != todayIndex;
}
