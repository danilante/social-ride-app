import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/services/battery_service.dart';

void main() {
  test('isBelow returns true when level is under threshold', () async {
    final service = BatteryService(readLevel: () async => 15);
    expect(await service.isBelow(20), isTrue);
  });

  test('isBelow returns false when level is at or above threshold', () async {
    final service = BatteryService(readLevel: () async => 20);
    expect(await service.isBelow(20), isFalse);
    expect(await service.isBelow(15), isFalse);
  });

  test('isBelow returns false when level is unavailable', () async {
    final service = BatteryService(readLevel: () async => null);
    expect(await service.isBelow(20), isFalse);
  });

  test('getBatteryLevel returns injected value', () async {
    final service = BatteryService(readLevel: () async => 42);
    expect(await service.getBatteryLevel(), 42);
  });
}
