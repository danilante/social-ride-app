import 'package:battery_plus/battery_plus.dart';

/// Reads battery level for low-battery warnings during a ride.
/// Injectable so tests can supply a fixed level without platform channels.
class BatteryService {
  final Future<int?> Function() _readLevel;

  BatteryService({Future<int?> Function()? readLevel})
      : _readLevel = readLevel ?? _platformReadLevel;

  /// Returns battery percentage 0–100, or null if unavailable.
  Future<int?> getBatteryLevel() => _readLevel();

  /// True when level is known and strictly below [thresholdPercent].
  Future<bool> isBelow(int thresholdPercent) async {
    final level = await getBatteryLevel();
    if (level == null) return false;
    return level < thresholdPercent;
  }

  static Future<int?> _platformReadLevel() async {
    try {
      final level = await Battery().batteryLevel;
      return level;
    } catch (_) {
      return null;
    }
  }
}
