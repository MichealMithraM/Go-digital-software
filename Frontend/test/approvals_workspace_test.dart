import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:godigital_portal/hrms_admin/features/approvals/approvals_page.dart';
import 'package:godigital_portal/services/auth_service.dart';

void main() {
  for (final size in [const Size(1600, 1000), const Size(1100, 760)]) {
    testWidgets(
      'Approvals list and detail fit $size and review the selected request',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final reviews = <String>[];
        var reviewed = false;
        final ranges = <Map<String, String>>[];
        final client = MockClient((request) async {
          Object data = {};
          if (request.method == 'PATCH') {
            reviews.add(request.url.path);
            reviewed = true;
          } else if (request.url.path.contains('correction-requests')) {
            data = {'items': []};
          } else {
            if (request.url.queryParameters.containsKey('startDate')) ranges.add(request.url.queryParameters);
            data = {
              'items': [
                {
                  'id': 71,
                  'name': 'Ravi Kumar',
                  'employeeCode': 'E71',
                  'type': 'Casual Leave',
                  'dates': '2 Nov 2026',
                  'duration': '1 Day',
                  'reason': 'Family appointment',
                  'status': reviewed ? 'Approved' : 'Pending',
                },
                {
                  'id': 72,
                  'name': 'Priya Devi',
                  'employeeCode': 'E72',
                  'type': 'Casual Leave',
                  'dates': '2 Nov 2026',
                  'duration': '1 Day',
                  'reason': 'Personal work',
                  'status': 'Pending',
                },
              ],
              'employees': ['Ravi Kumar', 'Priya Devi'],
              'kpis': {'pending': 2, 'approved': 0, 'rejected': 0},
            };
            final start = request.url.queryParameters['startDate'];
            final end = request.url.queryParameters['endDate'];
            if (start != null && end != null && (start.compareTo('2026-11-02') > 0 || end.compareTo('2026-11-02') < 0)) {
              (data as Map<String, dynamic>)['items'] = [];
            }
          }
          return http.Response(
            jsonEncode({'success': true, 'data': data}),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        await http.runWithClient(() async {
          await tester.pumpWidget(
            ChangeNotifierProvider(
              create: (_) => AuthService(),
              child: const MaterialApp(home: ApprovalsPage()),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Request Details'), findsWidgets);
          expect(find.text('#71'), findsOneWidget);
          expect(ranges, isNotEmpty);
          expect(ranges.last['startDate'], ranges.last['endDate']);
          expect(find.text('Day'), findsOneWidget);
          final initialSearch = find.byType(TextField);
          await tester.enterText(initialSearch, 'Family appointment');
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Previous date'));
          await tester.pumpAndSettle();
          expect(find.text('No approval requests match these filters.'), findsOneWidget);
          await tester.tap(find.byTooltip('Next date'));
          await tester.pumpAndSettle();
          expect(find.text('#71'), findsOneWidget);
          expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Family appointment');
          await tester.enterText(find.byType(TextField), '');
          await tester.pumpAndSettle();
          await tester.tap(find.text('Month'));
          await tester.pumpAndSettle();
          expect(find.text('#71'), findsOneWidget);
          expect(ranges.last['startDate'], endsWith('-01'));
          expect(ranges.last['endDate'], endsWith('-30'));
          await tester.tap(find.text('Day'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(find.text('Priya Devi'), 100,
            scrollable: find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first);
          await tester.ensureVisible(find.text('Priya Devi').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Priya Devi').first);
          await tester.pumpAndSettle();
          expect(find.text('#72'), findsOneWidget);
          final workspace = find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_ApprovalsWorkspace',
          );
          expect(
            find.descendant(
              of: workspace,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is SingleChildScrollView &&
                    w.scrollDirection == Axis.horizontal,
              ),
            ),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
          await tester.pumpAndSettle();
          expect(reviews, hasLength(1));
          expect(reviews.single, contains('72'));
          final search = find.descendant(
            of: workspace,
            matching: find.byType(TextField),
          );
          await tester.enterText(search, 'Family appointment');
          await tester.pumpAndSettle();
          expect(find.text('Priya Devi'), findsNothing);
          expect(find.text('#71'), findsOneWidget);
          final reset = find.text('Reset Filters');
          await tester.tap(reset.evaluate().isEmpty ? find.byTooltip('Reset Filters') : reset);
          await tester.pumpAndSettle();
          expect(find.text('Priya Devi'), findsWidgets);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }, () => client);
      },
    );
  }
}
