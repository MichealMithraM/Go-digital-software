import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:godigital_portal/services/home_location_capture.dart';

Position fix(double accuracy, {DateTime? timestamp, double latitude = 13}) =>
    Position(
      latitude: latitude,
      longitude: 80,
      timestamp: timestamp ?? DateTime.now(),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  test(
    'coarse browser fixes are skipped until a precise reading arrives',
    () async {
      final result = await accurateHomePosition(
        Stream.fromIterable([fix(200000), fix(5000), fix(80)]),
        100,
      );
      expect(result.accuracy, 80);
    },
  );
  test(
    'accuracy follows the supplied admin radius, including its boundary',
    () async {
      expect(validHomePosition(fix(250), 250), true);
      expect(validHomePosition(fix(250), 100), false);
      expect(
        (await accurateHomePosition(Stream.value(fix(350)), 400)).accuracy,
        350,
      );
    },
  );
  test('stale, future and invalid positions cannot be submitted', () {
    expect(
      validHomePosition(
        fix(5, timestamp: DateTime.now().subtract(const Duration(minutes: 3))),
        100,
      ),
      false,
    );
    expect(
      validHomePosition(
        fix(5, timestamp: DateTime.now().add(const Duration(minutes: 1))),
        100,
      ),
      false,
    );
    expect(validHomePosition(fix(5, latitude: double.nan), 100), false);
    expect(validHomePosition(fix(-1), 100), false);
  });
  test('overall timeout cancels continuous coarse updates', () async {
    var cancelled = false;
    final stream = StreamController<Position>(
      onCancel: () {
        cancelled = true;
      },
    );
    final future = accurateHomePosition(
      stream.stream,
      100,
      timeout: const Duration(milliseconds: 30),
    );
    final expectation = expectLater(
      future,
      throwsA(predicate((e) => e.toString().contains('phone'))),
    );
    stream.add(fix(5000));
    await expectation;
    expect(cancelled, true);
    await stream.close();
  });
  test('a successful reading cancels the GPS subscription', () async {
    var cancelled = false;
    final stream = StreamController<Position>(
      onCancel: () {
        cancelled = true;
      },
    );
    final future = accurateHomePosition(stream.stream, 100);
    stream.add(fix(25));
    await future;
    expect(cancelled, true);
    await stream.close();
  });
  test(
    'missing admin configuration is rejected instead of using a default',
    () async {
      await expectLater(
        accurateHomePosition(const Stream.empty(), 0),
        throwsA(predicate((e) => e.toString().contains('admin'))),
      );
    },
  );
}
