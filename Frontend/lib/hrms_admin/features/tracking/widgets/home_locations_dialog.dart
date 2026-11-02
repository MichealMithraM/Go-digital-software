import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../services/hrms_tracking_api.dart';

class HomeLocationsDialog extends StatefulWidget {
  const HomeLocationsDialog({super.key});

  @override
  State<HomeLocationsDialog> createState() => _HomeLocationsDialogState();
}

class _HomeLocationsDialogState extends State<HomeLocationsDialog> {
  // ── controllers ──────────────────────────────────────────────────────────
  final _radiusCtrl = TextEditingController();
  final _graceCtrl = TextEditingController();
  final _noGpsCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  // ── state ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _homes = [];
  bool _loadingSettings = true;
  bool _loadingHomes = true;
  bool _savingRadius = false;
  bool _savingGrace = false;
  bool _savingNoGps = false;
  bool _savingToggle = false;
  bool _homeTrackingEnabled = true;
  int? _reviewingId;
  int _tab = 0; // 0=Pending 1=Approved 2=Rejected
  String _search = '';
  String? _settingsError;
  String? _homesError;

  static const _blue = Color(0xFF0B5FFF);
  static const _navy = Color(0xFF061457);
  static const _muted = Color(0xFF657087);
  static const _line = Color(0xFFE3E9F4);
  static const _cardBorder = Color(0xFFDCE8FF);
  static const _iconBg = Color(0xFFEAF3FF);
  static const _iconColor = Color(0xFF0B5FFF);
  static const _green = Color(0xFF16A34A);
  static const _greenBg = Color(0xFFDCFCE7);

  bool get _busy => _savingRadius || _savingGrace || _savingNoGps || _savingToggle || _reviewingId != null;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadHomes();
  }

  @override
  void dispose() {
    _radiusCtrl.dispose();
    _graceCtrl.dispose();
    _noGpsCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── data loading ──────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    setState(() { _loadingSettings = true; _settingsError = null; });
    try {
      final s = await HrmsTrackingApi.trackingSettings();
      if (!mounted) return;
      setState(() {
        _radiusCtrl.text = '${s['home_radius_meters'] ?? 200}';
        _graceCtrl.text = '${s['home_outside_radius_grace_minutes'] ?? 5}';
        _noGpsCtrl.text = '${s['home_no_gps_timeout_minutes'] ?? 30}';
        _homeTrackingEnabled = (s['home_tracking_enabled'] ?? 1) != 0;
        _loadingSettings = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loadingSettings = false; _settingsError = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _loadHomes() async {
    setState(() { _loadingHomes = true; _homesError = null; });
    try {
      final homes = await HrmsTrackingApi.homeLocations();
      if (!mounted) return;
      setState(() {
        _homes = homes;
        _loadingHomes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loadingHomes = false; _homesError = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  // ── save actions ──────────────────────────────────────────────────────────

  Future<void> _saveRadius() async {
    if (_busy) return;
    final radius = int.tryParse(_radiusCtrl.text.trim());
    if (radius == null || radius < 1) return;
    setState(() => _savingRadius = true);
    try {
      await HrmsTrackingApi.updateHomeRadius(radius);
      if (mounted) _showSnack('Home Check In radius saved.');
    } catch (e) {
      if (mounted) setState(() => _settingsError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingRadius = false);
    }
  }

  Future<void> _saveGrace() async {
    if (_busy) return;
    final grace = int.tryParse(_graceCtrl.text.trim());
    if (grace == null || grace < 1) return;
    setState(() => _savingGrace = true);
    try {
      await HrmsTrackingApi.updateHomeSettings(homeOutsideRadiusGraceMinutes: grace);
      if (mounted) _showSnack('Home checkout grace time saved.');
    } catch (e) {
      if (mounted) setState(() => _settingsError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingGrace = false);
    }
  }

  Future<void> _saveNoGps() async {
    if (_busy) return;
    final noGps = int.tryParse(_noGpsCtrl.text.trim());
    if (noGps == null || noGps < 1) return;
    setState(() => _savingNoGps = true);
    try {
      await HrmsTrackingApi.updateHomeSettings(homeNoGpsTimeoutMinutes: noGps);
      if (mounted) _showSnack('Home no-GPS timeout saved.');
    } catch (e) {
      if (mounted) setState(() => _settingsError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingNoGps = false);
    }
  }

  Future<void> _saveToggle() async {
    if (_busy) return;
    setState(() => _savingToggle = true);
    try {
      await HrmsTrackingApi.updateHomeSettings(homeTrackingEnabled: _homeTrackingEnabled);
      if (mounted) _showSnack(_homeTrackingEnabled ? 'Home tracking enabled.' : 'Home tracking disabled.');
    } catch (e) {
      if (mounted) setState(() => _settingsError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingToggle = false);
    }
  }

  Future<void> _review(Map<String, dynamic> home, bool approve) async {
    if (_busy) return;
    final id = int.tryParse('${home['employee_user_id']}');
    final lat = double.tryParse('${home['latitude']}');
    final lng = double.tryParse('${home['longitude']}');
    if (id == null || lat == null || lng == null) return;
    setState(() => _reviewingId = id);
    try {
      if (approve && home['capture_source'] == 'map_pin') {
        final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
          title: const Text('Verify Home Location'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('The employee selected this pin manually. Check the map and confirm the Home address before approving.'),
            const SizedBox(height: 12),
            Text('${home['address'] ?? ''}'),
            SelectableText('$lat, $lng'),
            TextButton.icon(onPressed: () => _viewHome(home), icon: const Icon(Icons.map_outlined), label: const Text('View Selected Location')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('I Verified This Location')),
          ],
        ));
        if (!mounted || confirmed != true) return;
      }
      String? reason;
      if (!approve) {
        reason = await showDialog<String>(context: context, builder: (_) => const _HomeRejectionDialog());
        if (!mounted || reason == null) return;
      }
      await HrmsTrackingApi.reviewHomeLocation(
        employeeUserId: id, approve: approve, latitude: lat, longitude: lng, rejectionReason: reason,
        mapPinVerified: approve && home['capture_source'] == 'map_pin', reviewedAddress: home['address']?.toString());
      if (!mounted) return;
      await _loadHomes();
    } catch (e) {
      if (mounted) setState(() => _homesError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _reviewingId = null);
    }
  }

  void _showSnack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _viewHome(Map<String, dynamic> home) async {
    final lat = double.tryParse('${home['latitude']}');
    final lng = double.tryParse('${home['longitude']}');
    if (lat == null || lng == null || !lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) return;
    try {
      final opened = await launchUrl(Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$lat,$lng'}), mode: LaunchMode.externalApplication);
      if (!opened && mounted) _showSnack('Could not open the map. Please retry.');
    } catch (_) {
      if (mounted) _showSnack('Could not open the map. Please retry.');
    }
  }

  // ── filtered list ─────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _filtered {
    const statuses = ['pending', 'approved', 'rejected'];
    final status = statuses[_tab];
    final q = _search.toLowerCase();
    return _homes.where((h) {
      if ('${h['approval_status']}' != status) return false;
      if (q.isEmpty) return true;
      final name = '${h['full_name'] ?? h['username'] ?? ''}'.toLowerCase();
      final code = '${h['employee_code'] ?? ''}'.toLowerCase();
      return name.contains(q) || code.contains(q);
    }).toList();
  }

  // ── widgets ───────────────────────────────────────────────────────────────

  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: _line)),
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    child: Row(children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.home_rounded, color: _green, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
        Text('Home Approvals', style: TextStyle(color: _navy, fontSize: 15, fontWeight: FontWeight.w700)),
        SizedBox(height: 2),
        Text('Manage home location approvals and settings for employees.',
            style: TextStyle(color: _muted, fontSize: 11)),
      ])),
      IconButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close, color: _muted, size: 20),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    ]),
  );

  Widget _sectionCard({required IconData icon, required Color iconColor, required Color iconBg,
      required String title, required String desc, required Widget child}) =>
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _cardBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 34, height: 34,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: iconColor, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: _navy, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(desc, style: const TextStyle(color: _muted, fontSize: 11, height: 1.35)),
          ])),
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );

  InputDecoration _inputDec({String? suffix}) => InputDecoration(
    suffixText: suffix,
    suffixStyle: const TextStyle(color: _muted, fontSize: 12),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFCDD7EE)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _blue, width: 1.5),
    ),
    filled: true, fillColor: Colors.white,
  );

  Widget _saveBtn(String label, {required VoidCallback? onTap, bool loading = false}) =>
    FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: _blue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      ),
      icon: loading
          ? const SizedBox.square(dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.save_outlined, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );

  Widget _radiusCard() => _sectionCard(
    icon: Icons.location_on_rounded,
    iconColor: _iconColor, iconBg: _iconBg,
    title: 'Home Check In Radius',
    desc: 'This applies to approved Home locations only. Office radius is configured separately in Manage Office Location.',
    child: _loadingSettings
        ? const LinearProgressIndicator()
        : Row(children: [
            Expanded(child: TextField(
              controller: _radiusCtrl,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 15),
              decoration: _inputDec(suffix: 'metres'),
            )),
            const SizedBox(width: 10),
            _saveBtn(_savingRadius ? 'Saving...' : 'Save Radius',
                onTap: _busy ? null : _saveRadius, loading: _savingRadius),
          ]),
  );

  Widget _graceCard() => _sectionCard(
    icon: Icons.schedule_rounded,
    iconColor: _iconColor, iconBg: _iconBg,
    title: 'Home Checkout Grace Time',
    desc: 'Allowed time outside the radius before auto-checkout for Home employees.',
    child: _loadingSettings
        ? const LinearProgressIndicator()
        : Row(children: [
            Expanded(child: TextField(
              controller: _graceCtrl,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 15),
              decoration: _inputDec(suffix: 'minutes'),
            )),
            const SizedBox(width: 10),
            _saveBtn(_savingGrace ? 'Saving...' : 'Save Grace Time',
                onTap: _busy ? null : _saveGrace, loading: _savingGrace),
          ]),
  );

  Widget _noGpsCard() => _sectionCard(
    icon: Icons.signal_wifi_off_rounded,
    iconColor: _iconColor, iconBg: _iconBg,
    title: 'Home No-GPS Timeout',
    desc: 'Auto-checkout Home employees if no GPS ping is received for this long.',
    child: _loadingSettings
        ? const LinearProgressIndicator()
        : Row(children: [
            Expanded(child: TextField(
              controller: _noGpsCtrl,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 15),
              decoration: _inputDec(suffix: 'minutes'),
            )),
            const SizedBox(width: 10),
            _saveBtn(_savingNoGps ? 'Saving...' : 'Save Timeout',
                onTap: _busy ? null : _saveNoGps, loading: _savingNoGps),
          ]),
  );

  Widget _tabs() => Wrap(spacing: 6, runSpacing: 6, children: [
    _tabPill(0, 'Pending'),
    _tabPill(1, 'Approved'),
    _tabPill(2, 'Rejected'),
  ]);

  Widget _tabPill(int index, String label) {
    final active = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _blue : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? _blue : _line),
        ),
        child: Text(label,
            style: TextStyle(
              color: active ? Colors.white : _muted,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              fontSize: 13,
            )),
      ),
    );
  }

  Widget _searchBar() => Container(
    height: 42,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(children: [
      const Padding(padding: EdgeInsets.symmetric(horizontal: 10),
          child: Icon(Icons.search, color: _muted, size: 18)),
      Expanded(child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _search = v),
        style: const TextStyle(fontSize: 13, color: _navy),
        decoration: const InputDecoration(
          hintText: 'Search by employee name or ID...',
          hintStyle: TextStyle(color: _muted, fontSize: 13),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      )),
    ]),
  );

  Widget _emptyState() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 28),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F5FF),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: const [
      Icon(Icons.home_work_outlined, size: 56, color: Color(0xFF93B4E8)),
      SizedBox(height: 12),
      Text('No home location requests yet.',
          style: TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 14)),
    ]),
  );

  Widget _homeCard(Map<String, dynamic> h) {
    final id = int.tryParse('${h['employee_user_id']}');
    final name = '${h['full_name'] ?? h['username'] ?? 'Employee $id'}';
    final code = '${h['employee_code'] ?? ''}'.trim();
    final address = '${h['address'] ?? ''}'.trim();
    final status = '${h['approval_status'] ?? 'pending'}';
    final isPending = status == 'pending';
    final isReviewing = _reviewingId == id;

    Color chipColor;
    Color chipBg;
    switch (status) {
      case 'approved': chipColor = _green; chipBg = _greenBg; break;
      case 'rejected': chipColor = Colors.red; chipBg = const Color(0xFFFEE2E2); break;
      default: chipColor = const Color(0xFFB45309); chipBg = const Color(0xFFFEF3C7);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _cardBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 18, backgroundColor: _iconBg,
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: _iconColor, fontWeight: FontWeight.w700))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 14)),
            if (code.isNotEmpty)
              Text(code, style: const TextStyle(color: _muted, fontSize: 12)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(20)),
            child: Text(status[0].toUpperCase() + status.substring(1),
                style: TextStyle(color: chipColor, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
        if (address.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(address, style: const TextStyle(color: _muted, fontSize: 12)),
        ],
        if (h['capture_source'] == 'map_pin') ...[
          const SizedBox(height: 8),
          const Text('Map-selected Home — verify the pin and address before approval.', style: TextStyle(color: Color(0xFFB45309), fontSize: 12)),
        ],
        TextButton.icon(onPressed: () => _viewHome(h), icon: const Icon(Icons.map_outlined, size: 18), label: const Text('View Location')),
        if (h['rejection_reason'] != null) ...[
          const SizedBox(height: 4),
          Text('Reason: ${h['rejection_reason']}',
              style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
        if (isPending) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: _busy ? null : () => _review(h, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: const Text('Reject', style: TextStyle(fontSize: 13)),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(
              onPressed: _busy ? null : () => _review(h, true),
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: isReviewing
                  ? const SizedBox.square(dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 16),
              label: Text(isReviewing ? 'Saving...' : 'Approve', style: const TextStyle(fontSize: 13)),
            )),
          ]),
        ],
      ]),
    );
  }

  Widget _registrationsCard() => _sectionCard(
    icon: Icons.group_add_rounded,
    iconColor: _iconColor, iconBg: _iconBg,
    title: 'Employee Home Registrations',
    desc: 'Verify the Home pin and address before approval. Employee work mode and WFH permission remain managed separately.',
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _tabs(),
      const SizedBox(height: 8),
      _searchBar(),
      const SizedBox(height: 12),
      if (_loadingHomes)
        const LinearProgressIndicator()
      else if (_homesError != null)
        Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_homesError!, style: const TextStyle(color: Colors.red, fontSize: 12)))
      else if (_filtered.isEmpty)
        _emptyState()
      else
        Column(children: _filtered.map(_homeCard).toList()),
    ]),
  );

  Widget _trackingToggleCard() => _sectionCard(
    icon: Icons.settings_rounded,
    iconColor: _iconColor, iconBg: _iconBg,
    title: 'Enable Home Tracking',
    desc: 'When off, Home tracking is hidden and blocked for employees.',
    child: Row(children: [
      Switch(
        value: _homeTrackingEnabled,
        activeThumbColor: Colors.white,
        activeTrackColor: _green,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: const Color(0xFFCBD5E1),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        onChanged: _busy ? null : (v) => setState(() => _homeTrackingEnabled = v),
      ),
      const SizedBox(width: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _homeTrackingEnabled ? _greenBg : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle, size: 15,
              color: _homeTrackingEnabled ? _green : _muted),
          const SizedBox(width: 5),
          Text(_homeTrackingEnabled ? 'Enabled' : 'Disabled',
              style: TextStyle(
                color: _homeTrackingEnabled ? _green : _muted,
                fontWeight: FontWeight.w600, fontSize: 12)),
        ]),
      ),
      const Spacer(),
      _saveBtn(_savingToggle ? 'Saving...' : 'Save Setting',
          onTap: _busy ? null : _saveToggle, loading: _savingToggle),
    ]),
  );

  Widget _footer() => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: _line)),
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
    ),
    child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      if (_settingsError != null)
        Expanded(child: Text(_settingsError!, style: const TextStyle(color: Colors.red, fontSize: 12))),
      OutlinedButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        style: OutlinedButton.styleFrom(
          foregroundColor: _navy,
          side: const BorderSide(color: _line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ),
        child: const Text('Cancel', style: TextStyle(fontSize: 13)),
      ),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        style: FilledButton.styleFrom(
          backgroundColor: _blue,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        ),
        child: const Text('Done', style: TextStyle(fontSize: 13)),
      ),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 640;

    return PopScope(
      canPop: !_busy,
      child: Dialog(
        backgroundColor: Colors.white,
        insetPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 24, vertical: isMobile ? 12 : 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _header(),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Top row: radius + grace — side-by-side on desktop, stacked on mobile
                  if (isMobile) ...[
                    _radiusCard(),
                    const SizedBox(height: 12),
                    _graceCard(),
                    const SizedBox(height: 12),
                    _noGpsCard(),
                  ] else ...[
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _radiusCard()),
                      const SizedBox(width: 12),
                      Expanded(child: _graceCard()),
                    ]),
                    const SizedBox(height: 12),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _noGpsCard()),
                      const SizedBox(width: 12),
                      const Expanded(child: SizedBox()),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  _registrationsCard(),
                  const SizedBox(height: 12),
                  _trackingToggleCard(),
                ]),
              ),
            ),
            _footer(),
          ]),
        ),
      ),
    );
  }
}

// ── Rejection reason dialog ────────────────────────────────────────────────

class _HomeRejectionDialog extends StatefulWidget {
  const _HomeRejectionDialog();

  @override
  State<_HomeRejectionDialog> createState() => _HomeRejectionDialogState();
}

class _HomeRejectionDialogState extends State<_HomeRejectionDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text('Reject Home Location',
        style: TextStyle(color: Color(0xFF061457), fontWeight: FontWeight.w700)),
    content: SizedBox(
      width: 400,
      child: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: 500,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: 'Reason for rejection',
          errorText: _error,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: Colors.red),
        onPressed: () {
          final reason = _ctrl.text.trim();
          if (reason.isEmpty) { setState(() => _error = 'Enter a reason for the employee.'); return; }
          Navigator.of(context).pop(reason);
        },
        child: const Text('Reject Location'),
      ),
    ],
  );
}
