import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:godigital_portal/services/auth_service.dart';
import 'package:godigital_portal/hrms_admin/features/tracking/tracking_page.dart';

class _Maps extends MethodChannelGoogleMapsFlutter {
  @override
  Future<void> updateGroundOverlays(GroundOverlayUpdates updates, {required int mapId}) async {}
}

void main() {
  for (final mode in ['Home', 'Office']) {
  testWidgets('$mode check-in, check-out and map use API data and refresh on polling', (tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'admin_tracking_last_mode': mode});
    final previousMaps = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = _Maps();
    addTearDown(() => GoogleMapsFlutterPlatform.instance = previousMaps);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
      final args = call.arguments as Map;
      if (call.method == 'create') {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel('plugins.flutter.io/google_maps_${args['id']}'), (_) async => null);
        return 1;
      }
      if (call.method == 'resize') return {'width': args['width'], 'height': args['height']};
      return null;
    });
    var checkedOut = false;
    var onBreak = false;
    var requests = 0;
    final client = MockClient((request) async {
      Object data = {};
      if (request.url.path.endsWith('/live')) {
        requests++;
        final date = request.url.queryParameters['date'];
        data = {'counts': {mode.toLowerCase(): 1}, 'items': [{
          'employeeUserId': 7, 'name': 'Ravi Kumar', 'employeeCode': 'E7', 'status': mode.toLowerCase(),
          'attendanceDate': date, 'checkInAt': '${date}T09:00:00+05:30',
          'checkOutAt': checkedOut ? '${date}T10:00:00+05:30' : null,
          'active': !checkedOut, 'homeApprovalStatus': 'approved',
          'onBreak': onBreak,
          'homeLatitude': 13.1, 'homeLongitude': 80.2, 'homeAddress': 'Registered home',
          'homeRadiusMeters': 345, 'accuracyMeters': 18.5,
        }]};
      } else if (request.url.path.endsWith('/settings')) {
        data = {'office_latitude': 12.0, 'office_longitude': 79.0, 'office_radius_meters': 678};
      }
      return http.Response(jsonEncode({'success': true, 'data': data}), 200, headers: {'content-type': 'application/json'});
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(ChangeNotifierProvider(create: (_) => AuthService(), child: const MaterialApp(home: TrackingPage())));
      await tester.pumpAndSettle();
      expect(find.text('Checked in'), findsWidgets);
      expect(find.text('Not checked in'), findsNothing);
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap).first);
      expect(map.initialCameraPosition.target, mode == 'Home' ? const LatLng(13.1, 80.2) : const LatLng(12, 79));
      expect(map.markers.any((m) => m.markerId.value == '__office__'), mode == 'Office');
      expect(map.markers.any((m) => m.markerId.value == '__home__'), mode == 'Home');
      expect(tester.takeException(), isNull);
      final detail = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_DesktopFixedLocationDetail');
      onBreak = true;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.descendant(of: detail, matching: find.text('On break')), findsOneWidget);
      onBreak = false;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.descendant(of: detail, matching: find.text('On break')), findsNothing);
      expect(find.descendant(of: detail, matching: find.text('Checked in')), findsOneWidget);
      checkedOut = true;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(requests, greaterThan(1));
      expect(find.text('Checked out'), findsWidgets);
      expect(find.descendant(of: detail, matching: find.text('Checked in')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }, () => client);
  });
  }
}
