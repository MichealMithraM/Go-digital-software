import 'dart:html' as html;
import 'dart:math';

class AttendanceClientIdentity {
  const AttendanceClientIdentity._();

  static bool get _isIos {
    final ua = html.window.navigator.userAgent.toLowerCase();
    // iPadOS desktop-mode Safari uses a Macintosh platform identifier.
    return ua.contains('iphone') || ua.contains('ipod') || ua.contains('ipad') ||
        (ua.contains('macintosh') && ua.contains('mobile/'));
  }

  static String _deviceId() {
    const key = 'attendance_ios_web_device_id';
    final stored = html.window.localStorage[key];
    if (stored != null && RegExp(r'^[A-Za-z0-9_-]{32,160}$').hasMatch(stored)) {
      return stored;
    }
    final random = Random.secure();
    final value = List<String>.generate(
      48,
      (_) => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
          [random.nextInt(64)],
    ).join();
    html.window.localStorage[key] = value;
    return value;
  }

  static Future<Map<String, String>> headers() async => {
    'X-Attendance-Client': _isIos ? 'ios-web' : 'web',
    if (_isIos) 'X-Attendance-Device-Id': _deviceId(),
  };

  static Future<bool> get isIosWeb async => _isIos;
}
