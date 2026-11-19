import 'package:geolocator/geolocator.dart';

class LocationService {
  final Stream<Position> Function() positionStreamFactory;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;

  LocationService({
    Stream<Position> Function()? positionStreamFactory,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
  })  : positionStreamFactory =
            positionStreamFactory ?? Geolocator.getPositionStream,
        _checkPermission = checkPermission ?? Geolocator.checkPermission,
        _requestPermission = requestPermission ?? Geolocator.requestPermission;

  Future<bool> ensurePermission() async {
    LocationPermission permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
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
