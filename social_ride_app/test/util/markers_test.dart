import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/models/rider_doc.dart';
import 'package:social_ride_app/models/track_point.dart';
import 'package:social_ride_app/util/markers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildTrackPolyline returns empty set for fewer than 2 points', () {
    expect(buildTrackPolyline([]), isEmpty);
    expect(buildTrackPolyline([TrackPoint(lat: 1, lng: 1)]), isEmpty);
  });

  test('buildTrackPolyline caps to kMaxTrackPolylinePoints', () {
    final points = List.generate(
      kMaxTrackPolylinePoints + 50,
      (i) => TrackPoint(lat: 45.0 + i * 0.0001, lng: 7.0),
    );
    final polylines = buildTrackPolyline(points);
    expect(polylines.length, 1);
    expect(polylines.first.points.length, kMaxTrackPolylinePoints);
  });

  test('buildTrackPolyline builds a single red polyline through all points',
      () {
    final points = [
      TrackPoint(lat: 1, lng: 1),
      TrackPoint(lat: 2, lng: 2),
      TrackPoint(lat: 3, lng: 3),
    ];

    final polylines = buildTrackPolyline(points);

    expect(polylines, hasLength(1));
    final polyline = polylines.first;
    expect(polyline.color, Colors.redAccent);
    expect(polyline.points.map((p) => p.latitude), [1, 2, 3]);
  });

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
