import 'package:geolocator/geolocator.dart';

class LocationService {
  final Stream<Position> Function() positionStreamFactory;

  LocationService({Stream<Position> Function()? positionStreamFactory})
      : positionStreamFactory =
            positionStreamFactory ?? Geolocator.getPositionStream;

  Future<bool> ensurePermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
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
