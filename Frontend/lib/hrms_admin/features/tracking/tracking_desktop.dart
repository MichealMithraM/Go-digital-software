part of 'tracking_page.dart';

const _desktopBorder = Color(0xFFDDE5F1);
const _desktopMuted = Color(0xFF62708E);
const _desktopGreen = Color(0xFF12A150);
const _desktopOrange = Color(0xFFF59E0B);
const _desktopRed = Color(0xFFEF3340);

class _DesktopTrackingDashboard extends StatelessWidget {
  const _DesktopTrackingDashboard({
    required this.mode,
    required this.employees,
    required this.selectedEmployee,
    required this.selectedDate,
    required this.lastLoadedAt,
    required this.onModeChanged,
    required this.onDateChanged,
    required this.onSelectEmployee,
    required this.onViewActivity,
    required this.onHomeApprovals,
    required this.onViewReport,
  });

  final String mode;
  final List<_TrackedEmployee> employees;
  final _TrackedEmployee? selectedEmployee;
  final DateTime selectedDate;
  final DateTime? lastLoadedAt;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<_TrackedEmployee> onSelectEmployee;
  final ValueChanged<_TrackedEmployee> onViewActivity;
  final VoidCallback onHomeApprovals;
  final ValueChanged<_TrackedEmployee> onViewReport;

  @override
  Widget build(BuildContext context) {
    final selected =
        employees.any(
          (item) => item.employeeUserId == selectedEmployee?.employeeUserId,
        )
        ? selectedEmployee
        : (employees.isEmpty ? null : employees.first);
    return Column(
      children: [
        _DesktopTrackingKpis(mode: mode, employees: employees),
        const SizedBox(height: 20),
        SizedBox(
          height: 650,
          child: Row(
            children: [
              Expanded(
                flex: mode == 'Hybrid' ? 39 : 46,
                child: _DesktopEmployeePanel(
                  mode: mode,
                  employees: employees,
                  selected: selected,
                  selectedDate: selectedDate,
                  lastLoadedAt: lastLoadedAt,
                  onModeChanged: onModeChanged,
                  onDateChanged: onDateChanged,
                  onSelect: onSelectEmployee,
                  onViewActivity: onViewActivity,
                  onViewReport: onViewReport,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: mode == 'Hybrid' ? 61 : 54,
                child: _DesktopEmployeeDetail(
                  key: ValueKey(
                    '${mode}_${selected?.employeeUserId}_${DateFormat('yyyy-MM-dd').format(selectedDate)}',
                  ),
                  mode: mode,
                  employee: selected,
                  selectedDate: selectedDate,
                  onViewActivity: onViewActivity,
                  onHomeApprovals: onHomeApprovals,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopTrackingKpis extends StatelessWidget {
  const _DesktopTrackingKpis({required this.mode, required this.employees});

  final String mode;
  final List<_TrackedEmployee> employees;

  @override
  Widget build(BuildContext context) {
    final checkedIn = employees.where((item) => item.checkInAt != null).length;
    final late = employees
        .where((item) => item.checkInAt != null && item.isLate)
        .length;
    final lateCount = employees
        .where((item) => item.checkInAt != null && item.isLate)
        .length;
    final active = employees
        .where((item) => item.active && !item.onBreak)
        .length;
    final breaks = employees.where((item) => item.onBreak).length;
    final cards = mode == 'Office'
        ? [
            _DesktopKpiData(
              'Office',
              employees.length,
              'Total office employees',
              Icons.apartment_rounded,
              HrmsColors.blue,
            ),
            _DesktopKpiData(
              'Checked In',
              checkedIn,
              'Employees checked in',
              Icons.person_outline_rounded,
              _desktopGreen,
            ),
            _DesktopKpiData(
              'Late',
              late,
              'Employees checked in late',
              Icons.schedule_rounded,
              const Color(0xFFFF6A00),
            ),
            _DesktopKpiData(
              'Not Checked In',
              employees.length - checkedIn,
              'Employees not checked in',
              Icons.person_off_outlined,
              _desktopRed,
            ),
          ]
        : mode == 'Home'
        ? [
            _DesktopKpiData(
              'Home',
              employees.length,
              'Tracked employees',
              Icons.home_outlined,
              _desktopGreen,
            ),
            _DesktopKpiData(
              'Checked In',
              checkedIn,
              'Employees checked in',
              Icons.verified_user_outlined,
              HrmsColors.blue,
            ),
            _DesktopKpiData(
              'Late',
              lateCount,
              'Checked in late',
              Icons.schedule_rounded,
              const Color(0xFFFF7A00),
            ),
            _DesktopKpiData(
              'Not Checked In',
              employees.length - checkedIn,
              'Employees not checked in',
              Icons.close_rounded,
              _desktopRed,
            ),
          ]
        : [
            _DesktopKpiData(
              'Hybrid',
              employees.length,
              'Tracked employees',
              Icons.hiking_rounded,
              const Color(0xFFFF5A1F),
            ),
            _DesktopKpiData(
              'Active Now',
              active,
              'Employees active',
              Icons.wifi_rounded,
              _desktopGreen,
            ),
            _DesktopKpiData(
              'On Break',
              breaks,
              'Employees on break',
              Icons.coffee_outlined,
              _desktopOrange,
            ),
            _DesktopKpiData(
              'Offline',
              employees.length - active - breaks,
              'Employees offline',
              Icons.wifi_off_rounded,
              const Color(0xFF64748B),
            ),
          ];
    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 14),
          Expanded(child: _DesktopKpiCard(data: cards[i])),
        ],
      ],
    );
  }
}

class _DesktopKpiData {
  const _DesktopKpiData(
    this.label,
    this.value,
    this.caption,
    this.icon,
    this.color,
  );
  final String label, caption;
  final int value;
  final IconData icon;
  final Color color;
}

class _DesktopKpiCard extends StatelessWidget {
  const _DesktopKpiCard({required this.data});
  final _DesktopKpiData data;

  @override
  Widget build(BuildContext context) => Container(
    height: 108,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _desktopBorder),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: .11),
                  shape: BoxShape.circle,
                ),
                child: Icon(data.icon, color: data.color, size: 30),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      data.label,
                      style: const TextStyle(
                        color: _desktopMuted,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${data.value}',
                      style: const TextStyle(
                        color: Color(0xFF0D1838),
                        fontSize: 27,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      data.caption,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _desktopMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 62,
            height: 4,
            decoration: BoxDecoration(
              color: HrmsColors.blue,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ],
    ),
  );
}

class _DesktopEmployeePanel extends StatefulWidget {
  const _DesktopEmployeePanel({
    required this.mode,
    required this.employees,
    required this.selected,
    required this.selectedDate,
    required this.lastLoadedAt,
    required this.onModeChanged,
    required this.onDateChanged,
    required this.onSelect,
    required this.onViewActivity,
    required this.onViewReport,
  });

  final String mode;
  final List<_TrackedEmployee> employees;
  final _TrackedEmployee? selected;
  final DateTime selectedDate;
  final DateTime? lastLoadedAt;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<_TrackedEmployee> onSelect;
  final ValueChanged<_TrackedEmployee> onViewActivity;
  final ValueChanged<_TrackedEmployee> onViewReport;

  @override
  State<_DesktopEmployeePanel> createState() => _DesktopEmployeePanelState();
}

class _DesktopEmployeePanelState extends State<_DesktopEmployeePanel> {
  String query = '';

  String get updated {
    final value = widget.lastLoadedAt;
    if (value == null) return 'Updating…';
    final seconds = DateTime.now().difference(value).inSeconds;
    if (seconds < 5) return 'Updated just now';
    if (seconds < 60) return 'Updated ${seconds}s ago';
    return 'Updated ${(seconds / 60).floor()}m ago';
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) widget.onDateChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final rows = widget.employees.where((employee) {
      return needle.isEmpty ||
          employee.name.toLowerCase().contains(needle) ||
          employee.id.toLowerCase().contains(needle);
    }).toList();
    return _desktopSurface(
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.mode} Employees',
                    style: const TextStyle(
                      color: Color(0xFF10162E),
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(Icons.circle, size: 10, color: _desktopGreen),
                const SizedBox(width: 9),
                Text(
                  updated,
                  style: const TextStyle(color: _desktopMuted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _DesktopModeTabs(
                    mode: widget.mode,
                    onChanged: widget.onModeChanged,
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 205,
                  child: _dateButton(pickDate, widget.selectedDate),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _searchField('Search ${widget.mode.toLowerCase()} employee'),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: _desktopBorder),
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: rows.isEmpty
                    ? const _EmptyTrackedState()
                    : Column(
                        children: [
                          _DesktopTableHeader(mode: widget.mode),
                          Expanded(
                            child: ListView.builder(
                              itemCount: rows.length,
                              itemBuilder: (_, index) {
                                final employee = rows[index];
                                return _DesktopEmployeeRow(
                                  mode: widget.mode,
                                  employee: employee,
                                  selected:
                                      widget.selected?.employeeUserId ==
                                      employee.employeeUserId,
                                  onTap: () => widget.onSelect(employee),
                                  onHistory: () =>
                                      widget.onViewActivity(employee),
                                  onViewReport: () =>
                                      widget.onViewReport(employee),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchField(String hint) => TextField(
    onChanged: (value) => setState(() => query = value),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF8A96AC), fontSize: 12),
      prefixIcon: const Icon(Icons.search_rounded, color: _desktopMuted),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: _desktopBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: _desktopBorder),
      ),
    ),
  );

  Widget _dateButton(VoidCallback onTap, DateTime date) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF14203E),
      minimumSize: const Size.fromHeight(45),
      alignment: Alignment.centerLeft,
      side: const BorderSide(color: _desktopBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.calendar_month_outlined,
          size: 19,
          color: HrmsColors.blue,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(DateFormat('dd MMM yyyy').format(date))),
        const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
      ],
    ),
  );
}

class _DesktopModeTabs extends StatelessWidget {
  const _DesktopModeTabs({required this.mode, required this.onChanged});
  final String mode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    decoration: BoxDecoration(
      border: Border.all(color: _desktopBorder),
      borderRadius: BorderRadius.circular(25),
    ),
    child: Row(
      children: [
        for (final item in const ['Office', 'Home', 'Hybrid'])
          Expanded(
            child: InkWell(
              onTap: () => onChanged(item),
              borderRadius: BorderRadius.circular(24),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: mode == item ? HrmsColors.blue : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  item,
                  style: TextStyle(
                    color: mode == item
                        ? Colors.white
                        : const Color(0xFF10162E),
                    fontSize: 13,
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

class _DesktopTableHeader extends StatelessWidget {
  const _DesktopTableHeader({required this.mode});
  final String mode;

  @override
  Widget build(BuildContext context) {
    final labels = mode == 'Office'
        ? const ['Employee', 'Check-in Time', 'Actions']
        : mode == 'Home'
        ? const ['Employee', 'Check-in Time', 'Status']
        : const ['Employee', 'Status', 'Last Ping'];
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: const Color(0xFFFBFCFF),
      child: Row(
        children: [
          Expanded(flex: 42, child: Text(labels[0], style: _deskHead)),
          Expanded(flex: 35, child: Text(labels[1], style: _deskHead)),
          Expanded(flex: 23, child: Text(labels[2], style: _deskHead)),
        ],
      ),
    );
  }
}

const _deskHead = TextStyle(
  color: Color(0xFF17213E),
  fontSize: 11,
  fontWeight: FontWeight.w700,
);

class _DesktopEmployeeRow extends StatelessWidget {
  const _DesktopEmployeeRow({
    required this.mode,
    required this.employee,
    required this.selected,
    required this.onTap,
    required this.onHistory,
    required this.onViewReport,
  });
  final String mode;
  final _TrackedEmployee employee;
  final bool selected;
  final VoidCallback onTap, onHistory, onViewReport;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFFEAF4FF) : Colors.white,
    child: InkWell(
      onTap: onTap,
      child: Container(
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: selected
              ? const Border(
                  left: BorderSide(color: HrmsColors.blue, width: 2),
                  top: BorderSide(color: _desktopBorder),
                )
              : const Border(top: BorderSide(color: _desktopBorder)),
        ),
        child: Row(
          children: [
            Expanded(flex: 42, child: _employeeIdentity(employee, onViewReport)),
            Expanded(flex: 35, child: _secondCell()),
            Expanded(flex: 23, child: _actions()),
          ],
        ),
      ),
    ),
  );

  Widget _secondCell() {
    if (mode == 'Hybrid') return _trackingStatus(employee);
    if (employee.checkInAt == null) {
      return const Text('-', style: TextStyle(color: _desktopMuted));
    }
    final color = employee.isLate ? const Color(0xFFFF6A00) : _desktopGreen;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.circle, size: 9, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                employee.isLate ? 'Late' : 'Checked in',
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 17, top: 3),
          child: Text(
            DateFormat('h:mm a').format(employee.checkInAt!),
            style: const TextStyle(color: _desktopMuted, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _actions() {
    if (mode == 'Home') {
      return Row(
        children: [
          Flexible(child: _statusChip(employee, mode)),
          const Icon(
            Icons.chevron_right_rounded,
            color: _desktopMuted,
            size: 18,
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          tooltip: 'View on map',
          onPressed: onTap,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 36),
          icon: Icon(
            mode == 'Hybrid' ? Icons.location_on_outlined : Icons.map_outlined,
            color: HrmsColors.blue,
            size: 22,
          ),
        ),
        if (mode == 'Office')
          IconButton(
            tooltip: 'Activity history',
            onPressed: onHistory,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 36),
            icon: const Icon(
              Icons.history_rounded,
              color: Color(0xFF00A884),
              size: 22,
            ),
          )
        else
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_vert, color: _desktopMuted, size: 19),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'activity', child: Text('View activity')),
            ],
            onSelected: (_) => onHistory(),
          ),
      ],
    );
  }
}

class _DesktopEmployeeDetail extends StatelessWidget {
  const _DesktopEmployeeDetail({
    super.key,
    required this.mode,
    required this.employee,
    required this.selectedDate,
    required this.onViewActivity,
    required this.onHomeApprovals,
  });

  final String mode;
  final _TrackedEmployee? employee;
  final DateTime selectedDate;
  final ValueChanged<_TrackedEmployee> onViewActivity;
  final VoidCallback onHomeApprovals;

  @override
  Widget build(BuildContext context) {
    final value = employee;
    return _desktopSurface(
      value == null
          ? const Center(
              child: Text(
                'Select an employee to view tracking details',
                style: TextStyle(color: _desktopMuted),
              ),
            )
          : mode == 'Hybrid'
          ? _DesktopHybridDetail(employee: value, date: selectedDate)
          : _DesktopFixedLocationDetail(
              mode: mode,
              employee: value,
              onViewActivity: () => onViewActivity(value),
              onHomeApprovals: onHomeApprovals,
            ),
    );
  }
}

class _DesktopFixedLocationDetail extends StatefulWidget {
  const _DesktopFixedLocationDetail({
    required this.mode,
    required this.employee,
    required this.onViewActivity,
    required this.onHomeApprovals,
  });

  final String mode;
  final _TrackedEmployee employee;
  final VoidCallback onViewActivity, onHomeApprovals;

  @override
  State<_DesktopFixedLocationDetail> createState() =>
      _DesktopFixedLocationDetailState();
}

class _DesktopFixedLocationDetailState
    extends State<_DesktopFixedLocationDetail> {
  GoogleMapController? _mapController;

  void _panToDay(_AttendanceDay day) {
    if (day.checkInLat == null || day.checkInLng == null) return;
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(day.checkInLat!, day.checkInLng!), 15),
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.mode == 'Home';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 31,
                backgroundColor: const Color(0xFFEAF1FB),
                child: Text(
                  _initial(widget.employee.name),
                  style: const TextStyle(
                    color: HrmsColors.navy,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.employee.name,
                      style: const TextStyle(
                        color: Color(0xFF111A35),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      widget.employee.id,
                      style: const TextStyle(
                        color: _desktopMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _modeChip(widget.mode),
              const SizedBox(width: 12),
              _statusChip(widget.employee, widget.mode),
              if (home) ...[
                const SizedBox(width: 14),
                OutlinedButton(
                  onPressed: widget.onHomeApprovals,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: HrmsColors.blue,
                    side: const BorderSide(color: HrmsColors.blue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('View Home Approval'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 96,
            decoration: BoxDecoration(
              border: Border.all(color: _desktopBorder),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _detailMetric(
                  Icons.login_rounded,
                  'Check-in',
                  widget.employee.checkInAt == null
                      ? '—'
                      : DateFormat('h:mm a').format(widget.employee.checkInAt!),
                  widget.employee.attendanceDate ?? '',
                ),
                _detailDivider(),
                _detailMetric(
                  Icons.logout_rounded,
                  'Check-out',
                  widget.employee.checkOutAt == null
                      ? '—'
                      : DateFormat(
                          'h:mm a',
                        ).format(widget.employee.checkOutAt!),
                  '',
                ),
                _detailDivider(),
                _detailMetric(
                  Icons.gps_fixed_rounded,
                  'GPS accuracy',
                  widget.employee.accuracyMeters == null
                      ? '—'
                      : '${widget.employee.accuracyMeters!.round()} m',
                  '',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _LiveMap(
                employees: [widget.employee],
                onViewRoute: (_) => widget.onViewActivity(),
                onMapCreated: (ctrl) => _mapController = ctrl,
                highlightedEmployee: widget.mode == 'Home'
                    ? widget.employee
                    : null,
                showEmptyOverlay: widget.mode == 'Home',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyRecords extends StatelessWidget {
  const _DailyRecords({
    required this.employee,
    required this.mode,
  }) : onDayTap = null;
  final _TrackedEmployee employee;
  final String mode;
  final ValueChanged<_AttendanceDay>? onDayTap;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: _desktopBorder),
      borderRadius: BorderRadius.circular(10),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Daily Check-in Records',
                style: TextStyle(
                  color: Color(0xFF131C38),
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Text(
                'Tap a record to view location on map.',
                style: TextStyle(color: _desktopMuted, fontSize: 10),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: _desktopBorder),
        Expanded(
          child: employee.recentAttendance.isEmpty
              ? const Center(
                  child: Text(
                    'No check-in records',
                    style: TextStyle(color: _desktopMuted, fontSize: 12),
                  ),
                )
              : ListView.separated(
                  itemCount: employee.recentAttendance.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: _desktopBorder),
                  itemBuilder: (_, index) {
                    final day = employee.recentAttendance[index];
                    return _DailyRecordRow(
                      day: day,
                      mode: mode,
                      employee: employee,
                      onTap: onDayTap != null && day.checkInLat != null
                          ? () => onDayTap!(day)
                          : null,
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class _DailyRecordRow extends StatelessWidget {
  const _DailyRecordRow({
    required this.day,
    required this.mode,
    required this.employee,
    this.onTap,
  });
  final _AttendanceDay day;
  final String mode;
  final _TrackedEmployee employee;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(day.date);
    final verified = day.checkInAt != null && day.status != 'absent';
    if (mode == 'Home') {
      return InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 85,
          child: Row(
            children: [
              Container(
                width: 62,
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FB),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  parsed == null
                      ? '--'
                      : DateFormat('dd\nMMM\nyyyy').format(parsed),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: HrmsColors.navy,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.circle,
                size: 9,
                color: verified ? _desktopGreen : _desktopRed,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      day.checkInAt == null
                          ? 'Not checked in'
                          : DateFormat('h:mm a').format(day.checkInAt!),
                      style: const TextStyle(
                        color: Color(0xFF17213E),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      day.status ?? 'Attendance recorded',
                      style: TextStyle(color: _desktopMuted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: _desktopMuted,
                size: 18,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    parsed == null
                        ? day.date
                        : DateFormat('dd MMM yyyy').format(parsed),
                    style: const TextStyle(
                      color: HrmsColors.navy,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  day.checkInAt == null
                      ? '—'
                      : DateFormat('h:mm a').format(day.checkInAt!),
                  style: const TextStyle(
                    color: Color(0xFF17213E),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 10),
                _smallVerified(verified),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.location_on_rounded,
                  size: 13,
                  color: verified ? _desktopGreen : _desktopRed,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    verified ? 'Inside office' : 'No verified location',
                    style: const TextStyle(color: _desktopMuted, fontSize: 10),
                  ),
                ),
              ],
            ),
            if (employee.accuracyMeters != null ||
                employee.officeDistanceMeters != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Accuracy: ${employee.accuracyMeters?.round() ?? 0} m  |  Distance: ${employee.officeDistanceMeters?.round() ?? 0} m',
                  style: const TextStyle(color: _desktopMuted, fontSize: 9),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DesktopHybridDetail extends StatefulWidget {
  const _DesktopHybridDetail({required this.employee, required this.date});
  final _TrackedEmployee employee;
  final DateTime date;

  @override
  State<_DesktopHybridDetail> createState() => _DesktopHybridDetailState();
}

class _DesktopHybridDetailState extends State<_DesktopHybridDetail> {
  bool loading = true;
  String? error;
  Map<String, dynamic>? data;
  GoogleMapController? controller;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant _DesktopHybridDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employee.employeeUserId != widget.employee.employeeUserId ||
        oldWidget.date != widget.date) {
      load();
    }
  }

  @override
  void dispose() {
    _request++;
    controller?.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final request = ++_request;
    setState(() {
      loading = true;
      error = null;
    });
    final id = widget.employee.employeeUserId;
    if (id == null) {
      setState(() => loading = false);
      return;
    }
    try {
      final result = await HrmsTrackingApi.route(
        employeeUserId: id,
        date: DateFormat('yyyy-MM-dd').format(widget.date),
      );
      if (mounted && request == _request) {
        setState(() {
          data = result;
          loading = false;
        });
      }
    } catch (exception) {
      if (mounted && request == _request) {
        setState(() {
          error = exception.toString().replaceFirst('Exception: ', '');
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = (data?['routePoints'] as List? ?? [])
        .whereType<Map>()
        .map(
          (item) => LatLng(
            (item['latitude'] as num).toDouble(),
            (item['longitude'] as num).toDouble(),
          ),
        )
        .toList();
    final activities = (data?['activities'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final durationSeconds = (data?['durationSeconds'] as num?)?.toInt() ?? 0;
    final duration = Duration(seconds: durationSeconds);
    final stops = _countStops(activities);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFFEAF1FB),
                child: Text(
                  _initial(widget.employee.name),
                  style: const TextStyle(
                    color: HrmsColors.navy,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.employee.name,
                      style: const TextStyle(
                        color: Color(0xFF10162E),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'ID: ${widget.employee.id}',
                      style: const TextStyle(
                        color: _desktopMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _modeChip('Hybrid'),
              const SizedBox(width: 10),
              _statusChip(widget.employee, 'Hybrid'),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: load,
                icon: const Icon(Icons.history_rounded, size: 19),
                label: const Text('View Route History'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: HrmsColors.blue,
                  side: const BorderSide(color: HrmsColors.blue),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _hybridMetric(
                  Icons.route_rounded,
                  'Distance',
                  '${(((data?['distanceMeters'] as num?) ?? 0) / 1000).toStringAsFixed(1)} km',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _hybridMetric(
                  Icons.schedule_outlined,
                  'Active time',
                  '${duration.inHours}h ${duration.inMinutes.remainder(60)}m',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _hybridMetric(
                  Icons.location_on_rounded,
                  'Stops',
                  '$stops',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _hybridMetric(
                  Icons.polyline_rounded,
                  'GPS points',
                  '${data?['totalPointCount'] ?? points.length}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if ((data?['unverifiedPointCount'] as num? ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '${data!['unverifiedPointCount']} recorded points have poor or unknown accuracy. '
                'They remain in activity history but are excluded from the route and distance.',
                style: const TextStyle(color: Color(0xFF986000), fontSize: 12),
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(
                    child: Text(
                      error!,
                      style: const TextStyle(color: _desktopRed),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        flex: 72,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: points.isEmpty
                              ? const ColoredBox(
                                  color: Color(0xFFF4F7FC),
                                  child: Center(
                                    child: Text(
                                      'No accurate GPS route for this date.\nCheck recorded activity for unverified points.',
                                      style: TextStyle(color: _desktopMuted),
                                    ),
                                  ),
                                )
                              : GoogleMap(
                                  initialCameraPosition: CameraPosition(
                                    target: points.first,
                                    zoom: 13,
                                  ),
                                  polylines: {
                                    Polyline(
                                      polylineId: const PolylineId(
                                        'desktop-route',
                                      ),
                                      points: points,
                                      color: HrmsColors.blue,
                                      width: 5,
                                    ),
                                  },
                                  markers: {
                                    Marker(
                                      markerId: const MarkerId('start'),
                                      position: points.first,
                                      infoWindow: const InfoWindow(
                                        title: 'Start',
                                      ),
                                      icon:
                                          BitmapDescriptor.defaultMarkerWithHue(
                                            BitmapDescriptor.hueGreen,
                                          ),
                                    ),
                                    if (points.length > 1)
                                      Marker(
                                        markerId: const MarkerId('current'),
                                        position: points.last,
                                        infoWindow: InfoWindow(
                                          title: widget.employee.name,
                                        ),
                                      ),
                                  },
                                  mapToolbarEnabled: false,
                                  zoomControlsEnabled: true,
                                  onMapCreated: (value) => controller = value,
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 28,
                        child: _HybridActivityTimeline(activities: activities),
                      ),
                    ],
                  ),
          ),
          if (!loading && error == null) ...[
            const SizedBox(height: 14),
            _RouteProgressBar(activities: activities),
          ],
        ],
      ),
    );
  }
}

class _HybridActivityTimeline extends StatelessWidget {
  const _HybridActivityTimeline({required this.activities});
  final List<Map> activities;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: _desktopBorder),
      borderRadius: BorderRadius.circular(10),
    ),
    padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recorded activity',
          style: TextStyle(
            color: Color(0xFF111A35),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        const Divider(height: 1, color: _desktopBorder),
        const SizedBox(height: 4),
        Expanded(
          child: activities.isEmpty
              ? const Center(
                  child: Text(
                    'No activity recorded',
                    style: TextStyle(color: _desktopMuted, fontSize: 11),
                  ),
                )
              : ListView.builder(
                  itemCount: activities.length,
                  itemBuilder: (_, index) {
                    final item = activities[index];
                    final time = DateTime.tryParse(
                      '${item['recordedAt'] ?? ''}',
                    )?.toLocal();
                    final color = index == 0
                        ? _desktopGreen
                        : index == activities.length - 1
                        ? _desktopRed
                        : HrmsColors.blue;
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 22,
                            child: Column(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: color.withValues(alpha: .2),
                                      width: 3,
                                    ),
                                  ),
                                ),
                                if (index < activities.length - 1)
                                  Expanded(
                                    child: Container(
                                      width: 1,
                                      color: _desktopBorder,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 58,
                            child: Text(
                              time == null
                                  ? '--:--'
                                  : DateFormat('h:mm a').format(time),
                              style: const TextStyle(
                                color: _desktopMuted,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['locationQuality'] == 'usable'
                                        ? 'Location update'
                                        : 'Unverified location',
                                    style: const TextStyle(
                                      color: Color(0xFF17213E),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${item['placeName'] ?? 'Location unavailable'}',
                                    maxLines: 5,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _desktopMuted,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
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
  );
}

class _RouteProgressBar extends StatelessWidget {
  const _RouteProgressBar({required this.activities});
  final List<Map> activities;

  @override
  Widget build(BuildContext context) {
    String timeAt(int index) {
      if (activities.isEmpty) return '--:--';
      final parsed = DateTime.tryParse(
        '${activities[index.clamp(0, activities.length - 1)]['recordedAt'] ?? ''}',
      )?.toLocal();
      return parsed == null ? '--:--' : DateFormat('h:mm a').format(parsed);
    }

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: _desktopBorder),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: HrmsColors.blue,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Text(
            timeAt(0),
            style: const TextStyle(color: _desktopMuted, fontSize: 10),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(height: 3, color: const Color(0xFFBFD2FF)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    activities.isEmpty ? 2 : activities.length.clamp(2, 6),
                    (index) => Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: index == 0
                            ? _desktopGreen
                            : index ==
                                  (activities.isEmpty
                                      ? 1
                                      : activities.length.clamp(2, 6) - 1)
                            ? _desktopRed
                            : HrmsColors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            timeAt(activities.isEmpty ? 0 : activities.length - 1),
            style: const TextStyle(color: _desktopMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

Widget _desktopSurface(Widget child) => Container(
  decoration: BoxDecoration(
    color: Colors.white,
    border: Border.all(color: _desktopBorder),
    borderRadius: BorderRadius.circular(12),
  ),
  clipBehavior: Clip.antiAlias,
  child: child,
);

Widget _employeeIdentity(_TrackedEmployee employee, VoidCallback onViewReport) => Row(
  children: [
    CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0xFFEAF1FB),
      child: Text(
        _initial(employee.name),
        style: const TextStyle(
          color: HrmsColors.navy,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    const SizedBox(width: 11),
    Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onViewReport,
            child: Text(
              employee.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: HrmsColors.blue,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: HrmsColors.blue,
              ),
            ),
          ),
          Text(
            employee.id,
            style: const TextStyle(color: _desktopMuted, fontSize: 11),
          ),
        ],
      ),
    ),
  ],
);

String _initial(String name) =>
    name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();

Widget _modeChip(String mode) {
  final home = mode == 'Home';
  final hybrid = mode == 'Hybrid';
  final color = home
      ? HrmsColors.blue
      : hybrid
      ? const Color(0xFFC77B00)
      : HrmsColors.blue;
  final background = home
      ? const Color(0xFFEAF3FF)
      : hybrid
      ? const Color(0xFFFFF0D4)
      : const Color(0xFFEAF3FF);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          home
              ? Icons.home_outlined
              : hybrid
              ? Icons.circle
              : Icons.apartment_rounded,
          size: hybrid ? 9 : 15,
          color: color,
        ),
        const SizedBox(width: 7),
        Text(mode, style: TextStyle(color: color, fontSize: 11)),
      ],
    ),
  );
}

Widget _trackingStatus(_TrackedEmployee employee) {
  final label = employee.onBreak
      ? 'On Break'
      : employee.active
      ? 'Active'
      : 'Offline';
  final color = employee.onBreak
      ? const Color(0xFFC77B00)
      : employee.active
      ? _desktopGreen
      : const Color(0xFF64748B);
  final bg = employee.onBreak
      ? const Color(0xFFFFF0D4)
      : employee.active
      ? const Color(0xFFE2F7EA)
      : const Color(0xFFEDF0F4);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 9, color: color),
        const SizedBox(width: 7),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    ),
  );
}

Widget _statusChip(_TrackedEmployee employee, String mode) {
  if (mode == 'Hybrid') return _trackingStatus(employee);
  String label;
  Color color;
  Color background;
  if (employee.checkOutAt != null) {
    label = 'Checked out';
    color = const Color(0xFF596176);
    background = const Color(0xFFF0F2F6);
  } else if (employee.checkInAt != null && employee.onBreak) {
    label = 'On break';
    color = const Color(0xFFB86A00);
    background = const Color(0xFFFFF2DE);
  } else if (employee.checkInAt != null) {
    label = 'Checked in';
    color = const Color(0xFF087A34);
    background = const Color(0xFFE2F6E9);
  } else {
    label = 'Not checked in';
    color = const Color(0xFFDF252F);
    background = const Color(0xFFFFE6E8);
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 10)),
  );
}

Widget _detailMetric(
  IconData icon,
  String label,
  String value,
  String caption, {
  Color valueColor = const Color(0xFF111A35),
}) => Expanded(
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 13),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: Color(0xFFEAF3FF),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: HrmsColors.blue, size: 23),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: _desktopMuted, fontSize: 10),
              ),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 15,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (caption.isNotEmpty)
                Text(
                  caption,
                  style: const TextStyle(color: _desktopMuted, fontSize: 10),
                ),
            ],
          ),
        ),
      ],
    ),
  ),
);

Widget _detailDivider() =>
    const SizedBox(height: 70, child: VerticalDivider(color: _desktopBorder));

Widget _hybridMetric(IconData icon, String label, String value) => Container(
  height: 78,
  padding: const EdgeInsets.symmetric(horizontal: 12),
  decoration: BoxDecoration(
    border: Border.all(color: _desktopBorder),
    borderRadius: BorderRadius.circular(9),
  ),
  child: Row(
    children: [
      Container(
        width: 43,
        height: 43,
        decoration: const BoxDecoration(
          color: Color(0xFFEAF3FF),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: HrmsColors.blue, size: 23),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: _desktopMuted, fontSize: 10),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF10162E),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ],
  ),
);

Widget _smallVerified(bool verified) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  decoration: BoxDecoration(
    color: verified ? const Color(0xFFE2F6E9) : const Color(0xFFFFE6E8),
    borderRadius: BorderRadius.circular(14),
  ),
  child: Text(
    verified ? 'Verified' : 'Unverified',
    style: TextStyle(
      color: verified ? const Color(0xFF087A34) : const Color(0xFFDF252F),
      fontSize: 9,
    ),
  ),
);

int _countStops(List<Map> activities) {
  if (activities.length < 2) return 0;
  var stops = 0;
  DateTime? previous;
  for (final item in activities) {
    final current = DateTime.tryParse('${item['recordedAt'] ?? ''}');
    if (current != null &&
        previous != null &&
        current.difference(previous).inMinutes >= 15) {
      stops++;
    }
    previous = current;
  }
  return stops;
}
