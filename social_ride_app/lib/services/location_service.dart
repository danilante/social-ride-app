import 'package:geolocator/geolocator.dart';
import 'package:social_ride_app/util/geo.dart';

class LocationService {
  final Stream<Position> Function() positionStreamFactory;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final Future<Position> Function() _getCurrentPosition;

  LocationService({
    Stream<Position> Function()? positionStreamFactory,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<Position> Function()? getCurrentPositionFn,
  })  : positionStreamFactory =
            positionStreamFactory ?? Geolocator.getPositionStream,
        _checkPermission = checkPermission ?? Geolocator.checkPermission,
        _requestPermission = requestPermission ?? Geolocator.requestPermission,
        _getCurrentPosition =
            getCurrentPositionFn ?? Geolocator.getCurrentPosition;

  /// Requests permission, preferring "always" (needed for background
  /// tracking while the phone is in a jersey pocket). Falls back to
  /// whileInUse if the platform / user only grants that.
  Future<bool> ensurePermission() async {
    LocationPermission permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _requestPermission();
    }
    // On some platforms a second request can upgrade whileInUse → always.
    if (permission == LocationPermission.whileInUse) {
      // Best-effort upgrade; ignore if the OS does not allow it.
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

  /// Best-effort current position for centering map on open. Returns
  /// null (never throws) so missing permission or platform lookup
  /// failure falls back to map's default camera.
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

  /// Emits positions at most once every [interval], and only when the
  /// rider has moved at least [minDistanceMeters] from the last emitted
  /// point (or it is the first point). Both filters reduce Firestore
  /// writes and Cloud Function invocations.
  Stream<Position> throttledPositionStream({
    Duration interval = const Duration(seconds: 10),
    double minDistanceMeters = 15,
  }) {
    DateTime? lastEmittedAt;
    double? lastLat;
    double? lastLng;

    return positionStreamFactory().where((position) {
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
}
