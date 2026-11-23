import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:social_ride_app/app.dart';
import 'package:social_ride_app/services/location_service.dart';
import 'package:social_ride_app/services/push_service.dart';
import 'package:social_ride_app/services/recent_ride_store.dart';
import 'package:social_ride_app/services/ride_repository.dart';

class _FakeTokenProvider implements PushTokenProvider {
  @override
  Future<void> requestPermission() async {}

  @override
  Future<String?> getToken() async => null;
}

class _FakeRecentRideStore implements RecentRideStore {
  RecentRide? _ride;

  @override
  Future<void> save(RecentRide ride) async => _ride = ride;

  @override
  Future<RecentRide?> load() async => _ride;
}

void main() {
  testWidgets('creating a ride opens the ride screen with a working back button',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final repository =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');

    await tester.pumpWidget(SocialRideApp(
      rideRepository: repository,
      locationServiceFactory: () =>
          LocationService(checkPermission: () async => LocationPermission.denied),
      pushServiceFactory: (rideRepository) => PushService(
        tokenProvider: _FakeTokenProvider(),
        rideRepository: rideRepository,
      ),
      recentRideStore: _FakeRecentRideStore(),
    ));

    await tester.enterText(find.byKey(const Key('displayNameField')), 'Mario');
    await tester.enterText(find.byKey(const Key('rideNameField')), 'Giro');
    await tester.tap(find.byKey(const Key('createRideButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('displayNameField')), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('displayNameField')), findsOneWidget);
  });
}
