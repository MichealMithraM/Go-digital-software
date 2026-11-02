import 'dart:convert';

import 'package:godigital_portal/services/authenticated_http.dart' as http;

import 'api_config.dart';
import 'auth_storage.dart';
import 'office_address_search.dart';

class HrmsTrackingApi {
  HrmsTrackingApi._();

  static Future<Map<String, dynamic>?> myHomeLocation() async {
    final response = await http
        .get(
          Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/home-location'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));
    final data = _decode(response);
    return data['employee_user_id'] == null ? null : data;
  }

  static Future<void> submitHomeLocation({
    required double latitude,
    required double longitude,
    double? accuracy,
    String? capturedAt,
    String captureSource = 'gps',
    String? address,
  }) async {
    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/home-location'),
          headers: await _headers(),
          body: jsonEncode({
            'latitude': latitude,
            'longitude': longitude,
            'accuracy': accuracy,
            'capturedAt': capturedAt,
            'captureSource': captureSource,
            'address': address,
          }),
        )
        .timeout(const Duration(seconds: 15));
    _decode(response);
  }

  static Future<List<Map<String, dynamic>>> homeLocations() async {
    final response = await http
        .get(
          Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/home-locations'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));
    final data = _decode(response);
    return (data['items'] as List? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<void> reviewHomeLocation({
    required int employeeUserId,
    required bool approve,
    required double latitude,
    required double longitude,
    String? rejectionReason,
    bool mapPinVerified = false,
    String? reviewedAddress,
  }) async {
    final response = await http
        .patch(
          Uri.parse(
            '${ApiConfig.baseUrl}/hrms/tracking/home-locations/$employeeUserId',
          ),
          headers: await _headers(),
          body: jsonEncode({
            'approvalStatus': approve ? 'approved' : 'rejected',
            'latitude': latitude,
            'longitude': longitude,
            'rejectionReason': rejectionReason,
            'mapPinVerified': mapPinVerified,
            'reviewedAddress': reviewedAddress,
          }),
        )
        .timeout(const Duration(seconds: 15));
    _decode(response);
  }

  static Future<void> updateOfficeRadius(int radiusMeters) async {
    final response = await http
        .put(
          Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/settings'),
          headers: await _headers(),
          body: jsonEncode({'officeRadiusMeters': radiusMeters}),
        )
        .timeout(const Duration(seconds: 15));
    _decode(response);
  }

  static Future<void> updateHomeRadius(int radiusMeters) async {
    final response = await http
        .put(
          Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/home-settings'),
          headers: await _headers(),
          body: jsonEncode({'homeRadiusMeters': radiusMeters}),
        )
        .timeout(const Duration(seconds: 15));
    _decode(response);
  }

  static Future<void> updateHomeSettings({
    int? homeRadiusMeters,
    int? homeOutsideRadiusGraceMinutes,
    int? homeNoGpsTimeoutMinutes,
    bool? homeTrackingEnabled,
  }) async {
    final body = <String, dynamic>{};
    if (homeRadiusMeters != null) body['homeRadiusMeters'] = homeRadiusMeters;
    if (homeOutsideRadiusGraceMinutes != null) {
      body['homeOutsideRadiusGraceMinutes'] = homeOutsideRadiusGraceMinutes;
    }
    if (homeNoGpsTimeoutMinutes != null) {
      body['homeNoGpsTimeoutMinutes'] = homeNoGpsTimeoutMinutes;
    }
    if (homeTrackingEnabled != null) {
      body['homeTrackingEnabled'] = homeTrackingEnabled;
    }
    final response = await http
        .put(
          Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/home-settings'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    _decode(response);
  }

  static Future<Map<String, dynamic>> updateOfficeLocation({
    required String officeName,
    required String officeAddress,
    required double officeLatitude,
    required double officeLongitude,
    required int officeRadiusMeters,
  }) async {
    final response = await http
        .put(
          Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/settings'),
          headers: await _headers(),
          body: jsonEncode({
            'officeName': officeName,
            'officeAddress': officeAddress,
            'officeLatitude': officeLatitude,
            'officeLongitude': officeLongitude,
            'officeRadiusMeters': officeRadiusMeters,
          }),
        )
        .timeout(const Duration(seconds: 15));
    return _decode(response);
  }

  static Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.getString('auth_token');

    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _decode(http.Response response) {
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);

    if (decoded is! Map) {
      throw Exception('Unexpected response');
    }

    final map = Map<String, dynamic>.from(decoded);

    if (response.statusCode >= 400 || map['success'] == false) {
      throw Exception(map['message']?.toString() ?? 'Request failed');
    }

    final data = map['data'];

    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    return map;
  }

  static Future<Map<String, dynamic>> live({String? date}) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/hrms/tracking/live',
    ).replace(queryParameters: date == null ? null : {'date': date});
    final response = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    return _resolveTrackingNames(_decode(response));
  }

  static Future<Map<String, dynamic>> monthlyReport({
    required int employeeUserId,
    required String month,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/hrms/tracking/employee/$employeeUserId/monthly',
    ).replace(queryParameters: {'month': month});
    final response = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 20));
    return _decode(response);
  }

  static Future<Map<String, dynamic>> route({
    required int employeeUserId,
    required String date,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/hrms/tracking/route/$employeeUserId',
    ).replace(queryParameters: {'date': date});

    final response = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    return _resolveTrackingNames(_decode(response));
  }

  static Future<Map<String, dynamic>> _resolveTrackingNames(
    Map<String, dynamic> data,
  ) async {
    final lists = <String, List<Map<String, dynamic>>>{
      for (final key in ['items', 'activities'])
        key: (data[key] as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(),
    };
    final lookups = <String, Future<String?>>{};
    String? coordinateKey(Map<String, dynamic> item) {
      final lat = double.tryParse('${item['latitude'] ?? ''}');
      final lng = double.tryParse('${item['longitude'] ?? ''}');
      if (lat == null ||
          lng == null ||
          !lat.isFinite ||
          !lng.isFinite ||
          lat.abs() > 90 ||
          lng.abs() > 180) {
        return null;
      }
      return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    }

    // Bound lookup work: failed geocoding must not hide an entire history
    // behind a sequence of 15-second requests for every recorded point.
    for (final item in lists.values.expand((items) => items)) {
      final key = coordinateKey(item);
      final existing = '${item['placeName'] ?? item['address'] ?? ''}'.trim();
      if (key != null &&
          (existing.isEmpty || existing == 'Location name unavailable') &&
          lookups.length < 8 &&
          !lookups.containsKey(key)) {
        lookups[key] =
            reverseGeocodeOfficeLocation(
                  double.parse('${item['latitude']}'),
                  double.parse('${item['longitude']}'),
                )
                .timeout(const Duration(seconds: 4), onTimeout: () => null)
                .catchError((Object _) => null);
      }
    }
    final resolved = <String, String?>{};
    await Future.wait(
      lookups.entries.map((entry) async {
        resolved[entry.key] = await entry.value;
      }),
    );
    for (final entry in lists.entries) {
      for (final item in entry.value) {
        final field = entry.key == 'activities' ? 'placeName' : 'address';
        final key = coordinateKey(item);
        final existing = '${item[field] ?? ''}'.trim();
        if (existing.isEmpty || existing == 'Location name unavailable') {
          item[field] =
              resolved[key] ??
              (key == null
                  ? 'No location recorded'
                  : 'Address unavailable ($key)');
        }
        if (entry.key == 'activities' &&
            item['locationQuality'] != null &&
            item['locationQuality'] != 'usable') {
          final accuracy = item['accuracyMeters'];
          item[field] =
              '${item[field]} — ${accuracy == null ? 'accuracy unknown' : 'accuracy $accuracy m'} (unverified)';
        }
      }
    }
    return {
      ...data,
      for (final entry in lists.entries)
        if (data.containsKey(entry.key)) entry.key: entry.value,
    };
  }

  static Future<Map<String, dynamic>> myRoute({required String date}) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/hrms/tracking/route/me',
    ).replace(queryParameters: {'date': date});
    final response = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    return _resolveTrackingNames(_decode(response));
  }

  static Future<void> setStatus(String status) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/status'),
      headers: await _headers(),
      body: jsonEncode({'status': status}),
    );

    _decode(response);
  }

  static Future<void> ping({
    required double latitude,
    required double longitude,
    double? accuracy,
    required String capturedAt,
    String? address,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/ping'),
      headers: await _headers(),
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': ?accuracy,
        'capturedAt': capturedAt,
        'address': address,
      }),
    );

    _decode(response);
  }

  static Future<Map<String, dynamic>> fieldSession() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/field-session'),
      headers: await _headers(),
    );

    return _decode(response);
  }

  static Future<Map<String, dynamic>> hybridSession() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/hybrid-session'),
      headers: await _headers(),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> startFieldSession({
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/field-session/start'),
      headers: await _headers(),
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': ?accuracy,
      }),
    );

    return _decode(response);
  }

  static Future<Map<String, dynamic>> startHybridSession({
    required double latitude,
    required double longitude,
    double? accuracy,
    required String capturedAt,
    String? address,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/hybrid-session/start'),
      headers: await _headers(),
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': ?accuracy,
        'capturedAt': capturedAt,
        'address': address,
      }),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> stopFieldSession({
    double? latitude,
    double? longitude,
    double? accuracy,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/field-session/stop'),
      headers: await _headers(),
      body: jsonEncode({
        'latitude': ?latitude,
        'longitude': ?longitude,
        'accuracy': ?accuracy,
      }),
    );

    return _decode(response);
  }

  static Future<Map<String, dynamic>> stopHybridSession({
    double? latitude,
    double? longitude,
    double? accuracy,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/hybrid-session/stop'),
      headers: await _headers(),
      body: jsonEncode({
        'latitude': ?latitude,
        'longitude': ?longitude,
        'accuracy': ?accuracy,
      }),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>?> waitingAlert() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/field-waiting-alert'),
      headers: await _headers(),
    );

    final data = _decode(response);

    // When no alert exists, backend returns { success: true, data: null }.
    if (data['id'] == null) {
      return null;
    }

    return data;
  }

  static Future<void> submitWaitingReason({
    required int reasonId,
    required String reason,
  }) async {
    final response = await http.post(
      Uri.parse(
        '${ApiConfig.baseUrl}/hrms/tracking/field-waiting-reasons/$reasonId',
      ),
      headers: await _headers(),
      body: jsonEncode({'reason': reason}),
    );

    _decode(response);
  }

  static Future<Map<String, dynamic>> trackingSettings() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/settings'),
      headers: await _headers(),
    );

    return _decode(response);
  }

  static Future<Map<String, dynamic>> updateFieldWaitingSettings({
    required int fieldWaitingMinutes,
    required int stationaryRadiusMeters,
    required int fieldPingIntervalMinutes,
    required int officeOutsideRadiusGraceMinutes,
    required int homeOutsideRadiusGraceMinutes,
    bool? homeTrackingEnabled,
  }) async {
    final response = await http.put(
      Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/settings'),
      headers: await _headers(),
      body: jsonEncode({
        'fieldWaitingMinutes': fieldWaitingMinutes,
        'stationaryRadiusMeters': stationaryRadiusMeters,
        'fieldPingIntervalMinutes': fieldPingIntervalMinutes,
        'officeOutsideRadiusGraceMinutes': officeOutsideRadiusGraceMinutes,
        'homeOutsideRadiusGraceMinutes': homeOutsideRadiusGraceMinutes,
        'homeTrackingEnabled': ?homeTrackingEnabled,
      }),
    );

    return _decode(response);
  }

  static Future<Map<String, dynamic>> updateHybridSettings({
    required int fieldWaitingMinutes,
    required int stationaryRadiusMeters,
    required int fieldPingIntervalMinutes,
    required int officeOutsideRadiusGraceMinutes,
    int? officeNoGpsTimeoutMinutes,
  }) async {
    final body = <String, dynamic>{
      'fieldWaitingMinutes': fieldWaitingMinutes,
      'stationaryRadiusMeters': stationaryRadiusMeters,
      'fieldPingIntervalMinutes': fieldPingIntervalMinutes,
      'officeOutsideRadiusGraceMinutes': officeOutsideRadiusGraceMinutes,
    };
    if (officeNoGpsTimeoutMinutes != null) {
      body['officeNoGpsTimeoutMinutes'] = officeNoGpsTimeoutMinutes;
    }
    final response = await http
        .put(
          Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/hybrid-settings'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    return _decode(response);
  }

  static Future<List<Map<String, dynamic>>> fieldWaitingReasons() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/hrms/tracking/field-waiting-reasons'),
      headers: await _headers(),
    );

    final data = _decode(response);
    final items = data['items'] as List? ?? [];

    return items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<void> reviewFieldWaitingReason(int reasonId) async {
    final response = await http.patch(
      Uri.parse(
        '${ApiConfig.baseUrl}/hrms/tracking/field-waiting-reasons/$reasonId/review',
      ),
      headers: await _headers(),
    );

    _decode(response);
  }
}
