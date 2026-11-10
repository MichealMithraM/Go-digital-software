import 'dart:convert';

import 'package:godigital_portal/services/authenticated_http.dart' as http;

import 'api_config.dart';
import 'auth_storage.dart';

abstract final class HrmsClockLogsApi {
  static Future<List<Map<String, dynamic>>> iosWebDevices() async {
    final token = await AuthStorage.getString('auth_token');
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/attendance/ios-web-devices'),
      headers: {if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'},
    );
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final map = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    if (response.statusCode >= 400 || map['success'] == false) {
      throw Exception(map['message']?.toString() ?? 'Could not load iPhone access requests');
    }
    return ((map['data'] as Map?)?['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<void> updateIosWebDevice(int id, String status) async {
    final token = await AuthStorage.getString('auth_token');
    final response = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/attendance/ios-web-devices/$id'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'status': status}),
    );
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final map = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    if (response.statusCode >= 400 || map['success'] == false) {
      throw Exception(map['message']?.toString() ?? 'Could not update iPhone access');
    }
  }

  static Future<Map<String, dynamic>> calendar({
    required int employeeId,
    required DateTime month,
  }) async {
    final token = await AuthStorage.getString('auth_token');
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/attendance/clock-logs/calendar').replace(
        queryParameters: {
          'employeeId': '$employeeId',
          'month': '${month.year}-${month.month.toString().padLeft(2, '0')}',
        },
      ),
      headers: {if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'},
    );
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final map = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    if (response.statusCode >= 400 || map['success'] == false) {
      throw Exception(map['message']?.toString() ?? 'Could not load employee calendar');
    }
    return map['data'] is Map ? Map<String, dynamic>.from(map['data']) : map;
  }

  static Future<Map<String, dynamic>> correctStatus({
    required int employeeId,
    required String date,
    required String status,
    required String reason,
  }) async {
    final token = await AuthStorage.getString('auth_token');
    final response = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/attendance/clock-logs/status'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'employeeId': employeeId,
        'date': date,
        'status': status,
        'reason': reason,
      }),
    );
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final map = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    if (response.statusCode >= 400 || map['success'] == false) {
      throw Exception(map['message']?.toString() ?? 'Could not correct attendance');
    }
    return map['data'] is Map ? Map<String, dynamic>.from(map['data']) : map;
  }

  static Future<Map<String, dynamic>> list({
    required DateTime date,
    required bool monthly,
    int? employeeId,
  }) async {
    final query = <String, String>{
      'view': monthly ? 'month' : 'day',
      'date': _date(date),
      'month': '${date.year}-${date.month.toString().padLeft(2, '0')}',
      if (employeeId != null) 'employeeId': '$employeeId',
    };
    final token = await AuthStorage.getString('auth_token');
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/attendance/clock-logs')
          .replace(queryParameters: query),
      headers: {if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'},
    );
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final map = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    if (response.statusCode >= 400 || map['success'] == false) {
      throw Exception(map['message']?.toString() ?? 'Could not load clock logs');
    }
    return map['data'] is Map ? Map<String, dynamic>.from(map['data']) : map;
  }

  static Future<Map<String, dynamic>> getBreakReview(int breakId) async {
    final token = await AuthStorage.getString('auth_token');
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/attendance/breaks/$breakId/review'),
      headers: {if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'},
    );
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final map = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    if (response.statusCode >= 400 || map['success'] == false) {
      throw Exception(map['message']?.toString() ?? 'Could not load break review');
    }
    return map['data'] is Map ? Map<String, dynamic>.from(map['data']) : map;
  }

  static Future<void> reviewBreak(int breakId, {required String action, String? clarification}) async {
    final token = await AuthStorage.getString('auth_token');
    final response = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/attendance/breaks/$breakId/review'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'action': action, if (clarification != null && clarification.isNotEmpty) 'clarification': clarification}),
    );
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final map = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    if (response.statusCode >= 400 || map['success'] == false) {
      throw Exception(map['message']?.toString() ?? 'Could not submit review');
    }
  }

  static String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
