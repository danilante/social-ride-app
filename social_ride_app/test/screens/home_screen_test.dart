import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/screens/home_screen.dart';
import 'package:social_ride_app/services/recent_ride_store.dart';
import 'package:social_ride_app/services/ride_repository.dart';

class _FakeRecentRideStore implements RecentRideStore {
  RecentRide? _ride;

  @override
  Future<void> save(RecentRide ride) async => _ride = ride;

  @override
  Future<RecentRide?> load() async => _ride;
}

void main() {
  testWidgets('creating a ride writes it to Firestore and calls onRideReady',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final repository =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    String? readyRideId;

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        rideRepository: repository,
        onRideReady: (rideId) => readyRideId = rideId,
        recentRideStore: _FakeRecentRideStore(),
      ),
    ));

    await tester.enterText(find.byKey(const Key('displayNameField')), 'Mario');
    await tester.enterText(find.byKey(const Key('rideNameField')), 'Giro');
    await tester.tap(find.byKey(const Key('createRideButton')));
    await tester.pumpAndSettle();

    expect(readyRideId, isNotNull);
    final rideDoc = await firestore.collection('rides').doc(readyRideId).get();
    expect(rideDoc.data()!['name'], 'Giro');
  });

  testWidgets('joining a ride calls onRideReady with the entered code',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final creatorRepo =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    final rideId = await creatorRepo.createRide('Giro', 'Mario');

    final joinerRepo =
        RideRepository(firestore: firestore, currentUserId: () => 'user2');
    String? readyRideId;

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        rideRepository: joinerRepo,
        onRideReady: (id) => readyRideId = id,
        recentRideStore: _FakeRecentRideStore(),
      ),
    ));

    await tester.enterText(find.byKey(const Key('displayNameField')), 'Luca');
    await tester.enterText(find.byKey(const Key('rideCodeField')), rideId);
    await tester.tap(find.byKey(const Key('joinRideButton')));
    await tester.pumpAndSettle();

    expect(readyRideId, rideId);
  });

  testWidgets('joining without a name is blocked and shows an error',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final creatorRepo =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    final rideId = await creatorRepo.createRide('Giro', 'Mario');

    final joinerRepo =
        RideRepository(firestore: firestore, currentUserId: () => 'user2');
    String? readyRideId;

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        rideRepository: joinerRepo,
        onRideReady: (id) => readyRideId = id,
        recentRideStore: _FakeRecentRideStore(),
      ),
    ));

    await tester.enterText(find.byKey(const Key('rideCodeField')), rideId);
    await tester.tap(find.byKey(const Key('joinRideButton')));
    await tester.pumpAndSettle();

    expect(readyRideId, isNull);
    expect(find.textContaining('nome'), findsWidgets);
  });

  testWidgets('creating without a name is blocked and shows an error',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final repository =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    String? readyRideId;

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        rideRepository: repository,
        onRideReady: (rideId) => readyRideId = rideId,
        recentRideStore: _FakeRecentRideStore(),
      ),
    ));

    await tester.enterText(find.byKey(const Key('rideNameField')), 'Giro');
    await tester.tap(find.byKey(const Key('createRideButton')));
    await tester.pumpAndSettle();

    expect(readyRideId, isNull);
    expect(find.textContaining('nome'), findsWidgets);
  });

  testWidgets('creating a ride saves it as the recent ride', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final repository =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    final store = _FakeRecentRideStore();
    String? readyRideId;

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        rideRepository: repository,
        onRideReady: (rideId) => readyRideId = rideId,
        recentRideStore: store,
      ),
    ));

    await tester.enterText(find.byKey(const Key('displayNameField')), 'Mario');
    await tester.enterText(find.byKey(const Key('rideNameField')), 'Giro');
    await tester.tap(find.byKey(const Key('createRideButton')));
    await tester.pumpAndSettle();

    final saved = await store.load();
    expect(saved?.rideId, readyRideId);
    expect(saved?.displayName, 'Mario');
  });

  testWidgets('shows a shortcut back into a recent ride and continuing skips the form',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final repository =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    final rideId = await repository.createRide('Giro', 'Mario');
    final store = _FakeRecentRideStore();
    await store.save(RecentRide(rideId: rideId, displayName: 'Mario'));
    String? readyRideId;

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        rideRepository: repository,
        onRideReady: (id) => readyRideId = id,
        recentRideStore: store,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recentRideCard')), findsOneWidget);

    await tester.tap(find.byKey(const Key('continueRecentRideButton')));
    await tester.pumpAndSettle();

    expect(readyRideId, rideId);
  });

  testWidgets('joining with a nonexistent ride code shows an error and stays on home',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final repository =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    String? readyRideId;

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        rideRepository: repository,
        onRideReady: (id) => readyRideId = id,
        recentRideStore: _FakeRecentRideStore(),
      ),
    ));

    await tester.enterText(find.byKey(const Key('displayNameField')), 'Mario');
    await tester.enterText(find.byKey(const Key('rideCodeField')), 'ZZZZZZ');
    await tester.tap(find.byKey(const Key('joinRideButton')));
    await tester.pumpAndSettle();

    expect(readyRideId, isNull);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('non trovat'), findsWidgets);
  });
}
