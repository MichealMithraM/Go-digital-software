import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:godigital_portal/services/authenticated_http.dart' as http;

import 'api_config.dart';

class AttendanceLocationError implements Exception {
  const AttendanceLocationError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Captures a location only when the employee explicitly registers a home
/// or presses Clock In. The server makes the final distance/approval decision.
class AttendanceLocation {
  AttendanceLocation._();

  static Future<Position> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const AttendanceLocationError(
          'Turn on device location and try again.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const AttendanceLocationError(
          'Allow location for this app in your browser or device settings, then retry.',
        );
      }
      if (permission == LocationPermission.denied) {
        throw const AttendanceLocationError(
          'Location permission is needed to verify Check In.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      ).timeout(const Duration(seconds: 30));
      final age = DateTime.now().toUtc().difference(position.timestamp.toUtc());
      if (age > const Duration(minutes: 2) ||
          age < const Duration(seconds: -30)) {
        throw const AttendanceLocationError(
          'The location reading is out of date. Please retry.',
        );
      }
      if (!position.latitude.isFinite ||
          position.latitude.abs() > 90 ||
          !position.longitude.isFinite ||
          position.longitude.abs() > 180 ||
          !position.accuracy.isFinite ||
          position.accuracy < 0) {
        throw const AttendanceLocationError(
          'A valid GPS reading is required. Please retry.',
        );
      }
      return position;
    } on AttendanceLocationError {
      rethrow;
    } on TimeoutException {
      throw const AttendanceLocationError(
        'GPS took too long. Check location access and retry.',
      );
    } catch (_) {
      throw const AttendanceLocationError(
        'Could not get your location. Check location access and retry.',
      );
    }
  }

  static Future<Map<String, dynamic>> checkInPolicy({
    required http.Client client,
    required String token,
  }) async {
    final response = await client
        .get(
          Uri.parse('${ApiConfig.baseUrl}/attendance/check-in-policy'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const AttendanceLocationError(
        'Could not load Check In rules. Please retry.',
      );
    }
    if (response.statusCode != 200 ||
        decoded is! Map ||
        decoded['success'] != true) {
      throw AttendanceLocationError(
        decoded is Map
            ? decoded['message']?.toString() ?? 'Could not load Check In rules.'
            : 'Could not load Check In rules.',
      );
    }
    final policy = decoded['data'];
    if (policy is! Map) {
      throw const AttendanceLocationError(
        'Check In rules are unavailable. Contact your admin.',
      );
    }
    return Map<String, dynamic>.from(policy);
  }

  static Future<Map<String, dynamic>> checkInPayload({
    required http.Client client,
    required String token,
    Future<Position> Function()? locate,
    bool forceLocation = false,
  }) async {
    final policy = await checkInPolicy(client: client, token: token);
    if (policy['workMode'] == 'Hybrid' && !forceLocation) {
      // Hybrid employees may Clock In from any location. The backend records
      // the work mode and the Tracking endpoint later requires this Clock In.
      return <String, dynamic>{};
    }
    if (!forceLocation &&
        (policy['requiresLocation'] != true ||
            !['Office', 'Home'].contains(policy['workMode']))) {
      throw const AttendanceLocationError(
        'Check In rules are unavailable. Contact your admin.',
      );
    }
    final position = await (locate ?? currentPosition)();
    return {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'capturedAt': position.timestamp.toUtc().toIso8601String(),
    };
  }
}
