import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:social_ride_app/services/ride_foreground_service.dart';
import 'package:social_ride_app/util/geo.dart';

class LocationService {
  final Stream<Position> Function({LocationSettings? locationSettings})
      positionStreamFactory;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final Future<Position> Function() _getCurrentPosition;

  LocationService({
    Stream<Position> Function({LocationSettings? locationSettings})?
        positionStreamFactory,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<Position> Function()? getCurrentPositionFn,
  })  : positionStreamFactory = positionStreamFactory ??
            (({LocationSettings? locationSettings}) =>
                Geolocator.getPositionStream(
                    locationSettings: locationSettings)),
        _checkPermission = checkPermission ?? Geolocator.checkPermission,
        _requestPermission = requestPermission ?? Geolocator.requestPermission,
        _getCurrentPosition =
            getCurrentPositionFn ?? Geolocator.getCurrentPosition;

  Future<bool> ensurePermission() async {
    LocationPermission permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _requestPermission();
    }
    if (permission == LocationPermission.whileInUse) {
      try {
        final upgraded = await _requestPermission();
        if (upgraded == LocationPermission.always) {
          permission = upgraded;
        }
      } catch (_) {}
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<Position?> getCurrentPosition() async {
    final permission = await _checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return null;
    }
    try {
      return await _getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  Stream<Position> throttledPositionStream({
    Duration interval = const Duration(seconds: 10),
    double minDistanceMeters = 15,
    String rideCode = '',
  }) {
    DateTime? lastEmittedAt;
    double? lastLat;
    double? lastLng;

    final settings = _locationSettingsForPlatform(rideCode);

    return positionStreamFactory(locationSettings: settings).where((position) {
      final now = position.timestamp;
      final timeOk = lastEmittedAt == null ||
          now.difference(lastEmittedAt!) >= interval;

      final distanceOk = lastLat == null ||
          lastLng == null ||
          distanceMeters(
                  lastLat!, lastLng!, position.latitude, position.longitude) >=
              minDistanceMeters;

      if (timeOk && distanceOk) {
        lastEmittedAt = now;
        lastLat = position.latitude;
        lastLng = position.longitude;
        return true;
      }
      return false;
    });
  }

  LocationSettings? _locationSettingsForPlatform(String rideCode) {
    if (kIsWeb) return null;
    try {
      if (Platform.isAndroid) {
        return RideForegroundService.trackingSettings(rideCode: rideCode);
      }
      if (Platform.isIOS) {
        return RideForegroundService.appleSettings();
      }
    } catch (_) {}
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
  }
}
