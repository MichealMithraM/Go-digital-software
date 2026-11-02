part of 'approvals_page.dart';

class _ApprovalsWorkspace extends StatefulWidget {
  const _ApprovalsWorkspace({
    required this.category,
    required this.counts,
    required this.requests,
    required this.employees,
    required this.employee,
    required this.status,
    required this.period,
    required this.loading,
    required this.error,
    required this.onCategory,
    required this.onSearch,
    required this.onEmployee,
    required this.onStatus,
    required this.onPeriod,
    required this.onReset,
    required this.onReview,
    required this.corrections,
    required this.selectedDate,
    required this.onDate,
  });
  final String category, employee, status, period;
  final List<int> counts;
  final List<_ApprovalRequest> requests;
  final List<String> employees;
  final bool loading;
  final String? error;
  final ValueChanged<String> onCategory,
      onSearch,
      onEmployee,
      onStatus,
      onPeriod;
  final VoidCallback onReset;
  final Future<void> Function(_ApprovalRequest, String) onReview;
  final Widget corrections;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDate;
  @override
  State<_ApprovalsWorkspace> createState() => _ApprovalsWorkspaceState();
}

class _ApprovalsWorkspaceState extends State<_ApprovalsWorkspace> {
  final _search = TextEditingController();
  int? _selectedId;
  bool _reviewing = false;
  static const _line = Color(0xFFDDE5F2);
  static const _muted = Color(0xFF667995);

  @override
  void didUpdateWidget(covariant _ApprovalsWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category) _selectedId = null;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _review(_ApprovalRequest request, String nextStatus) async {
    if (_reviewing) return;
    setState(() => _reviewing = true);
    try {
      await widget.onReview(request, nextStatus);
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  Widget _card(Widget child) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  Widget _filter(
    String label,
    String value,
    List<String> items,
    ValueChanged<String> onChanged, {
    bool compact = false,
  }) => DropdownButtonFormField<String>(
    key: ValueKey('$label:$value'),
    initialValue: value,
    isExpanded: true,
    style: TextStyle(fontSize: compact ? 13 : 14, color: _ApprovalsColors.navy),
    decoration: InputDecoration(
      labelText: compact ? null : label,
      filled: true,
      fillColor: const Color(0xFFF7F9FD),
      isDense: compact,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: compact ? 10 : 14,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: _line),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
    ),
    items: items
        .map(
          (v) => DropdownMenuItem(
            value: v,
            child: Text(v, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: _reviewing
        ? null
        : (v) {
            if (v != null) onChanged(v);
          },
  );

  Widget _cell(Widget child, int flex) => Expanded(
    flex: flex,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: child,
    ),
  );

  Widget _list(_ApprovalRequest? selected) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: const Color(0xFFF3F6FA),
          padding: const EdgeInsets.symmetric(vertical: 17),
          child: Row(
            children: [
              const SizedBox(width: 38),
              _cell(const Text('Employee', style: TextStyle(color: _muted)), 3),
              _cell(
                const Text('Request Details', style: TextStyle(color: _muted)),
                3,
              ),
              _cell(const Text('Dates', style: TextStyle(color: _muted)), 2),
              _cell(const Text('Duration', style: TextStyle(color: _muted)), 2),
              _cell(const Text('Status', style: TextStyle(color: _muted)), 2),
            ],
          ),
        ),
        Expanded(
          child: widget.requests.isEmpty
              ? const Center(
                  child: Text('No approval requests match these filters.'),
                )
              : ListView.builder(
                  itemCount: widget.requests.length,
                  itemBuilder: (_, index) {
                    final r = widget.requests[index];
                    final active = r.requestId == selected?.requestId;
                    return Material(
                      color: active ? const Color(0xFFEAF2FF) : Colors.white,
                      child: InkWell(
                        onTap: _reviewing
                            ? null
                            : () => setState(() => _selectedId = r.requestId),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: _line)),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 38,
                                child: Icon(
                                  active
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  size: 19,
                                  color: active ? _ApprovalsColors.blue : _line,
                                ),
                              ),
                              _cell(
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      r.id,
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                3,
                              ),
                              _cell(
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.type,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      r.reason,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                3,
                              ),
                              _cell(
                                Text(
                                  r.dates,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                2,
                              ),
                              _cell(Text(r.duration), 2),
                              _cell(_RequestStatus(status: r.status), 2),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );

  Widget _detail(_ApprovalRequest? r) => _card(
    Padding(
      padding: const EdgeInsets.all(20),
      child: r == null
          ? const Center(
              child: Text(
                'Select a request to review its details.',
                textAlign: TextAlign.center,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFFEAF0FA),
                      child: Text(
                        r.name.isEmpty ? '?' : r.name.substring(0, 1),
                        style: const TextStyle(color: _ApprovalsColors.navy),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.name,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(r.id, style: const TextStyle(color: _muted)),
                        ],
                      ),
                    ),
                    _RequestStatus(status: r.status),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Request Details',
                  style: TextStyle(
                    color: _ApprovalsColors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Divider(height: 28, color: _line),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _detailLine('Request Type', r.type),
                        _detailLine('Reason', r.reason),
                        _detailLine('Dates', r.dates),
                        _detailLine('Duration', r.duration),
                        _detailLine('Request ID', '#${r.requestId}'),
                        if (r.homeDetails != null)
                          _detailLine('Captured Home Location', r.homeDetails!),
                      ],
                    ),
                  ),
                ),
                if (r.status.toLowerCase() == 'pending') ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _reviewing || widget.loading
                              ? null
                              : () => _review(r, 'Approved'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _ApprovalsColors.blue,
                            padding: const EdgeInsets.symmetric(vertical: 17),
                          ),
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(_reviewing ? 'Saving…' : 'Approve'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _reviewing || widget.loading
                              ? null
                              : () => _review(r, 'Rejected'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _ApprovalsColors.blue,
                            padding: const EdgeInsets.symmetric(vertical: 17),
                          ),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Reject'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    ),
  );

  Widget _detailLine(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(label, style: const TextStyle(color: _muted)),
        ),
        const SizedBox(width: 10),
        Expanded(flex: 3, child: SelectableText(value)),
      ],
    ),
  );

  Widget _dateControls() {
    final day = widget.period == 'Today';
    void move(int step) {
      final d = widget.selectedDate;
      widget.onDate(
        day
            ? DateTime(d.year, d.month, d.day + step)
            : DateTime(d.year, d.month + step),
      );
    }

    Widget mode(String label, bool active, String value) => InkWell(
      onTap: _reviewing ? null : () => widget.onPeriod(value),
      child: Container(
        height: 44,
        width: 65,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? _ApprovalsColors.blue : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? _ApprovalsColors.navy : _muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mode('Day', day, 'Today'),
        mode('Month', !day, 'This Month'),
        const SizedBox(width: 12),
        IconButton.outlined(
          tooltip: 'Previous date',
          onPressed: _reviewing ? null : () => move(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 240,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _reviewing
                ? null
                : () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: widget.selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100, 12, 31),
                    );
                    if (mounted && picked != null) widget.onDate(picked);
                  },
            style: OutlinedButton.styleFrom(
              foregroundColor: _ApprovalsColors.navy,
              side: const BorderSide(color: _line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.calendar_month_outlined, size: 20),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(
                  DateFormat(
                    day ? 'dd MMMM yyyy' : 'MMMM yyyy',
                  ).format(widget.selectedDate),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                )),
                const SizedBox(width: 12),
                const Icon(Icons.expand_more, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.outlined(
          tooltip: 'Next date',
          onPressed: _reviewing ? null : () => move(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _ApprovalRequest? selected;
    for (final r in widget.requests) {
      if (r.requestId == _selectedId) {
        selected = r;
        break;
      }
    }
    selected ??= widget.requests.isEmpty ? null : widget.requests.first;
    final entries = [
      ('leave', 'Leave', Icons.calendar_month_outlined),
      ('permission', 'Permission', Icons.schedule),
      ('corrections', 'Attendance Corrections', Icons.edit_calendar_outlined),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Approvals',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: _ApprovalsColors.navy,
                      ),
                    ),
                    Text(
                      'Review and take action on employee requests.',
                      style: TextStyle(color: _muted),
                    ),
                  ],
                ),
              ),
              _dateControls(),
            ],
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              for (var i = 0; i < entries.length; i++)
                OutlinedButton.icon(
                  onPressed: _reviewing
                      ? null
                      : () => widget.onCategory(entries[i].$1),
                  style: OutlinedButton.styleFrom(
                    fixedSize: const Size(280, 52),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                    foregroundColor: _ApprovalsColors.blue,
                    backgroundColor: widget.category == entries[i].$1
                        ? const Color(0xFFEAF2FF)
                        : Colors.white,
                    side: BorderSide(
                      color: widget.category == entries[i].$1
                          ? _ApprovalsColors.blue
                          : _line,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: Icon(entries[i].$3, size: 22),
                  label: Text(
                    '${entries[i].$2}${widget.counts[i == 2 ? 3 : i] > 0 ? '  (${widget.counts[i == 2 ? 3 : i]})' : ''}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (widget.category == 'corrections')
            Expanded(child: SingleChildScrollView(child: widget.corrections))
          else ...[
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _card(
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: LayoutBuilder(
                              builder: (context, constraints) => SizedBox(
                                height: 44,
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 4,
                                      child: TextField(
                                        style: const TextStyle(fontSize: 13),
                                        controller: _search,
                                        onChanged: widget.onSearch,
                                        decoration: InputDecoration(
                                          hintText:
                                              'Search employee, request or reason…',
                                          isDense: true,
                                          prefixIcon: const Icon(
                                            Icons.search,
                                            size: 20,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              9,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 12,
                                              ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 3,
                                      child: _filter(
                                        'Employee',
                                        widget.employee,
                                        widget.employees,
                                        widget.onEmployee,
                                        compact: true,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 2,
                                      child: _filter(
                                        'Status',
                                        widget.status,
                                        const [
                                          'All Status',
                                          'Pending',
                                          'Approved',
                                          'Rejected',
                                        ],
                                        widget.onStatus,
                                        compact: true,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: constraints.maxWidth < 750
                                          ? 40
                                          : 144,
                                      child: constraints.maxWidth < 750
                                          ? IconButton(
                                              tooltip: 'Reset Filters',
                                              onPressed: _reviewing
                                                  ? null
                                                  : () {
                                                      _search.clear();
                                                      widget.onReset();
                                                    },
                                              icon: const Icon(
                                                Icons.restart_alt,
                                                size: 20,
                                              ),
                                            )
                                          : TextButton.icon(
                                              onPressed: _reviewing
                                                  ? null
                                                  : () {
                                                      _search.clear();
                                                      widget.onReset();
                                                    },
                                              icon: const Icon(
                                                Icons.restart_alt,
                                              ),
                                              label: const Text(
                                                'Reset Filters',
                                                maxLines: 1,
                                                softWrap: false,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(fontSize: 13),
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (widget.loading)
                          const LinearProgressIndicator(minHeight: 2),
                        if (widget.error != null)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              widget.error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        const SizedBox(height: 14),
                        Expanded(child: _list(selected)),
                        const SizedBox(height: 12),
                        Text(
                          'Showing ${widget.requests.length} requests',
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(child: _detail(selected)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
