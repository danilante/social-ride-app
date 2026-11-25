import 'package:geolocator/geolocator.dart';

/// Builds platform [LocationSettings] that keep GPS alive while the app is
/// backgrounded (phone in jersey pocket).
///
/// On Android this attaches a persistent foreground-service notification via
/// Geolocator's [ForegroundNotificationConfig]. On other platforms it uses
/// high-accuracy defaults.
class RideForegroundService {
  /// Settings used by the live position stream during an active ride.
  static LocationSettings trackingSettings({
    String rideCode = '',
  }) {
    final title = 'Social Ride attiva';
    final text = rideCode.isEmpty
        ? 'Condivisione posizione con il gruppo'
        : 'Condivisione posizione — codice $rideCode';

    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      forceLocationManager: false,
      intervalDuration: const Duration(seconds: 5),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: title,
        notificationText: text,
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }

  /// Fallback for non-Android (iOS uses Info.plist background modes).
  static LocationSettings appleSettings() {
    return AppleSettings(
      accuracy: LocationAccuracy.high,
      activityType: ActivityType.fitness,
      distanceFilter: 10,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
    );
  }
}
