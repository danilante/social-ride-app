// test/models/rider_doc_test.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/models/rider_doc.dart';

void main() {
  test('RiderDoc.fromMap parses position and state', () {
    final rider = RiderDoc.fromMap('user1', {
      'displayName': 'Mario',
      'lat': 45.07,
      'lng': 7.68,
      'positionUpdatedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
      'state': 'dropped_off',
      'distanceFromGroupMeters': 350.5,
    });

    expect(rider.userId, 'user1');
    expect(rider.displayName, 'Mario');
    expect(rider.lat, 45.07);
    expect(rider.lng, 7.68);
    expect(rider.positionUpdatedAt, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(rider.state, RiderState.droppedOff);
    expect(rider.distanceFromGroupMeters, 350.5);
  });

  test('RiderDoc.fromMap defaults state to inGroup when missing', () {
    final rider = RiderDoc.fromMap('user1', {'displayName': 'Mario'});
    expect(rider.state, RiderState.inGroup);
    expect(rider.lat, isNull);
    expect(rider.positionUpdatedAt, isNull);
  });

  test('RiderDoc.fromMap parses dropoffAudioUrl when present', () {
    final rider = RiderDoc.fromMap('user1', {
      'displayName': 'Mario',
      'dropoffAudioUrl': 'https://example.com/audio.m4a',
    });
    expect(rider.dropoffAudioUrl, 'https://example.com/audio.m4a');
  });

  test('RiderDoc.fromMap defaults dropoffAudioUrl to null when missing', () {
    final rider = RiderDoc.fromMap('user1', {'displayName': 'Mario'});
    expect(rider.dropoffAudioUrl, isNull);
  });
}
