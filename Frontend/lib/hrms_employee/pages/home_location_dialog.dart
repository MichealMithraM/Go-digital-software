import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'home_location_picker.dart';

import '../../services/attendance_location.dart';
import '../../services/hrms_tracking_api.dart';
import '../../services/home_location_capture.dart';

/// Registration is explicit: opening this dialog never collects or saves GPS.
class HomeLocationDialog extends StatefulWidget {
  const HomeLocationDialog({super.key});

  @override
  State<HomeLocationDialog> createState() => _HomeLocationDialogState();
}

class _HomeLocationDialogState extends State<HomeLocationDialog> {
  final _addressController = TextEditingController();
  Map<String, dynamic>? _home;
  Position? _position;
  HomeMapSelection? _mapSelection;
  bool _loading = true;
  bool _capturing = false;
  bool _saving = false;
  bool _selectingMap = false;
  bool _loadFailed = false;
  String? _error;
  String? _notice;
  double? _maximumAccuracy;

  String _message(Object error) => error is TimeoutException
      ? 'The server did not respond in time. Check your internet connection and retry.'
      : error.toString().replaceFirst('Exception: ', '');

  bool get _busy => _capturing || _saving || _selectingMap;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _error = null;
    });
    try {
      final home = await HrmsTrackingApi.myHomeLocation();
      if (!mounted) return;
      setState(() {
        _home = home;
        _addressController.text = home?['address']?.toString() ?? '';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
        _error = _message(error);
      });
    }
  }

  Future<void> _capture() async {
    if (_busy) return;
    setState(() {
      _capturing = true;
      _error = null;
      _notice = null;
      _position = null;
      _mapSelection = null;
    });
    try {
      final settings = await HrmsTrackingApi.trackingSettings().timeout(
        const Duration(seconds: 15),
      );
      if (!mounted) return;
      final limit = double.tryParse('${settings['home_radius_meters']}');
      if (limit == null || !limit.isFinite || limit <= 0) {
        throw const AttendanceLocationError(
          'Ask your admin to configure the Home radius.',
        );
      }
      setState(() => _maximumAccuracy = limit);
      final position = await AttendanceLocation.currentPosition();
      if (!mounted) return;
      setState(() => _position = position);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _message(error);
      });
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _selectMap() async {
    if (_busy) return;
    setState(() {
      _selectingMap = true;
      _error = null;
      _notice = null;
    });
    try {
      final lat = double.tryParse('${_home?['latitude']}');
      final lng = double.tryParse('${_home?['longitude']}');
      final selection = await showDialog<HomeMapSelection>(
        context: context,
        builder: (_) => HomeLocationPicker(
          center:
              _mapSelection?.point ??
              (lat != null && lng != null ? LatLng(lat, lng) : null),
          address: _addressController.text,
        ),
      );
      if (!mounted || selection == null) return;
      setState(() {
        _position = null;
        _mapSelection = selection;
        _addressController.text = selection.address;
        _notice =
            'Map-selected location. Submit it for admin verification; Home check-in remains blocked until approval.';
      });
    } finally {
      if (mounted) setState(() => _selectingMap = false);
    }
  }

  Future<void> _submit() async {
    final position = _position;
    final selection = _mapSelection;
    if (_busy || (position == null && selection == null)) return;
    if (selection == null &&
        (_maximumAccuracy == null ||
            !validHomePosition(position!, _maximumAccuracy!))) {
      setState(() {
        _position = null;
        _error =
            'Capture a fresh, precise Home GPS location before submitting.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await HrmsTrackingApi.submitHomeLocation(
        latitude: selection?.point.latitude ?? position!.latitude,
        longitude: selection?.point.longitude ?? position!.longitude,
        accuracy: selection == null ? position!.accuracy : null,
        capturedAt: selection == null
            ? position!.timestamp.toUtc().toIso8601String()
            : null,
        captureSource: selection == null ? 'gps' : 'map_pin',
        address: _addressController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _home = {
          ...?_home,
          'latitude': selection?.point.latitude ?? position!.latitude,
          'longitude': selection?.point.longitude ?? position!.longitude,
          'capture_source': selection == null ? 'gps' : 'map_pin',
          'address': _addressController.text.trim(),
          'approval_status': 'pending',
          'rejection_reason': null,
        };
        _position = null;
        _mapSelection = null;
        _notice =
            'Home location submitted. An admin must approve it before '
            'Home Check In is available.';
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      if (error is TimeoutException) {
        // A timed-out response does not prove that the server rejected the save.
        final editedAddress = _addressController.text;
        await _load();
        if (!mounted) return;
        _addressController.text = editedAddress;
        setState(() {
          _position = null;
          _mapSelection = null;
          if (!_loadFailed) {
            _error =
                'The submission response timed out. The saved status above '
                'has been refreshed. Check it before capturing and submitting again.';
          }
        });
        return;
      }
      setState(() {
        _error = _message(error);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _coordinates(Object? latitude, Object? longitude) {
    final lat = double.tryParse('$latitude');
    final lng = double.tryParse('$longitude');
    if (lat == null || lng == null) return 'Not registered';
    return '${lat.toStringAsFixed(7)}, ${lng.toStringAsFixed(7)}';
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    final capturedPoint = position == null
        ? null
        : LatLng(position.latitude, position.longitude);
    final status = _home?['approval_status']?.toString() ?? 'not registered';
    final statusText = switch (status) {
      'approved' => 'Approved',
      'pending' => 'Pending admin approval',
      'rejected' => 'Rejected',
      _ => 'Not registered',
    };

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Home Location'),
        content: SizedBox(
          width: 460,
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Status: $statusText',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (_home != null) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          'Registered Home: '
                          '${_coordinates(_home!['latitude'], _home!['longitude'])}',
                        ),
                        if (status == 'rejected' &&
                            _home!['rejection_reason'] != null) ...[
                          const SizedBox(height: 8),
                          Text('Admin reason: ${_home!['rejection_reason']}'),
                        ],
                      ],
                      if (!_loadFailed) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Capture your GPS while at home, or select your home on the map. Submit the location for admin approval.',
                        ),
                        if (status == 'approved') ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Updating your approved location requires '
                            'new admin approval. Home Check In will be blocked '
                            'until the new location is approved.',
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextField(
                          controller: _addressController,
                          enabled: !_busy,
                          maxLength: 500,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Home address (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _capture,
                            icon: const Icon(Icons.my_location),
                            label: Text(
                              _capturing
                                  ? 'Finding location...'
                                  : 'Capture Current GPS',
                            ),
                          ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _selectMap,
                          icon: const Icon(Icons.pin_drop_outlined),
                          label: const Text('Select Home on Map'),
                        ),
                        if (_mapSelection != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Selected on map: ${_coordinates(_mapSelection!.point.latitude, _mapSelection!.point.longitude)}',
                          ),
                          const Text(
                            'Admin verification required. This is a map pin, not a GPS reading.',
                          ),
                        ],
                        if (capturedPoint != null) ...[
                          const SizedBox(height: 8),
                          SelectableText(
                            'Captured GPS: '
                            '${_coordinates(_position!.latitude, _position!.longitude)}',
                          ),
                          Text(
                            'Accuracy: ${_position!.accuracy.toStringAsFixed(0)} m'
                            ' (admin will verify this location)',
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 460,
                            height: 180,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: GoogleMap(
                                key: ValueKey(capturedPoint),
                                initialCameraPosition: CameraPosition(
                                  target: capturedPoint,
                                  zoom: 16,
                                ),
                                markers: {
                                  Marker(
                                    markerId: const MarkerId('captured-home'),
                                    position: capturedPoint,
                                  ),
                                },
                                mapToolbarEnabled: false,
                                zoomControlsEnabled: false,
                                scrollGesturesEnabled: false,
                                zoomGesturesEnabled: false,
                                rotateGesturesEnabled: false,
                                tiltGesturesEnabled: false,
                              ),
                            ),
                          ),
                        ],
                      ],
                      if (_notice != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _notice!,
                          style: const TextStyle(color: Color(0xFF138A20)),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      if (_loadFailed)
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed:
                _loading ||
                    _loadFailed ||
                    _busy ||
                    (_position == null && _mapSelection == null)
                ? null
                : _submit,
            child: Text(
              _saving
                  ? 'Submitting...'
                  : _home == null
                  ? 'Register Home Location'
                  : 'Update Home Location',
            ),
          ),
        ],
      ),
    );
  }
}
