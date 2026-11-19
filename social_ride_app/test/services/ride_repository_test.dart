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

  test('createRide uses a short, easy to type/share ride code', () async {
    final firestore = FakeFirebaseFirestore();
    final repo = RideRepository(
      firestore: firestore,
      currentUserId: () => 'user1',
    );

    final rideId = await repo.createRide('Giro', 'Mario');

    expect(rideId.length, 6);
    expect(rideId, equals(rideId.toUpperCase()));
    expect(RegExp(r'^[A-Z0-9]{6}$').hasMatch(rideId), isTrue);
  });

  test('createRide retries with a new code when one is already taken',
      () async {
    final firestore = FakeFirebaseFirestore();
    var calls = 0;
    final repo = RideRepository(
      firestore: firestore,
      currentUserId: () => 'user1',
      codeGenerator: () {
        calls++;
        return calls == 1 ? 'ABC123' : 'XYZ999';
      },
    );
    await firestore.collection('rides').doc('ABC123').set({'name': 'Taken'});

    final rideId = await repo.createRide('Giro', 'Mario');

    expect(rideId, 'XYZ999');

    final takenDoc = await firestore.collection('rides').doc('ABC123').get();
    expect(takenDoc.data()!['name'], 'Taken');
  });

  test(
      'createRide does not clobber a ride another client just claimed with '
      'the same generated code', () async {
    final firestore = FakeFirebaseFirestore();
    var calls = 0;
    final repo = RideRepository(
      firestore: firestore,
      currentUserId: () => 'user1',
      codeGenerator: () {
        calls++;
        if (calls == 1) {
          // Simulate another client claiming this code just before this
          // client's own create transaction runs.
          firestore
              .collection('rides')
              .doc('ABC123')
              .set({'name': 'ClaimedByOtherClient', 'creatorId': 'user2'});
          return 'ABC123';
        }
        return 'XYZ999';
      },
    );

    final rideId = await repo.createRide('Giro', 'Mario');

    expect(rideId, 'XYZ999');
    final claimedDoc = await firestore.collection('rides').doc('ABC123').get();
    expect(claimedDoc.data()!['name'], 'ClaimedByOtherClient');
    expect(claimedDoc.data()!['creatorId'], 'user2');
  });

  test('joinRide accepts a ride code regardless of letter case', () async {
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
    await joinerRepo.joinRide(rideId.toLowerCase(), 'Luca');

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
