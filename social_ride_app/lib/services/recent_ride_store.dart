import 'package:shared_preferences/shared_preferences.dart';

/// The last ride the user created or joined, so the home screen can offer a
/// shortcut back into it after they navigate back without having to retype
/// the ride code.
class RecentRide {
  final String rideId;
  final String displayName;

  const RecentRide({required this.rideId, required this.displayName});
}

abstract class RecentRideStore {
  Future<void> save(RecentRide ride);
  Future<RecentRide?> load();
}

class SharedPreferencesRecentRideStore implements RecentRideStore {
  static const _rideIdKey = 'recent_ride_id';
  static const _displayNameKey = 'recent_ride_display_name';

  @override
  Future<void> save(RecentRide ride) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rideIdKey, ride.rideId);
    await prefs.setString(_displayNameKey, ride.displayName);
  }

  @override
  Future<RecentRide?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rideId = prefs.getString(_rideIdKey);
    final displayName = prefs.getString(_displayNameKey);
    if (rideId == null || displayName == null) return null;
    return RecentRide(rideId: rideId, displayName: displayName);
  }
}
