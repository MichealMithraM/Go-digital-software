import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/hrms_tracking_api.dart';
import '../../../services/office_address_search.dart';
import '../../shared/widgets/admin_top_nav.dart';
import '../../shared/widgets/admin_page_scroll_view.dart';
import 'employee_tracking_report_page.dart';
import 'widgets/home_locations_dialog.dart';

part 'tracking_desktop.dart';

abstract final class HrmsColors {
  static const blue = Color(0xFF075EF7);
  static const navy = Color(0xFF061457);
  static const page = Color(0xFFFCFDFF);
}

Future<void> showOfficeLocationDialog(BuildContext context) async {
  await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _OfficeLocationDialog(),
  );
}

Future<void> showHybridSettingsDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _FieldWaitingSettingsDialog(),
  );
}

Future<void> showHomeApprovalsDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const HomeLocationsDialog(),
  );
}

class TrackingPage extends StatefulWidget {
  const TrackingPage({super.key});

  static Widget builder(BuildContext context) => const TrackingPage();

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {

  static const _modeStorageKey = 'admin_tracking_last_mode';
  static const _pollInterval = Duration(seconds: 30);

  List<_TrackedEmployee> employees = [];
  _TrackingCounts counts = const _TrackingCounts(
    office: 0,
    home: 0,
    field: 0,
    activeNow: 0,
  );
  String mode = 'Office';
  bool loading = true;
  String? error;
  DateTime? lastLoadedAt;
  Timer? _pollTimer;
  int _loadRequest = 0;
  _TrackedEmployee? _selectedEmployee;
  DateTime _selectedDate = DateTime.now();
  final _pageScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMode();
    _load();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pageScrollController.dispose();
    super.dispose();
  }

  Future<void> _openFieldWaitingSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _FieldWaitingSettingsDialog(),
    );
  }

  Future<void> _openFieldWaitingReasons() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _FieldWaitingReasonsDialog(),
    );
  }

  Future<void> _openHomeApprovals() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const HomeLocationsDialog(),
    );
    if (mounted) await _load(silent: true);
  }

  Future<void> _openOfficeLocation() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _OfficeLocationDialog(),
    );
    if (saved == true && mounted) await _load(silent: true);
  }

  Future<void> _loadMode() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_modeStorageKey);
    if (!mounted || saved == null) return;
    if (saved == 'Office' || saved == 'Home' || saved == 'Hybrid') {
      setState(() => mode = saved);
    }
  }

  Future<void> _setMode(String value) async {
    setState(() => mode = value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_modeStorageKey, value);
  }

  /// [silent] is used by the background poll timer so it doesn't flash a
  /// full-screen loading spinner every 30 seconds — only the first load
  /// and manual pull-to-refresh show that.
  Future<void> _load({bool silent = false}) async {
    final request = ++_loadRequest;
    if (!silent) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final data = await HrmsTrackingApi.live(
        date: DateFormat('yyyy-MM-dd').format(_selectedDate),
      );
      final countsJson = Map<String, dynamic>.from(
        data['counts'] as Map? ?? {},
      );
      final items = (data['items'] as List? ?? [])
          .whereType<Map>()
          .map(
            (item) => _TrackedEmployee.fromApi(Map<String, dynamic>.from(item)),
          )
          .toList();
      if (!mounted || request != _loadRequest) return;
      setState(() {
        employees = items;
        if (_selectedEmployee != null) {
          final matches = items.where(
            (item) => item.employeeUserId == _selectedEmployee!.employeeUserId,
          );
          _selectedEmployee = matches.isEmpty ? null : matches.first;
        }
        counts = _TrackingCounts.fromApi(countsJson);
        loading = false;
        error = null;
        lastLoadedAt = DateTime.now();
      });
    } catch (err) {
      if (!mounted || request != _loadRequest) return;
      setState(() {
        loading = false;
        if (!silent) {
          error = err.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  List<_TrackedEmployee> get _visibleEmployees =>
      employees.where((employee) => employee.mode == mode).toList();

  void _viewRoute(_TrackedEmployee employee) {
    setState(() => _selectedEmployee = employee);
  }

  void _returnToLiveMap() {
    setState(() => _selectedEmployee = null);
  }

  void _setDate(DateTime d) {
    setState(() => _selectedDate = d);
    _load();
  }

  void _viewActivity(_TrackedEmployee employee) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          _EmployeeActivityDialog(employee: employee, date: _selectedDate),
    );
  }

  void _viewReport(_TrackedEmployee employee) {
    if (employee.employeeUserId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmployeeTrackingReportPage(
          employeeUserId: employee.employeeUserId!,
          employeeName: employee.name,
          employeeCode: employee.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: HrmsColors.page,
      bottomNavigationBar: mobile
          ? const AdminMobileBottomNav(activeRoute: '/admin/tracking')
          : null,
      body: PrimaryScrollController(
        controller: _pageScrollController,
        child: Column(
          children: [
            const AdminTopNav(activeRoute: '/admin/tracking'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: AdminPageScrollView(
                  primary: true,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    mobile ? 16 : 29,
                    18,
                    mobile ? 16 : 29,
                    28,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1580),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TrackingHeader(
                            onRefresh: _load,
                            onViewReasons: _openFieldWaitingReasons,
                          ),
                          const SizedBox(height: 14),
                          if (loading && employees.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 80),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (error != null && employees.isEmpty)
                            _TrackingErrorState(message: error!, onRetry: _load)
                          else if (mobile) ...[
                            _TrackingKpis(counts: counts),
                            const SizedBox(height: 14),
                            _TrackingWorkspace(
                              mode: mode,
                              employees: _visibleEmployees,
                              lastLoadedAt: lastLoadedAt,
                              onModeChanged: (value) => _setMode(value),
                              onViewRoute: _viewRoute,
                              onViewActivity: _viewActivity,
                              selectedEmployee: _selectedEmployee,
                              onReturnToLiveMap: _returnToLiveMap,
                            ),
                          ] else ...[
                            _DesktopTrackingDashboard(
                              mode: mode,
                              employees: _visibleEmployees,
                              selectedEmployee: _selectedEmployee,
                              selectedDate: _selectedDate,
                              lastLoadedAt: lastLoadedAt,
                              onModeChanged: _setMode,
                              onDateChanged: _setDate,
                              onSelectEmployee: _viewRoute,
                              onViewActivity: _viewActivity,
                              onHomeApprovals: _openHomeApprovals,
                              onViewReport: _viewReport,
                            ),
                          ],
                        ],
                      ),
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
}

class _TrackingMobileActions extends StatelessWidget {
  const _TrackingMobileActions({
    required this.onRefresh,
  });
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => Container(
    height: 72,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFC9D9F3)),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        _tool(Icons.refresh, 'Refresh', () => onRefresh()),
      ],
    ),
  );

  Widget _tool(IconData icon, String label, VoidCallback onTap) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: HrmsColors.blue, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: HrmsColors.navy,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TrackingHeader extends StatelessWidget {
  const _TrackingHeader({
    required this.onRefresh,
    required this.onViewReasons,
  });

  final Future<void> Function() onRefresh;
  final VoidCallback onViewReasons;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final mobile = constraints.maxWidth < 700;
      final toolbar = _TrackingActionToolbar(
        mobile: mobile,
        onViewReasons: onViewReasons,
        onRefresh: onRefresh,
      );
      if (mobile) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdminPageHeader(
              title: 'Employee Tracking',
              breadcrumb: 'Tracking',
            ),
            const SizedBox(height: 12),
            toolbar,
          ],
        );
      }
      return AdminPageHeader(
        title: 'Employee Tracking',
        breadcrumb: 'Tracking',
        trailing: toolbar,
      );
    },
  );
}

class _TrackingActionToolbar extends StatefulWidget {
  const _TrackingActionToolbar({
    required this.onViewReasons,
    required this.onRefresh,
    this.mobile = false,
  });

  final VoidCallback onViewReasons;
  final Future<void> Function() onRefresh;
  final bool mobile;

  @override
  State<_TrackingActionToolbar> createState() => _TrackingActionToolbarState();
}

class _TrackingActionToolbarState extends State<_TrackingActionToolbar> {
  int _selected = 0;

  void _tap(int index, VoidCallback action) {
    setState(() => _selected = index);
    action();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mobile) return _buildMobile();
    return _buildDesktop();
  }

  Widget _buildDesktop() => Container(
    height: 52,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE5EAF3)),
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [
        BoxShadow(
          color: Color(0x09071A72),
          blurRadius: 10,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 6),
        _tab(
          0,
          Icons.fact_check_outlined,
          'Waiting Reasons',
          () => _tap(0, widget.onViewReasons),
        ),
        const SizedBox(width: 6),
        const _ToolbarDivider(),
        _refreshBtn(),
        const SizedBox(width: 6),
      ],
    ),
  );

  Widget _buildMobile() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE5EAF3)),
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [
        BoxShadow(
          color: Color(0x09071A72),
          blurRadius: 10,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        Expanded(
          child: _mobTab(
            0,
            Icons.fact_check_outlined,
            'Waiting',
            () => _tap(0, widget.onViewReasons),
          ),
        ),
        _mobDivider(),
        Expanded(child: _mobRefreshTab()),
      ],
    ),
  );

  Widget _mobDivider() =>
      Container(width: 1, height: 36, color: const Color(0xFFE5EAF3));

  Widget _mobTab(int index, IconData icon, String label, VoidCallback onTap) {
    final active = _selected == index;
    return InkWell(
      onTap: onTap,
      borderRadius: index == 0
          ? const BorderRadius.horizontal(left: Radius.circular(13))
          : BorderRadius.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEEF3FF) : Colors.transparent,
          borderRadius: index == 0
              ? const BorderRadius.horizontal(left: Radius.circular(13))
              : BorderRadius.zero,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: active ? HrmsColors.blue : const Color(0xFF596176),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? HrmsColors.blue : const Color(0xFF596176),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobRefreshTab() => InkWell(
    onTap: () => widget.onRefresh(),
    borderRadius: const BorderRadius.horizontal(right: Radius.circular(13)),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.refresh_rounded, size: 18, color: HrmsColors.blue),
          SizedBox(height: 3),
          Text(
            'Refresh',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: HrmsColors.blue,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _tab(int index, IconData icon, String label, VoidCallback onTap) {
    final active = _selected == index;
    if (active) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 9),
        child: Material(
          color: HrmsColors.blue,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: const Color(0xFF596176)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF596176),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _refreshBtn() => Tooltip(
    message: 'Refresh',
    child: InkWell(
      onTap: () => widget.onRefresh(),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh_rounded, size: 16, color: HrmsColors.blue),
            const SizedBox(width: 5),
            const Text(
              'Refresh',
              style: TextStyle(
                color: HrmsColors.blue,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 10),
    child: SizedBox(
      height: 32,
      child: VerticalDivider(width: 1, thickness: 1, color: Color(0xFFD5E1F5)),
    ),
  );
}

class _TrackingErrorState extends StatelessWidget {
  const _TrackingErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE3E7EF)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        const Icon(Icons.wifi_off_rounded, color: Color(0xFF657087), size: 34),
        const SizedBox(height: 12),
        Text(
          'Could not load tracking data',
          style: const TextStyle(
            color: HrmsColors.navy,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF657087), fontSize: 12),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => onRetry(),
          style: ElevatedButton.styleFrom(backgroundColor: HrmsColors.blue),
          child: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _TrackingCounts {
  const _TrackingCounts({
    required this.office,
    required this.home,
    required this.field,
    required this.activeNow,
  });
  final int office, home, field, activeNow;

  factory _TrackingCounts.fromApi(Map<String, dynamic> json) => _TrackingCounts(
    office: _asInt(json['office']),
    home: _asInt(json['home']),
    field: _asInt(json['hybrid'] ?? json['field']),
    activeNow: _asInt(json['activeNow']),
  );

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }
}

class _TrackingKpis extends StatelessWidget {
  const _TrackingKpis({required this.counts});
  final _TrackingCounts counts;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final cards = [
      _TrackingKpi(
        label: 'Office',
        value: '${counts.office}',
        caption: 'Tracked employees',
        icon: Icons.apartment_outlined,
        color: HrmsColors.blue,
        compact: isMobile,
      ),
      _TrackingKpi(
        label: 'Home',
        value: '${counts.home}',
        caption: 'Tracked employees',
        icon: Icons.home_outlined,
        color: const Color(0xFF138A20),
        compact: isMobile,
      ),
      _TrackingKpi(
        label: 'Hybrid',
        value: '${counts.field}',
        caption: 'Tracked employees',
        icon: Icons.hiking_outlined,
        color: const Color(0xFFFF6500),
        compact: isMobile,
      ),
      _TrackingKpi(
        label: 'Active Now',
        value: '${counts.activeNow}',
        caption: 'Employees active',
        icon: Icons.wifi_rounded,
        color: const Color(0xFF138A20),
        compact: isMobile,
      ),
    ];
    return Row(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          if (i > 0) SizedBox(width: isMobile ? 6 : 10),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }
}

class _TrackingKpi extends StatelessWidget {
  const _TrackingKpi({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
    this.compact = false,
  });
  final String label, value, caption;
  final IconData icon;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 32.0 : 44.0;
    final iconInner = compact ? 16.0 : 22.0;
    final radius = compact ? 8.0 : 10.0;
    final numSize = compact ? 20.0 : 26.0;
    final labelSize = compact ? 9.5 : 11.0;
    final captionSize = compact ? 9.0 : 10.0;
    final pad = compact
        ? const EdgeInsets.fromLTRB(8, 10, 8, 0)
        : const EdgeInsets.fromLTRB(14, 14, 14, 0);
    final gap = compact ? 6.0 : 12.0;

    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE3E7EF)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08071A72),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Icon(icon, color: color, size: iconInner),
              ),
              SizedBox(width: gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFF6B7280),
                        fontSize: labelSize,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        color: HrmsColors.navy,
                        fontSize: numSize,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      caption,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFF9AA3B2),
                        fontSize: captionSize,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingWorkspace extends StatelessWidget {
  const _TrackingWorkspace({
    required this.mode,
    required this.employees,
    required this.lastLoadedAt,
    required this.onModeChanged,
    required this.onViewRoute,
    required this.onViewActivity,
    required this.selectedEmployee,
    required this.onReturnToLiveMap,
  });
  final String mode;
  final List<_TrackedEmployee> employees;
  final DateTime? lastLoadedAt;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<_TrackedEmployee> onViewRoute;
  final ValueChanged<_TrackedEmployee> onViewActivity;
  final _TrackedEmployee? selectedEmployee;
  final VoidCallback onReturnToLiveMap;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE3E7EF)),
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [
        BoxShadow(
          color: Color(0x08071A72),
          blurRadius: 15,
          offset: Offset(0, 6),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: LayoutBuilder(
      builder: (_, constraints) {
        // The phone layout follows the admin mobile design: live map first,
        // then a distinct employee card. The same live API data powers both.
        if (constraints.maxWidth < 700 && selectedEmployee == null) {
          return Column(
            children: [
              _MobileLiveLocationCard(
                employees: employees,
                onViewRoute: onViewRoute,
              ),
              const SizedBox(height: 14),
              _MobileEmployeesCard(
                mode: mode,
                employees: employees,
                lastLoadedAt: lastLoadedAt,
                onModeChanged: onModeChanged,
                onViewRoute: onViewRoute,
                onViewActivity: onViewActivity,
              ),
            ],
          );
        }
        // On mobile with an employee selected, show only the route panel.
        if (constraints.maxWidth < 700 && selectedEmployee != null) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: KeyedSubtree(
              key: ValueKey(selectedEmployee!.employeeUserId),
              child: _AdminRoutePanel(
                employee: selectedEmployee!,
                onReturnToLiveMap: onReturnToLiveMap,
                mode: mode,
                onModeChanged: onModeChanged,
              ),
            ),
          );
        }
        final stacked = constraints.maxWidth < 1050;
        final map = selectedEmployee == null
            ? _MapPanel(
                mode: mode,
                employees: employees,
                onModeChanged: onModeChanged,
                onViewRoute: onViewRoute,
                fillHeight: !stacked,
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: double.infinity,
                    child: KeyedSubtree(
                      key: ValueKey(selectedEmployee!.employeeUserId),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _AdminRoutePanel(
                              employee: selectedEmployee!,
                              onReturnToLiveMap: onReturnToLiveMap,
                              mode: mode,
                              onModeChanged: onModeChanged,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
        final table = _TrackedEmployeesPanel(
          mode: mode,
          employees: employees,
          lastLoadedAt: lastLoadedAt,
          onViewRoute: onViewRoute,
          onViewActivity: onViewActivity,
        );
        if (stacked) {
          return Column(
            children: [
              map,
              const Divider(height: 1, color: Color(0xFFE3E7EF)),
              table,
            ],
          );
        }
        return SizedBox(
          height: 615,
          child: Row(
            children: [
              Expanded(flex: 10, child: _TrackingSurface(child: table)),
              const SizedBox(width: 16),
              Expanded(flex: 11, child: _TrackingSurface(child: map)),
            ],
          ),
        );
      },
    ),
  );
}

class _TrackingSurface extends StatelessWidget {
  const _TrackingSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE3E7EF)),
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [
        BoxShadow(
          color: Color(0x08071A72),
          blurRadius: 15,
          offset: Offset(0, 6),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _MobileLiveLocationCard extends StatefulWidget {
  const _MobileLiveLocationCard({
    required this.employees,
    required this.onViewRoute,
  });

  final List<_TrackedEmployee> employees;
  final ValueChanged<_TrackedEmployee> onViewRoute;

  @override
  State<_MobileLiveLocationCard> createState() =>
      _MobileLiveLocationCardState();
}

class _MobileLiveLocationCardState extends State<_MobileLiveLocationCard> {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE3E7EF)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Live Location',
                style: TextStyle(
                  color: HrmsColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Open live map',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _LiveMapFullscreen(
                    employees: widget.employees,
                    onViewRoute: widget.onViewRoute,
                  ),
                ),
              ),
              icon: const Icon(
                Icons.fullscreen_rounded,
                color: HrmsColors.navy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 230,
          width: double.infinity,
          child: _LiveMap(
            employees: widget.employees,
            onViewRoute: widget.onViewRoute,
          ),
        ),
      ],
    ),
  );
}

class _MobileEmployeesCard extends StatefulWidget {
  const _MobileEmployeesCard({
    required this.mode,
    required this.employees,
    required this.lastLoadedAt,
    required this.onModeChanged,
    required this.onViewRoute,
    required this.onViewActivity,
  });

  final String mode;
  final List<_TrackedEmployee> employees;
  final DateTime? lastLoadedAt;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<_TrackedEmployee> onViewRoute;
  final ValueChanged<_TrackedEmployee> onViewActivity;

  @override
  State<_MobileEmployeesCard> createState() => _MobileEmployeesCardState();
}

class _MobileEmployeesCardState extends State<_MobileEmployeesCard> {
  String _query = '';

  String get _updatedLabel {
    final loadedAt = widget.lastLoadedAt;
    if (loadedAt == null) return 'Updating…';
    final minutes = DateTime.now().difference(loadedAt).inMinutes;
    return minutes == 0 ? 'Updated just now' : 'Updated ${minutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    // Filter employees by the active mode tab
    final modeEmployees = widget.employees
        .where((e) => e.mode == widget.mode)
        .toList();
    final matches = modeEmployees.where((e) {
      return query.isEmpty ||
          e.name.toLowerCase().contains(query) ||
          e.id.toLowerCase().contains(query);
    }).toList();

    final activeCount = modeEmployees.where((e) => e.active).length;
    final inactiveCount = modeEmployees.length - activeCount;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE3E7EF)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Employee Tracking',
                  style: TextStyle(
                    color: HrmsColors.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF16A34A),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _updatedLabel,
                style: const TextStyle(color: Color(0xFF657087), fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Mode tabs (Office | Home | Hybrid)
          Row(
            children: [
              for (final item in ['Office', 'Home', 'Hybrid']) ...[
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: item == 'Hybrid' ? 0 : 6),
                    child: _ModeButton(
                      label: item,
                      active: widget.mode == item,
                      onTap: () => widget.onModeChanged(item),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Mode-specific mini KPI row
          _MobileModeKpis(
            mode: widget.mode,
            total: modeEmployees.length,
            activeCount: activeCount,
            inactiveCount: inactiveCount,
          ),
          const SizedBox(height: 12),

          // Search bar (always visible)
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search ${widget.mode.toLowerCase()} employees…',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD6DDEA)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD6DDEA)),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 10),

          // Employee list — mode-specific layout
          if (matches.isEmpty)
            const _EmptyTrackedState()
          else if (widget.mode == 'Home')
            _MobileHomeGrid(
              employees: matches,
              onViewRoute: widget.onViewRoute,
              onViewActivity: widget.onViewActivity,
            )
          else
            ...matches.map(
              (e) => _MobileEmployeeRow(
                employee: e,
                onViewRoute: widget.onViewRoute,
                onViewActivity: widget.onViewActivity,
              ),
            ),
        ],
      ),
    );
  }
}

/// Mode-specific mini KPI strip inside the mobile employees card.
class _MobileModeKpis extends StatelessWidget {
  const _MobileModeKpis({
    required this.mode,
    required this.total,
    required this.activeCount,
    required this.inactiveCount,
  });
  final String mode;
  final int total, activeCount, inactiveCount;

  @override
  Widget build(BuildContext context) {
    final List<(String, int, Color)> kpis;
    switch (mode) {
      case 'Home':
        kpis = [
          ('Home', total, const Color(0xFF138A20)),
          ('Checked In', activeCount, HrmsColors.blue),
          ('Not Checked In', inactiveCount, const Color(0xFFDC2626)),
        ];
      case 'Hybrid':
        kpis = [
          ('Hybrid', total, const Color(0xFFFF6500)),
          ('Active Now', activeCount, const Color(0xFF138A20)),
          ('Offline', inactiveCount, const Color(0xFF657087)),
        ];
      default: // Office
        kpis = [
          ('Office', total, HrmsColors.blue),
          ('Checked In', activeCount, const Color(0xFF138A20)),
          ('Not Checked In', inactiveCount, const Color(0xFFDC2626)),
        ];
    }
    return Row(
      children: [
        for (int i = 0; i < kpis.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              decoration: BoxDecoration(
                color: kpis[i].$3.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kpis[i].$3.withValues(alpha: .25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${kpis[i].$2}',
                    style: TextStyle(
                      color: kpis[i].$3,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    kpis[i].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF657087),
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 3-column compact grid used for Home mode employees.
class _MobileHomeGrid extends StatelessWidget {
  const _MobileHomeGrid({
    required this.employees,
    required this.onViewRoute,
    required this.onViewActivity,
  });
  final List<_TrackedEmployee> employees;
  final ValueChanged<_TrackedEmployee> onViewRoute;
  final ValueChanged<_TrackedEmployee> onViewActivity;

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      childAspectRatio: 0.82,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
    ),
    itemCount: employees.length,
    itemBuilder: (_, i) => _MobileHomeCard(
      employee: employees[i],
      onTap: () => onViewRoute(employees[i]),
    ),
  );
}

/// Compact avatar card used inside the Home grid.
class _MobileHomeCard extends StatelessWidget {
  const _MobileHomeCard({required this.employee, required this.onTap});
  final _TrackedEmployee employee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = employee.active;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE3E7EF)),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x06071A72),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFFE8F0FF),
              child: Text(
                employee.name.isEmpty ? '?' : employee.name[0].toUpperCase(),
                style: const TextStyle(
                  color: HrmsColors.navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              employee.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: HrmsColors.navy,
              ),
            ),
            Text(
              employee.id,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, color: Color(0xFF657087)),
            ),
            const SizedBox(height: 5),
            // Home badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F4FF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Home',
                style: TextStyle(
                  color: HrmsColors.blue,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 3),
            // Status chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isActive ? 'Checked In' : 'Not In',
                style: TextStyle(
                  color: isActive
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width row for Office and Hybrid modes.
class _MobileEmployeeRow extends StatelessWidget {
  const _MobileEmployeeRow({
    required this.employee,
    required this.onViewRoute,
    required this.onViewActivity,
  });
  final _TrackedEmployee employee;
  final ValueChanged<_TrackedEmployee> onViewRoute;
  final ValueChanged<_TrackedEmployee> onViewActivity;

  @override
  Widget build(BuildContext context) {
    final isHybrid = employee.mode == 'Hybrid';
    final isActive = employee.active;

    // Mode badge styling
    final (badgeLabel, badgeBg, badgeFg) = isHybrid
        ? ('Hybrid', const Color(0xFFFFF4EC), const Color(0xFFFF6500))
        : ('Office', const Color(0xFFE8F0FF), HrmsColors.blue);

    // Status chip styling
    final (statusLabel, statusBg, statusFg) = isHybrid
        ? isActive
              ? ('Active', const Color(0xFFDCFCE7), const Color(0xFF16A34A))
              : ('Offline', const Color(0xFFF3F4F6), const Color(0xFF6B7280))
        : isActive
        ? ('Checked In', const Color(0xFFDCFCE7), const Color(0xFF16A34A))
        : ('Not Checked In', const Color(0xFFFEF2F2), const Color(0xFFDC2626));

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEDF0F6))),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFE8F0FF),
            child: Text(
              employee.name.isEmpty ? '?' : employee.name[0].toUpperCase(),
              style: const TextStyle(
                color: HrmsColors.navy,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Name / ID / location
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        employee.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: HrmsColors.navy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Mode badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(
                          color: badgeFg,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  employee.id,
                  style: const TextStyle(
                    color: Color(0xFF657087),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 3),
                if (isHybrid)
                  Row(
                    children: [
                      const Icon(
                        Icons.wifi_rounded,
                        color: Color(0xFFFF6500),
                        size: 12,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Last ping: ${employee.updatedLabel.replaceFirst('Updated ', '')}',
                        style: const TextStyle(
                          color: Color(0xFF657087),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: HrmsColors.blue,
                        size: 12,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          employee.address ?? 'No location yet',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF657087),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Status chip + action buttons
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusFg,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RowIconBtn(
                    icon: Icons.map_outlined,
                    tooltip: 'View on map',
                    color: HrmsColors.blue,
                    onTap: () => onViewRoute(employee),
                  ),
                  const SizedBox(width: 2),
                  _RowIconBtn(
                    icon: Icons.history_rounded,
                    tooltip: 'Location history',
                    color: const Color(0xFF00A884),
                    onTap: () => onViewActivity(employee),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small icon button used in mobile employee rows.
class _RowIconBtn extends StatelessWidget {
  const _RowIconBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, color: color, size: 18),
      ),
    ),
  );
}

class _MapPanel extends StatelessWidget {
  const _MapPanel({
    required this.mode,
    required this.employees,
    required this.onModeChanged,
    required this.onViewRoute,
    this.fillHeight = false,
  });
  final String mode;
  final List<_TrackedEmployee> employees;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<_TrackedEmployee> onViewRoute;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(17, 16, 17, 18),
    child: Column(
      children: [
        _MapModeTabs(mode: mode, onModeChanged: onModeChanged),
        const SizedBox(height: 15),
        if (fillHeight)
          Expanded(
            child: _LiveMap(employees: employees, onViewRoute: onViewRoute),
          )
        else
          AspectRatio(
            aspectRatio: 1.44,
            child: _LiveMap(employees: employees, onViewRoute: onViewRoute),
          ),
      ],
    ),
  );
}

class _MapModeTabs extends StatelessWidget {
  const _MapModeTabs({required this.mode, required this.onModeChanged});

  final String mode;
  final ValueChanged<String> onModeChanged;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Row(
        children: [
          for (final item in ['Office', 'Home', 'Hybrid']) ...[
            if (item != 'Office') const SizedBox(width: 10),
            Expanded(
              child: _ModeButton(
                label: item,
                active: mode == item,
                onTap: () => onModeChanged(item),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Google Maps display for the live employee markers. Only employees with
/// at least one GPS ping recorded are shown as pins — an employee who has
/// only set a status but never sent a location has nothing to plot yet.
class _LiveMap extends StatefulWidget {
  const _LiveMap({
    required this.employees,
    required this.onViewRoute,
    this.onMapCreated,
    this.highlightedEmployee,
    this.showEmptyOverlay = true,
  });
  final List<_TrackedEmployee> employees;
  final ValueChanged<_TrackedEmployee> onViewRoute;
  final ValueChanged<GoogleMapController>? onMapCreated;
  final _TrackedEmployee? highlightedEmployee;
  final bool showEmptyOverlay;

  @override
  State<_LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<_LiveMap> {
  GoogleMapController? _controller;
  late LatLng _center;
  double _zoom = 11;

  static const _fallbackCenter = LatLng(20.5937, 78.9629); // India center

  LatLng? _officeCenter;
  String? _officeAddress;
  double? _officeRadiusMeters;

  List<_TrackedEmployee> get _located => widget.employees
      .where((employee) => employee.lat != null && employee.lng != null)
      .toList();

  @override
  void initState() {
    super.initState();
    _center = _initialCenter;
    _loadOfficeCenter();
  }

  Future<void> _loadOfficeCenter() async {
    try {
      final data = await HrmsTrackingApi.trackingSettings();
      final lat = _mapNumber(data['office_latitude'] ?? data['officeLatitude']);
      final lng = _mapNumber(
        data['office_longitude'] ?? data['officeLongitude'],
      );
      final radius = _mapNumber(
        data['office_radius_meters'] ?? data['officeRadiusMeters'],
      );
      if (lat != null && lng != null && mounted) {
        final officeView = widget.highlightedEmployee == null;
        setState(() {
          _officeCenter = LatLng(lat, lng);
          _officeAddress = (data['office_address'] ?? data['officeAddress'])
              ?.toString();
          _officeRadiusMeters = radius;
          if (officeView) {
            _center = _officeCenter!;
            _zoom = 15;
          }
        });
        if (officeView) {
          _controller?.animateCamera(
            CameraUpdate.newLatLngZoom(_officeCenter!, 15),
          );
        }
      }
    } catch (_) {}
  }

  double? _mapNumber(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }

  @override
  void didUpdateWidget(covariant _LiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newHighlight = widget.highlightedEmployee;
    final oldHighlight = oldWidget.highlightedEmployee;
    if ((newHighlight?.employeeUserId != oldHighlight?.employeeUserId || newHighlight?.homeLat != oldHighlight?.homeLat || newHighlight?.homeLng != oldHighlight?.homeLng) &&
        newHighlight?.homeLat != null &&
        newHighlight?.homeLng != null &&
        _located.isEmpty) {
      _moveTo(LatLng(newHighlight!.homeLat!, newHighlight.homeLng!), 14);
    } else if (oldWidget.employees != widget.employees && _located.isNotEmpty) {
      _center = _initialCenter;
      if (newHighlight != null && (newHighlight.lat != oldHighlight?.lat || newHighlight.lng != oldHighlight?.lng)) _moveTo(_center);
    }
  }

  LatLng get _initialCenter {
    // In the Office tab the configured office/geofence is the map's anchor.
    // Employee GPS remains visible as a separate marker when available.
    if (widget.highlightedEmployee == null && _officeCenter != null) {
      return _officeCenter!;
    }
    if (_located.isNotEmpty) {
      return LatLng(_located.first.lat!, _located.first.lng!);
    }
    final h = widget.highlightedEmployee;
    if (h?.homeLat != null && h?.homeLng != null) {
      return LatLng(h!.homeLat!, h.homeLng!);
    }
    return widget.highlightedEmployee == null ? (_officeCenter ?? _fallbackCenter) : _fallbackCenter;
  }

  Future<void> _moveTo(LatLng target, [double? zoom]) async {
    _center = target;
    if (zoom != null) _zoom = zoom;
    await _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(_center, _zoom),
    );
  }

  Future<void> _changeZoom(double change) async {
    _zoom = (_zoom + change).clamp(3.0, 20.0);
    await _controller?.animateCamera(CameraUpdate.zoomTo(_zoom));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: _zoom),
            onMapCreated: (controller) {
              _controller = controller;
              widget.onMapCreated?.call(controller);
              if (widget.highlightedEmployee == null && _officeCenter != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(_officeCenter!, 15),
                );
              }
            },
            mapToolbarEnabled: false,
            circles: {
              if (widget.highlightedEmployee == null && _officeCenter != null && (_officeRadiusMeters ?? 0) > 0)
                Circle(
                  circleId: const CircleId('__office_geofence__'),
                  center: _officeCenter!,
                  radius: _officeRadiusMeters!,
                  strokeColor: HrmsColors.blue,
                  strokeWidth: 2,
                  fillColor: HrmsColors.blue.withValues(alpha: 0.12),
                ),
            },
            markers: {
              ..._located.map(
                (employee) => Marker(
                  markerId: MarkerId(employee.id),
                  position: LatLng(employee.lat!, employee.lng!),
                  infoWindow: InfoWindow(
                    title: employee.name,
                    snippet:
                        employee.address ?? 'Location not yet reverse-geocoded',
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    _markerHue(employee.mode),
                  ),
                  onTap: () => widget.onViewRoute(employee),
                ),
              ),
              if (widget.highlightedEmployee == null && _officeCenter != null)
                Marker(
                  markerId: const MarkerId('__office__'),
                  position: _officeCenter!,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure,
                  ),
                  infoWindow: InfoWindow(
                    title: 'Office Location',
                    snippet: _officeAddress?.trim().isNotEmpty == true
                        ? _officeAddress
                        : 'Configured office geofence',
                  ),
                ),
              if (widget.highlightedEmployee?.homeLat != null &&
                  widget.highlightedEmployee?.homeLng != null)
                Marker(
                  markerId: const MarkerId('__home__'),
                  position: LatLng(
                    widget.highlightedEmployee!.homeLat!,
                    widget.highlightedEmployee!.homeLng!,
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen,
                  ),
                  infoWindow: InfoWindow(
                    title: '${widget.highlightedEmployee!.name} – Home',
                    snippet:
                        widget.highlightedEmployee!.homeAddress ??
                        'Approved home location',
                  ),
                ),
            },
          ),
          Positioned(
            right: 10,
            top: 10,
            child: Column(
              children: [
                _mapControl(
                  Icons.gps_fixed_rounded,
                  'Recenter live locations',
                  () => _moveTo(_initialCenter, 11),
                ),
                const SizedBox(height: 8),
                _mapControl(Icons.add_rounded, 'Zoom in', () => _changeZoom(1)),
                const SizedBox(height: 8),
                _mapControl(
                  Icons.remove_rounded,
                  'Zoom out',
                  () => _changeZoom(-1),
                ),
              ],
            ),
          ),
          if (widget.showEmptyOverlay &&
              _located.isEmpty &&
              (widget.highlightedEmployee != null || _officeCenter == null) &&
              (widget.highlightedEmployee?.homeLat == null ||
                  widget.highlightedEmployee?.homeLng == null))
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xCCFFFFFF),
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'No live locations for this filter yet',
                    style: TextStyle(
                      color: HrmsColors.navy,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _mapControl(IconData icon, String label, VoidCallback action) =>
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        elevation: 2,
        child: IconButton(
          tooltip: label,
          onPressed: action,
          icon: Icon(icon, color: HrmsColors.blue),
        ),
      );

  double _markerHue(String mode) => switch (mode) {
    'Office' => BitmapDescriptor.hueAzure,
    'Home' => BitmapDescriptor.hueGreen,
    _ => BitmapDescriptor.hueOrange,
  };
}

class _LiveMapFullscreen extends StatelessWidget {
  const _LiveMapFullscreen({
    required this.employees,
    required this.onViewRoute,
  });
  final List<_TrackedEmployee> employees;
  final ValueChanged<_TrackedEmployee> onViewRoute;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: _LiveMap(employees: employees, onViewRoute: onViewRoute),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              child: IconButton(
                tooltip: 'Close full screen map',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: HrmsColors.navy),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(22),
    child: Container(
      width: double.infinity,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? HrmsColors.blue : Colors.white,
        border: Border.all(
          color: active ? HrmsColors.blue : const Color(0xFFDCE1EB),
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : const Color(0xFF303747),
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _TrackedEmployeesPanel extends StatelessWidget {
  const _TrackedEmployeesPanel({
    required this.mode,
    required this.employees,
    required this.lastLoadedAt,
    required this.onViewRoute,
    required this.onViewActivity,
  });
  final String mode;
  final List<_TrackedEmployee> employees;
  final DateTime? lastLoadedAt;
  final ValueChanged<_TrackedEmployee> onViewRoute;
  final ValueChanged<_TrackedEmployee> onViewActivity;

  String get _updatedLabel {
    if (lastLoadedAt == null) return 'Updating…';
    final seconds = DateTime.now().difference(lastLoadedAt!).inSeconds;
    if (seconds < 5) return 'Updated just now';
    if (seconds < 60) return 'Updated ${seconds}s ago';
    final minutes = (seconds / 60).floor();
    return 'Updated ${minutes}m ago';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$mode Employees',
              style: const TextStyle(
                color: Color(0xFF11131A),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF138A20),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _updatedLabel,
              style: const TextStyle(color: Color(0xFF596176), fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (employees.isEmpty)
          const _EmptyTrackedState()
        else if (MediaQuery.sizeOf(context).width < 600)
          _MobileTrackedList(employees: employees, onViewRoute: onViewRoute)
        else
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE2E6ED)),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: LayoutBuilder(
                builder: (_, c) {
                  const minW = 560.0;
                  final tableW = c.maxWidth < minW ? minW : c.maxWidth;
                  return SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: tableW,
                        child: Column(
                          children: [
                            _TrackingTableHeader(width: tableW),
                            ...employees.map(
                              (employee) => _TrackingRow(
                                employee: employee,
                                tableWidth: tableW,
                                onViewRoute: onViewRoute,
                                onViewActivity: onViewActivity,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    ),
  );
}

class _EmptyTrackedState extends StatelessWidget {
  const _EmptyTrackedState();
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 32),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFE2E6ED)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Column(
      children: [
        Icon(Icons.location_off_outlined, color: Color(0xFF9AA3B2), size: 28),
        SizedBox(height: 8),
        Text(
          'No employees in this status right now',
          style: TextStyle(color: Color(0xFF657087), fontSize: 12),
        ),
      ],
    ),
  );
}

class _MobileTrackedList extends StatelessWidget {
  const _MobileTrackedList({
    required this.employees,
    required this.onViewRoute,
  });
  final List<_TrackedEmployee> employees;
  final ValueChanged<_TrackedEmployee> onViewRoute;

  @override
  Widget build(BuildContext context) => Column(
    children: employees
        .map(
          (employee) => Container(
            margin: const EdgeInsets.only(bottom: 9),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFBFCFF),
              border: Border.all(color: const Color(0xFFE5EAF3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFEAF1FF),
                  child: Text(
                    employee.name.isNotEmpty
                        ? employee.name.substring(0, 1)
                        : '?',
                    style: const TextStyle(
                      color: HrmsColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              employee.name,
                              style: const TextStyle(
                                color: HrmsColors.navy,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          _ActiveBadge(active: employee.active),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: HrmsColors.blue,
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              employee.address ?? 'No location yet',
                              style: const TextStyle(
                                color: Color(0xFF657087),
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => onViewRoute(employee),
                  icon: const Icon(
                    Icons.map_outlined,
                    color: HrmsColors.blue,
                    size: 23,
                  ),
                ),
              ],
            ),
          ),
        )
        .toList(),
  );
}

class _TrackingTableHeader extends StatelessWidget {
  const _TrackingTableHeader({this.width = 560});
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = _colWidths(width);
    return Container(
      width: width,
      height: 42,
      color: const Color(0xFFFCFCFD),
      child: Row(
        children: [
          _TrackingCell(
            width: c[0],
            child: const Text('Employee', style: _headStyle),
          ),
          _TrackingCell(
            width: c[1],
            child: const Text('Current Location', style: _headStyle),
          ),
          _TrackingCell(
            width: c[2],
            child: const Text('Status', style: _headStyle),
          ),
          _TrackingCell(
            width: c[3],
            child: const Text('Actions', style: _headStyle),
          ),
        ],
      ),
    );
  }
}

// Proportional column widths: Employee 34%, Location 34%, Status 17%, Actions 15%
List<double> _colWidths(double total) => [
  total * 0.34,
  total * 0.34,
  total * 0.17,
  total * 0.15,
];

class _TrackingRow extends StatelessWidget {
  const _TrackingRow({
    required this.employee,
    required this.onViewRoute,
    required this.onViewActivity,
    this.tableWidth = 560,
  });
  final _TrackedEmployee employee;
  final ValueChanged<_TrackedEmployee> onViewRoute;
  final ValueChanged<_TrackedEmployee> onViewActivity;
  final double tableWidth;

  @override
  Widget build(BuildContext context) {
    final c = _colWidths(tableWidth);
    return Container(
      width: tableWidth,
      height: 59,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E8EF))),
      ),
      child: Row(
        children: [
          _TrackingCell(
            width: c[0],
            child: Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: const Color(0xFFE8EEF8),
                  child: Text(
                    employee.name.isNotEmpty
                        ? employee.name.substring(0, 1)
                        : '?',
                    style: const TextStyle(
                      color: HrmsColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.name,
                      style: const TextStyle(
                        color: Color(0xFF303747),
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      employee.id,
                      style: const TextStyle(
                        color: Color(0xFF657087),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _TrackingCell(
            width: c[1],
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.location_on,
                    color: HrmsColors.blue,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.address ?? 'No location yet',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF303747),
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        employee.updatedLabel,
                        style: const TextStyle(
                          color: Color(0xFF657087),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _TrackingCell(
            width: c[2],
            child: _ActiveBadge(active: employee.active),
          ),
          _TrackingCell(
            width: c[3],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'View route',
                  onPressed: () => onViewRoute(employee),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 40,
                  ),
                  icon: const Icon(
                    Icons.map_outlined,
                    color: HrmsColors.blue,
                    size: 24,
                  ),
                ),
                IconButton(
                  tooltip: 'View activity history',
                  onPressed: () => onViewActivity(employee),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 40,
                  ),
                  icon: const Icon(
                    Icons.history,
                    color: Color(0xFF00AB84),
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingCell extends StatelessWidget {
  const _TrackingCell({required this.width, required this.child});
  final double width;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: child,
    ),
  );
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
    decoration: BoxDecoration(
      color: active ? const Color(0xFFEAF6E6) : const Color(0xFFF1F2F5),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      active ? 'Active' : 'Inactive',
      style: TextStyle(
        color: active ? const Color(0xFF177020) : const Color(0xFF657087),
        fontSize: 11,
      ),
    ),
  );
}

/// One employee row for the admin tracking dashboard, built entirely from
/// `GET /api/hrms/tracking/live`. `mode` is normalized to 'Office' / 'Home'
/// / 'Hybrid' (title case) to match the tab labels in this UI; the backend
/// itself stores it lowercase.
class _AttendanceDay {
  const _AttendanceDay({
    required this.date,
    this.checkInAt,
    this.status,
    this.checkInLat,
    this.checkInLng,
  });
  final String date;
  final DateTime? checkInAt;
  final String? status;
  final double? checkInLat;
  final double? checkInLng;

  factory _AttendanceDay.fromApi(Map<String, dynamic> json) => _AttendanceDay(
    date: '${json['date'] ?? ''}',
    checkInAt: json['checkInAt'] != null
        ? DateTime.tryParse('${json['checkInAt']}')?.toLocal()
        : null,
    status: json['status'] as String?,
    checkInLat: (json['checkInLat'] as num?)?.toDouble(),
    checkInLng: (json['checkInLng'] as num?)?.toDouble(),
  );
}

class _TrackedEmployee {
  const _TrackedEmployee({
    required this.employeeUserId,
    required this.name,
    required this.id,
    required this.mode,
    required this.active,
    this.lat,
    this.lng,
    this.address,
    this.lastUpdated,
    this.checkInAt,
    this.checkOutAt,
    this.isLate = false,
    this.onBreak = false,
    this.homeApprovalStatus,
    this.homeDistanceMeters,
    this.officeDistanceMeters,
    this.homeRadiusMeters,
    this.officeRadiusMeters,
    this.accuracyMeters,
    this.attendanceDate,
    this.recentAttendance = const [],
    this.workingMinutes,
    this.sessionStatus,
    this.checkInMethod,
    this.attendanceStatus,
    this.homeAddress,
    this.homeLat,
    this.homeLng,
  });

  final int? employeeUserId;
  final String name, id, mode;
  final bool active;
  final double? lat, lng;
  final String? address;
  final DateTime? lastUpdated;

  // Extended fields for desktop new UI
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final bool isLate;
  final bool onBreak;
  final String? homeApprovalStatus;
  final double? homeDistanceMeters;
  final double? officeDistanceMeters;
  final double? homeRadiusMeters;
  final double? officeRadiusMeters;
  final double? accuracyMeters;
  final String? attendanceDate;
  final List<_AttendanceDay> recentAttendance;
  final int? workingMinutes;
  final String? sessionStatus;
  final String? checkInMethod;
  final String? attendanceStatus;
  final String? homeAddress;
  final double? homeLat;
  final double? homeLng;

  factory _TrackedEmployee.fromApi(Map<String, dynamic> json) {
    final rawStatus = (json['status'] ?? '').toString();
    final mode =
        rawStatus.toLowerCase() == 'field' ||
            rawStatus.toLowerCase() == 'hybrid'
        ? 'Hybrid'
        : rawStatus.isEmpty
        ? 'Unknown'
        : rawStatus[0].toUpperCase() + rawStatus.substring(1).toLowerCase();
    final rawUpdated = json['lastUpdated'];
    final lastUpdated = rawUpdated != null
        ? DateTime.tryParse(rawUpdated.toString())
        : null;
    final rawCheckIn = json['checkInAt'] ?? json['check_in_at'];
    final checkInAt = rawCheckIn != null
        ? DateTime.tryParse('$rawCheckIn')?.toLocal()
        : null;
    final rawCheckOut = json['checkOutAt'] ?? json['check_out_at'];
    final checkOutAt = rawCheckOut != null
        ? DateTime.tryParse('$rawCheckOut')?.toLocal()
        : null;
    final recentRaw = json['recentAttendance'] as List? ?? [];
    return _TrackedEmployee(
      employeeUserId: json['employeeUserId'] is int
          ? json['employeeUserId'] as int
          : int.tryParse('${json['employeeUserId']}'),
      name: (json['name'] ?? '').toString(),
      id: (json['employeeCode'] ?? '').toString(),
      mode: mode,
      active: json['active'] == true,
      lat: (json['latitude'] as num?)?.toDouble(),
      lng: (json['longitude'] as num?)?.toDouble(),
      address: (json['address'] as String?)?.trim().isEmpty == true
          ? null
          : json['address'] as String?,
      lastUpdated: lastUpdated,
      checkInAt: checkInAt,
      checkOutAt: checkOutAt,
      isLate: json['isLate'] == true || json['is_late'] == true,
      onBreak: json['onBreak'] == true || json['on_break'] == true,
      homeApprovalStatus:
          json['homeApprovalStatus']?.toString() ??
          json['home_approval_status']?.toString(),
      homeDistanceMeters:
          (json['homeDistanceMeters'] as num?)?.toDouble() ??
          (json['home_distance_meters'] as num?)?.toDouble(),
      officeDistanceMeters:
          (json['officeDistanceMeters'] as num?)?.toDouble() ??
          (json['office_distance_meters'] as num?)?.toDouble(),
      homeRadiusMeters:
          (json['homeRadiusMeters'] as num?)?.toDouble() ??
          (json['home_radius_meters'] as num?)?.toDouble(),
      officeRadiusMeters:
          (json['officeRadiusMeters'] as num?)?.toDouble() ??
          (json['office_radius_meters'] as num?)?.toDouble(),
      accuracyMeters:
          (json['accuracyMeters'] as num?)?.toDouble() ??
          (json['accuracy_meters'] as num?)?.toDouble(),
      attendanceDate:
          json['attendanceDate']?.toString() ??
          json['attendance_date']?.toString(),
      recentAttendance: recentRaw
          .whereType<Map>()
          .map(
            (item) => _AttendanceDay.fromApi(Map<String, dynamic>.from(item)),
          )
          .toList(),
      workingMinutes:
          (json['workingMinutes'] as num?)?.toInt() ??
          (json['working_minutes'] as num?)?.toInt(),
      sessionStatus:
          json['sessionStatus']?.toString() ??
          json['session_status']?.toString(),
      checkInMethod:
          json['checkInMethod']?.toString() ??
          json['check_in_method']?.toString(),
      attendanceStatus:
          json['attendanceStatus']?.toString() ??
          json['attendance_status']?.toString(),
      homeAddress:
          json['homeAddress']?.toString() ?? json['home_address']?.toString(),
      homeLat:
          (json['homeLatitude'] as num?)?.toDouble() ??
          (json['home_latitude'] as num?)?.toDouble(),
      homeLng:
          (json['homeLongitude'] as num?)?.toDouble() ??
          (json['home_longitude'] as num?)?.toDouble(),
    );
  }

  String get updatedLabel {
    if (lastUpdated == null) return 'No pings yet';
    final minutes = DateTime.now().difference(lastUpdated!).inMinutes;
    if (minutes < 1) return 'Updated just now';
    if (minutes < 60) return 'Updated ${minutes}m ago';
    final hours = (minutes / 60).floor();
    return 'Updated ${hours}h ago';
  }
}

class _RoutePoint {
  const _RoutePoint({required this.time, required this.location});
  final String time, location;

  factory _RoutePoint.fromApi(Map<String, dynamic> json) {
    final rawTime = json['recordedAt']?.toString();
    final recorded = rawTime != null ? DateTime.tryParse(rawTime) : null;
    final time = recorded != null
        ? DateFormat('hh:mm a').format(recorded.toLocal())
        : '--:--';
    final address = (json['address'] as String?)?.trim();
    final lat = (json['latitude'] as num?)?.toDouble();
    final lng = (json['longitude'] as num?)?.toDouble();
    final location = (address != null && address.isNotEmpty)
        ? address
        : (lat != null && lng != null)
        ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
        : 'Unknown location';
    return _RoutePoint(time: time, location: location);
  }
}

class _AdminRoutePanel extends StatefulWidget {
  const _AdminRoutePanel({
    required this.employee,
    required this.onReturnToLiveMap,
    this.mode,
    this.onModeChanged,
  });
  final _TrackedEmployee employee;
  final VoidCallback onReturnToLiveMap;
  final String? mode;
  final ValueChanged<String>? onModeChanged;
  @override
  State<_AdminRoutePanel> createState() => _AdminRoutePanelState();
}

class _AdminRoutePanelState extends State<_AdminRoutePanel> {
  DateTime _date = DateTime.now();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  GoogleMapController? _routeMapController;

  Future<void> _fitRouteBounds(List<LatLng> points) async {
    if (_routeMapController == null || points.isEmpty) return;
    if (points.length == 1) {
      await _routeMapController!.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 15),
      );
      return;
    }
    var south = points.first.latitude, north = south;
    var west = points.first.longitude, east = west;
    for (final point in points.skip(1)) {
      south = point.latitude < south ? point.latitude : south;
      north = point.latitude > north ? point.latitude : north;
      west = point.longitude < west ? point.longitude : west;
      east = point.longitude > east ? point.longitude : east;
    }
    await _routeMapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        48,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AdminRoutePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employee.employeeUserId != widget.employee.employeeUserId) {
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.employee.employeeUserId;
    if (id == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await HrmsTrackingApi.route(
        employeeUserId: id,
        date: DateFormat('yyyy-MM-dd').format(_date),
      );
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _load();
    }
  }

  String _lastUpdatedLabel(dynamic value) {
    final timestamp = DateTime.tryParse('${value ?? ''}')?.toLocal();
    if (timestamp == null) return 'No updates yet';
    final difference = DateTime.now().difference(timestamp);
    if (difference.inMinutes < 1) return 'Updated just now';
    if (difference.inMinutes < 60) {
      return 'Updated ${difference.inMinutes}m ago';
    }
    if (difference.inHours < 24) return 'Updated ${difference.inHours}h ago';
    return 'Updated ${difference.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final points = (_data?['routePoints'] as List? ?? [])
        .whereType<Map>()
        .map(
          (p) => LatLng(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ),
        )
        .toList();
    final activities = (_data?['activities'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final markers = <Marker>{
      if (points.isNotEmpty)
        Marker(
          markerId: const MarkerId('S'),
          position: points.first,
          infoWindow: const InfoWindow(title: 'S — Start'),
        ),
      if (points.length > 1)
        Marker(
          markerId: const MarkerId('E'),
          position: points.last,
          infoWindow: const InfoWindow(title: 'E — End'),
        ),
      ...points
          .skip(1)
          .take(points.length > 2 ? points.length - 2 : 0)
          .map(
            (p) => Marker(
              markerId: MarkerId('${p.latitude},${p.longitude}'),
              position: p,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
            ),
          ),
    };
    final isMobileWidth = MediaQuery.sizeOf(context).width < 600;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE3E7EF)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobileWidth) ...[
            Text(
              widget.employee.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: HrmsColors.navy,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Text(
              'Route history',
              style: TextStyle(color: Color(0xFF657087), fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onReturnToLiveMap,
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Back to Live Map'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pick,
                    icon: const Icon(Icons.calendar_month_outlined, size: 16),
                    label: Text(
                      DateFormat('dd MMM yyyy').format(_date),
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.employee.name} — Route history',
                    style: const TextStyle(
                      color: HrmsColors.navy,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onReturnToLiveMap,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back to Live Map'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(DateFormat('dd MMM yyyy').format(_date)),
                ),
              ],
            ),
          if (widget.mode != null && widget.onModeChanged != null) ...[
            const SizedBox(height: 12),
            _MapModeTabs(
              mode: widget.mode!,
              onModeChanged: widget.onModeChanged!,
            ),
          ],
          const SizedBox(height: 14),
          if (_loading)
            const SizedBox(
              height: 250,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red))
          else if (points.isEmpty)
            const SizedBox(
              height: 180,
              child: Center(
                child: Text('No GPS route was recorded for the selected date'),
              ),
            )
          else ...[
            SizedBox(
              height: 320,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: points.first,
                    zoom: 14,
                  ),
                  polylines: {
                    Polyline(
                      polylineId: const PolylineId('route'),
                      points: points,
                      color: HrmsColors.blue,
                      width: 5,
                    ),
                  },
                  markers: markers,
                  mapToolbarEnabled: false,
                  onMapCreated: (controller) {
                    _routeMapController = controller;
                    Future.delayed(
                      const Duration(milliseconds: 250),
                      () => _fitRouteBounds(points),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            _AdminRouteSummaryStrip(
              distance:
                  '${((_data?['distanceMeters'] as num? ?? 0) / 1000).toStringAsFixed(2)} km',
              duration:
                  '${((_data?['durationSeconds'] as num? ?? 0) / 60).round()} min',
              averageSpeed:
                  '${(_data?['averageSpeedKmh'] as num? ?? 0).toStringAsFixed(1)} km/h',
              updated: _lastUpdatedLabel(_data?['lastUpdated']),
            ),
            const SizedBox(height: 10),
            const Text(
              'Activity history',
              style: TextStyle(
                color: HrmsColors.navy,
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final item in activities.take(8))
              ListTile(
                dense: true,
                leading: const Icon(
                  Icons.place_outlined,
                  color: HrmsColors.blue,
                ),
                title: Text('${item['placeName'] ?? 'Location pending'}'),
                subtitle: Text('${item['recordedAt'] ?? ''}'),
              ),
          ],
        ],
      ),
    );
  }
}

class _AdminRouteSummaryStrip extends StatelessWidget {
  const _AdminRouteSummaryStrip({
    required this.distance,
    required this.duration,
    required this.averageSpeed,
    required this.updated,
  });

  final String distance;
  final String duration;
  final String averageSpeed;
  final String updated;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F9FD),
      border: Border.all(color: const Color(0xFFE0E7F2)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final items = [
          _AdminRouteSummaryMetric(
            icon: Icons.route_outlined,
            label: 'Distance',
            value: distance,
          ),
          _AdminRouteSummaryMetric(
            icon: Icons.timer_outlined,
            label: 'Duration',
            value: duration,
          ),
          _AdminRouteSummaryMetric(
            icon: Icons.speed_outlined,
            label: 'Avg speed',
            value: averageSpeed,
          ),
          _AdminRouteSummaryMetric(
            icon: Icons.update_rounded,
            label: 'Updated',
            value: updated,
          ),
        ];
        if (compact) {
          return Wrap(
            spacing: 16,
            runSpacing: 12,
            children: items
                .map((item) => SizedBox(width: 170, child: item))
                .toList(),
          );
        }
        return Row(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              Expanded(child: items[index]),
              if (index < items.length - 1)
                const SizedBox(
                  height: 34,
                  child: VerticalDivider(color: Color(0xFFE0E7F2)),
                ),
            ],
          ],
        );
      },
    ),
  );
}

class _AdminRouteSummaryMetric extends StatelessWidget {
  const _AdminRouteSummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: const Color(0xFF00AB84), size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(color: Color(0xFF71809A), fontSize: 11),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: HrmsColors.navy,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _EmployeeActivityDialog extends StatefulWidget {
  const _EmployeeActivityDialog({required this.employee, required this.date});
  final _TrackedEmployee employee;
  final DateTime date;

  @override
  State<_EmployeeActivityDialog> createState() =>
      _EmployeeActivityDialogState();
}

class _EmployeeActivityDialogState extends State<_EmployeeActivityDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _activities = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final employeeUserId = widget.employee.employeeUserId;
    if (employeeUserId == null) {
      setState(() {
        _loading = false;
        _error = 'No employee ID is available for this activity history.';
      });
      return;
    }
    try {
      final data = await HrmsTrackingApi.route(
        employeeUserId: employeeUserId,
        date: DateFormat('yyyy-MM-dd').format(widget.date),
      );
      if (!mounted) return;
      setState(() {
        _activities = (data['activities'] as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _displayTime(dynamic value) {
    final date = DateTime.tryParse('${value ?? ''}');
    return date == null
        ? 'Time unavailable'
        : DateFormat('hh:mm a').format(date.toLocal());
  }

  String _displayPlace(dynamic value) {
    final place = '${value ?? ''}'.trim();
    return place.isEmpty || place == 'Location pending'
        ? 'Location name unavailable'
        : place;
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    return Dialog(
      backgroundColor: const Color(0xFFF9F9FF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 650, maxHeight: screenH * 0.85),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.employee.name} — Activity',
                      style: const TextStyle(
                        color: HrmsColors.navy,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 28),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFEDEDF4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${_activities.length} location update(s) on ${DateFormat('dd MMM yyyy').format(widget.date)}',
                style: const TextStyle(color: Color(0xFF657087), fontSize: 14),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F3FA),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text('TIME', style: _activityHeaderStyle),
                    ),
                    Text('PLACE', style: _activityHeaderStyle),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    : _activities.isEmpty
                    ? const Center(
                        child: Text(
                          'No GPS activity recorded for this date.',
                          style: TextStyle(
                            color: Color(0xFF657087),
                            fontSize: 16,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _activities.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Color(0xFFE2E6ED)),
                        itemBuilder: (_, index) {
                          final item = _activities[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 92,
                                  child: Text(
                                    _displayTime(item['recordedAt']),
                                    style: const TextStyle(
                                      color: HrmsColors.navy,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _displayPlace(item['placeName']),
                                    style: const TextStyle(
                                      color: Color(0xFF3E4658),
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
    );
  }
}

const _activityHeaderStyle = TextStyle(
  color: Color(0xFF657087),
  fontSize: 12,
  fontWeight: FontWeight.w700,
);

class _RouteDialog extends StatefulWidget {
  const _RouteDialog({required this.employee});
  final _TrackedEmployee employee;

  @override
  State<_RouteDialog> createState() => _RouteDialogState();
}

class _RouteDialogState extends State<_RouteDialog> {
  bool loading = true;
  String? error;
  List<_RoutePoint> points = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final employeeUserId = widget.employee.employeeUserId;
    if (employeeUserId == null) {
      setState(() {
        loading = false;
        error = 'No employee ID available for this row';
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final data = await HrmsTrackingApi.route(
        employeeUserId: employeeUserId,
        date: today,
      );
      final items = (data['points'] as List? ?? [])
          .whereType<Map>()
          .map((item) => _RoutePoint.fromApi(Map<String, dynamic>.from(item)))
          .toList();
      if (!mounted) return;
      setState(() {
        points = items;
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

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.employee.name} — Today\'s Route',
                    style: const TextStyle(
                      color: HrmsColors.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            Text(
              '${widget.employee.id} · ${widget.employee.mode} mode',
              style: const TextStyle(color: Color(0xFF657087), fontSize: 12),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : error != null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    )
                  : points.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'No location pings recorded for this employee today.',
                        style: TextStyle(
                          color: Color(0xFF657087),
                          fontSize: 12,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final point in points)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    margin: const EdgeInsets.only(top: 4),
                                    decoration: const BoxDecoration(
                                      color: HrmsColors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          point.time,
                                          style: const TextStyle(
                                            color: HrmsColors.navy,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          point.location,
                                          style: const TextStyle(
                                            color: Color(0xFF596176),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _OfficeLocationDialog extends StatefulWidget {
  const _OfficeLocationDialog();

  @override
  State<_OfficeLocationDialog> createState() => _OfficeLocationDialogState();
}

class _OfficeLocationDialogState extends State<_OfficeLocationDialog> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _matches = [];
  LatLng? _pin;
  GoogleMapController? _mapController;
  bool _searching = false;
  bool _loaded = false;
  int _searchVersion = 0;
  String? _searchError;
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _radius = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _gpsLoading = false;
  String? _error;

  static const _blue = Color(0xFF075EF7);
  static const _navy = Color(0xFF061457);
  static const _muted = Color(0xFF657087);
  static const _line = Color(0xFFE3E9F4);
  static const _inputBorder = Color(0xFFD0DBEE);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchVersion++;
    _search.dispose();
    _mapController?.dispose();
    _name.dispose();
    _address.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _radius.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await HrmsTrackingApi.trackingSettings();
      if (!mounted) return;
      setState(() {
        _name.text = '${data['office_name'] ?? ''}';
        _address.text = '${data['office_address'] ?? ''}';
        _latitude.text = '${data['office_latitude'] ?? ''}';
        _longitude.text = '${data['office_longitude'] ?? ''}';
        _radius.text = '${data['office_radius_meters'] ?? ''}';
        final lat = double.tryParse(_latitude.text);
        final lng = double.tryParse(_longitude.text);
        _pin = lat != null && lng != null && lat.isFinite && lng.isFinite
            ? LatLng(lat, lng)
            : null;
        _loaded = true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        final msg = error.toString().replaceFirst('Exception: ', '');
        _error = msg.contains('Route not found')
            ? 'The running backend is an older version. Start the backend from Go-digital-software, then Retry.'
            : msg;
      });
    }
  }

  Future<void> _captureGps() async {
    if (_gpsLoading || _saving) return;
    setState(() {
      _gpsLoading = true;
      _error = null;
    });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied.');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permission permanently denied. Enable it in Settings.',
        );
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      final point = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _pin = point;
        _latitude.text = pos.latitude.toStringAsFixed(7);
        _longitude.text = pos.longitude.toStringAsFixed(7);
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(point, 17));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _findAddress() async {
    if (_searching || _saving) return;
    final query = _search.text.trim();
    if (query.length < 3) {
      setState(() => _searchError = 'Enter a street address and city.');
      return;
    }
    final version = ++_searchVersion;
    setState(() {
      _searching = true;
      _searchError = null;
      _matches = [];
    });
    try {
      final matches = await searchOfficeAddress(query);
      if (!mounted || version != _searchVersion) return;
      setState(() {
        _matches = matches;
        if (matches.isEmpty) {
          _searchError = 'No matches. Add a city or postcode and search again.';
        }
      });
    } catch (error) {
      if (!mounted || version != _searchVersion) return;
      setState(
        () => _searchError = error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted && version == _searchVersion) {
        setState(() => _searching = false);
      }
    }
  }

  void _selectPin(LatLng point, {String? address}) {
    if (_saving) return;
    setState(() {
      _pin = point;
      _latitude.text = point.latitude.toStringAsFixed(7);
      _longitude.text = point.longitude.toStringAsFixed(7);
      if (address != null) _address.text = address;
      _matches = [];
    });
    if (address != null) {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(point, 17));
    }
  }

  Future<void> _save() async {
    if (!_loaded || _saving || _searching) return;
    final name = _name.text.trim();
    final address = _address.text.trim();
    final latitude = double.tryParse(_latitude.text.trim());
    final longitude = double.tryParse(_longitude.text.trim());
    final radius = int.tryParse(_radius.text.trim());
    if (name.isEmpty ||
        address.isEmpty ||
        latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        radius == null ||
        radius < 1) {
      setState(
        () => _error =
            'Enter an office name and address, select a map pin, and enter a valid radius.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await HrmsTrackingApi.updateOfficeLocation(
        officeName: name,
        officeAddress: address,
        officeLatitude: latitude,
        officeLongitude: longitude,
        officeRadiusMeters: radius,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Office location saved for all employees.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  InputDecoration _dec(String label, {String? helper}) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: _muted, fontSize: 13),
    helperText: helper,
    helperStyle: const TextStyle(color: _muted, fontSize: 11),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _inputBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _blue, width: 1.5),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _inputBorder),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    filled: true,
    fillColor: Colors.white,
  );

  Widget _searchBar() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _inputBorder),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Icon(Icons.search, color: _muted, size: 20),
            ),
            Expanded(
              child: TextField(
                controller: _search,
                enabled: !_saving && !_searching,
                onSubmitted: (_) => _findAddress(),
                style: const TextStyle(fontSize: 14, color: _navy),
                decoration: const InputDecoration(
                  hintText: 'Search office address',
                  hintStyle: TextStyle(color: _muted, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 14,
                  ),
                ),
              ),
            ),
            InkWell(
              onTap: _saving || _searching ? null : _findAddress,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: const Icon(Icons.arrow_forward, color: _navy, size: 20),
              ),
            ),
          ],
        ),
      ),
      if (_searching)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: LinearProgressIndicator(),
        ),
      if (_searchError != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _searchError!,
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      for (final match in _matches)
        ListTile(
          dense: true,
          leading: const Icon(Icons.place_outlined, size: 18),
          title: Text(
            '${match['address']}',
            style: const TextStyle(fontSize: 13),
          ),
          onTap: () => _selectPin(
            LatLng(match['latitude'] as double, match['longitude'] as double),
            address: match['address'] as String,
          ),
        ),
    ],
  );

  Widget _map() => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      height: 180,
      child: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _pin ?? const LatLng(20.5937, 78.9629),
          zoom: _pin == null ? 4 : 17,
        ),
        onMapCreated: (c) => _mapController = c,
        onTap: _saving ? null : _selectPin,
        mapToolbarEnabled: false,
        markers: {
          if (_pin != null)
            Marker(
              markerId: const MarkerId('office-location'),
              position: _pin!,
              draggable: !_saving,
              onDragEnd: _selectPin,
              infoWindow: const InfoWindow(title: 'Office entrance'),
            ),
        },
        circles: {
          if (_pin != null)
            Circle(
              circleId: const CircleId('office-radius'),
              center: _pin!,
              radius: (int.tryParse(_radius.text) ?? 100)
                  .clamp(1, 100000)
                  .toDouble(),
              strokeColor: _blue,
              strokeWidth: 2,
              fillColor: _blue.withValues(alpha: 0.12),
            ),
        },
      ),
    ),
  );

  Widget _gpsButton({bool fullWidth = false}) {
    final btn = OutlinedButton.icon(
      onPressed: (_gpsLoading || _saving) ? null : _captureGps,
      icon: _gpsLoading
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _blue),
            )
          : const Icon(Icons.my_location_rounded, size: 18),
      label: Text(_gpsLoading ? 'Getting GPS...' : 'Capture Current GPS'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _blue,
        side: const BorderSide(color: _blue),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      ),
    );
    if (fullWidth) return SizedBox(width: double.infinity, child: btn);
    return btn;
  }

  Widget _body(bool isMobile) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Office name
        TextField(
          controller: _name,
          enabled: !_saving,
          style: const TextStyle(color: _navy, fontSize: 14),
          decoration: _dec('Office / branch name'),
        ),
        const SizedBox(height: 14),
        // Search bar
        _searchBar(),
        const SizedBox(height: 12),
        // GPS button
        if (isMobile) ...[
          _gpsButton(fullWidth: true),
          const SizedBox(height: 6),
          const Text(
            'Use this device\'s current location.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ] else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Use this device\'s current location',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              _gpsButton(),
            ],
          ),
        const SizedBox(height: 12),
        // Map
        _map(),
        const SizedBox(height: 8),
        Text(
          _pin == null
              ? 'Search and select an address, or tap the map to place your office pin.'
              : 'Drag the pin to the office entrance. Coordinates are filled automatically.',
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        // Lat / Lng side-by-side
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Latitude',
                    style: TextStyle(
                      color: _navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _latitude,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    style: const TextStyle(color: _navy, fontSize: 14),
                    decoration: _dec(''),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Longitude',
                    style: TextStyle(
                      color: _navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _longitude,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    style: const TextStyle(color: _navy, fontSize: 14),
                    decoration: _dec(''),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Full address
        const Text(
          'Full office address',
          style: TextStyle(
            color: _navy,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _address,
          enabled: !_saving,
          minLines: 2,
          maxLines: 3,
          style: const TextStyle(color: _navy, fontSize: 14),
          decoration: _dec(''),
        ),
        const SizedBox(height: 14),
        // Radius
        TextField(
          controller: _radius,
          enabled: !_saving,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: _navy, fontSize: 14),
          decoration: _dec(
            'Allowed Check In radius (metres)',
            helper: 'This distance also applies to approved home locations.',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: 4),
      ],
    ),
  );

  Widget _footer(bool isMobile) => Container(
    padding: EdgeInsets.fromLTRB(
      isMobile ? 12 : 16,
      8,
      isMobile ? 12 : 16,
      isMobile ? 12 : 12,
    ),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: _line)),
      color: Colors.white,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (!_loaded && !_loading)
          TextButton(onPressed: _load, child: const Text('Retry')),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: _navy),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _saving || _loading || !_loaded || _searching
              ? null
              : _save,
          style: FilledButton.styleFrom(
            backgroundColor: _blue,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          icon: _saving
              ? const SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_outlined, size: 16),
          label: Text(
            _saving ? 'Saving...' : 'Save Location',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    ),
  );

  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _line)),
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFE8EFFE),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.location_on_rounded, color: _blue, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Manage Office Location',
                style: TextStyle(
                  color: _navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Configure the company office geofence used for employee clock-in',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.close, color: _muted, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    if (isMobile) {
      return Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: _loading
                    ? const SizedBox(
                        height: 220,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _body(true),
              ),
            ),
            _footer(true),
          ],
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 820),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: _loading
                    ? const SizedBox(
                        height: 220,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _body(false),
              ),
            ),
            _footer(false),
          ],
        ),
      ),
    );
  }
}

class _FieldWaitingSettingsDialog extends StatefulWidget {
  const _FieldWaitingSettingsDialog();

  @override
  State<_FieldWaitingSettingsDialog> createState() =>
      _FieldWaitingSettingsDialogState();
}

class _FieldWaitingSettingsDialogState
    extends State<_FieldWaitingSettingsDialog> {
  final _waitingCtrl = TextEditingController();
  final _stationaryCtrl = TextEditingController();
  final _pingCtrl = TextEditingController();
  final _officeGraceCtrl = TextEditingController();
  final _officeNoGpsCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  DateTime? _lastUpdated;
  String? _error;

  static const _blue = Color(0xFF0B5FFF);
  static const _navy = Color(0xFF061457);
  static const _muted = Color(0xFF657087);
  static const _line = Color(0xFFE3E9F4);
  static const _cardBg = Colors.white;
  static const _cardBorder = Color(0xFFE0E8F8);
  static const _iconBg = Color(0xFFFFF0E0);
  static const _iconColor = Color(0xFFE07A00);
  static const _infoBg = Color(0xFFEFF4FF);
  static const _infoBorder = Color(0xFFBFD1FF);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _waitingCtrl.dispose();
    _stationaryCtrl.dispose();
    _pingCtrl.dispose();
    _officeGraceCtrl.dispose();
    _officeNoGpsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await HrmsTrackingApi.trackingSettings();
      if (!mounted) return;
      setState(() {
        _waitingCtrl.text = '${data['field_waiting_minutes'] ?? 60}';
        _stationaryCtrl.text = '${data['stationary_radius_meters'] ?? 50}';
        _pingCtrl.text = '${data['field_ping_interval_minutes'] ?? 15}';
        _officeGraceCtrl.text =
            '${data['office_outside_radius_grace_minutes'] ?? 5}';
        _officeNoGpsCtrl.text =
            '${data['office_no_gps_timeout_minutes'] ?? 30}';
        final updated = data['updated_at'];
        _lastUpdated = updated != null ? DateTime.tryParse('$updated') : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final waiting = int.tryParse(_waitingCtrl.text.trim());
    final stationary = int.tryParse(_stationaryCtrl.text.trim());
    final ping = int.tryParse(_pingCtrl.text.trim());
    final officeGrace = int.tryParse(_officeGraceCtrl.text.trim());
    final officeNoGps = int.tryParse(_officeNoGpsCtrl.text.trim());

    if (waiting == null ||
        waiting < 1 ||
        stationary == null ||
        stationary < 1 ||
        ping == null ||
        ping < 1 ||
        officeGrace == null ||
        officeGrace < 1 ||
        officeNoGps == null ||
        officeNoGps < 1) {
      setState(
        () => _error = 'All fields must be whole numbers greater than zero.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await HrmsTrackingApi.updateHybridSettings(
        fieldWaitingMinutes: waiting,
        stationaryRadiusMeters: stationary,
        fieldPingIntervalMinutes: ping,
        officeOutsideRadiusGraceMinutes: officeGrace,
        officeNoGpsTimeoutMinutes: officeNoGps,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _lastUpdated = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hybrid tracking settings saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── widgets ───────────────────────────────────────────────────────────────

  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: _line)),
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.home_work_rounded,
            color: _iconColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Hybrid Settings',
                style: TextStyle(
                  color: _navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Configure tracking behaviour and checkout rules for Office and Hybrid employees.',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: _muted, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ],
    ),
  );

  Widget _infoBanner(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: _infoBg,
      border: Border.all(color: _infoBorder),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: _blue, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: _navy, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    ),
  );

  Widget _settingCard({
    required IconData icon,
    required String title,
    required String desc,
    required TextEditingController ctrl,
    required String unit,
  }) {
    final isMins = unit == 'minute';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        border: Border.all(color: _cardBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              color: _navy,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              suffixText: isMins ? 'minute' : unit,
              suffixStyle: const TextStyle(
                color: _muted,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _blue, width: 1.5),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _cardBorder),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String _lastUpdatedLabel() {
    if (_lastUpdated == null) return '';
    final diff = DateTime.now().difference(_lastUpdated!);
    if (diff.inSeconds < 60) return 'Last updated just now';
    if (diff.inMinutes < 60) return 'Last updated ${diff.inMinutes}m ago';
    return 'Last updated ${diff.inHours}h ago';
  }

  Widget _footer() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 400;
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _line)),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            Row(
              children: [
                const Spacer(),
                OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _navy,
                    side: const BorderSide(color: _line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading || _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 12 : 18,
                      vertical: 10,
                    ),
                  ),
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          compact ? 'Save' : 'Save Settings',
                          style: const TextStyle(fontSize: 13),
                        ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: isMobile ? 12 : 20,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            Flexible(
              child: _loading
                  ? const SizedBox(
                      height: 220,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : SingleChildScrollView(
                      padding: EdgeInsets.all(isMobile ? 12 : 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _infoBanner(
                            'Hybrid waiting uses the first three tracking settings. '
                            'Office/Hybrid and Home checkout grace are saved separately.',
                          ),
                          const SizedBox(height: 16),
                          // 2×2 grid — wrap to single column on mobile
                          if (isMobile) ...[
                            _settingCard(
                              icon: Icons.timer_outlined,
                              title: 'Waiting Time',
                              desc:
                                  'Time an employee must remain stationary before a stop is detected.',
                              ctrl: _waitingCtrl,
                              unit: 'minute',
                            ),
                            const SizedBox(height: 12),
                            _settingCard(
                              icon: Icons.location_searching_rounded,
                              title: 'Stationary Radius',
                              desc:
                                  'Movement within this radius is treated as one stationary location.',
                              ctrl: _stationaryCtrl,
                              unit: 'metres',
                            ),
                            const SizedBox(height: 12),
                            _settingCard(
                              icon: Icons.wifi_tethering_rounded,
                              title: 'GPS Update Interval',
                              desc:
                                  "How often the employee's live location is refreshed.",
                              ctrl: _pingCtrl,
                              unit: 'minute',
                            ),
                            const SizedBox(height: 12),
                            _settingCard(
                              icon: Icons.update_rounded,
                              title: 'Office / Hybrid Checkout Grace',
                              desc:
                                  'Allowed time outside the radius before auto-checkout for Office and Hybrid.',
                              ctrl: _officeGraceCtrl,
                              unit: 'minutes',
                            ),
                            const SizedBox(height: 12),
                            _settingCard(
                              icon: Icons.signal_wifi_off_rounded,
                              title: 'Office No-GPS Timeout',
                              desc:
                                  'Auto-checkout Office/Hybrid employees if no GPS ping is received for this long.',
                              ctrl: _officeNoGpsCtrl,
                              unit: 'minutes',
                            ),
                          ] else ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _settingCard(
                                    icon: Icons.timer_outlined,
                                    title: 'Waiting Time',
                                    desc:
                                        'Time an employee must remain stationary before a stop is detected.',
                                    ctrl: _waitingCtrl,
                                    unit: 'minute',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _settingCard(
                                    icon: Icons.location_searching_rounded,
                                    title: 'Stationary Radius',
                                    desc:
                                        'Movement within this radius is treated as one stationary location.',
                                    ctrl: _stationaryCtrl,
                                    unit: 'metres',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _settingCard(
                                    icon: Icons.wifi_tethering_rounded,
                                    title: 'GPS Update Interval',
                                    desc:
                                        "How often the employee's live location is refreshed.",
                                    ctrl: _pingCtrl,
                                    unit: 'minute',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _settingCard(
                                    icon: Icons.update_rounded,
                                    title: 'Office / Hybrid Checkout Grace',
                                    desc:
                                        'Allowed time outside the radius before auto-checkout for Office and Hybrid.',
                                    ctrl: _officeGraceCtrl,
                                    unit: 'minutes',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _settingCard(
                                    icon: Icons.signal_wifi_off_rounded,
                                    title: 'Office No-GPS Timeout',
                                    desc:
                                        'Auto-checkout Office/Hybrid employees if no GPS ping is received for this long.',
                                    ctrl: _officeNoGpsCtrl,
                                    unit: 'minutes',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(child: SizedBox()),
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),
                          _infoBanner(
                            'Home checkout grace is configured separately in Home Approvals.',
                          ),
                        ],
                      ),
                    ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }
}

class _FieldWaitingReasonsDialog extends StatefulWidget {
  const _FieldWaitingReasonsDialog();

  @override
  State<_FieldWaitingReasonsDialog> createState() =>
      _FieldWaitingReasonsDialogState();
}

class _FieldWaitingReasonsDialogState
    extends State<_FieldWaitingReasonsDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await HrmsTrackingApi.fieldWaitingReasons();

      if (!mounted) return;

      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _markReviewed(int id) async {
    try {
      await HrmsTrackingApi.reviewFieldWaitingReason(id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting reason marked as reviewed')),
      );

      await _load();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.fact_check_outlined, color: HrmsColors.blue),
        SizedBox(width: 10),
        Text('Submitted Waiting Reasons'),
      ],
    ),
    content: SizedBox(
      width: 720,
      height: 440,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : _items.isEmpty
          ? const Center(child: Text('No waiting reasons submitted yet.'))
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final item = _items[index];
                final id = int.tryParse('${item['id']}');
                final fullName = '${item['full_name'] ?? 'Unknown employee'}';
                final employeeCode = '${item['employee_code'] ?? ''}';
                final reason = '${item['reason'] ?? ''}';
                final minutes = '${item['waiting_minutes'] ?? 0}';
                final status = '${item['review_status'] ?? 'pending'}';
                final submittedAt = '${item['reason_submitted_at'] ?? ''}';

                final reviewed = status == 'reviewed';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFFEAF1FF),
                        child: Text(
                          fullName.isNotEmpty ? fullName.substring(0, 1) : '?',
                          style: const TextStyle(
                            color: HrmsColors.blue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: HrmsColors.navy,
                              ),
                            ),
                            Text(
                              '$employeeCode · Waited $minutes minutes',
                              style: const TextStyle(
                                color: Color(0xFF657087),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(reason),
                            const SizedBox(height: 5),
                            Text(
                              submittedAt,
                              style: const TextStyle(
                                color: Color(0xFF657087),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      reviewed
                          ? const Chip(
                              label: Text('Reviewed'),
                              backgroundColor: Color(0xFFE4F6E8),
                            )
                          : TextButton(
                              onPressed: id == null
                                  ? null
                                  : () => _markReviewed(id),
                              child: const Text('Mark Reviewed'),
                            ),
                    ],
                  ),
                );
              },
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}

const _headStyle = TextStyle(
  color: Color(0xFF171B25),
  fontSize: 12,
  fontWeight: FontWeight.w600,
);
