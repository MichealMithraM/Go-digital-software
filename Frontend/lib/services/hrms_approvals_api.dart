import 'dart:convert';

import 'package:godigital_portal/services/authenticated_http.dart' as http;

import 'api_config.dart';
import 'auth_storage.dart';

class HrmsApprovalsApi {
  HrmsApprovalsApi._();

  static Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _decode(http.Response response) {
    final decoded =
        response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
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

  static Future<Map<String, dynamic>> list({
    bool leaveTab = true,
    String? tab,
    String employee = 'All Employees',
    String status = 'All Status',
    String? startDate,
    String? endDate,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/hrms/approvals').replace(
      queryParameters: {
        'tab': tab ?? (leaveTab ? 'leave' : 'extra'),
        'employee': employee,
        'status': status,
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
      },
    );
    final response = await http.get(uri, headers: await _headers());
    return _decode(response);
  }

  static Future<Map<String, dynamic>> review(int id, String status) async {
    final response = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/hrms/approvals/$id'),
      headers: await _headers(),
      body: jsonEncode({'status': status.toLowerCase()}),
    );
    return _decode(response);
  }
}
