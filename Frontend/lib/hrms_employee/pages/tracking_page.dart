import 'dart:typed_data';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import '../../services/waiting_alert_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../services/hrms_tracking_api.dart';
import '../../services/attendance_api.dart';
import '../../services/attendance_location.dart';
import '../../services/office_address_search.dart';
import '../shared/employee_ui.dart';
import 'home_location_dialog.dart';

class EmployeeTrackingPage extends StatelessWidget {
  const EmployeeTrackingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final arguments = ModalRoute.of(context)?.settings.arguments;
    final routeHistory = arguments == 'history';
    return EmployeeScaffold(
      route: '/employee/tracking',
      title: routeHistory ? 'Route History' : 'Live Tracking',
      subtitle: routeHistory
          ? 'Your recent travel routes'
          : 'Live employee location and today’s hybrid activity',
      desktopHeaderAction: routeHistory
          ? null
          : FilledButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const HomeLocationDialog(),
              ),
              icon: const Icon(Icons.add_home_outlined),
              label: const Text('Home Location'),
              style: FilledButton.styleFrom(
                backgroundColor: employeeBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
      desktop: _TrackingView(
        mobile: false,
        routeHistory: routeHistory,
      ),
      mobile: _TrackingView(
        mobile: true,
        routeHistory: routeHistory,
      ),
    );
  }
}

enum _WorkMode { office, home, hybrid }

class _RoutePoint {
  const _RoutePoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  factory _RoutePoint.fromJson(Map<String, dynamic> json) {
    return _RoutePoint(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
    );
  }

  LatLng get latLng => LatLng(latitude, longitude);
}

Future<BitmapDescriptor> _routeMarkerIcon({
  required Color color,
  required String label,
}) async {
  const size = Size(56, 70);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final pin = Path()
    ..moveTo(28, 64)
    ..lineTo(13, 35)
    ..arcToPoint(const Offset(43, 35), radius: const Radius.circular(20))
    ..close();
  canvas.drawPath(pin, Paint()..color = color);
  canvas.drawCircle(const Offset(28, 28), 16, Paint()..color = Colors.white);
  final text = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  text.paint(canvas, Offset(28 - text.width / 2, 28 - text.height / 2));
  final image = await recorder.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(
    Uint8List.fromList(bytes!.buffer.asUint8List()),
  );
}

class _TrackingView extends StatefulWidget {
  const _TrackingView({
    required this.mobile,
    required this.routeHistory,
  });
  final bool mobile;
  final bool routeHistory;

  @override
  State<_TrackingView> createState() => _TrackingViewState();
}

class _TrackingViewState extends State<_TrackingView> {
  _WorkMode mode = _WorkMode.office;
  String updated = 'Not tracking yet';
  bool trackingActive = false;
  bool _isHybridEmployee = false;
  Timer? _locationTimer;
  Timer? _radiusHeartbeatTimer;
  Position? _lastPosition;
  Map<String, dynamic>? _homeLocation;
  Map<String, dynamic>? _officeSettings;
  bool _homeLoading = true;
  bool _officeLoading = true;
  bool _homeDialogOpen = false;
  String? _homeError;

  String distance = '—';
  String duration = '—';
  String avgSpeed = '—';
  DateTime _routeDate = DateTime.now();
  bool _routeLoading = true;
  String? _routeError;
  List<_RoutePoint> _routePoints = const [];
  BitmapDescriptor? _routeStartMarker;
  BitmapDescriptor? _routeEndMarker;

  List<dynamic> activities = [
    {
      'activity_time': '--:--',
      'activity_text': 'No live tracking activity yet',
    },
  ];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHybridSession();
      _loadHomeLocation();
      _loadOfficeSettings();
      _loadRoute();
      _loadRouteMarkerIcons();
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _radiusHeartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRouteMarkerIcons() async {
    final icons = await Future.wait([
      _routeMarkerIcon(color: employeeBlue, label: 'S'),
      _routeMarkerIcon(color: const Color(0xFF7E20E8), label: 'E'),
    ]);
    if (!mounted) return;
    setState(() {
      _routeStartMarker = icons[0];
      _routeEndMarker = icons[1];
    });
  }

  Future<void> _loadRoute({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _routeLoading = true;
        _routeError = null;
      });
    }
    try {
      final route = await HrmsTrackingApi.myRoute(
        date: DateFormat('yyyy-MM-dd').format(_routeDate),
      );
      final routePoints =
          (route['routePoints'] as List? ?? route['points'] as List? ?? [])
              .whereType<Map>()
              .map(
                (item) => _RoutePoint.fromJson(Map<String, dynamic>.from(item)),
              )
              .where((point) => point.latitude != 0 && point.longitude != 0)
              .toList();
      final routeActivities = (route['activities'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (!mounted) return;
      setState(() {
        _routePoints = routePoints;
        _routeLoading = false;
        _routeError = null;
        distance = _formatDistance(route['distanceMeters']);
        duration = _formatDuration(route['durationSeconds']);
        avgSpeed = _formatSpeed(route['averageSpeedKmh']);
        updated = _formatLastUpdated(route['lastUpdated']);
        activities = routeActivities.isEmpty
            ? [
                {
                  'activity_time': '--:--',
                  'activity_text': 'No GPS activity recorded for this date',
                },
              ]
            : routeActivities.map(_activityFromRoute).toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _routeLoading = false;
        _routeError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Map<String, dynamic> _activityFromRoute(Map<String, dynamic> item) {
    final recordedAt = DateTime.tryParse('${item['recordedAt'] ?? ''}');
    return {
      'activity_time': recordedAt == null
          ? '--:--'
          : DateFormat.jm().format(recordedAt.toLocal()),
      'activity_text': _placeName(item['placeName']),
    };
  }

  String _placeName(dynamic value) {
    final place = '${value ?? ''}'.trim();
    return place.isEmpty || place == 'Location pending'
        ? 'Location name is being updated'
        : place;
  }

  String _formatDistance(dynamic meters) {
    final value =
        (meters as num?)?.toDouble() ?? double.tryParse('$meters') ?? 0;
    return '${(value / 1000).toStringAsFixed(2)} km';
  }

  String _formatDuration(dynamic seconds) {
    final value = (seconds as num?)?.round() ?? int.tryParse('$seconds') ?? 0;
    return '${value ~/ 3600}h ${(value % 3600) ~/ 60}m';
  }

  String _formatSpeed(dynamic kmh) {
    final value = (kmh as num?)?.toDouble() ?? double.tryParse('$kmh') ?? 0;
    return '${value.toStringAsFixed(1)} km/h';
  }

  String _formatLastUpdated(dynamic value) {
    final date = DateTime.tryParse('${value ?? ''}');
    return date == null
        ? 'No route updates yet'
        : 'Updated ${DateFormat.jm().format(date.toLocal())}';
  }

  Future<void> _selectRouteDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _routeDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (selected == null || !mounted) return;
    setState(() => _routeDate = selected);
    await _loadRoute();
  }

  void _startRadiusHeartbeat() {
    _radiusHeartbeatTimer?.cancel();
    final minutes = int.tryParse(
      '${_officeSettings?['field_ping_interval_minutes']}',
    );
    if (minutes == null || minutes < 1) return;
    _sendRadiusHeartbeat();
    _radiusHeartbeatTimer = Timer.periodic(
      Duration(minutes: minutes),
      (_) => _sendRadiusHeartbeat(),
    );
  }

  Future<void> _sendRadiusHeartbeat() async {
    try {
      final position = await _getCurrentPosition();
      await AttendanceApi.locationHeartbeat(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } catch (_) {}
  }

  Future<void> _loadOfficeSettings() async {
    try {
      final settings = await HrmsTrackingApi.trackingSettings();
      if (!mounted) return;
      setState(() {
        _officeSettings = settings;
        _officeLoading = false;
      });
      _startRadiusHeartbeat();
      if (trackingActive) _startLocationTimer();
    } catch (_) {
      if (!mounted) return;
      setState(() => _officeLoading = false);
    }
  }

  Future<Position> _getCurrentPosition() async {
    return AttendanceLocation.currentPosition();
  }

  Future<void> _loadHomeLocation() async {
    try {
      final home = await HrmsTrackingApi.myHomeLocation();
      if (!mounted) return;
      setState(() {
        _homeLocation = home;
        _homeLoading = false;
        _homeError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _homeLoading = false;
        _homeError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openHomeLocation() async {
    if (_homeDialogOpen) return;
    setState(() => _homeDialogOpen = true);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const HomeLocationDialog(),
      );
      if (mounted) await _loadHomeLocation();
    } finally {
      if (mounted) setState(() => _homeDialogOpen = false);
    }
  }

  Future<void> _loadHybridSession() async {
    try {
      final session = await HrmsTrackingApi.hybridSession();

      final active =
          session['is_active'] == 1 ||
          session['is_active'] == true ||
          session['isActive'] == true;

      if (!mounted) return;

      setState(() {
        _isHybridEmployee =
            session['isHybrid'] == true || session['is_hybrid'] == 1;
        trackingActive = active;

        if (active) {
          mode = _WorkMode.hybrid;
          updated = 'Live tracking active';
        }
      });

      if (active) {
        _startLocationTimer();
      }
    } catch (_) {
      // Office and Home employees do not receive a Hybrid tracking session.
    }
  }

  void _startLocationTimer() {
    _locationTimer?.cancel();

    final minutes = int.tryParse(
      '${_officeSettings?['field_ping_interval_minutes']}',
    );
    if (minutes == null || minutes < 1) return;
    context.read<WaitingAlertService?>()?.refresh();
    _locationTimer = Timer.periodic(Duration(minutes: minutes), (
      _,
    ) {
      _loadRoute(silent: true);
    });
  }

  Future<void> _sendLocationPing({required bool showMessage}) async {
    if (!trackingActive) return;

    try {
      final position = await _getCurrentPosition();
      await _sendPositionPing(position, showMessage: showMessage);
    } catch (error) {
      if (showMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  Future<void> _sendPositionPing(
    Position position, {
    required bool showMessage,
  }) async {
    if (!trackingActive) return;
    if (!position.accuracy.isFinite || position.accuracy > 200) {
      throw Exception(
        'Live tracking needs GPS accuracy of 200 metres or better. Current accuracy: ${position.accuracy.toStringAsFixed(0)} m.',
      );
    }
    final address = await reverseGeocodeOfficeLocation(
      position.latitude,
      position.longitude,
    );
    await HrmsTrackingApi.ping(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      capturedAt: position.timestamp.toUtc().toIso8601String(),
      address: address,
    );
    if (!mounted) return;
    setState(() {
      _lastPosition = position;
      updated = 'Updated just now';
      activities = [
        {
          'activity_time': TimeOfDay.now().format(context),
          'activity_text': 'Live location updated',
        },
        ...activities.where(
          (item) => item['activity_text'] != 'No live tracking activity yet',
        ),
      ];
    });
    await _loadRoute(silent: true);
    if (showMessage && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Live location refreshed.')));
    }
  }

  Future<void> toggleTracking() async {
    try {
      // Clock In is the first step of Hybrid work. Check it before requesting
      // GPS or attempting to create a tracking session.
      if (!trackingActive) {
        final attendance = await AttendanceApi.dashboard(DateTime.now());
        if (attendance['status'] != 'checked_in') {
          await _requireClockIn();
          return;
        }
      }
      final position = await _getCurrentPosition();

      if (!trackingActive) {
        final address = await reverseGeocodeOfficeLocation(
          position.latitude,
          position.longitude,
        );
        await HrmsTrackingApi.startHybridSession(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          capturedAt: position.timestamp.toUtc().toIso8601String(),
          address: address,
        );

        if (!mounted) return;

        setState(() {
          trackingActive = true;
          mode = _WorkMode.hybrid;
          _lastPosition = position;
          updated = 'Updated just now';
          activities = [
            {
              'activity_time': TimeOfDay.now().format(context),
              'activity_text': 'Started live Hybrid tracking',
            },
          ];
        });

        _startLocationTimer();
        await _loadRoute(silent: true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Live tracking started.')));
      } else {
        await HrmsTrackingApi.stopHybridSession(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
        );

        _locationTimer?.cancel();
        context.read<WaitingAlertService?>()?.refresh();

        if (!mounted) return;

        setState(() {
          trackingActive = false;
          _lastPosition = position;
          updated = 'Live tracking stopped';
          activities = [
            {
              'activity_time': TimeOfDay.now().format(context),
              'activity_text': 'Stopped live Hybrid tracking',
            },
            ...activities,
          ];
        });
        await _loadRoute(silent: true);

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Live tracking stopped.')));
      }
    } catch (error) {
      if (!mounted) return;

      final message = error.toString().replaceFirst('Exception: ', '');
      if (message.contains('Clock in before starting Hybrid live tracking.')) {
        await _requireClockIn();
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _requireClockIn() async {
    if (!mounted) return;
    final goToClockIn = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Check In required'),
        content: const Text(
          'Check In first, then you can start Hybrid live tracking.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Go to Check In'),
          ),
        ],
      ),
    );
    if (goToClockIn == true && mounted) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/employee/dashboard', (route) => false);
    }
  }

  void refreshLocation() {
    _sendLocationPing(showMessage: true);
  }

  String get modeLabel => switch (mode) {
    _WorkMode.office => 'Office',
    _WorkMode.home => 'Home',
    _WorkMode.hybrid => 'Hybrid',
  };

  String get address {
    if (mode == _WorkMode.office) {
      if (_officeLoading) return 'Loading office location...';
      final officeName = '${_officeSettings?['office_name'] ?? ''}'.trim();
      final officeAddress = '${_officeSettings?['office_address'] ?? ''}'
          .trim();
      if (officeName.isEmpty && officeAddress.isEmpty) {
        return 'Office location has not been configured by admin.';
      }
      return [
        officeName,
        officeAddress,
      ].where((value) => value.isNotEmpty).join('\n');
    }

    if (mode == _WorkMode.home) {
      if (_homeLoading) return 'Loading home location...';
      if (_homeError != null) return _homeError!;
      if (_homeLocation == null) {
        return 'Register your home location for admin approval';
      }
      final status = _homeLocation!['approval_status'];
      final description = switch (status) {
        'approved' => 'Approved home location',
        'pending' => 'Pending admin approval — Home Check In unavailable',
        'rejected' => 'Home location rejected — update and resubmit',
        _ => 'Home location approval required',
      };
      return '$description\n'
          '${_homeLocation!['address'] ?? ''}\n'
          'GPS: ${_homeLocation!['latitude']}, ${_homeLocation!['longitude']}';
    }

    if (_lastPosition != null) {
      return 'Live GPS: '
          '${_lastPosition!.latitude.toStringAsFixed(6)}, '
          '${_lastPosition!.longitude.toStringAsFixed(6)}';
    }

    return 'Hybrid location will appear after live tracking starts';
  }

  Color get activeColor =>
      mode == _WorkMode.hybrid ? employeeGreen : employeeBlue;

  @override
  Widget build(BuildContext context) {
    if (widget.routeHistory) {
      return _RouteHistoryView(mobile: widget.mobile);
    }

    final modes = _ModeTabs(
      selected: mode,
      homeEnabled: _officeSettings?['home_tracking_enabled'] != 0,
      onChanged: (value) => setState(() => mode = value),
    );

    final status = _CurrentStatusCard(
      mode: modeLabel,
      address: address,
      color: activeColor,
      lastUpdated: updated,
      onRefresh: mode == _WorkMode.office
          ? _loadOfficeSettings
          : mode == _WorkMode.home
          ? _loadHomeLocation
          : refreshLocation,
    );

    final map = _RouteMap(
      mode: mode,
      position: _lastPosition,
      homeLocation: _homeLocation,
      officeSettings: _officeSettings,
      routePoints: _routePoints,
      routeLoading: _routeLoading,
      routeError: _routeError,
      startMarker: _routeStartMarker,
      endMarker: _routeEndMarker,
    );

    final routeDateButton = OutlinedButton.icon(
      onPressed: _routeLoading ? null : _selectRouteDate,
      icon: const Icon(Icons.calendar_today_outlined, size: 16),
      label: Text(DateFormat('dd MMM yyyy').format(_routeDate)),
    );

    final metrics = _TripMetrics(
      distance: distance,
      duration: duration,
      avgSpeed: avgSpeed,
      updated: updated,
    );

    final timeline = _ActivityTimeline(activities: activities);

    final live = _LiveTrackingControl(
      active: trackingActive,
      onToggle: toggleTracking,
    );

    if (widget.mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MobileEmployeeHeader(),
          const SizedBox(height: 14),
          EmployeePageTitle(
            title: 'Live Tracking',
            trailing: OutlinedButton.icon(
              onPressed: _openHomeLocation,
              icon: const Icon(Icons.add_home_outlined, size: 16),
              label: const Text('Home Location'),
              style: OutlinedButton.styleFrom(
                foregroundColor: employeeBlue,
                side: const BorderSide(color: employeeBlue),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          modes,
          const SizedBox(height: 14),
          status,
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Live Location',
                  style: TextStyle(
                    color: employeeNavy,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              routeDateButton,
            ],
          ),
          const SizedBox(height: 12),
          map,
          const SizedBox(height: 14),
          metrics,
          const SizedBox(height: 22),
          const Text(
            'Today’s Activity',
            style: TextStyle(
              color: employeeNavy,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          timeline,
          const SizedBox(height: 18),
          if (_isHybridEmployee) live,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        modes,
        const SizedBox(height: 18),
        status,
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Live Location',
                style: TextStyle(
                  color: employeeNavy,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            routeDateButton,
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 7,
              child: Column(
                children: [map, const SizedBox(height: 14), metrics],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Today’s Activity',
                      style: TextStyle(
                        color: employeeNavy,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  timeline,
                  const SizedBox(height: 18),
                  if (_isHybridEmployee) live,
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RouteHistoryView extends StatefulWidget {
  const _RouteHistoryView({required this.mobile});
  final bool mobile;

  @override
  State<_RouteHistoryView> createState() => _RouteHistoryViewState();
}

class _RouteHistoryViewState extends State<_RouteHistoryView> {
  DateTime _date = DateTime.now();
  bool _loading = true;
  Map<String, dynamic>? _route;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final route = await HrmsTrackingApi.myRoute(
        date: _date.toIso8601String().substring(0, 10),
      );
      if (mounted) {
        setState(() {
          _route = route;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _pickDate() async {
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

  @override
  Widget build(BuildContext context) {
    final raw = (_route?['routePoints'] as List? ?? [])
        .whereType<Map>()
        .map(
          (p) => LatLng(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ),
        )
        .toList();
    final activities = (_route?['activities'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final markers = <Marker>{
      if (raw.isNotEmpty)
        Marker(
          markerId: const MarkerId('start'),
          position: raw.first,
          infoWindow: const InfoWindow(title: 'S — Start'),
        ),
      if (raw.length > 1)
        Marker(
          markerId: const MarkerId('end'),
          position: raw.last,
          infoWindow: const InfoWindow(title: 'E — End'),
        ),
      ...raw
          .skip(1)
          .take(raw.length > 2 ? raw.length - 2 : 0)
          .map(
            (point) => Marker(
              markerId: MarkerId('${point.latitude},${point.longitude}'),
              position: point,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
            ),
          ),
    };
    final history = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Route History',
                style: TextStyle(
                  color: employeeNavy,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text('${_date.day}/${_date.month}/${_date.year}'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red))
        else if (raw.isEmpty)
          const EmployeeCard(
            padding: EdgeInsets.all(16),
            child: Text('No GPS route was recorded for the selected date'),
          )
        else ...[
          SizedBox(
            height: 280,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: raw.first,
                  zoom: 14,
                ),
                polylines: {
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: raw,
                    color: employeeBlue,
                    width: 5,
                  ),
                },
                markers: markers,
                mapToolbarEnabled: false,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _RouteHistoryCard(
            DateFormat('dd MMM yyyy').format(_date),
            '${((_route?['distanceMeters'] as num? ?? 0) / 1000).toStringAsFixed(2)} km · ${((_route?['averageSpeedKmh'] as num? ?? 0)).toStringAsFixed(1)} km/h',
            '${((_route?['durationSeconds'] as num? ?? 0) / 60).round()} min',
            '${activities.length} updates',
          ),
          for (final item in activities.take(8))
            ListTile(
              leading: const Icon(Icons.place_outlined, color: employeeBlue),
              title: Text('${item['placeName'] ?? 'Location pending'}'),
              subtitle: Text('${item['recordedAt'] ?? ''}'),
            ),
        ],
      ],
    );
    return widget.mobile
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MobileEmployeeHeader(),
              const SizedBox(height: 14),
              const EmployeePageTitle(title: 'Route History'),
              const SizedBox(height: 20),
              history,
            ],
          )
        : history;
  }
}

class _RouteHistoryCard extends StatelessWidget {
  const _RouteHistoryCard(this.date, this.route, this.distance, this.duration);
  final String date, route, distance, duration;

  @override
  Widget build(BuildContext context) => EmployeeCard(
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: const Color(0xFFE9F7F7),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.route_outlined, color: Color(0xFF079B9B)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                date,
                style: const TextStyle(
                  color: employeeNavy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                route,
                style: const TextStyle(color: employeeMuted, fontSize: 13),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              distance,
              style: const TextStyle(
                color: employeeNavy,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              duration,
              style: const TextStyle(color: employeeMuted, fontSize: 12),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ModeTabs extends StatelessWidget {
  const _ModeTabs({
    required this.selected,
    required this.homeEnabled,
    required this.onChanged,
  });
  final _WorkMode selected;
  final bool homeEnabled;
  final ValueChanged<_WorkMode> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _ModeTab(
        icon: Icons.business_outlined,
        label: 'Office',
        active: selected == _WorkMode.office,
        onTap: () => onChanged(_WorkMode.office),
      ),
      if (homeEnabled) ...[
        const SizedBox(width: 8),
        _ModeTab(
          icon: Icons.home_outlined,
          label: 'Home',
          active: selected == _WorkMode.home,
          onTap: () => onChanged(_WorkMode.home),
        ),
      ],
      const SizedBox(width: 8),
      _ModeTab(
        icon: Icons.person_outline_rounded,
        label: 'Hybrid',
        active: selected == _WorkMode.hybrid,
        onTap: () => onChanged(_WorkMode.hybrid),
      ),
    ],
  );
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    colors: [Color(0xFF13C58A), Color(0xFF00AE7B)],
                  )
                : null,
            border: Border.all(
              color: active ? Colors.transparent : employeeLine,
            ),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: active ? Colors.white : employeeMuted,
                size: 25,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : employeeNavy,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CurrentStatusCard extends StatelessWidget {
  const _CurrentStatusCard({
    required this.mode,
    required this.address,
    required this.color,
    required this.lastUpdated,
    required this.onRefresh,
  });
  final String mode;
  final String address;
  final Color color;
  final String lastUpdated;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => EmployeeCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Current Status',
              style: TextStyle(
                color: employeeNavy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 12),
            CircleAvatar(radius: 5, backgroundColor: color),
            const SizedBox(width: 7),
            Text(
              mode,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              lastUpdated,
              style: const TextStyle(color: employeeMuted, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Icon(
              Icons.location_on_outlined,
              color: employeeMuted,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                address,
                style: const TextStyle(color: employeeMuted, height: 1.4),
              ),
            ),
            IconButton.outlined(
              tooltip: 'Refresh live location',
              onPressed: onRefresh,
              icon: const Icon(
                Icons.refresh_rounded,
                color: employeeBlue,
                size: 27,
              ),
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(11),
                side: const BorderSide(color: employeeLine),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _RouteMap extends StatelessWidget {
  const _RouteMap({
    required this.mode,
    required this.position,
    this.homeLocation,
    this.officeSettings,
    required this.routePoints,
    required this.routeLoading,
    this.routeError,
    this.startMarker,
    this.endMarker,
  });

  final _WorkMode mode;
  final Position? position;
  final Map<String, dynamic>? homeLocation;
  final Map<String, dynamic>? officeSettings;
  final List<_RoutePoint> routePoints;
  final bool routeLoading;
  final String? routeError;
  final BitmapDescriptor? startMarker;
  final BitmapDescriptor? endMarker;

  @override
  Widget build(BuildContext context) {
    if (routeLoading) {
      return const AspectRatio(
        aspectRatio: 1.95,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (routePoints.isEmpty && mode == _WorkMode.hybrid) {
      return AspectRatio(
        aspectRatio: 1.95,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFD),
            border: Border.all(color: employeeLine),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            routeError == null
                ? 'No GPS route was recorded for the selected date.'
                : 'Unable to load GPS route: $routeError',
            textAlign: TextAlign.center,
            style: const TextStyle(color: employeeMuted),
          ),
        ),
      );
    }
    final livePoint = position == null
        ? null
        : LatLng(position!.latitude, position!.longitude);

    final homeLat = double.tryParse('${homeLocation?['latitude']}');
    final homeLng = double.tryParse('${homeLocation?['longitude']}');
    final homePoint = homeLat != null && homeLng != null
        ? LatLng(homeLat, homeLng)
        : null;
    final routeCoordinates = mode == _WorkMode.hybrid
        ? routePoints.map((point) => point.latLng).toList()
        : const <LatLng>[];
    final officeLat = double.tryParse('${officeSettings?['office_latitude']}');
    final officeLng = double.tryParse('${officeSettings?['office_longitude']}');
    final officePoint = officeLat != null && officeLng != null
        ? LatLng(officeLat, officeLng)
        : null;
    final officeName = '${officeSettings?['office_name'] ?? 'Office'}';

    final center = routeCoordinates.isNotEmpty
        ? routeCoordinates.first
        : mode == _WorkMode.hybrid && livePoint != null
        ? livePoint
        : mode == _WorkMode.home && homePoint != null
        ? homePoint
        : officePoint;

    if (center == null) {
      return AspectRatio(
        aspectRatio: 1.95,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFD),
            border: Border.all(color: employeeLine),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'A location is not available yet.',
            style: TextStyle(color: employeeMuted),
          ),
        ),
      );
    }

    final markerColor = mode == _WorkMode.hybrid
        ? BitmapDescriptor.hueRed
        : mode == _WorkMode.home
        ? BitmapDescriptor.hueGreen
        : BitmapDescriptor.hueAzure;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 1.95,
        child: GoogleMap(
          key: ValueKey(
            'tracking-map-${mode.name}-${officePoint?.latitude}-${officePoint?.longitude}-${homePoint?.latitude}-${homePoint?.longitude}-${routeCoordinates.length}-${routeCoordinates.isEmpty ? '' : routeCoordinates.first}-${routeCoordinates.isEmpty ? '' : routeCoordinates.last}',
          ),
          initialCameraPosition: CameraPosition(
            target: center,
            zoom: mode == _WorkMode.hybrid && livePoint != null ? 16 : 15,
          ),
          mapToolbarEnabled: false,
          markers: {
            if (officePoint != null)
              Marker(
                markerId: const MarkerId('office'),
                position: officePoint,
                infoWindow: InfoWindow(title: officeName),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
              ),
            if (mode == _WorkMode.home && homePoint != null)
              Marker(
                markerId: const MarkerId('registered-home'),
                position: homePoint,
                infoWindow: InfoWindow(
                  title: 'Registered Home',
                  snippet: '${homeLocation?['approval_status'] ?? ''}',
                ),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen,
                ),
              ),
            if (mode == _WorkMode.hybrid &&
                livePoint != null &&
                routeCoordinates.isEmpty)
              Marker(
                markerId: const MarkerId('live-location'),
                position: livePoint,
                infoWindow: const InfoWindow(title: 'Your Live Location'),
                icon: BitmapDescriptor.defaultMarkerWithHue(markerColor),
              ),
            if (routeCoordinates.isNotEmpty)
              Marker(
                markerId: const MarkerId('route-start'),
                position: routeCoordinates.first,
                infoWindow: const InfoWindow(title: 'S — Start'),
                icon: startMarker ?? BitmapDescriptor.defaultMarker,
              ),
            if (routeCoordinates.length > 1)
              Marker(
                markerId: const MarkerId('route-end'),
                position: routeCoordinates.last,
                infoWindow: const InfoWindow(title: 'E — End'),
                icon: endMarker ?? BitmapDescriptor.defaultMarker,
              ),
          },
          circles: {
            for (var index = 1; index < routeCoordinates.length - 1; index++)
              Circle(
                circleId: CircleId('route-point-$index'),
                center: routeCoordinates[index],
                radius: 1.5,
                fillColor: employeeGreen,
                strokeColor: Colors.white,
                strokeWidth: 1,
              ),
          },
          polylines: routeCoordinates.length < 2
              ? const <Polyline>{}
              : {
                  Polyline(
                    polylineId: const PolylineId('employee-route'),
                    points: routeCoordinates,
                    color: employeeBlue,
                    width: 5,
                  ),
                },
        ),
      ),
    );
  }
}

class _TripMetrics extends StatelessWidget {
  const _TripMetrics({
    required this.distance,
    required this.duration,
    required this.avgSpeed,
    required this.updated,
  });

  final String distance;
  final String duration;
  final String avgSpeed;
  final String updated;

  @override
  Widget build(BuildContext context) => EmployeeCard(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
    child: Row(
      children: [
        Expanded(
          child: _TripMetric(
            Icons.route_outlined,
            'Distance',
            distance,
            employeeGreen,
          ),
        ),
        const SizedBox(height: 42, child: VerticalDivider(color: employeeLine)),
        Expanded(
          child: _TripMetric(
            Icons.timer_outlined,
            'Duration',
            duration,
            employeeGreen,
          ),
        ),
        const SizedBox(height: 42, child: VerticalDivider(color: employeeLine)),
        Expanded(
          child: _TripMetric(
            Icons.speed_outlined,
            'Avg speed',
            avgSpeed,
            employeeGreen,
          ),
        ),
        const SizedBox(height: 42, child: VerticalDivider(color: employeeLine)),
        Expanded(
          child: _TripMetric(
            Icons.update_rounded,
            'Updated',
            updated.replaceFirst('Updated ', ''),
            employeeGreen,
          ),
        ),
      ],
    ),
  );
}

class _TripMetric extends StatelessWidget {
  const _TripMetric(this.icon, this.label, this.value, this.color);
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: employeeMuted, fontSize: 11),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: employeeNavy,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ActivityTimeline extends StatelessWidget {
  const _ActivityTimeline({required this.activities});
  final List<dynamic> activities;

  @override
  Widget build(BuildContext context) => EmployeeCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      children: activities.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        final timeStr = item['activity_time']?.toString() ?? '--:--';
        final textStr = item['activity_text']?.toString() ?? '';
        final isLast = idx == activities.length - 1;

        return Column(
          children: [
            _TimelineRow(timeStr, textStr),
            if (!isLast) const Divider(indent: 42, color: employeeLine),
          ],
        );
      }).toList(),
    ),
  );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow(this.time, this.label);
  final String time;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        const CircleAvatar(
          radius: 14,
          backgroundColor: employeeGreen,
          child: Icon(Icons.check, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 14),
        SizedBox(
          width: 78,
          child: Text(
            time,
            style: const TextStyle(
              color: employeeNavy,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(label, style: const TextStyle(color: employeeMuted)),
        ),
      ],
    ),
  );
}

class _LiveTrackingControl extends StatelessWidget {
  const _LiveTrackingControl({required this.active, required this.onToggle});
  final bool active;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: active ? const Color(0xFFEAF9F4) : const Color(0xFFF5F7FB),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: active ? const Color(0xFFCAEDE1) : employeeLine,
      ),
    ),
    child: Column(
      children: [
        Text(
          active ? '●  Live tracking active' : 'Live tracking is off',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? employeeGreen : employeeMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: onToggle,
          icon: Icon(
            active ? Icons.stop_circle_outlined : Icons.play_circle_outline,
          ),
          label: Text(active ? 'Stop Live Tracking' : 'Start Live Tracking'),
          style: FilledButton.styleFrom(
            backgroundColor: active ? const Color(0xFFD84343) : employeeGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ],
    ),
  );
}
