import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'attendance_api.dart';

/// Android foreground-service GPS tracker that keeps attendance pings alive
/// even when the screen is off.  Sends a location heartbeat every 60 seconds
/// while the employee is checked in so the server's radius-check and
/// auto-checkout rules always have fresh coordinates.
///
/// Usage:
///   HrmsAttendanceTracker.instance.startTracking()  — after check-in
///   HrmsAttendanceTracker.instance.stopTracking()   — after check-out
///   HrmsAttendanceTracker.instance.resumeIfActive() — on shell/app start
class HrmsAttendanceTracker {
  HrmsAttendanceTracker._();
  static final instance = HrmsAttendanceTracker._();

  StreamSubscription<Position>? _sub;
  Timer? _pingTimer;
  bool _active = false;
  Position? _lastPosition;

  bool get isActive => _active;

  /// Start the foreground-service GPS tracker.  No-op on web or non-Android.
  Future<void> startTracking() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_active) return;
    _active = true;
    _lastPosition = null;

    _sub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Go Digital — Tracking Active',
          notificationText: 'Your attendance is being tracked.',
          enableWakeLock: true,
        ),
      ),
    ).listen(
      (p) => _lastPosition = p,
      onError: (_) {},
      cancelOnError: false,
    );

    unawaited(_pingNow());
    _pingTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_pingFromCache()),
    );
  }

  /// Stop the tracker.  Call on check-out.
  Future<void> stopTracking() async {
    _active = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    await _sub?.cancel();
    _sub = null;
    _lastPosition = null;
  }

  /// If the employee was already checked in when the app restarted, resume
  /// background tracking so pings keep coming.
  Future<void> resumeIfActive() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_active) return;
    try {
      final d = await AttendanceApi.dashboard(DateTime.now());
      if (d['status'] == 'checked_in') await startTracking();
    } catch (_) {}
  }

  Future<void> _pingNow() async {
    if (!_active) return;
    try {
      Position? pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        final age = DateTime.now().toUtc().difference(pos.timestamp.toUtc());
        if (age.inMinutes >= 2) pos = null;
      }
      pos ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      _lastPosition = pos;
      await _sendHeartbeat(pos);
    } catch (_) {}
  }

  Future<void> _pingFromCache() async {
    if (!_active) return;
    final pos = _lastPosition;
    if (pos == null) {
      await _pingNow();
      return;
    }
    await _sendHeartbeat(pos);
  }

  Future<void> _sendHeartbeat(Position pos) async {
    try {
      await AttendanceApi.locationHeartbeat(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
      );
    } catch (_) {}
  }
}
