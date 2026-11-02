import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'attendance_location.dart';

bool validHomePosition(Position position, double maximumAccuracy) {
  final age = DateTime.now().toUtc().difference(position.timestamp.toUtc());
  return position.latitude.isFinite &&
      position.latitude.abs() <= 90 &&
      position.longitude.isFinite &&
      position.longitude.abs() <= 180 &&
      position.accuracy.isFinite &&
      position.accuracy >= 0 &&
      position.accuracy <= maximumAccuracy &&
      age <= const Duration(minutes: 2) &&
      age >= const Duration(seconds: -30);
}

/// An overall deadline also applies when the browser keeps sending coarse fixes.
Future<Position> accurateHomePosition(
  Stream<Position> readings,
  double maximumAccuracy, {
  Duration timeout = const Duration(seconds: 40),
}) async {
  if (!maximumAccuracy.isFinite || maximumAccuracy <= 0) {
    throw const AttendanceLocationError(
      'Ask your admin to configure the Home radius.',
    );
  }
  final result = Completer<Position>();
  final timer = Timer(timeout, () {
    if (!result.isCompleted)
      result.completeError(
        const AttendanceLocationError(
          'Your browser could not get a precise location. Enable precise location '
          'and Wi-Fi, then retry. If this computer still gives an approximate '
          'location, open this page on your phone while you are at home.',
        ),
      );
  });
  final subscription = readings.listen(
    (position) {
      if (!result.isCompleted && validHomePosition(position, maximumAccuracy)) {
        result.complete(position);
      }
    },
    onError: (Object error) {
      if (!result.isCompleted) result.completeError(error);
    },
    onDone: () {
      if (!result.isCompleted)
        result.completeError(
          const AttendanceLocationError(
            'A precise location was not available. Enable precise location and retry, '
            'or use your phone while you are at home.',
          ),
        );
    },
  );
  try {
    return await result.future;
  } finally {
    timer.cancel();
    await subscription.cancel();
  }
}
