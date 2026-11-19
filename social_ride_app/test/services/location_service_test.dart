import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:social_ride_app/services/location_service.dart';

Position _fakePosition(DateTime timestamp, {double lat = 45.0, double lng = 7.0}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: timestamp,
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  test('ensurePermission returns true when permission already granted', () async {
    final service = LocationService(
      checkPermission: () async => LocationPermission.whileInUse,
      requestPermission: () async => LocationPermission.denied,
    );

    expect(await service.ensurePermission(), isTrue);
  });

  test('ensurePermission requests permission when denied, then returns result',
      () async {
    final service = LocationService(
      checkPermission: () async => LocationPermission.denied,
      requestPermission: () async => LocationPermission.always,
    );

    expect(await service.ensurePermission(), isTrue);
  });

  test('ensurePermission returns false when permission denied forever',
      () async {
    final service = LocationService(
      checkPermission: () async => LocationPermission.deniedForever,
      requestPermission: () async => LocationPermission.deniedForever,
    );

    expect(await service.ensurePermission(), isFalse);
  });

  test('throttledPositionStream only emits positions at least interval apart', () async {
    final controller = StreamController<Position>();
    final service = LocationService(
      positionStreamFactory: () => controller.stream,
    );

    final emitted = <Position>[];
    final subscription = service
        .throttledPositionStream(interval: const Duration(seconds: 10))
        .listen(emitted.add);

    final base = DateTime(2026, 1, 1, 12, 0, 0);
    controller.add(_fakePosition(base));
    controller.add(_fakePosition(base.add(const Duration(seconds: 3))));
    controller.add(_fakePosition(base.add(const Duration(seconds: 11))));
    controller.add(_fakePosition(base.add(const Duration(seconds: 15))));
    await Future.delayed(Duration.zero);

    expect(emitted.length, 2);
    expect(emitted[0].timestamp, base);
    expect(emitted[1].timestamp, base.add(const Duration(seconds: 11)));

    await subscription.cancel();
    await controller.close();
  });
}
