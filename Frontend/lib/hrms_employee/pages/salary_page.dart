import 'package:flutter/material.dart';
import '../../services/hrms_payslip_api.dart';

import '../shared/employee_ui.dart';

class EmployeeSalaryPage extends StatelessWidget {
  const EmployeeSalaryPage({super.key});

  @override
  Widget build(BuildContext context) => const EmployeeScaffold(
        route: '/employee/salary',
        title: 'Salary',
        subtitle: 'Payslips and salary details',
        desktop: _SalaryView(mobile: false, showPayslip: true),
        mobile: _SalaryView(mobile: true, showPayslip: true),
      );
}

class _SalaryView extends StatelessWidget {
  const _SalaryView({required this.mobile, required this.showPayslip});
  final bool mobile;
  final bool showPayslip;

  static void openPayslipSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, 4, 22, 28),
          child: SingleChildScrollView(child: _RecentPayslipsCard()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewButton =
        _ViewPayslipButton(
          onPressed: () => _SalaryView.openPayslipSheet(context),
        );

    if (mobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const MobileEmployeeHeader(showGreeting: false),
        const SizedBox(height: 22),
        const Text('Payslips and salary details',
            style: TextStyle(color: employeeMuted, fontSize: 18)),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Expanded(
            child: Text('Salary',
                style: TextStyle(
                    color: employeeNavy,
                    fontSize: 34,
                    height: 1,
                    fontWeight: FontWeight.w800)),
          ),
          viewButton,
        ]),
        const SizedBox(height: 18),
        const _NetPayBanner(mobile: true),
        const SizedBox(height: 16),
        const _SalaryOverviewCard(),
        const SizedBox(height: 16),
        const _RecentPayslipsCard(),
        const SizedBox(height: 18),
        const Center(
          child: Text(
            'Payslips are available for download after payroll processing.',
            textAlign: TextAlign.center,
            style: TextStyle(color: employeeMuted, fontSize: 12),
          ),
        ),
      ]);
    }

    if (!showPayslip) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: const [
          Expanded(child: _NetPayBanner(mobile: false)),
          SizedBox(width: 20),
          Expanded(
            child: _SalaryOverviewCard(),
          ),
        ])),
      const SizedBox(height: 20),
      const _RecentPayslipsCard(),
      const SizedBox(height: 14),
      const Center(
        child: Text(
          'Payslips are available for download after payroll processing.',
          style: TextStyle(color: employeeMuted, fontSize: 12),
        ),
      ),
    ]);
  }
}

class _ViewPayslipButton extends StatelessWidget {
  const _ViewPayslipButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.description_outlined, size: 21),
        label: const Text('View Payslip',
            style: TextStyle(fontWeight: FontWeight.w700)),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF052D70),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
}

String _money(dynamic value) => '₹${(num.tryParse('$value') ?? 0).toStringAsFixed(0)}';
Map<String, dynamic> _dataMap(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : const {};
Map<String, dynamic> _currentPayroll(Map<String, dynamic>? summary) {
  final live = _dataMap(summary?['livePayroll']);
  if (live.isNotEmpty) {
    return {
      'monthly_salary': live['monthlySalary'], 'deductions': live['deductions'],
      'lop_days': live['lopDays'],
      'net_pay': live['netPay'], 'daily_rate': live['dailyRate'],
      'working_days': live['workingDays'], 'paid_days_to_date': live['paidDaysToDate'],
      'earned_to_date': live['earnedToDate'], 'status': '${live['status']}'.toLowerCase(),
      'pay_month': live['periodStart']?.toString().substring(5, 7),
      'pay_year': live['periodStart']?.toString().substring(0, 4),
    };
  }
  return _dataMap(summary?['payroll']);
}

class _NetPayBanner extends StatefulWidget {
  const _NetPayBanner({required this.mobile});
  final bool mobile;
  @override State<_NetPayBanner> createState() => _NetPayBannerState();
}
class _NetPayBannerState extends State<_NetPayBanner> {
  late final Future<Map<String, dynamic>> _data = HrmsPayslipApi.summary();

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(future: _data, builder: (context, snapshot) {
    final payroll = _currentPayroll(snapshot.data);
    final paid = payroll['status'] == 'paid';
    return Container(
        constraints: BoxConstraints(minHeight: widget.mobile ? 190 : 285),
        padding: EdgeInsets.all(widget.mobile ? 18 : 28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF063B82), Color(0xFF031C54)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26002061),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(paid ? 'Net Pay' : 'Updated Salary',
                    style: TextStyle(
                        color: Colors.white, fontSize: widget.mobile ? 18 : 22)),
                const SizedBox(height: 10),
                if (payroll.isEmpty)
                  Text(snapshot.data?['reviewRequired'] == true ? 'Payroll under review' : 'Payroll not generated', style: TextStyle(color: Colors.white, fontSize: widget.mobile ? 22 : 28, fontWeight: FontWeight.w700))
                else ...[
                  Text(_money(payroll['net_pay']), maxLines: 1, style: TextStyle(color: Colors.white, fontSize: widget.mobile ? 38 : 50, fontWeight: FontWeight.w800)),
                  Text('Earned to Date: ${payroll['earned_to_date'] == null ? '–' : _money(payroll['earned_to_date'])}', style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 8),
                  Text('${payroll['pay_month']}/${payroll['pay_year']}',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: widget.mobile ? 18 : 21,
                        fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 13),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF005A43),
                    border: Border.all(color: const Color(0xFF008F63)),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(radius: 5, backgroundColor: paid ? const Color(0xFF1DDA83) : const Color(0xFFB7C6DF)),
                    const SizedBox(width: 8),
                    Text(paid ? 'PAID' : 'UPDATES DAILY', style: TextStyle(color: paid ? const Color(0xFF2DE38E) : const Color(0xFFD6E0EF), fontWeight: FontWeight.w700)),
                  ]),
                ),
              ],
            ),
          ),
          SizedBox(width: widget.mobile ? 8 : 24),
          _WalletArtwork(size: widget.mobile ? 118 : 190),
        ]),
      );
  });
}

class _WalletArtwork extends StatelessWidget {
  const _WalletArtwork({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0x1F61A8FF),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x33489EFF)),
            ),
          ),
          Icon(Icons.account_balance_wallet_rounded,
              color: const Color(0xFF9DBDE8), size: size * .56),
          Positioned(
            top: size * .10,
            right: size * .30,
            child: _Coin(size: size * .27),
          ),
          Positioned(
            top: size * .38,
            right: size * .02,
            child: _Coin(size: size * .25),
          ),
        ]),
      );
}

class _Coin extends StatelessWidget {
  const _Coin({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF789FD3),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFAEC7E8)),
        ),
        child: Text('₹',
            style: TextStyle(
                color: const Color(0xFF315C98),
                fontSize: size * .48,
                fontWeight: FontWeight.w800)),
      );
}

class _SalaryTile extends StatelessWidget {
  const _SalaryTile({required this.label, required this.value, this.valueColor, this.highlight = false});
  final String label, value;
  final Color? valueColor;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: highlight ? BoxDecoration(color: employeeBlue.withValues(alpha: 0.06)) : null,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: employeeMuted, fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: valueColor ?? const Color(0xFF1A2340))),
    ]),
  );
}

class _SalaryOverviewCard extends StatefulWidget {
  const _SalaryOverviewCard();
  @override State<_SalaryOverviewCard> createState() => _SalaryOverviewCardState();
}
class _SalaryOverviewCardState extends State<_SalaryOverviewCard> {
  late final Future<Map<String, dynamic>> _data = HrmsPayslipApi.summary();

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(future: _data, builder: (context, snapshot) {
    final payroll = _currentPayroll(snapshot.data);
    return SizedBox(width: double.infinity, child: EmployeeCard(
        padding: EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SalaryHeading('Salary Overview'), const SizedBox(height: 10),
          if (payroll.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(snapshot.data?['reviewRequired'] == true ? 'Admin needs to correct an existing payroll record before salary payment details can be shown.' : 'Payroll has not been generated for this employee.', style: const TextStyle(color: employeeMuted))) else ...[
            const SizedBox(height: 4),
            IntrinsicHeight(
              child: Row(children: [
                Expanded(child: _SalaryTile(
                  label: 'Salary / Month',
                  value: _money(payroll['monthly_salary']),
                )),
                const VerticalDivider(width: 1, color: employeeLine),
                Expanded(child: _SalaryTile(
                  label: 'Deduction',
                  value: '−${_money(payroll['deductions'])} / ${payroll['lop_days'] ?? '–'} ${num.tryParse('${payroll['lop_days']}') == 1 ? 'day' : 'days'}',
                  valueColor: const Color(0xFFE05252),
                )),
                const VerticalDivider(width: 1, color: employeeLine),
                Expanded(child: _SalaryTile(
                  label: 'Updated Salary',
                  value: _money(payroll['net_pay']),
                  valueColor: employeeBlue,
                  highlight: true,
                )),
              ]),
            ),
            const SizedBox(height: 10),
            LabeledValue('Total Working Days', '${payroll['working_days'] ?? '–'}'),
            const Divider(height: 1, color: employeeLine),
            LabeledValue('Earned to Date', '${payroll['earned_to_date'] == null ? '–' : _money(payroll['earned_to_date'])} / ${payroll['paid_days_to_date'] ?? '–'} ${(num.tryParse('${payroll['paid_days_to_date']}') == 1) ? 'day' : 'days'}'),
          ],
        ]),
      ));
  });
}

class _SalaryBreakdownCard extends StatefulWidget {
  const _SalaryBreakdownCard();
  @override State<_SalaryBreakdownCard> createState() => _SalaryBreakdownCardState();
}
class _SalaryBreakdownCardState extends State<_SalaryBreakdownCard> {
  late final Future<Map<String, dynamic>> _data = HrmsPayslipApi.summary();

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(future: _data, builder: (context, snapshot) {
    final compensation = _dataMap(snapshot.data?['compensation']);
    final payroll = _currentPayroll(snapshot.data);
    return SizedBox(width: double.infinity, child: EmployeeCard(
        padding: EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SalaryHeading('Salary Breakdown'), const SizedBox(height: 10),
          if (compensation.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Salary not configured. Contact Admin to set your compensation.', style: TextStyle(color: employeeMuted)))
          else if (payroll.isEmpty) ...[
            LabeledValue('Monthly Salary', _money(compensation['monthly_salary'])),
            const Divider(height: 1, color: employeeLine),
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(snapshot.data?['reviewRequired'] == true ? 'Payroll correction required.' : 'Payroll not generated yet.', style: const TextStyle(color: employeeMuted))),
          ] else ...[
            LabeledValue('Monthly Salary', _money(payroll['monthly_salary'])), const Divider(height: 1, color: employeeLine),
            LabeledValue('Working Days', '${payroll['working_days'] ?? '–'}'), const Divider(height: 1, color: employeeLine),
            LabeledValue('Paid days to date', '${payroll['paid_days_to_date'] ?? '–'}'), const Divider(height: 1, color: employeeLine),
            LabeledValue('Leave Deduction', '−${_money(payroll['deductions'])}'),
            const Divider(height: 1, color: employeeLine),
            LabeledValue('Updated Salary', _money(payroll['net_pay'])),
            const Divider(height: 1, color: employeeLine),
            LabeledValue('Earned to Date', payroll['earned_to_date'] == null ? '–' : _money(payroll['earned_to_date'])),
          ],
        ]),
      ));
  });
}

class _SalaryHeading extends StatelessWidget {
  const _SalaryHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: employeeNavy, fontSize: 20, fontWeight: FontWeight.w800));
}

class _RecentPayslipsCard extends StatefulWidget {
  const _RecentPayslipsCard();
  @override
  State<_RecentPayslipsCard> createState() => _RecentPayslipsCardState();
}

class _RecentPayslipsCardState extends State<_RecentPayslipsCard> {
  late Future<List<Map<String, dynamic>>> _items = HrmsPayslipApi.mine();
  void _refresh() {
    final next = HrmsPayslipApi.mine();
    if (!mounted) return;
    setState(() {
      _items = next;
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _items,
    builder: (context, snapshot) => SizedBox(width: double.infinity, child: EmployeeCard(
        padding: EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SalaryHeading('Recent Payslips'),
          SizedBox(height: 10),
          if (snapshot.connectionState != ConnectionState.done) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (snapshot.hasError) const Padding(padding: EdgeInsets.all(16), child: Text('Unable to load payslips', style: TextStyle(color: employeeMuted)))
          else if ((snapshot.data ?? const <Map<String, dynamic>>[]).isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No paid payslips are available yet.', style: TextStyle(color: employeeMuted)))
          else ...((snapshot.data ?? const <Map<String, dynamic>>[]).take(3).map((item) => _LivePayslipRow(item: item, onChanged: _refresh))),
        ]),
      )));
}

class _LivePayslipRow extends StatefulWidget {
  const _LivePayslipRow({required this.item, required this.onChanged});
  final Map<String, dynamic> item;
  final VoidCallback onChanged;
  @override State<_LivePayslipRow> createState() => _LivePayslipRowState();
}
class _LivePayslipRowState extends State<_LivePayslipRow> {
  bool busy = false;
  String get status => '${widget.item['request_status']}';
  String get month => '${widget.item['pay_month']}/${widget.item['pay_year']}';
  Future<void> download(BuildContext context) async {
    final canRequest = status == 'not_requested' || status == 'rejected';
    if (canRequest) {
      final retrying = status == 'rejected';
      final confirm = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(title: Text(retrying ? 'Send payslip request again?' : 'Send payslip request?'), content: Text(retrying ? 'Your previous request was rejected. Send a new download request to Admin?' : 'Send this download request to Admin for approval?'), actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Send request'))]));
      if (confirm != true || !mounted || !context.mounted) return;
    }
    setState(() => busy = true);
    try {
      if (status == 'approved') { await HrmsPayslipApi.download(int.parse('${widget.item['id']}')); if (!context.mounted) return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payslip download started.'))); }
      else if (canRequest) { await HrmsPayslipApi.request(int.parse('${widget.item['id']}')); widget.onChanged(); }
      else { if (!context.mounted) return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your request is awaiting Admin approval.'))); }
    } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(month, style: const TextStyle(color: employeeNavy, fontWeight: FontWeight.w800)), Text(status == 'approved' ? 'Approved for download' : status == 'pending' ? 'Approval pending' : status == 'rejected' ? 'Request rejected' : 'Request download approval', style: const TextStyle(color: employeeMuted, fontSize: 12))])), Text('₹${widget.item['net_pay']}', style: const TextStyle(color: employeeNavy, fontWeight: FontWeight.w700)), const SizedBox(width: 7), IconButton(tooltip: status == 'approved' ? 'Download payslip' : 'Request payslip', onPressed: busy ? null : () => download(context), icon: Icon(Icons.download_rounded, color: status == 'approved' ? const Color(0xFF158C20) : employeeBlue))]));
}
