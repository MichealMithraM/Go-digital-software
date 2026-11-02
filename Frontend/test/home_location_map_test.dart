import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:godigital_portal/hrms_employee/pages/home_location_dialog.dart';
import 'package:godigital_portal/hrms_admin/features/tracking/widgets/home_locations_dialog.dart';

// Widget tests use the method-channel fallback. The real web plugin implements
// ground overlays; the fallback leaves this unused operation unimplemented.
class _TestMaps extends MethodChannelGoogleMapsFlutter {
  @override
  Future<void> updateGroundOverlays(
    GroundOverlayUpdates updates, {
    required int mapId,
  }) async {}
}

void main() {
  testWidgets(
    'admin must explicitly verify a manually selected Home before approval',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'auth_token': 'admin-test'});
      await SharedPreferences.getInstance();
      var status = 'pending';
      final approvals = <Map<String, dynamic>>[];
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add(request.url.path);
        expect(request.headers['authorization'], 'Bearer admin-test');
        Object data = {};
        if (request.url.path.endsWith('/settings')) {
          data = {
            'home_radius_meters': 100,
            'home_outside_radius_grace_minutes': 5,
            'home_no_gps_timeout_minutes': 10,
            'home_tracking_enabled': 1,
          };
        } else if (request.method == 'PATCH') {
          approvals.add(Map<String, dynamic>.from(jsonDecode(request.body)));
          status = 'approved';
        } else {
          data = {
            'items': [
              {
                'employee_user_id': 7,
                'full_name': 'Ravi',
                'employee_code': 'E7',
                'latitude': 13,
                'longitude': 80,
                'address': 'My home',
                'approval_status': status,
                'capture_source': 'map_pin',
              },
            ],
          };
        }
        return http.Response(
          jsonEncode({'success': true, 'data': data}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const HomeLocationsDialog(),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.byType(LinearProgressIndicator),
          findsNothing,
          reason: requests.toString(),
        );
        await tester.ensureVisible(find.text('Approve'));
        await tester.tap(find.text('Approve'));
        // The row remains busy while the verification dialog is open.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Verify Home Location'), findsOneWidget);
        expect(approvals, isEmpty);
        await tester.tap(find.text('I Verified This Location'));
        await tester.pumpAndSettle();
        expect(approvals, hasLength(1));
        expect(approvals.single['mapPinVerified'], true);
        expect(approvals.single['reviewedAddress'], 'My home');
        expect(approvals.single['latitude'], 13);
        expect(approvals.single['longitude'], 80);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }, () => client);
    },
  );
  testWidgets(
    'manual Home pin requires address and is submitted for approval without invented GPS',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousMaps = GoogleMapsFlutterPlatform.instance;
      GoogleMapsFlutterPlatform.instance = _TestMaps();
      addTearDown(() => GoogleMapsFlutterPlatform.instance = previousMaps);
      SharedPreferences.setMockInitialValues({'auth_token': 'home-test'});
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (call) async {
          if (call.method == 'create') {
            final args = call.arguments as Map;
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              MethodChannel('plugins.flutter.io/google_maps_${args['id']}'),
              (_) async => null,
            );
            return 1;
          }
          if (call.method == 'resize') {
            final args = call.arguments as Map;
            return {'width': args['width'], 'height': args['height']};
          }
          return null;
        },
      );
      Map<String, dynamic>? saved;
      var submissions = 0;
      final client = MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer home-test');
        expect(request.url.path, '/api/hrms/tracking/home-location');
        if (request.method == 'POST') {
          saved = Map<String, dynamic>.from(jsonDecode(request.body));
          submissions++;
        }
        return http.Response(
          jsonEncode({
            'success': true,
            'data': saved == null
                ? {}
                : {
                    ...saved!,
                    'employee_user_id': 7,
                    'approval_status': 'pending',
                    'capture_source': 'map_pin',
                  },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const HomeLocationDialog(),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select Home on Map'));
        await tester.pumpAndSettle();
        expect(submissions, 0);
        tester.widget<GoogleMap>(find.byType(GoogleMap)).onTap!(
          const LatLng(13, 80),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use Selected Home'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Enter your Home address'), findsOneWidget);
        expect(submissions, 0);
        await tester.enterText(find.byType(TextField).last, 'My home address');
        await tester.tap(find.text('Use Selected Home'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Selected on map:'), findsOneWidget);
        await tester.tap(find.text('Register Home Location'));
        await tester.pumpAndSettle();
        expect(submissions, 1);
        expect(saved!['captureSource'], 'map_pin');
        expect(saved!['latitude'], 13);
        expect(saved!['longitude'], 80);
        expect(saved!['accuracy'], null);
        expect(saved!['capturedAt'], null);
        expect(saved!['address'], 'My home address');
        expect(find.text('Status: Pending admin approval'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }, () => client);
    },
  );
}
