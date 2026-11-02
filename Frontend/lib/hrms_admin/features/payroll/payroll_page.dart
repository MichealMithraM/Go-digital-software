import 'package:flutter/material.dart';

import '../../../services/hrms_payroll_api.dart';
import '../../shared/widgets/admin_top_nav.dart';
import '../../shared/widgets/admin_page_scroll_view.dart';

abstract final class _PayrollColors {
  static const blue = Color(0xFF075EF7);
  static const navy = Color(0xFF061457);
  static const page = Color(0xFFF7F9FD);
}

class PayrollPage extends StatefulWidget {
  const PayrollPage({super.key});

  static Widget builder(BuildContext context) => const PayrollPage();

  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage> {
  late int year;
  late int month;
  String employee = 'All Employees';
  String status = 'All Status';
  List<_PayrollRow> rows = [];
  List<String> employeeNames = const ['All Employees'];
  List<_MonthOption> months = [];
  String kpiTotal = '₹0';
  int kpiEmployees = 0;
  int kpiPaid = 0;
  int kpiPending = 0;
  bool loading = true;
  bool generating = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    year = now.year;
    month = now.month;
    _load();
  }

  String get _monthKey => '$year-${month.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await HrmsPayrollApi.list(
        year: year,
        month: month,
        employee: employee,
        status: status,
      );
      final items = (data['items'] as List? ?? [])
          .whereType<Map>()
          .map((item) => _PayrollRow.fromApi(Map<String, dynamic>.from(item)))
          .toList();
      final kpis = Map<String, dynamic>.from(data['kpis'] as Map? ?? {});
      final names = <String>{'All Employees'};
      names.addAll((data['employees'] as List? ?? []).map((e) => e.toString()));
      final monthItems = (data['months'] as List? ?? [])
          .whereType<Map>()
          .map((item) => _MonthOption.fromApi(Map<String, dynamic>.from(item)))
          .toList();
      if (!mounted) return;
      setState(() {
        rows = items;
        employeeNames = names.toList();
        if (!employeeNames.contains(employee)) employee = 'All Employees';
        months = monthItems;
        year = _asInt(data['year'], year);
        month = _asInt(data['month'], month);
        kpiTotal = (kpis['totalPayrollLabel'] ?? '₹0').toString();
        kpiEmployees = _asInt(kpis['employees'], 0);
        kpiPaid = _asInt(kpis['paid'], 0);
        kpiPending = _asInt(kpis['pending'], 0) + _asInt(kpis['draft'], 0);
        loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        error = err.toString().replaceFirst('Exception: ', '');
        loading = false;
      });
    }
  }

  int _asInt(dynamic value, int fallback) {
    if (value is int) return value;
    return int.tryParse('$value') ?? fallback;
  }

  Future<void> _generate() async {
    setState(() => generating = true);
    try {
      await HrmsPayrollApi.generate(year: year, month: month);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Month-end payroll draft generated. Review it before marking employees as paid.')),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  Future<void> _markPaid(_PayrollRow row) async {
    if (row.itemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Generate payroll for this month first.')),
      );
      return;
    }
    try {
      await HrmsPayrollApi.markPaid(row.itemId!);
      await _load();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: _PayrollColors.page,
      bottomNavigationBar: mobile ? const AdminMobileBottomNav(activeRoute: '/admin/payroll') : null,
      body: Column(
        children: [
          const AdminTopNav(activeRoute: '/admin/payroll'),
          Expanded(
            child: loading && rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : error != null && rows.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(error!, textAlign: TextAlign.center),
                            ),
                            FilledButton(
                                onPressed: _load, child: const Text('Retry')),
                          ],
                        ),
                      )
                    : AdminPageScrollView(
                        padding: EdgeInsets.fromLTRB(
                            mobile ? 16 : 28, 18, mobile ? 16 : 28, 28),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1580),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _PayrollHeader(
                                  generating: generating,
                                  onGenerate: _generate,
                                ),
                                const SizedBox(height: 17),
                                _PayrollKpis(
                                  total: kpiTotal,
                                  employees: kpiEmployees,
                                  paid: kpiPaid,
                                  pending: kpiPending,
                                ),
                                const SizedBox(height: 16),
                                if (loading)
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 12),
                                    child: LinearProgressIndicator(minHeight: 2),
                                  ),
                                _PayrollPanel(
                                  monthKey: _monthKey,
                                  months: months,
                                  employee: employee,
                                  status: status,
                                  employees: employeeNames,
                                  rows: rows,
                                  year: year,
                                  month: month,
                                  onMonthChanged: (value) {
                                    if (value == null) return;
                                    final parts = value.split('-');
                                    year = int.parse(parts[0]);
                                    month = int.parse(parts[1]);
                                    _load();
                                  },
                                  onEmployeeChanged: (value) {
                                    employee = value!;
                                    _load();
                                  },
                                  onStatusChanged: (value) {
                                    status = value!;
                                    _load();
                                  },
                                  onReset: () {
                                    employee = 'All Employees';
                                    status = 'All Status';
                                    _load();
                                  },
                                  onMarkPaid: _markPaid,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _editPolicy() async {
    try {
      final saved = await showDialog<bool>(context: context, builder: (_) => const PayrollPolicyDialog());
      if (saved == true) _load();
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))));
    }
  }
}

class PayrollPolicyDialog extends StatefulWidget {
  const PayrollPolicyDialog({super.key});
  @override State<PayrollPolicyDialog> createState() => _PayrollPolicyDialogState();
}

class _PayrollPolicyDialogState extends State<PayrollPolicyDialog> {
  Set<int> offDays = {0};
  bool explicitAbsence = true;
  bool missingAttendance = false;
  bool loading = true;
  bool saving = false;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final data = await HrmsPayrollApi.policy();
    if (!mounted) return;
    setState(() { offDays = ((data['weeklyOffDays'] as List? ?? [0]).map((v) => int.tryParse('$v') ?? 0).toSet()); explicitAbsence = data['deductExplicitAbsence'] == true; missingAttendance = data['missingAttendanceIsAbsent'] == true; loading = false; });
  }
  Future<void> _save() async {
    setState(() => saving = true);
    try { await HrmsPayrollApi.savePolicy({'weeklyOffDays': offDays.toList()..sort(), 'deductExplicitAbsence': explicitAbsence, 'missingAttendanceIsAbsent': missingAttendance}); if (mounted) Navigator.pop(context, true); }
    finally { if (mounted) setState(() => saving = false); }
  }
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('Payroll policy'),
    content: loading ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())) : SingleChildScrollView(child: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Weekly off days'),
      Wrap(children: List.generate(7, (day) { const labels = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat']; return FilterChip(label: Text(labels[day]), selected: offDays.contains(day), onSelected: (selected) => setState(() { if (selected) { offDays.add(day); } else { offDays.remove(day); } })); })),
      const SizedBox(height: 10),
      const Padding(padding: EdgeInsets.only(top: 10), child: Text('Daily salary is calculated from the actual working days in each pay period.', style: TextStyle(fontSize: 12, color: Color(0xFF657087)))),
      const Padding(padding: EdgeInsets.only(top: 8), child: Text('Paid or unpaid leave is controlled per leave type in Leave Policy.', style: TextStyle(fontSize: 12, color: Color(0xFF657087)))),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Deduct explicit absence'), value: explicitAbsence, onChanged: (value) => setState(() => explicitAbsence = value)),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Treat missing attendance as absence'), value: missingAttendance, onChanged: (value) => setState(() => missingAttendance = value)),
    ]))),
    actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: saving ? null : _save, child: Text(saving ? 'Saving…' : 'Save policy'))],
  );
}

class _MonthOption {
  const _MonthOption({
    required this.year,
    required this.month,
    required this.label,
  });
  final int year, month;
  final String label;
  String get key => '$year-${month.toString().padLeft(2, '0')}';

  factory _MonthOption.fromApi(Map<String, dynamic> json) {
    int asInt(dynamic value) =>
        value is int ? value : int.tryParse('$value') ?? 0;
    return _MonthOption(
      year: asInt(json['year']),
      month: asInt(json['month']),
      label: (json['label'] ?? '').toString(),
    );
  }
}

class _PayrollHeader extends StatelessWidget {
  const _PayrollHeader({required this.generating, required this.onGenerate});
  final bool generating;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Row(
      children: [
        Expanded(child: AdminPageHeader(
          title: 'Payroll',
          fitBreadcrumb: MediaQuery.sizeOf(context).width < 600,
        )),
        Tooltip(
          message: 'Generate the month-end draft after attendance and leave are final. Live salary previews update automatically every day.',
          child: FilledButton.icon(
          onPressed: generating ? null : onGenerate,
          icon: generating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.playlist_add_check_rounded),
          label: Text(generating ? 'Generating…' : (mobile ? 'Generate draft' : 'Generate month-end draft')),
          style: FilledButton.styleFrom(
            backgroundColor: _PayrollColors.blue,
            padding: EdgeInsets.symmetric(
              horizontal: mobile ? 10 : 16,
              vertical: mobile ? 8 : 14,
            ),
            minimumSize: mobile ? const Size(0, 36) : null,
            textStyle: mobile ? const TextStyle(fontSize: 12, fontWeight: FontWeight.w600) : null,
            iconSize: mobile ? 18 : null,
          ),
          ),
        ),
      ],
    );
  }
}

class _PayrollKpis extends StatelessWidget {
  const _PayrollKpis({
    required this.total,
    required this.employees,
    required this.paid,
    required this.pending,
  });
  final String total;
  final int employees, paid, pending;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _PayrollKpi('This month net', total, 'Present + late days vs working days',
          Icons.account_balance_wallet_outlined, _PayrollColors.blue),
      _PayrollKpi('Employees', '$employees', 'Active / on leave staff',
          Icons.groups_outlined, const Color(0xFF158C20)),
      _PayrollKpi('Paid', '$paid', 'Marked paid',
          Icons.check_circle_outline_rounded, const Color(0xFF158C20)),
      _PayrollKpi('Unpaid', '$pending', 'Draft or pending rows',
          Icons.pending_actions_outlined, const Color(0xFFFF6500)),
    ];
    return LayoutBuilder(builder: (_, constraints) {
      final mobile = constraints.maxWidth < 600;
      final columns = mobile
          ? 4
          : constraints.maxWidth < 700
          ? 1
          : constraints.maxWidth < 1100
              ? 2
              : 4;
      final spacing = mobile ? 8.0 : 16.0;
      final width = (constraints.maxWidth - (columns - 1) * spacing) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: mobile ? 8 : 16,
        children: cards
            .map((card) => SizedBox(width: width, child: card))
            .toList(),
      );
    });
  }
}

class _PayrollKpi extends StatelessWidget {
  const _PayrollKpi(
      this.label, this.value, this.caption, this.icon, this.color);
  final String label, value, caption;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    if (compact) {
      return Container(
        height: 72,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: color.withValues(alpha: .25)), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF50649E), fontSize: 11)),
          Expanded(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 23, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
        ]),
      );
    }
    return Container(
        height: 104,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE5E8EF)),
          borderRadius: BorderRadius.circular(13),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0C071A72), blurRadius: 16, offset: Offset(0, 6))
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: .09),
                      shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: Color(0xFF596176), fontSize: 14)),
                      Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFF090B12),
                              fontSize: 24,
                              height: 1.15,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFF596176), fontSize: 12)),
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
                    color: _PayrollColors.blue,
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ],
        ),
      );
  }
}

class _PayrollPanel extends StatelessWidget {
  const _PayrollPanel({
    required this.monthKey,
    required this.months,
    required this.employee,
    required this.status,
    required this.employees,
    required this.rows,
    required this.year,
    required this.month,
    required this.onMonthChanged,
    required this.onEmployeeChanged,
    required this.onStatusChanged,
    required this.onReset,
    required this.onMarkPaid,
  });

  final String monthKey;
  final List<_MonthOption> months;
  final String employee, status;
  final List<String> employees;
  final List<_PayrollRow> rows;
  final int year, month;
  final ValueChanged<String?> onMonthChanged, onEmployeeChanged, onStatusChanged;
  final VoidCallback onReset;
  final ValueChanged<_PayrollRow> onMarkPaid;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Container(
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width < 600 ? 12 : 22,
          16,
          MediaQuery.sizeOf(context).width < 600 ? 12 : 22,
          14,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE4E7EE)),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A071A72), blurRadius: 16, offset: Offset(0, 6))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mobile) const Text('Monthly payroll',
                style: TextStyle(
                    color: _PayrollColors.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            if (!mobile) const SizedBox(height: 6),
            if (!mobile) const Text(
              'Generate one monthly run for all employees with configured compensation. Net pay is monthly salary minus deductions from the Payroll policy.',
              style: TextStyle(color: Color(0xFF596176), fontSize: 13),
            ),
            SizedBox(height: mobile ? 0 : 16),
            _PayrollFilters(
              monthKey: monthKey,
              months: months,
              employee: employee,
              employees: employees,
              status: status,
              onMonthChanged: onMonthChanged,
              onEmployeeChanged: onEmployeeChanged,
              onStatusChanged: onStatusChanged,
              onReset: onReset,
            ),
            const SizedBox(height: 16),
            if (MediaQuery.sizeOf(context).width < 600)
              _MobilePayrollList(rows: rows, onMarkPaid: onMarkPaid)
            else
              _PayrollTable(rows: rows, onMarkPaid: onMarkPaid, year: year, month: month),
            const SizedBox(height: 16),
            Text(
              rows.isEmpty
                  ? 'No payroll rows for these filters.'
                  : 'Showing ${rows.length} employee${rows.length == 1 ? '' : 's'}',
              style: const TextStyle(color: Color(0xFF596176), fontSize: 13),
            ),
          ],
        ),
      );
  }
}

class _PayrollFilters extends StatelessWidget {
  const _PayrollFilters({
    required this.monthKey,
    required this.months,
    required this.employee,
    required this.employees,
    required this.status,
    required this.onMonthChanged,
    required this.onEmployeeChanged,
    required this.onStatusChanged,
    required this.onReset,
  });

  final String monthKey;
  final List<_MonthOption> months;
  final String employee, status;
  final List<String> employees;
  final ValueChanged<String?> onMonthChanged, onEmployeeChanged, onStatusChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final monthValue = months.any((item) => item.key == monthKey)
        ? monthKey
        : (months.isEmpty ? monthKey : months.first.key);
    return LayoutBuilder(builder: (_, constraints) {
      final mobile = MediaQuery.sizeOf(context).width < 600;
      if (mobile) {
        return Row(children: [
          OutlinedButton.icon(onPressed: () => _showMobileFilters(context, monthValue), icon: const Icon(Icons.tune_rounded, size: 19), label: const Text('Filter'), style: OutlinedButton.styleFrom(foregroundColor: _PayrollColors.blue, side: const BorderSide(color: _PayrollColors.blue), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13))),
          const SizedBox(width: 8),
          IconButton.outlined(onPressed: onReset, icon: const Icon(Icons.restart_alt_rounded), color: _PayrollColors.blue, tooltip: 'Reset filters'),
        ]);
      }
      final width = constraints.maxWidth < 900 ? constraints.maxWidth : 280.0;
      return Wrap(
        spacing: 24,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          _FilterField(
            label: 'Month',
            width: width,
            child: DropdownButtonFormField<String>(
              initialValue: monthValue,
              onChanged: onMonthChanged,
              decoration: _fieldDecoration(),
              items: (months.isEmpty
                      ? [
                          _MonthOption(
                              year: DateTime.now().year,
                              month: DateTime.now().month,
                              label: 'This month')
                        ]
                      : months)
                  .map((item) => DropdownMenuItem(
                      value: item.key, child: Text(item.label)))
                  .toList(),
            ),
          ),
          _FilterField(
            label: 'Employee',
            width: width,
            child: DropdownButtonFormField<String>(
              initialValue: employee,
              onChanged: onEmployeeChanged,
              decoration: _fieldDecoration(),
              items: employees
                  .map((item) =>
                      DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
            ),
          ),
          _FilterField(
            label: 'Status',
            width: width,
            child: DropdownButtonFormField<String>(
              initialValue: status,
              onChanged: onStatusChanged,
              decoration: _fieldDecoration(),
              items: const [
                'All Status',
                'Draft',
                'Pending',
                'Paid',
              ]
                  .map((item) =>
                      DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reset'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _PayrollColors.blue,
              side: const BorderSide(color: Color(0xFFD6DDEA)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 17, vertical: 17),
            ),
          ),
        ],
      );
    });
  }

  void _showMobileFilters(BuildContext context, String monthValue) {
    showModalBottomSheet<void>(context: context, backgroundColor: Colors.transparent, builder: (sheetContext) => SafeArea(top: false, child: Container(padding: const EdgeInsets.fromLTRB(16, 14, 16, 20), decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(22))), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Filter payroll', style: TextStyle(color: _PayrollColors.navy, fontSize: 18, fontWeight: FontWeight.w700)), const SizedBox(height: 16),
      DropdownButtonFormField<String>(initialValue: monthValue, onChanged: onMonthChanged, decoration: _fieldDecoration().copyWith(labelText: 'Month'), items: months.map((item) => DropdownMenuItem(value: item.key, child: Text(item.label))).toList()), const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: employee, onChanged: onEmployeeChanged, decoration: _fieldDecoration().copyWith(labelText: 'Employee'), items: employees.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList()), const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: status, onChanged: onStatusChanged, decoration: _fieldDecoration().copyWith(labelText: 'Status'), items: const ['All Status','Draft','Pending','Paid'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList()), const SizedBox(height: 16),
      FilledButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Apply filters')),
    ]))));
  }
}

class _FilterField extends StatelessWidget {
  const _FilterField(
      {required this.label, required this.width, required this.child});
  final String label;
  final double width;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF596176), fontSize: 13)),
          const SizedBox(height: 8),
          child,
        ]),
      );
}

InputDecoration _fieldDecoration() => InputDecoration(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: Color(0xFFD8DEE9))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: _PayrollColors.blue)),
    );

class _MobilePayrollList extends StatelessWidget {
  const _MobilePayrollList({required this.rows, required this.onMarkPaid});
  final List<_PayrollRow> rows;
  final ValueChanged<_PayrollRow> onMarkPaid;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox(
          height: 140,
          child: Center(child: Text('No payroll rows match these filters.')));
    }
    return Column(
      children: rows
          .asMap()
          .entries
          .map(
            (e) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE5EAF3)),
                  borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('#${e.key + 1}',
                        style: const TextStyle(
                            color: Color(0xFF9DAABF),
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFFEAF1FF),
                        child: Text(
                            e.value.name.isEmpty ? '?' : e.value.name.substring(0, 1),
                            style: const TextStyle(
                                color: _PayrollColors.blue,
                                fontWeight: FontWeight.w800))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(e.value.name,
                              style: const TextStyle(
                                  color: _PayrollColors.navy,
                                  fontWeight: FontWeight.w700)),
                          Text('${e.value.code} • ${e.value.department}',
                              style: const TextStyle(
                                  color: Color(0xFF657087), fontSize: 11)),
                        ])),
                    _PayStatus(status: e.value.status),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                      e.value.status == 'Paid'
                          ? 'Salary ${e.value.salary}  →  Net ${e.value.netPay}'
                          : 'Salary ${e.value.salary}  →  Updated ${e.value.netPay} · Earned to Date ${e.value.earnedToDate}',
                      style: const TextStyle(
                          color: _PayrollColors.navy,
                          fontWeight: FontWeight.w600)),
                  Text(
                      'Paid ${e.value.paidDays}/${e.value.workingDays} days • LOP ${e.value.lopDays}',
                      style: const TextStyle(
                          color: Color(0xFF657087), fontSize: 12)),
                  Text('Daily ${e.value.dailyRate}',
                      style: const TextStyle(color: Color(0xFF657087), fontSize: 12)),
                  if (e.value.status == 'Pending') ...[
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: () => onMarkPaid(e.value),
                      style: FilledButton.styleFrom(
                          backgroundColor: _PayrollColors.blue),
                      child: const Text('Mark paid'),
                    ),
                  ],
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _PayrollTable extends StatefulWidget {
  const _PayrollTable({required this.rows, required this.onMarkPaid, required this.year, required this.month});
  final List<_PayrollRow> rows;
  final ValueChanged<_PayrollRow> onMarkPaid;
  final int year, month;

  @override
  State<_PayrollTable> createState() => _PayrollTableState();
}

class _PayrollTableState extends State<_PayrollTable> {
  final _tableHeaderScrollCtrl = ScrollController();
  final _tableBodyScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _tableBodyScrollCtrl.addListener(() {
      if (_tableHeaderScrollCtrl.hasClients &&
          (_tableHeaderScrollCtrl.offset - _tableBodyScrollCtrl.offset).abs() > 0.5) {
        _tableHeaderScrollCtrl.jumpTo(_tableBodyScrollCtrl.offset);
      }
    });
  }

  @override
  void dispose() {
    _tableHeaderScrollCtrl.dispose();
    _tableBodyScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE3E7EF)),
            borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SingleChildScrollView(
              controller: _tableHeaderScrollCtrl,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: const SizedBox(
                width: 1940,
                child: _PayrollTableHeader(),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: SingleChildScrollView(
                controller: _tableBodyScrollCtrl,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1940,
                  child: SingleChildScrollView(
                    primary: false,
                    child: Column(
                      children: [
                        if (widget.rows.isEmpty)
                          const SizedBox(
                              height: 160,
                              child: Center(
                                  child: Text(
                                      'No payroll rows match these filters.')))
                        else
                          ...widget.rows.asMap().entries.map((e) =>
                              _PayrollTableRow(index: e.key + 1, row: e.value, onMarkPaid: widget.onMarkPaid, year: widget.year, month: widget.month)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _PayrollTableHeader extends StatelessWidget {
  const _PayrollTableHeader();
  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        color: const Color(0xFFFCFCFD),
        child: const Row(children: [
          _Cell(width: 70, child: Text('S.No', style: _headStyle)),
          _Cell(width: 250, child: Text('Employee', style: _headStyle)),
          _Cell(width: 150, child: Text('Department', style: _headStyle)),
          _Cell(width: 140, child: Text('Monthly salary', style: _headStyle)),
          _Cell(width: 120, child: Text('Daily salary', style: _headStyle)),
          _Cell(width: 140, child: Text('Earned to date', style: _headStyle)),
          _Cell(width: 150, child: Text('Period', style: _headStyle)),
          _Cell(width: 110, child: Text('Working', style: _headStyle)),
          _Cell(width: 110, child: Text('Paid days', style: _headStyle)),
          _Cell(width: 90, child: Text('LOP', style: _headStyle)),
          _Cell(width: 140, child: Text('Deductions', style: _headStyle)),
          _Cell(width: 140, child: Text('Updated Salary', style: _headStyle)),
          _Cell(width: 120, child: Text('Status', style: _headStyle)),
          _Cell(width: 140, child: Text('Action', style: _headStyle)),
        ]),
      );
}

class _PayrollTableRow extends StatelessWidget {
  const _PayrollTableRow({required this.index, required this.row, required this.onMarkPaid, required this.year, required this.month});
  final int index;
  final _PayrollRow row;
  final ValueChanged<_PayrollRow> onMarkPaid;
  final int year, month;

  @override
  Widget build(BuildContext context) => Container(
        height: 64,
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE6E9EF)))),
        child: Row(
          children: [
            _Cell(
              width: 70,
              child: Text('$index', style: const TextStyle(color: Color(0xFF596176), fontSize: 13)),
            ),
            _Cell(
              width: 250,
              child: Row(children: [
                CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFFE8EEF8),
                    child: Text(
                        row.name.isEmpty ? '?' : row.name.substring(0, 1),
                        style: const TextStyle(
                            color: _PayrollColors.navy,
                            fontWeight: FontWeight.w700))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Color(0xFF11131A),
                                fontWeight: FontWeight.w600)),
                        Text(row.code,
                            style: const TextStyle(
                                color: Color(0xFF596176), fontSize: 12)),
                      ]),
                ),
              ]),
            ),
            _Cell(width: 150, child: Text(row.department, style: _cellStyle)),
            _Cell(width: 140, child: Text(row.salary, style: _cellStyle)),
            _Cell(width: 120, child: Text(row.dailyRate, style: _cellStyle)),
            _Cell(width: 140, child: Text(row.earnedToDate, style: _cellStyle)),
            _Cell(
              width: 150,
              child: row.periodLabel != null
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F0FE),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(row.periodLabel!, style: const TextStyle(color: _PayrollColors.blue, fontSize: 11, fontWeight: FontWeight.w600)),
                    )
                  : Text(_formatPeriod(row.periodStart, row.periodEnd), style: const TextStyle(color: Color(0xFF596176), fontSize: 12)),
            ),
            _Cell(
                width: 110,
                child: Text('${row.workingDays}', style: _cellStyle)),
            _Cell(
                width: 110, child: Text('${row.paidDays}', style: _cellStyle)),
            _Cell(width: 90, child: Text('${row.lopDays}', style: _cellStyle)),
            _Cell(
                width: 140, child: Text(row.deductions, style: _cellStyle)),
            _Cell(
                width: 140,
                child: Text(row.netPay,
                    style: const TextStyle(
                        color: _PayrollColors.navy,
                        fontWeight: FontWeight.w700,
                        fontSize: 13))),
            _Cell(width: 120, child: _PayStatus(status: row.status)),
            _Cell(
              width: 180,
              child: row.status == 'Pending'
                  ? FilledButton(
                      onPressed: () => onMarkPaid(row),
                      style: FilledButton.styleFrom(
                        backgroundColor: _PayrollColors.blue,
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('Mark paid', style: TextStyle(fontSize: 12)),
                    )
                  : const Text('–', style: TextStyle(color: Color(0xFF596176))),
            ),
          ],
        ),
      );

  // Converts 'YYYY-MM-DD' to 'M/DD' display, e.g. '2026-09-30' → '9/30'
  String _formatPeriod(String? start, String? end) {
    String fmt(String? d) {
      if (d == null || d.length < 10) return '–';
      final m = int.tryParse(d.substring(5, 7)) ?? 0;
      final day = d.substring(8, 10);
      return '$m/$day';
    }
    return '${fmt(start)} – ${fmt(end)}';
  }

  void _showCustomCycleDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _CustomCycleDialog(row: row, year: year, month: month),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.width, required this.child});
  final double width;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: width,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14), child: child));
}

class _PayStatus extends StatelessWidget {
  const _PayStatus({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = status == 'Paid'
        ? const Color(0xFF188226)
        : status == 'Pending'
            ? const Color(0xFFFF6500)
            : const Color(0xFF596176);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(5)),
      child: Text(status, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

class _PayrollRow {
  const _PayrollRow({
    required this.itemId,
    required this.profileId,
    required this.name,
    required this.code,
    required this.department,
    required this.salary,
    required this.workingDays,
    required this.paidDays,
    required this.lopDays,
    required this.deductions,
    required this.netPay,
    required this.dailyRate,
    required this.earnedToDate,
    required this.status,
    this.salaryType = 'standard',
    this.periodLabel,
    this.periodStart,
    this.periodEnd,
  });

  final int? itemId, profileId;
  final String name, code, department, salary, deductions, netPay, dailyRate, earnedToDate, status;
  final int workingDays, paidDays, lopDays;
  final String salaryType;
  final String? periodLabel, periodStart, periodEnd;

  factory _PayrollRow.fromApi(Map<String, dynamic> json) {
    int asInt(dynamic value) =>
        value is int ? value : int.tryParse('$value') ?? 0;
    final rawId = json['id'];
    final rawProfileId = json['profileId'];
    return _PayrollRow(
      itemId: rawId == null ? null : asInt(rawId),
      profileId: rawProfileId == null ? null : asInt(rawProfileId),
      name: (json['name'] ?? '').toString(),
      code: (json['employeeCode'] ?? '').toString(),
      department: (json['department'] ?? '').toString(),
      salary: (json['salary'] ?? 'Not Set').toString(),
      workingDays: asInt(json['workingDays']),
      paidDays: asInt(json['paidDays']),
      lopDays: asInt(json['lopDays']),
      deductions: (json['deductionsLabel'] ?? '–').toString(),
      netPay: (json['netPayLabel'] ?? '–').toString(),
      dailyRate: (json['dailyRateLabel'] ?? '–').toString(),
      earnedToDate: (json['earnedToDateLabel'] ?? '–').toString(),
      status: (json['status'] ?? 'Draft').toString(),
      salaryType: (json['salaryType'] ?? 'standard').toString(),
      periodLabel: json['periodLabel']?.toString(),
      periodStart: json['periodStart']?.toString(),
      periodEnd: json['periodEnd']?.toString(),
    );
  }
}

const _headStyle = TextStyle(
    color: Color(0xFF11131A), fontSize: 13, fontWeight: FontWeight.w600);
const _cellStyle = TextStyle(color: Color(0xFF272B35), fontSize: 13);

class _CustomCycleDialog extends StatefulWidget {
  const _CustomCycleDialog({required this.row, required this.year, required this.month});
  final _PayrollRow row;
  final int year, month;

  @override
  State<_CustomCycleDialog> createState() => _CustomCycleDialogState();
}

class _CustomCycleDialogState extends State<_CustomCycleDialog> {
  late TextEditingController _startCtrl;
  late TextEditingController _endCtrl;
  bool _loading = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCtrl = TextEditingController();
    _endCtrl = TextEditingController();
    _fetchExisting();
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchExisting() async {
    if (widget.row.profileId == null) return;
    setState(() => _loading = true);
    try {
      final data = await HrmsPayrollApi.getCustomCycle(
        widget.row.profileId!,
        year: widget.year,
        month: widget.month,
      );
      if (!mounted) return;
      if (data != null) {
        _startCtrl.text = data['periodStart']?.toString() ?? '';
        _endCtrl.text = data['periodEnd']?.toString() ?? '';
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (widget.row.profileId == null) return;
    final start = _startCtrl.text.trim();
    final end = _endCtrl.text.trim();
    if (start.isEmpty || end.isEmpty) {
      setState(() => _error = 'Both dates are required');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await HrmsPayrollApi.setCustomCycle(
        widget.row.profileId!,
        year: widget.year,
        month: widget.month,
        periodStart: start,
        periodEnd: end,
      );
      if (!mounted) return;
      setState(() { _loading = false; _saved = true; });
    } catch (err) {
      if (!mounted) return;
      setState(() { _loading = false; _error = err.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(ctrl.text) ?? DateTime(widget.year, widget.month, 1),
      firstDate: DateTime(widget.year - 1),
      lastDate: DateTime(widget.year + 1),
    );
    if (picked != null && mounted) {
      ctrl.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Custom cycle – ${widget.row.name}'),
      content: SizedBox(
        width: 360,
        child: _saved
            ? const Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle, color: Color(0xFF188226), size: 40),
                SizedBox(height: 8),
                Text('Custom period saved. Regenerate payroll to apply.', textAlign: TextAlign.center),
              ])
            : Column(mainAxisSize: MainAxisSize.min, children: [
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 8),
                const Text(
                  'Override the pay period for this employee for this month only.',
                  style: TextStyle(color: Color(0xFF596176), fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _startCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Period start (YYYY-MM-DD)',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  onTap: () => _pickDate(_startCtrl),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _endCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Period end (YYYY-MM-DD)',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  onTap: () => _pickDate(_endCtrl),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_saved ? 'Close' : 'Cancel'),
        ),
        if (!_saved)
          FilledButton(
            onPressed: _loading ? null : _save,
            child: const Text('Save'),
          ),
      ],
    );
  }
}
