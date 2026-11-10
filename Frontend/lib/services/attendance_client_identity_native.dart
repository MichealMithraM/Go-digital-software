import 'package:flutter/foundation.dart';

class AttendanceClientIdentity {
  const AttendanceClientIdentity._();

  static Future<Map<String, String>> headers() async {
    final client = defaultTargetPlatform == TargetPlatform.iOS
        ? 'ios-app'
        : 'android-app';
    return {'X-Attendance-Client': client};
  }

  static Future<bool> get isIosWeb async => false;
}
