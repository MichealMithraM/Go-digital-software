import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:godigital_portal/services/authenticated_http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../services/api_config.dart';
import '../../../services/auth_service.dart';
import '../../../services/hrms_approvals_api.dart';
import '../../shared/widgets/admin_top_nav.dart';
import '../../shared/widgets/admin_page_scroll_view.dart';

part 'approvals_workspace.dart';

abstract final class _ApprovalsColors {
  static const blue = Color(0xFF075EF7);
  static const navy = Color(0xFF061457);
  static const page = Color(0xFFF7F9FD);
}

class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({super.key});

  static Widget builder(BuildContext context) => const ApprovalsPage();

  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  // 0 = leave, 1 = corrections
  int _activeTab = 0;
  bool leaveRequests = true;
  String requestCategory = 'leave';
  String employee = 'All Employees';
  String status = 'All Status';
  String dateRange = 'All Dates';
  String period = 'Today';
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  String searchQuery = '';
  List<_ApprovalRequest> requests = [];
  List<String> employeeNames = const ['All Employees'];
  List<_ApprovalRequest> _pendingLeaveItems = [];
  List<_ApprovalRequest> _pendingPermissionItems = [];
  int _pendingLeaveCount = 0;
  int _pendingExtraCount = 0;
  int _pendingPermissionCount = 0;
  int kpiPending = 0;
  int kpiApproved = 0;
  int kpiRejected = 0;
  bool loading = true;
  String? error;
  int _loadRequest = 0;
  bool _loadedOnce = false;
  Timer? _refreshTimer;
  bool _refreshing = false;

  // Correction requests
  List<Map<String, dynamic>> _corrections = [];
  bool _correctionsLoading = false;
  int _correctionsLoadRequest = 0;
  int _correctionsPendingCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCorrections();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshRequests(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshRequests() async {
    if (_refreshing || loading || _correctionsLoading || error != null) return;
    _refreshing = true;
    try {
      await Future.wait([
        _load(background: true),
        _loadCorrections(background: true),
      ]);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _loadCorrections({bool background = false}) async {
    final request = ++_correctionsLoadRequest;
    if (!background) setState(() => _correctionsLoading = true);
    try {
      final token = context.read<AuthService>().token ?? '';
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/attendance/correction-requests'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted || request != _correctionsLoadRequest) return;
      if (response.statusCode == 200 && body['success'] == true) {
        final items = (body['data']?['items'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        setState(() {
          _corrections = items;
          _correctionsPendingCount = items.where((e) => e['status'] == 'pending').length;
          _correctionsLoading = false;
        });
      } else {
        setState(() => _correctionsLoading = false);
      }
    } catch (_) {
      if (mounted && request == _correctionsLoadRequest) {
        setState(() => _correctionsLoading = false);
      }
    }
  }

  Future<void> _reviewCorrection(int id, String action) async {
    try {
      final token = context.read<AuthService>().token ?? '';
      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/attendance/correction-requests/$id/$action'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (response.statusCode == 200 && body['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(body['message']?.toString() ?? 'Done')),
        );
        _loadCorrections();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(body['message']?.toString() ?? 'Failed')),
        );
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connection error')));
    }
  }

  Future<void> _load({bool background = false}) async {
    final request = ++_loadRequest;
    final selectedCategory = requestCategory;
    final rangeStart = period == 'Today' ? _selectedDate : DateTime(_selectedDate.year, _selectedDate.month);
    final rangeEnd = period == 'Today' ? _selectedDate : DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
    final startDate = period == 'All' ? null : DateFormat('yyyy-MM-dd').format(rangeStart);
    final endDate = period == 'All' ? null : DateFormat('yyyy-MM-dd').format(rangeEnd);
    if (!background) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final results = await Future.wait([
        HrmsApprovalsApi.list(leaveTab: true, employee: employee, status: status, startDate: startDate, endDate: endDate),
        HrmsApprovalsApi.list(leaveTab: false, employee: employee, status: status, startDate: startDate, endDate: endDate),
        HrmsApprovalsApi.list(tab: 'permission', employee: employee, status: status, startDate: startDate, endDate: endDate),
        HrmsApprovalsApi.list(leaveTab: true, employee: 'All Employees', status: 'pending'),
        HrmsApprovalsApi.list(leaveTab: false, employee: 'All Employees', status: 'pending'),
        HrmsApprovalsApi.list(tab: 'permission', employee: 'All Employees', status: 'pending'),
      ]);
      final leave = results[0];
      final extra = results[1];
      final permissions = results[2];
      final leavePending = results[3];
      final extraPending = results[4];
      final permissionPending = results[5];
      final leaveItems = _parse(leave['items']);
      final extraItems = _parse(extra['items']);
      final permissionItems = _parse(permissions['items']);
      final kpis = Map<String, dynamic>.from(leave['kpis'] as Map? ?? {});
      final names = <String>{'All Employees'};
      names.addAll((leave['employees'] as List? ?? []).map((e) => e.toString()));
      names.addAll((extra['employees'] as List? ?? []).map((e) => e.toString()));
      names.addAll((permissions['employees'] as List? ?? []).map((e) => e.toString()));
      if (!mounted || request != _loadRequest) return;
      setState(() {
        requests = selectedCategory == 'leave' ? leaveItems : selectedCategory == 'extra' ? extraItems : permissionItems;
        _pendingLeaveItems = _parse(leavePending['items']);
        _pendingPermissionItems = _parse(permissionPending['items']);
        _pendingLeaveCount = (leavePending['items'] as List? ?? []).length;
        _pendingExtraCount = (extraPending['items'] as List? ?? []).length;
        _pendingPermissionCount = (permissionPending['items'] as List? ?? []).length;
        employeeNames = names.toList();
        if (!employeeNames.contains(employee)) employee = 'All Employees';
        kpiPending = _asInt(kpis['pending']);
        kpiApproved = _asInt(kpis['approved']);
        kpiRejected = _asInt(kpis['rejected']);
        loading = false;
        _loadedOnce = true;
      });
    } catch (err) {
      if (!mounted || request != _loadRequest || background) return;
      setState(() {
        error = err.toString().replaceFirst('Exception: ', '');
        loading = false;
      });
    }
  }

  void _openPending() {
    searchQuery = '';
    employee = 'All Employees';
    status = 'Pending';
    period = 'This Month';
    requests = [];
    _load();
  }

  List<_ApprovalRequest> _parse(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => _ApprovalRequest.fromApi(Map<String, dynamic>.from(item)))
        .toList();
  }

  int _asInt(dynamic value) =>
      value is int ? value : int.tryParse('$value') ?? 0;

  Future<void> _updateStatus(_ApprovalRequest request, String nextStatus) async {
    try {
      await HrmsApprovalsApi.review(request.requestId, nextStatus);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${request.name} was notified: request ${nextStatus.toLowerCase()}'),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  bool _matchesWorkspaceFilters(_ApprovalRequest request) {
    final query = searchQuery.trim().toLowerCase();
    final searchable =
        '${request.name} ${request.id} ${request.type} ${request.reason}';
    return searchable.toLowerCase().contains(query) &&
        _matchesPeriod(request, period, selected: _selectedDate);
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: _ApprovalsColors.page,
      bottomNavigationBar: mobile ? const AdminMobileBottomNav(activeRoute: '/admin/approvals') : null,
      body: Column(
        children: [
          const AdminTopNav(activeRoute: '/admin/approvals'),
          Expanded(
            child: loading && !_loadedOnce
                ? const Center(child: CircularProgressIndicator())
                : error != null && requests.isEmpty
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
                    : MediaQuery.sizeOf(context).width >= 1000
                        ? _ApprovalsWorkspace(
                            category: _activeTab == 1 ? 'corrections' : requestCategory,
                            counts: [
                              _pendingLeaveItems.where(_matchesWorkspaceFilters).length,
                              _pendingPermissionItems.where(_matchesWorkspaceFilters).length,
                            ],
                            pendingCount: requestCategory == 'leave'
                                ? _pendingLeaveCount
                                : _pendingPermissionCount,
                            requests: requests.where(_matchesWorkspaceFilters).toList(),
                            employees: employeeNames, employee: employee, status: status, period: period,
                            loading: loading, error: error,
                            onCategory: (value) { setState(() { _activeTab = value == 'corrections' ? 1 : 0; if (_activeTab == 0 && requestCategory != value) { requestCategory = value; requests = []; } }); if (_activeTab == 1) { _loadCorrections(); } else { _load(); } },
                            onPending: _openPending,
                            onSearch: (value) => setState(() => searchQuery = value),
                            onEmployee: (value) { employee = value; _load(); },
                            onStatus: (value) { status = value; period = 'This Month'; _load(); },
                            onPeriod: (value) { setState(() => period = value); _load(); },
                            selectedDate: _selectedDate,
                            onDate: (value) { setState(() => _selectedDate = value); _load(); },
                            onReset: () { setState(() { searchQuery = ''; employee = 'All Employees'; status = 'All Status'; period = 'Today'; _selectedDate = DateUtils.dateOnly(DateTime.now()); }); _load(); },
                            onReview: _updateStatus,
                            corrections: _CorrectionRequestsPanel(corrections: _corrections.where((c) {
                              if (period == 'All') return true;
                              final d = DateTime.tryParse('${c['attendance_date']}');
                              if (d == null) return true;
                              return d.year == _selectedDate.year && d.month == _selectedDate.month && (period != 'Today' || d.day == _selectedDate.day);
                            }).toList(),
                              pendingCount: _correctionsPendingCount,
                              onStatusSelected: () => setState(() => period = 'This Month'),
                              onPending: _loadCorrections,
                              loading: _correctionsLoading, onApprove: (id) => _reviewCorrection(id, 'approve'), onReject: (id) => _reviewCorrection(id, 'reject')),
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
                                _ApprovalsHeader(
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _MainTabBtn(label: 'Leave & Extra Hours', active: _activeTab == 0, onTap: () => setState(() => _activeTab = 0)),
                                      const SizedBox(width: 10),
                                      Flexible(child: _MainTabBtn(
                                        label: 'Attendance Corrections',
                                        active: _activeTab == 1,
                                        badge: _correctionsPendingCount,
                                        onTap: () { setState(() => _activeTab = 1); _loadCorrections(); },
                                      )),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 17),
                                _ApprovalKpis(
                                  pending: kpiPending,
                                  approved: kpiApproved,
                                  rejected: kpiRejected,
                                ),
                                const SizedBox(height: 14),
                                if (_activeTab == 1) ...[
                                  _CorrectionRequestsPanel(
                                    corrections: _corrections,
                                    pendingCount: _correctionsPendingCount,
                                    onStatusSelected: () => setState(() => period = 'This Month'),
                              onPending: _loadCorrections,
                                    loading: _correctionsLoading,
                                    onApprove: (id) => _reviewCorrection(id, 'approve'),
                                    onReject: (id) => _reviewCorrection(id, 'reject'),
                                  ),
                                ] else ...[
                                if (loading)
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 12),
                                    child: LinearProgressIndicator(minHeight: 2),
                                  ),
                                _RequestsPanel(
                                  employee: employee,
                                  status: status,
                                  dateRange: dateRange,
                                  period: period,
                                  employees: employeeNames,
                                  leaveCount: _pendingLeaveCount,
                                  extraCount: _pendingExtraCount,
                                  permissionCount: _pendingPermissionCount,
                                  requestCategory: requestCategory,
                                  requests: requests.where((request) {
                                    final query = searchQuery.trim().toLowerCase();
                                    return (query.isEmpty || request.name.toLowerCase().contains(query) || request.id.toLowerCase().contains(query) || request.type.toLowerCase().contains(query)) && _matchesPeriod(request, period, selected: _selectedDate);
                                  }).toList(),
                                  searchQuery: searchQuery,
                                  onPending: _openPending,
                                  onSearch: (value) => setState(() => searchQuery = value),
                                  onTabChanged: (value) {
                                    if (requestCategory != value) requests = [];
                                    requestCategory = value;
                                    leaveRequests = value == 'leave';
                                    _load();
                                  },
                                  onEmployeeChanged: (value) {
                                    employee = value!;
                                    _load();
                                  },
                                  onStatusChanged: (value) {
                                    status = value!;
                                    period = 'This Month';
                                    _load();
                                  },
                                  onDateChanged: (value) {
                                    dateRange = value!;
                                    setState(() {});
                                  },
                                  onPeriodChanged: (value) { setState(() => period = value); _load(); },
                                  onReset: () {
                                    employee = 'All Employees';
                                    status = 'All Status';
                                    dateRange = 'All Dates';
                                    period = 'Today';
                                    _load();
                                  },
                                  onApprove: (request) =>
                                      _updateStatus(request, 'Approved'),
                                  onReject: (request) =>
                                      _updateStatus(request, 'Rejected'),
                                ),
                                ], // end else (leave tab)
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
}

class _ApprovalsHeader extends StatelessWidget {
  const _ApprovalsHeader({required this.trailing});
  final Widget trailing;

  @override
  Widget build(BuildContext context) =>
      AdminPageHeader(title: 'Approvals', breadcrumb: 'Approvals', trailing: trailing);
}

class _ApprovalKpis extends StatelessWidget {
  const _ApprovalKpis({
    required this.pending,
    required this.approved,
    required this.rejected,
  });

  final int pending, approved, rejected;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _ApprovalKpi('Pending', '$pending', 'Requests awaiting approval',
          Icons.pending_actions_outlined, _ApprovalsColors.blue),
      _ApprovalKpi('Approved This Month', '$approved', 'Requests approved',
          Icons.check_circle_outline_rounded, Color(0xFF158C20)),
      _ApprovalKpi('Rejected', '$rejected', 'Requests rejected',
          Icons.highlight_off_rounded, Color(0xFFF0182A)),
    ];
    return LayoutBuilder(builder: (_, constraints) {
      final mobile = constraints.maxWidth < 600;
      final columns = mobile
          ? 3
          : constraints.maxWidth < 700
          ? 1
          : constraints.maxWidth < 1050
              ? 2
              : 3;
      final spacing = mobile ? 8.0 : 20.0;
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

class _ApprovalKpi extends StatelessWidget {
  const _ApprovalKpi(
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
                child: Text(value, style: TextStyle(color: color, fontSize: 25, fontWeight: FontWeight.w800)),
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
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: .09),
                      shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 29),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: Color(0xFF596176), fontSize: 15)),
                      Text(value,
                          style: const TextStyle(
                              color: Color(0xFF090B12),
                              fontSize: 29,
                              height: 1.15,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(caption,
                          style: const TextStyle(
                              color: Color(0xFF596176), fontSize: 13)),
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
                    color: _ApprovalsColors.blue,
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ],
        ),
      );
  }
}

class _RequestsPanel extends StatelessWidget {
  const _RequestsPanel({
    required this.requestCategory,
    required this.employee,
    required this.status,
    required this.dateRange,
    required this.period,
    required this.employees,
    required this.leaveCount,
    required this.extraCount,
    required this.permissionCount,
    required this.requests,
    required this.searchQuery,
    required this.onSearch,
    required this.onTabChanged,
    required this.onEmployeeChanged,
    required this.onStatusChanged,
    required this.onDateChanged,
    required this.onPeriodChanged,
    required this.onReset,
    required this.onPending,
    required this.onApprove,
    required this.onReject,
  });

  final String employee, status, dateRange, period;
  final List<String> employees;
  final int leaveCount, extraCount, permissionCount;
  final String requestCategory;
  final List<_ApprovalRequest> requests;
  final String searchQuery;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onTabChanged;
  final ValueChanged<String?> onEmployeeChanged, onStatusChanged, onDateChanged;
  final ValueChanged<String> onPeriodChanged;
  final VoidCallback onReset, onPending;
  final ValueChanged<_ApprovalRequest> onApprove, onReject;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Container(
        padding: EdgeInsets.fromLTRB(
          mobile ? 0 : 22, mobile ? 0 : 16, mobile ? 0 : 22, mobile ? 0 : 14,
        ),
        decoration: BoxDecoration(
          color: mobile ? Colors.transparent : Colors.white,
          border: mobile ? null : Border.all(color: const Color(0xFFE4E7EE)),
          borderRadius: BorderRadius.circular(14),
          boxShadow: mobile ? const [] : const [
            BoxShadow(
                color: Color(0x0A071A72), blurRadius: 16, offset: Offset(0, 6))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ApprovalTabs(
                requestCategory: requestCategory,
                leaveCount: leaveCount,
                extraCount: extraCount,
                permissionCount: permissionCount,
                onChanged: onTabChanged),
            const SizedBox(height: 12),
            _ApprovalFilters(
              employee: employee,
              employees: employees,
              status: status,
              dateRange: dateRange,
              period: period,
              onEmployeeChanged: onEmployeeChanged,
              onStatusChanged: onStatusChanged,
              onDateChanged: onDateChanged,
              onPeriodChanged: onPeriodChanged,
              onReset: onReset,
              onPending: onPending,
              pendingCount: switch (requestCategory) {
                'leave' => leaveCount,
                'extra' => extraCount,
                _ => permissionCount,
              },
              searchQuery: searchQuery,
              onSearch: onSearch,
            ),
            const SizedBox(height: 14),
            if (MediaQuery.sizeOf(context).width < 600)
              _MobileApprovalList(
                  requests: requests, onApprove: onApprove, onReject: onReject)
            else
              _ApprovalTable(
                  requests: requests, onApprove: onApprove, onReject: onReject),
            const SizedBox(height: 18),
            if (MediaQuery.sizeOf(context).width < 600)
              Center(
                  child: Text('${requests.length} requests',
                      style: const TextStyle(
                          color: Color(0xFF596176), fontSize: 12)))
            else
              Row(
                children: [
                  Text(
                      'Showing 1 to ${requests.length} of ${requests.length} requests',
                      style: const TextStyle(
                          color: Color(0xFF596176), fontSize: 13)),
                ],
              ),
          ],
        ),
      );
  }
}

class _MobileApprovalList extends StatelessWidget {
  const _MobileApprovalList(
      {required this.requests,
      required this.onApprove,
      required this.onReject});
  final List<_ApprovalRequest> requests;
  final ValueChanged<_ApprovalRequest> onApprove, onReject;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const SizedBox(
          height: 150,
          child: Center(
              child: Text('No approval requests match these filters.')));
    }
    return Column(
      children: requests
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
                        radius: 21,
                        backgroundColor: const Color(0xFFEAF1FF),
                        child: Text(
                            e.value.name.isEmpty
                                ? '?'
                                : e.value.name.substring(0, 1),
                            style: const TextStyle(
                                color: _ApprovalsColors.blue,
                                fontWeight: FontWeight.w800))),
                    const SizedBox(width: 11),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(e.value.name,
                              style: const TextStyle(
                                  color: _ApprovalsColors.navy,
                                  fontWeight: FontWeight.w700)),
                          Text('${e.value.id} • ${e.value.type}',
                              style: const TextStyle(
                                  color: Color(0xFF657087), fontSize: 10))
                        ])),
                    _RequestStatus(status: e.value.status),
                  ]),
                  const SizedBox(height: 13),
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF5F8FE),
                        borderRadius: BorderRadius.circular(10)),
                    child: Column(children: [
                      Row(children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 15, color: _ApprovalsColors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(e.value.dates,
                                style: const TextStyle(
                                    color: _ApprovalsColors.navy,
                                    fontSize: 11))),
                        Text(e.value.duration,
                            style: const TextStyle(
                                color: _ApprovalsColors.navy,
                                fontWeight: FontWeight.w700,
                                fontSize: 11))
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.notes_rounded,
                            size: 15, color: Color(0xFF657087)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(e.value.reason,
                                style: const TextStyle(
                                    color: Color(0xFF657087), fontSize: 11)))
                      ]),
                    ]),
                  ),
                  if (e.value.status == 'Pending') ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: FilledButton(
                              onPressed: () => onApprove(e.value),
                              style: FilledButton.styleFrom(
                                  backgroundColor: _ApprovalsColors.blue),
                              child: const Text('Approve'))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: OutlinedButton(
                              onPressed: () => onReject(e.value),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFF0182A),
                                  side: const BorderSide(
                                      color: Color(0xFFF0182A))),
                              child: const Text('Reject'))),
                    ]),
                  ],
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ApprovalTabs extends StatelessWidget {
  const _ApprovalTabs({
    required this.requestCategory,
    required this.leaveCount,
    required this.extraCount,
    required this.permissionCount,
    required this.onChanged,
  });
  final String requestCategory;
  final int leaveCount, extraCount, permissionCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (_, constraints) {
        return SizedBox(
          width: constraints.maxWidth < 600 ? constraints.maxWidth : 620,
          child: Row(children: [
            Expanded(child: _TabButton(label: 'Leave', count: leaveCount, active: requestCategory == 'leave', onTap: () => onChanged('leave'))),
            const SizedBox(width: 8),
            Expanded(child: _TabButton(label: 'Permission', count: permissionCount, active: requestCategory == 'permission', onTap: () => onChanged('permission'))),
          ]),
        );
      });
}

class _TabButton extends StatelessWidget {
  const _TabButton(
      {required this.label,
      required this.count,
      required this.active,
      required this.onTap});
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          height: 38,
          decoration: BoxDecoration(
              color: active ? _ApprovalsColors.blue : Colors.white,
              border: Border.all(
                  color: active
                      ? _ApprovalsColors.blue
                      : const Color(0xFFDCE1EB)),
              borderRadius: BorderRadius.circular(24)),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      color: active ? Colors.white : const Color(0xFF596176),
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Container(
                width: 21,
                height: 21,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: active ? Colors.white : const Color(0xFFE7E9ED),
                    shape: BoxShape.circle),
                child: Text('$count',
                    style: TextStyle(
                        color: active
                            ? _ApprovalsColors.blue
                            : const Color(0xFF596176),
                        fontSize: 12)),
              ),
            ],
          ),
        ),
      );
}

class _ApprovalFilters extends StatelessWidget {
  const _ApprovalFilters(
      {required this.employee,
      required this.status,
      required this.dateRange,
      required this.period,
      required this.employees,
      required this.onEmployeeChanged,
      required this.onStatusChanged,
      required this.onDateChanged,
      required this.onPeriodChanged,
      required this.onReset,
      required this.onPending,
      required this.pendingCount,
      required this.searchQuery,
      required this.onSearch});
  final String employee, status, dateRange, period;
  final List<String> employees;
  final ValueChanged<String?> onEmployeeChanged, onStatusChanged, onDateChanged;
  final ValueChanged<String> onPeriodChanged;
  final VoidCallback onReset, onPending;
  final int pendingCount;
  final String searchQuery;
  final ValueChanged<String> onSearch;

  Widget _statusButtons() => _ApprovalStatusButtons(
    status: status,
    pendingCount: pendingCount,
    onChanged: (value) {
      if (value == 'Pending') {
        onPending();
      } else {
        onStatusChanged(value);
      }
    },
  );

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (_, constraints) {
        final mobile = MediaQuery.sizeOf(context).width < 600;
        // Keep the complete desktop filter toolbar on one balanced row.
        final width = ((constraints.maxWidth - 590) / 3).clamp(210.0, 270.0);
        if (mobile) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              key: ValueKey(period),
              onChanged: onSearch,
              decoration: _fieldDecoration(prefix: Icons.search_rounded).copyWith(hintText: 'Search requests', contentPadding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const SizedBox(height: 10),
            _statusButtons(),
            Row(children: [
              OutlinedButton.icon(
                onPressed: () => _showMobileFilters(context),
                icon: const Icon(Icons.tune_rounded, size: 19),
                label: const Text('Filter'),
                style: OutlinedButton.styleFrom(foregroundColor: _ApprovalsColors.blue, side: const BorderSide(color: _ApprovalsColors.blue), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13)),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(onPressed: onReset, icon: const Icon(Icons.restart_alt_rounded), color: _ApprovalsColors.blue, tooltip: 'Reset filters'),
            ]),
          ]);
        }
        return Wrap(
          spacing: 18,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _FilterField(
                label: 'Employee',
                width: width,
                child: DropdownButtonFormField<String>(
                    key: ValueKey(employee),
                    initialValue: employee,
                    onChanged: onEmployeeChanged,
                    decoration: _fieldDecoration(),
                    items: employees
                        .map((item) => DropdownMenuItem<String>(
                            value: item, child: Text(item)))
                        .toList())),
            _FilterField(
                label: 'Date',
                width: width,
                child: DropdownButtonFormField<String>(
                    initialValue: dateRange,
                    onChanged: onDateChanged,
                    decoration:
                        _fieldDecoration(prefix: Icons.calendar_today_outlined),
                    items: const [
                      DropdownMenuItem<String>(
                          value: 'All Dates', child: Text('All Dates')),
                    ])),
            _statusButtons(),
            _FilterField(
                label: 'Period',
                width: 280,
                child: SizedBox(
                  width: 280,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Today', label: Text('Today', softWrap: false)),
                      ButtonSegment(value: 'This Month', label: Text('This Month', softWrap: false)),
                    ],
                    emptySelectionAllowed: true,
                    selected: period == 'All' ? const <String>{} : {period},
                    onSelectionChanged: (value) {
                      if (value.isNotEmpty) onPeriodChanged(value.first);
                    },
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
                      backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? _ApprovalsColors.blue : Colors.white),
                      foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Colors.white : _ApprovalsColors.navy),
                      side: const WidgetStatePropertyAll(BorderSide(color: Color(0xFFD2DCEC))),
                    ),
                  ),
                )),
            OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reset Filters'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: _ApprovalsColors.blue,
                  side: const BorderSide(color: Color(0xFFD6DDEA)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 17, vertical: 17),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
            ),
          ],
        );
      });

  void _showMobileFilters(BuildContext context) {
    showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (sheetContext) => SafeArea(top: false, child: Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFD8E1F0), borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 16), const Text('Filter requests', style: TextStyle(color: _ApprovalsColors.navy, fontSize: 18, fontWeight: FontWeight.w700)), const SizedBox(height: 16),
        _FilterField(label: 'Employee', width: double.infinity, child: DropdownButtonFormField<String>(initialValue: employee, onChanged: onEmployeeChanged, decoration: _fieldDecoration(), items: employees.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList())),
        const SizedBox(height: 12),
        const SizedBox(height: 18),
        FilledButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Apply filters')),
      ]),
    )));
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
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF596176), fontSize: 13)),
          const SizedBox(height: 8),
          child
        ]),
      );
}

InputDecoration _fieldDecoration({IconData? prefix}) => InputDecoration(
      prefixIcon: prefix == null
          ? null
          : Icon(prefix, color: const Color(0xFF596176), size: 19),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: Color(0xFFD8DEE9))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: _ApprovalsColors.blue)),
    );

class _ApprovalTable extends StatefulWidget {
  const _ApprovalTable(
      {required this.requests,
      required this.onApprove,
      required this.onReject});
  final List<_ApprovalRequest> requests;
  final ValueChanged<_ApprovalRequest> onApprove, onReject;

  @override
  State<_ApprovalTable> createState() => _ApprovalTableState();
}

class _ApprovalTableState extends State<_ApprovalTable> {
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
                width: 1480,
                child: _ApprovalTableHeader(),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: SingleChildScrollView(
                controller: _tableBodyScrollCtrl,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1480,
                  child: SingleChildScrollView(
                    primary: false,
                    child: Column(
                      children: [
                        if (widget.requests.isEmpty)
                          const SizedBox(
                              height: 180,
                              child: Center(
                                  child: Text(
                                      'No approval requests match these filters.')))
                        else
                          ...widget.requests.asMap().entries.map((e) => _ApprovalRow(
                              index: e.key + 1,
                              request: e.value,
                              onApprove: widget.onApprove,
                              onReject: widget.onReject)),
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

class _ApprovalTableHeader extends StatelessWidget {
  const _ApprovalTableHeader();
  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        color: const Color(0xFFFCFCFD),
        child: const Row(children: [
          _ApprovalCell(width: 80, child: Text('S.No', style: _headStyle)),
          _ApprovalCell(width: 270, child: Text('Employee', style: _headStyle)),
          _ApprovalCell(
              width: 200, child: Text('Leave Type', style: _headStyle)),
          _ApprovalCell(width: 270, child: Text('Dates', style: _headStyle)),
          _ApprovalCell(width: 115, child: Text('Duration', style: _headStyle)),
          _ApprovalCell(width: 200, child: Text('Reason', style: _headStyle)),
          _ApprovalCell(width: 140, child: Text('Status', style: _headStyle)),
          _ApprovalCell(width: 205, child: Text('Action', style: _headStyle)),
        ]),
      );
}

class _ApprovalRow extends StatelessWidget {
  const _ApprovalRow(
      {required this.index, required this.request, required this.onApprove, required this.onReject});
  final int index;
  final _ApprovalRequest request;
  final ValueChanged<_ApprovalRequest> onApprove, onReject;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => _showReasonDialog(context, request, onApprove, onReject),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
        height: 64,
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE6E9EF)))),
        child: Row(
          children: [
            _ApprovalCell(
              width: 80,
              child: Text('$index', style: const TextStyle(color: Color(0xFF596176), fontSize: 13)),
            ),
            _ApprovalCell(
              width: 270,
              child: Row(children: [
                CircleAvatar(
                    radius: 21,
                    backgroundColor: const Color(0xFFE8EEF8),
                    child: Text(
                        request.name.isEmpty
                            ? '?'
                            : request.name.substring(0, 1),
                        style: const TextStyle(
                            color: _ApprovalsColors.navy,
                            fontWeight: FontWeight.w700))),
                const SizedBox(width: 14),
                Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(request.name,
                          style: const TextStyle(
                              color: Color(0xFF11131A),
                              fontWeight: FontWeight.w600)),
                      Text(request.id,
                          style: const TextStyle(
                              color: Color(0xFF596176), fontSize: 12))
                    ]),
              ]),
            ),
            _ApprovalCell(
              width: 200,
              child: Row(children: [
                Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                        color: Color(request.color).withValues(alpha: .10),
                        shape: BoxShape.circle),
                    child: Icon(request.icon,
                        color: Color(request.color), size: 19)),
                const SizedBox(width: 11),
                Flexible(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(request.type,
                        style: const TextStyle(
                            color: Color(0xFF272B35), fontSize: 13)),
                    if (request.abbreviation != null)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Color(request.color).withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(request.abbreviation!,
                          style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700,
                            color: Color(request.color), letterSpacing: 0.5)),
                      ),
                  ],
                )),
              ]),
            ),
            _ApprovalCell(
                width: 270,
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(request.dates,
                          style: const TextStyle(
                              color: Color(0xFF272B35), fontSize: 13)),
                      Text(request.dayRange,
                          style: const TextStyle(
                              color: Color(0xFF596176), fontSize: 12))
                    ])),
            _ApprovalCell(
                width: 115, child: Text(request.duration, style: _cellStyle)),
            _ApprovalCell(
                width: 200,
                child: Text(
                  request.reason,
                  style: _cellStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )),
            _ApprovalCell(
                width: 140, child: _RequestStatus(status: request.status)),
            _ApprovalCell(
              width: 205,
              child: request.status == 'Pending'
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilledButton(
                                onPressed: () => onApprove(request),
                                style: FilledButton.styleFrom(
                                    backgroundColor: _ApprovalsColors.blue,
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    minimumSize: const Size(0, 32),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(6))),
                                child: const Text('Approve',
                                    style: TextStyle(fontSize: 12))),
                            const SizedBox(width: 6),
                            OutlinedButton(
                                onPressed: () => onReject(request),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFF0182A),
                                    side: const BorderSide(
                                        color: Color(0xFFF0182A)),
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    minimumSize: const Size(0, 32),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(6))),
                                child: const Text('Reject',
                                    style: TextStyle(fontSize: 12))),
                          ]))
                  : const Center(
                      child: Text('–',
                          style: TextStyle(color: Color(0xFF596176)))),
            ),
          ],
        ),
      )));
}

class _ApprovalCell extends StatelessWidget {
  const _ApprovalCell({required this.width, required this.child});
  final double width;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: width,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18), child: child));
}

class _RequestStatus extends StatelessWidget {
  const _RequestStatus({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = status == 'Approved'
        ? const Color(0xFF188226)
        : status == 'Rejected'
            ? const Color(0xFFF0182A)
            : const Color(0xFFFF6500);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(5)),
      child: Text(status, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

class _PaginationButton extends StatelessWidget {
  const _PaginationButton({this.icon}) : text = null, active = false;
  final String? text;
  final IconData? icon;
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
        width: 34,
        height: 34,
        margin: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
            color: active ? _ApprovalsColors.blue : Colors.white,
            border: Border.all(
                color: active
                    ? _ApprovalsColors.blue
                    : const Color(0xFFDCE1EB)),
            borderRadius: BorderRadius.circular(6)),
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, color: const Color(0xFF596176), size: 19)
            : Text(text!,
                style: TextStyle(
                    color: active ? Colors.white : _ApprovalsColors.navy)),
      );
}

bool _matchesPeriod(_ApprovalRequest request, String period, {DateTime? selected}) {
  if (period == 'All') return true;
  final match = RegExp(r'(\d{1,2})\s+([A-Za-z]{3,9})\s+(\d{4})').firstMatch(request.dates);
  if (match == null) return true;
  const months = <String, int>{'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12};
  final date = DateTime.tryParse('${match.group(3)}-${months[match.group(2)!.toLowerCase().substring(0, 3)]?.toString().padLeft(2, '0')}-${match.group(1)!.padLeft(2, '0')}');
  if (date == null) return true;
  final now = selected ?? DateTime.now();
  final end = request.endDate ?? date;
  return period == 'Today'
      ? !date.isAfter(DateUtils.dateOnly(now)) && !end.isBefore(DateUtils.dateOnly(now))
      : date.isBefore(DateTime(now.year, now.month + 1)) && !end.isBefore(DateTime(now.year, now.month));
}

class _ApprovalRequest {
  _ApprovalRequest({
    required this.requestId,
    required this.name,
    required this.id,
    required this.type,
    required this.abbreviation,
    required this.dates,
    required this.dayRange,
    required this.duration,
    required this.reason,
    required this.status,
    required this.icon,
    required this.color,
    this.homeDetails,
    this.endDate,
  });

  final int requestId;
  final String name, id, type, dates, dayRange, duration, reason;
  final String? abbreviation;
  String status;
  final IconData icon;
  final int color;
  final String? homeDetails;
  final DateTime? endDate;

  factory _ApprovalRequest.fromApi(Map<String, dynamic> json) {
    int asInt(dynamic value) =>
        value is int ? value : int.tryParse('$value') ?? 0;
    final iconKey = (json['icon'] ?? '').toString();
    final abbr = json['abbreviation']?.toString();
    final home = json['homeLocation'];
    final homeDetails = home is Map
        ? '${home['latitude']}, ${home['longitude']} · accuracy ${home['accuracyMeters']} m${home['address'] == null ? '' : ' · ${home['address']}'}'
        : null;
    return _ApprovalRequest(
      requestId: asInt(json['id']),
      name: (json['name'] ?? '').toString(),
      id: (json['employeeCode'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      abbreviation: (abbr != null && abbr.isNotEmpty) ? abbr : null,
      dates: (json['dates'] ?? '').toString(),
      dayRange: (json['dayRange'] ?? '').toString(),
      duration: (json['duration'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
      status: (json['status'] ?? 'Pending').toString(),
      icon: switch (iconKey) {
        'medical' => Icons.medical_services_outlined,
        'event_busy' => Icons.event_busy_outlined,
        'more_time' => Icons.more_time_rounded,
        'home' => Icons.home_work_outlined,
        _ => Icons.beach_access_outlined,
      },
      color: json['color'] is int ? json['color'] as int : 0xFF7137E8,
      homeDetails: homeDetails,
      endDate: DateTime.tryParse('${json['endDate']}'),
    );
  }
}

// ── Main tab switcher button ──────────────────────────────────────────────────
class _MainTabBtn extends StatelessWidget {
  const _MainTabBtn({required this.label, required this.active, required this.onTap, this.badge = 0});
  final String label;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: active ? _ApprovalsColors.blue : Colors.white,
        border: Border.all(color: active ? _ApprovalsColors.blue : const Color(0xFFDCE1EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: active ? Colors.white : const Color(0xFF596176)))),
        if (badge > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: active ? Colors.white.withValues(alpha: .25) : _ApprovalsColors.blue,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$badge', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: active ? Colors.white : Colors.white)),
          ),
        ],
      ]),
    ),
  );
}

// ── Correction requests panel (admin) ─────────────────────────────────────────
class _CorrectionRequestsPanel extends StatefulWidget {
  const _CorrectionRequestsPanel({
    required this.corrections,
    required this.loading,
    required this.pendingCount,
    required this.onPending,
    this.onStatusSelected,
    required this.onApprove,
    required this.onReject,
  });
  final List<Map<String, dynamic>> corrections;
  final bool loading;
  final int pendingCount;
  final VoidCallback onPending;
  final VoidCallback? onStatusSelected;
  final ValueChanged<int> onApprove, onReject;

  @override
  State<_CorrectionRequestsPanel> createState() => _CorrectionRequestsPanelState();
}

class _CorrectionRequestsPanelState extends State<_CorrectionRequestsPanel> {
  final _search = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'All Status';
  Object? _selectedId;


  List<Map<String, dynamic>> get _filtered {
    return widget.corrections.where((c) {
      final name = (c['full_name'] ?? '').toString().toLowerCase();
      final staffId = (c['staff_id'] ?? '').toString().toLowerCase();
      final q = _searchQuery.trim().toLowerCase();
      final matchSearch = q.isEmpty || name.contains(q) || staffId.contains(q);
      final status = (c['status'] ?? '').toString();
      final matchStatus = _statusFilter == 'All Status' ||
          status.toLowerCase() == _statusFilter.toLowerCase();
      return matchSearch && matchStatus;
    }).toList();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _resetFilters() {
    _search.clear();
    setState(() {
      _searchQuery = '';
      _statusFilter = 'All Status';
    });
  }

  Widget _statusButtons() => _ApprovalStatusButtons(
    status: _statusFilter,
    pendingCount: widget.pendingCount,
    onChanged: (value) {
      widget.onStatusSelected?.call();
      if (value != 'Pending') {
        setState(() => _statusFilter = value);
        return;
      }
      _search.clear();
      setState(() {
        _searchQuery = '';
        _statusFilter = 'Pending';
      });
      widget.onPending();
    },
  );

  String _fmt(dynamic raw) {
    if (raw == null) return '--';
    try {
      // Attendance timestamps are recorded wall-clock values. Keep those clock
      // components unchanged even when an older API response includes a UTC
      // suffix, otherwise 10:43 AM is incorrectly displayed as 4:13 PM in IST.
      final dt = DateTime.parse('$raw'.replaceFirst(' ', 'T'));
      final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $ampm';
    } catch (_) { return '--'; }
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return '--';
    try {
      final dt = DateTime.parse('$raw'.replaceFirst(' ', 'T'));
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) { return '--'; }
  }

  String _typeLabel(dynamic raw) {
    switch (raw?.toString()) {
      case 'missed_check_in': return 'Missed check-in';
      case 'missed_check_out': return 'Missed check-out';
      case 'incorrect_time': return 'Incorrect time';
      case 'automatic_absence': return 'Automatic absence';
      case 'checkout_correction': return 'Checkout correction';
      default: return 'Attendance correction';
    }
  }

  Widget _filterBar(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    if (mobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _search,
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: _fieldDecoration(prefix: Icons.search_rounded).copyWith(
            hintText: 'Search by name or ID',
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _statusButtons(),
          const SizedBox(width: 8),
          IconButton.outlined(
            onPressed: _resetFilters,
            icon: const Icon(Icons.restart_alt_rounded),
            color: _ApprovalsColors.blue,
            tooltip: 'Reset filters',
          ),
        ]),
        const SizedBox(height: 16),
      ]);
    }
    return Padding(
      padding: EdgeInsets.zero,
      child: Wrap(
        spacing: 14,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: _fieldDecoration(prefix: Icons.search_rounded).copyWith(
                hintText: 'Name or employee ID',
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          _statusButtons(),
          OutlinedButton.icon(
            onPressed: _resetFilters,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reset'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _ApprovalsColors.blue,
              side: const BorderSide(color: Color(0xFFD6DDEA)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestCard(Map<String, dynamic> c, {bool fillPane = false}) {
    final status = c['status']?.toString() ?? 'pending';
    final isPending = status == 'pending';
    final statusColor = status == 'approved' ? const Color(0xFF188226) : status == 'rejected' ? const Color(0xFFF0182A) : const Color(0xFFD97706);
    final statusBg = status == 'approved' ? const Color(0xFFE8F7E9) : status == 'rejected' ? const Color(0xFFFFEAEA) : const Color(0xFFFFF8E6);
    final name = c['full_name']?.toString() ?? '?';
    final staffId = c['staff_id']?.toString() ?? '';
    final initials = name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();
    final reason = Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF7F9FD), borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.topLeft, child: Text(c['reason']?.toString() ?? '—', style: const TextStyle(fontSize: 13, color: Color(0xFF333B52))),
        );
    return Container(
      margin: fillPane ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(fillPane ? 20 : 12),
      decoration: BoxDecoration(
        border: fillPane ? null : Border.all(color: const Color(0xFFE5EAF3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 20, backgroundColor: const Color(0xFFEAF1FF),
            child: Text(initials, style: const TextStyle(color: _ApprovalsColors.blue, fontWeight: FontWeight.w700))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700, color: _ApprovalsColors.navy)),
            Text(staffId, style: const TextStyle(fontSize: 11, color: Color(0xFF657087))),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
            child: Text(_displayStatus(c),
              style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Text(_typeLabel(c['request_type']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ApprovalsColors.blue)),
          const Spacer(),
          if (c['created_at'] != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.access_time_rounded, size: 13, color: Color(0xFF8A94A6)),
              const SizedBox(width: 4),
              Text('Requested ${_fmtDate(c['created_at'])}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF8A94A6))),
            ]),
        ]),
        if (c['attendance_date'] != null) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 13, color: Color(0xFF8A94A6)),
            const SizedBox(width: 4),
            Text('Attendance date: ${_fmtDate(c['attendance_date'])}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF8A94A6))),
          ]),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 6, children: [
          _CorrChip('Check in', _fmt(c['check_in_at'])),
          _CorrChip('Check out', _fmt(c['check_out_at'])),
          if (c['requested_check_in_at'] != null) _CorrChip('Requested in', _fmt(c['requested_check_in_at'])),
          if (c['requested_check_out_at'] != null) _CorrChip('Requested out', _fmt(c['requested_check_out_at'])),
        ]),
        const SizedBox(height: 10),
        const Text('REASON', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF8A94A6), letterSpacing: .06)),
        const SizedBox(height: 4),
        reason,
        if (isPending) ...[
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(
              onPressed: () => widget.onReject(c['id'] as int),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFF0182A),
                side: const BorderSide(color: Color(0xFFF0182A)),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 34),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('Reject', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => widget.onApprove(c['id'] as int),
              style: FilledButton.styleFrom(backgroundColor: _ApprovalsColors.blue,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 34),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('Approve correction', style: TextStyle(fontSize: 13)),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _desktopQueue(List<Map<String, dynamic>> requests) {
    final selected = requests.where((request) => request['id'] == _selectedId)
        .firstOrNull ?? requests.firstOrNull;

    Widget panel(Widget child) => Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDDE5F2)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    Widget row(List<Widget> cells, {Color? color, bool? selected}) => Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: selected == null
              ? null
              : Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 18,
                  color: selected ? _ApprovalsColors.blue : const Color(0xFFDDE5F2),
                ),
        ),
        for (var i = 0; i < cells.length; i++)
          Expanded(flex: i < 2 ? 3 : 2, child: cells[i]),
      ]),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              panel(Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: _filterBar(context),
              )),
              const SizedBox(height: 12),
              Expanded(
                child: panel(Column(
                  children: [
                    row(
                      const [
                        Text('Employee'),
                        Text('Request Details'),
                        Text('Attendance Date'),
                        Text('Status'),
                      ],
                      color: const Color(0xFFF4F6FB),
                    ),
                    Expanded(
                      child: requests.isEmpty
                          ? const Center(child: Text('No requests match the current filters.'))
                          : ListView.separated(
                              itemCount: requests.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final request = requests[index];
                                return InkWell(
                                  onTap: () => setState(() => _selectedId = request['id']),
                                  child: row(
                                    [
                                      Text("${request['full_name'] ?? '—'}\n${request['staff_id'] ?? ''}"),
                                      Text(_typeLabel(request['request_type'])),
                                      Text(_fmtDate(request['attendance_date'])),
                                      _RequestStatus(status: _displayStatus(request)),
                                    ],
                                    selected: identical(request, selected),
                                    color: identical(request, selected)
                                        ? const Color(0xFFEAF2FF)
                                        : null,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                )),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: panel(selected == null
              ? const Center(child: Text('Select a request to view its details.'))
              : LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: _requestCard(selected, fillPane: true),
                    ),
                  ),
                )),
        ),
      ],
    );
  }

  String _displayStatus(Map<String, dynamic> request) {
    final status = request['status']?.toString() ?? '';
    return status.isEmpty ? 'Pending' : status[0].toUpperCase() + status.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    final filtered = _filtered;
    if (MediaQuery.sizeOf(context).width >= 1000) {
      return _desktopQueue(filtered);
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE4E7EE)), borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x0A071A72), blurRadius: 16, offset: Offset(0, 6))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _filterBar(context),
          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Text(
                widget.corrections.isEmpty
                    ? 'No attendance correction requests.'
                    : 'No requests match the current filters.',
                style: const TextStyle(color: Color(0xFF596176)),
              ),
            )
          else
            ...filtered.map(_requestCard),

          // footer count
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Showing ${filtered.length} of ${widget.corrections.length} requests',
              style: const TextStyle(color: Color(0xFF596176), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _CorrChip extends StatelessWidget {
  const _CorrChip(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: const Color(0xFFF4F6FB), border: Border.all(color: const Color(0xFFE3E8F4)), borderRadius: BorderRadius.circular(7)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF8A94A6))),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );
}

void _showReasonDialog(
  BuildContext context,
  _ApprovalRequest request,
  void Function(_ApprovalRequest) onApprove,
  void Function(_ApprovalRequest) onReject,
) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Permission Request',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            color: Color(0xFF8A94A6), letterSpacing: .06)),
                        const SizedBox(height: 4),
                        Text('${request.name} · ${request.type}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                            color: Color(0xFF061457))),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(ctx),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F6FB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.close, size: 16, color: Color(0xFF8A94A6)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // meta chips
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _MetaChip(label: 'Date', value: request.dates),
                  _MetaChip(label: 'Duration', value: request.duration),
                  _MetaChip(label: 'Employee ID', value: request.id),
                  _MetaChip(label: 'Status', value: request.status,
                    valueColor: request.status == 'Pending'
                        ? const Color(0xFFD97706)
                        : request.status == 'Approved'
                            ? const Color(0xFF148B1A)
                            : const Color(0xFFD42B2B)),
                ],
              ),
              const SizedBox(height: 16),
              // reason
              const Text('REASON',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: Color(0xFF8A94A6), letterSpacing: .06)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6FB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(request.reason,
                  style: const TextStyle(fontSize: 14, height: 1.65,
                    color: Color(0xFF1a2340))),
              ),
              if (request.homeDetails != null) ...[
                const SizedBox(height: 16),
                const Text('CAPTURED HOME LOCATION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF8A94A6), letterSpacing: .06)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(10)),
                  child: Text(request.homeDetails!, style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF1a2340))),
                ),
              ],
              if (request.status == 'Pending') ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () { Navigator.pop(ctx); onReject(request); },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD42B2B),
                        side: const BorderSide(color: Color(0xFFD42B2B)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      ),
                      child: const Text('Reject', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: () { Navigator.pop(ctx); onApprove(request); },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF075EF7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      ),
                      child: const Text('Approve', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.value, this.valueColor});
  final String label, value;
  final Color? valueColor;
  @override
  Widget build(BuildContext context) => RichText(
    text: TextSpan(
      style: const TextStyle(fontSize: 12, color: Color(0xFF8A94A6)),
      children: [
        TextSpan(text: '$label: '),
        TextSpan(text: value,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: valueColor ?? const Color(0xFF061457),
          )),
      ],
    ),
  );
}

const _headStyle = TextStyle(
    color: Color(0xFF11131A), fontSize: 13, fontWeight: FontWeight.w600);
const _cellStyle = TextStyle(color: Color(0xFF272B35), fontSize: 13);
