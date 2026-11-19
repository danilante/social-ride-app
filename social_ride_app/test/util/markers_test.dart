import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/models/rider_doc.dart';
import 'package:social_ride_app/util/markers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildMarkers skips riders without a position', () {
    final riders = [
      RiderDoc(userId: 'u1', displayName: 'Mario'),
      RiderDoc(userId: 'u2', displayName: 'Luca', lat: 45.0, lng: 7.0),
    ];

    final markers = buildMarkers(riders);

    expect(markers.length, 1);
    expect(markers.first.markerId.value, 'u2');
  });

  test('buildMarkers marks dropped_off riders distinctly', () {
    final riders = [
      RiderDoc(
        userId: 'u1',
        displayName: 'Mario',
        lat: 45.0,
        lng: 7.0,
        state: RiderState.droppedOff,
        distanceFromGroupMeters: 350,
      ),
    ];

    final markers = buildMarkers(riders);

    expect(markers.length, 1);
    expect(markers.first.infoWindow.snippet, contains('350'));
  });
}
