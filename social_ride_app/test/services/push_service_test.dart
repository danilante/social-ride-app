import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/services/push_service.dart';
import 'package:social_ride_app/services/ride_repository.dart';

class FakeTokenProvider implements PushTokenProvider {
  bool permissionRequested = false;
  final String? tokenToReturn;

  FakeTokenProvider(this.tokenToReturn);

  @override
  Future<void> requestPermission() async {
    permissionRequested = true;
  }

  @override
  Future<String?> getToken() async => tokenToReturn;
}

void main() {
  test('registerForRide requests permission and stores the token', () async {
    final firestore = FakeFirebaseFirestore();
    final repository =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    final tokenProvider = FakeTokenProvider('token-123');
    final pushService =
        PushService(tokenProvider: tokenProvider, rideRepository: repository);

    await repository.createRide('Giro', 'Mario');
    final rideId = (await firestore.collection('rides').get()).docs.first.id;

    await pushService.registerForRide(rideId);

    expect(tokenProvider.permissionRequested, isTrue);
    final riderDoc = await firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc('user1')
        .get();
    expect(riderDoc.data()!['fcmToken'], 'token-123');
  });

  test('registerForRide does nothing when token is null', () async {
    final firestore = FakeFirebaseFirestore();
    final repository =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    final tokenProvider = FakeTokenProvider(null);
    final pushService =
        PushService(tokenProvider: tokenProvider, rideRepository: repository);

    final rideId = await repository.createRide('Giro', 'Mario');
    await pushService.registerForRide(rideId);

    final riderDoc = await firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc('user1')
        .get();
    expect(riderDoc.data()!.containsKey('fcmToken'), isFalse);
  });
}
