import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the user has already been told that drop-off alerts can
/// play even with the phone silenced, so the notice is shown only once.
abstract class VolumeNoticeStore {
  Future<bool> hasSeenNotice();
  Future<void> markNoticeSeen();
}

class SharedPreferencesVolumeNoticeStore implements VolumeNoticeStore {
  static const _key = 'has_seen_volume_notice';

  @override
  Future<bool> hasSeenNotice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  @override
  Future<void> markNoticeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
