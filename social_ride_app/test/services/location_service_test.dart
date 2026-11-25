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
        .throttledPositionStream(
          interval: const Duration(seconds: 10),
          minDistanceMeters: 0, // disable distance filter for this test
        )
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

  test('throttledPositionStream skips points that moved less than minDistanceMeters',
      () async {
    final controller = StreamController<Position>();
    final service = LocationService(
      positionStreamFactory: () => controller.stream,
    );

    final emitted = <Position>[];
    final subscription = service
        .throttledPositionStream(
          interval: const Duration(seconds: 1),
          minDistanceMeters: 20,
        )
        .listen(emitted.add);

    final base = DateTime(2026, 1, 1, 12, 0, 0);
    // First point always emitted
    controller.add(_fakePosition(base, lat: 45.0, lng: 7.0));
    // ~11 m north (~0.0001 deg lat) → below 20 m threshold
    controller.add(_fakePosition(base.add(const Duration(seconds: 5)),
        lat: 45.0001, lng: 7.0));
    // ~55 m north → above threshold and enough time
    controller.add(_fakePosition(base.add(const Duration(seconds: 10)),
        lat: 45.0005, lng: 7.0));
    await Future.delayed(Duration.zero);

    expect(emitted.length, 2);
    expect(emitted[0].latitude, 45.0);
    expect(emitted[1].latitude, 45.0005);

    await subscription.cancel();
    await controller.close();
  });

  test('getCurrentPosition returns null when permission denied', () async {
    final service = LocationService(
      checkPermission: () async => LocationPermission.denied,
      requestPermission: () async => LocationPermission.denied,
    );
    final position = await service.getCurrentPosition();
    expect(position, isNull);
  });

  test('getCurrentPosition returns a position when permission granted', () async {
    final fakePosition = Position(
      latitude: 45.07,
      longitude: 7.68,
      timestamp: DateTime.now(),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 0,
    );
    final service = LocationService(
      checkPermission: () async => LocationPermission.whileInUse,
      getCurrentPositionFn: () async => fakePosition,
    );
    final position = await service.getCurrentPosition();
    expect(position, fakePosition);
  });
}
