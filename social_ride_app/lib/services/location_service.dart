import 'package:geolocator/geolocator.dart';

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

  Future<bool> ensurePermission() async {
    LocationPermission permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _requestPermission();
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

  Stream<Position> throttledPositionStream(
      {Duration interval = const Duration(seconds: 10)}) {
    DateTime? lastEmitted;
    return positionStreamFactory().where((position) {
      if (lastEmitted == null ||
          position.timestamp.difference(lastEmitted!) >= interval) {
        lastEmitted = position.timestamp;
        return true;
      }
      return false;
    });
  }
}
