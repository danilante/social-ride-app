// test/models/ride_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/models/ride.dart';

void main() {
  test('Ride.fromMap parses known fields with defaults', () {
    final ride = Ride.fromMap('ride1', {
      'name': 'Giro domenicale',
      'creatorId': 'user1',
      'status': 'active',
      'dropoffThresholdMeters': 250,
    });

    expect(ride.id, 'ride1');
    expect(ride.name, 'Giro domenicale');
    expect(ride.creatorId, 'user1');
    expect(ride.status, 'active');
    expect(ride.dropoffThresholdMeters, 250);
  });

  test('Ride.fromMap defaults dropoffThresholdMeters to 300', () {
    final ride = Ride.fromMap('ride1', {'name': 'X', 'creatorId': 'u'});
    expect(ride.dropoffThresholdMeters, 300);
  });
}
