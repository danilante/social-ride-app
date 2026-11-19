import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/services/ride_repository.dart';

void main() {
  test('createRide creates a ride doc and adds the creator as a rider', () async {
    final firestore = FakeFirebaseFirestore();
    final repo = RideRepository(
      firestore: firestore,
      currentUserId: () => 'user1',
    );

    final rideId = await repo.createRide('Giro domenicale', 'Mario');

    final rideDoc = await firestore.collection('rides').doc(rideId).get();
    expect(rideDoc.data()!['name'], 'Giro domenicale');
    expect(rideDoc.data()!['creatorId'], 'user1');
    expect(rideDoc.data()!['status'], 'active');

    final riderDoc = await firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc('user1')
        .get();
    expect(riderDoc.data()!['displayName'], 'Mario');
    expect(riderDoc.data()!['state'], 'in_group');
  });

  test('joinRide adds a second rider to an existing ride', () async {
    final firestore = FakeFirebaseFirestore();
    final creatorRepo = RideRepository(
      firestore: firestore,
      currentUserId: () => 'user1',
    );
    final rideId = await creatorRepo.createRide('Giro', 'Mario');

    final joinerRepo = RideRepository(
      firestore: firestore,
      currentUserId: () => 'user2',
    );
    await joinerRepo.joinRide(rideId, 'Luca');

    final riderDoc = await firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc('user2')
        .get();
    expect(riderDoc.data()!['displayName'], 'Luca');
  });

  test('joinRide throws RideNotFoundException for unknown ride', () async {
    final firestore = FakeFirebaseFirestore();
    final repo = RideRepository(
      firestore: firestore,
      currentUserId: () => 'user1',
    );

    expect(
      () => repo.joinRide('does-not-exist', 'Mario'),
      throwsA(isA<RideNotFoundException>()),
    );
  });
}
