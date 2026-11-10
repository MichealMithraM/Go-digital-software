import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hrms_design_system/hrms_design_system.dart';
import 'package:hrms_responsive/hrms_responsive.dart';
import '../../services/attendance_api.dart';
import '../../services/attendance_location.dart';
import '../../services/hrms_attendance_tracker.dart';
import '../../services/hrms_tracking_api.dart';
import 'employee_nav.dart';

/// Responsive app shell per HRMS_PROJECT_BLUEPRINT.md, Section 3
/// (Employee, revised 2026-08-28):
/// - Desktop/Tablet: top navigation bar, same pattern as Admin — no left
///   sidebar (supersedes the earlier sidebar design).
/// - Mobile: no persistent nav at all. The Dashboard is the hub; other
///   pages are reached one level deep from it and use the platform back
///   button to return — no drawer, no bottom nav.
class EmployeeShell extends StatefulWidget {
  final Widget body;
  final EmployeeNavItem current;

  const EmployeeShell({super.key, required this.body, required this.current});

  @override
  State<EmployeeShell> createState() => _EmployeeShellState();
}

/// Runs after login on every employee page.  The backend remains the source
/// of truth: it applies the admin-configured Office/Home radius and grace
/// period, and returns `auto_checked_out` only when that rule is met.
class _EmployeeShellState extends State<EmployeeShell> {
  Timer? _locationTimer;
  bool _sendingLocation = false;
  String? _verificationMessage;
  String? _autoCheckoutMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startLocationGuard();
      HrmsAttendanceTracker.instance.resumeIfActive();
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _startLocationGuard() async {
    try {
      final settings = await HrmsTrackingApi.trackingSettings();
      final minutes = int.tryParse(
        '${settings['field_ping_interval_minutes']}',
      );
      if (minutes == null || minutes < 1) return;
      await _sendLocationHeartbeat();
      if (!mounted || _autoCheckoutMessage != null) return;
      _locationTimer?.cancel();
      _locationTimer = Timer.periodic(
        Duration(minutes: minutes),
        (_) => _sendLocationHeartbeat(),
      );
    } catch (_) {
      // A settings/API failure must not block an employee from viewing pages.
      // The next page load retries with the current admin settings.
    }
  }

  Future<void> _sendLocationHeartbeat() async {
    if (_sendingLocation || _autoCheckoutMessage != null) return;
    _sendingLocation = true;
    try {
      final dashboard = await AttendanceApi.dashboard(DateTime.now());
      if (dashboard['status'] != 'checked_in') {
        _locationTimer?.cancel();
        if (mounted && _verificationMessage != null) {
          setState(() => _verificationMessage = null);
        }
        return;
      }

      final position = await _currentPosition();
      final result = await AttendanceApi.locationHeartbeat(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
      if (!mounted) return;
      final radiusState = '${result['radius_state'] ?? ''}';
      if (radiusState == 'auto_checked_out') {
        _locationTimer?.cancel();
        setState(() {
          _verificationMessage = null;
          _autoCheckoutMessage =
              'You were checked out because you remained outside your approved location beyond the allowed grace period.';
        });
      } else if (_verificationMessage != null) {
        setState(() => _verificationMessage = null);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _verificationMessage =
              'Location verification is required while you are checked in. Enable precise location permission to continue.';
        });
      }
    } finally {
      _sendingLocation = false;
    }
  }

  Future<Position> _currentPosition() async {
    return AttendanceLocation.currentPosition();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ResponsiveBuilder(
          mobile: (context) =>
              _MobileShell(current: widget.current, body: widget.body),
          tablet: (context) =>
              _TopNavShell(current: widget.current, body: widget.body),
          desktop: (context) =>
              _TopNavShell(current: widget.current, body: widget.body),
        ),
        if (_verificationMessage != null)
          _LocationVerificationOverlay(message: _verificationMessage!),
        if (_autoCheckoutMessage != null)
          _AutoCheckoutOverlay(
            message: _autoCheckoutMessage!,
            onClose: () => setState(() => _autoCheckoutMessage = null),
          ),
      ],
    );
  }
}

class _LocationVerificationOverlay extends StatelessWidget {
  final String message;
  const _LocationVerificationOverlay({required this.message});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_off,
                      color: HrmsColors.danger,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Location verification required',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AutoCheckoutOverlay extends StatelessWidget {
  final String message;
  final VoidCallback onClose;
  const _AutoCheckoutOverlay({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.logout,
                      color: HrmsColors.danger,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Automatically checked out',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: onClose, child: const Text('OK')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: HrmsColors.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.diamond_outlined,
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'GO DIGITAL',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: HrmsColors.primary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _NavPill extends StatelessWidget {
  final EmployeeNavItem current;
  const _NavPill({required this.current});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: HrmsColors.pageBackground,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: EmployeeNavItem.values.map((item) {
          final isActive = item == current;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: isActive ? HrmsColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  if (!isActive) {
                    Navigator.of(context).pushReplacementNamed(item.route);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: isActive ? Colors.white : HrmsColors.textSecondary,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Live-time + Checked-in status chips, shown in the employee top bar on
/// desktop/tablet (see images 14-20) — not present on Admin or on the
/// employee mobile app, which shows check-in state on the Dashboard card
/// instead.
class _StatusChips extends StatefulWidget {
  const _StatusChips();

  @override
  State<_StatusChips> createState() => _StatusChipsState();
}

class _StatusChipsState extends State<_StatusChips> {
  Timer? _timer;
  bool _checkedIn = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final dashboard = await AttendanceApi.dashboard(DateTime.now());
      if (mounted) setState(() => _checkedIn = dashboard['status'] == 'checked_in');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    final label = now.format(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chip(label, HrmsColors.infoBg, HrmsColors.info),
        const SizedBox(width: 8),
        _chip(_checkedIn ? 'Checked In' : 'Not Checked In', HrmsColors.infoBg, HrmsColors.primary, dot: true),
      ],
    );
  }

  Widget _chip(String text, Color bg, Color fg, {bool dot = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _BellIcon extends StatelessWidget {
  const _BellIcon();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: HrmsColors.pageBackground,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.notifications_none,
            color: HrmsColors.textSecondary,
          ),
        ),
        Positioned(
          top: 6,
          right: 8,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: HrmsColors.danger,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

class _TopNavShell extends StatelessWidget {
  final EmployeeNavItem current;
  final Widget body;

  const _TopNavShell({required this.current, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: const BoxDecoration(
              color: HrmsColors.surface,
              border: Border(bottom: BorderSide(color: HrmsColors.border)),
            ),
            child: Row(
              children: [
                const _Logo(),
                const SizedBox(width: 20),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _NavPill(current: current),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                const _StatusChips(),
                const SizedBox(width: 16),
                const _BellIcon(),
                const SizedBox(width: 12),
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: HrmsColors.infoBg,
                  child: Icon(
                    Icons.person,
                    color: HrmsColors.primary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _MobileShell extends StatelessWidget {
  final EmployeeNavItem current;
  final Widget body;

  const _MobileShell({required this.current, required this.body});

  @override
  Widget build(BuildContext context) {
    // No drawer, no bottom nav — per the revised spec the Dashboard is the
    // hub and every other page is reached one level deep from it, using
    // the platform back button (auto-added leading arrow) to return.
    return Scaffold(
      appBar: AppBar(
        title: const _Logo(),
        actions: const [
          _BellIcon(),
          SizedBox(width: 12),
          CircleAvatar(
            radius: 16,
            backgroundColor: HrmsColors.infoBg,
            child: Icon(Icons.person, color: HrmsColors.primary, size: 18),
          ),
          SizedBox(width: 12),
        ],
      ),
      body: body,
    );
  }
}
