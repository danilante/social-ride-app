// Real end-to-end test of the live-location dropoff alert: runs against the
// actual Firebase emulators (Firestore + the real deployed Cloud Function),
// not fakes, on a real device/simulator. Requires:
//   firebase emulators:start --only firestore,auth,functions
// before `flutter test integration_test/dropoff_flow_test.dart -d <device>`.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:social_ride_app/firebase_options.dart';
import 'package:social_ride_app/screens/ride_screen.dart';
import 'package:social_ride_app/services/location_service.dart';
import 'package:social_ride_app/services/push_service.dart';
import 'package:social_ride_app/services/ride_repository.dart';

class _FakeTokenProvider implements PushTokenProvider {
  @override
  Future<void> requestPermission() async {}

  @override
  Future<String?> getToken() async => null;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxAttempts = 20,
}) async {
  for (var i = 0; i < maxAttempts; i++) {
    if (condition()) return;
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  });

  testWidgets(
      'a rider who drifts from the group gets flagged dropped_off by the '
      'real Cloud Function, and the viewer sees the alert', (tester) async {
    final cred = await FirebaseAuth.instance.signInAnonymously();
    final marioRepo = RideRepository(
      firestore: FirebaseFirestore.instance,
      currentUserId: () => cred.user!.uid,
    );
    final rideId = await marioRepo.createRide('Giro', 'Mario');
    await marioRepo.updateMyPosition(rideId, 0, 0);

    final lucaRepo = RideRepository(
      firestore: FirebaseFirestore.instance,
      currentUserId: () => 'integration-test-luca',
    );
    await lucaRepo.joinRide(rideId, 'Luca');

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: marioRepo,
        locationService:
            LocationService(checkPermission: () async => LocationPermission.denied),
        pushService: PushService(
          tokenProvider: _FakeTokenProvider(),
          rideRepository: marioRepo,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dropoffAlertBanner')), findsNothing);

    // Luca drifts far from Mario; thresholdExceededSince is seeded in the
    // past so the dwell window is already satisfied on this single write,
    // without the test needing to wait out the real 60s dwell time.
    await FirebaseFirestore.instance
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc('integration-test-luca')
        .set({
      'lat': 10.0,
      'lng': 10.0,
      'thresholdExceededSince':
          DateTime.now().millisecondsSinceEpoch - 61000,
    }, SetOptions(merge: true));

    await _pumpUntil(
      tester,
      () => find.byKey(const Key('dropoffAlertBanner')).evaluate().isNotEmpty,
    );

    final banner = find.byKey(const Key('dropoffAlertBanner'));
    expect(banner, findsOneWidget);
    expect(
      find.descendant(of: banner, matching: find.textContaining('Luca')),
      findsWidgets,
    );
    expect(
      find.descendant(of: banner, matching: find.textContaining('Mario')),
      findsNothing,
    );
  });

  testWidgets(
      'when the viewer themself is flagged dropped_off, they are not shown '
      'a self-referential alert', (tester) async {
    final cred = await FirebaseAuth.instance.signInAnonymously();
    final marioRepo = RideRepository(
      firestore: FirebaseFirestore.instance,
      currentUserId: () => cred.user!.uid,
    );
    final rideId = await marioRepo.createRide('Giro', 'Mario');

    final lucaRepo = RideRepository(
      firestore: FirebaseFirestore.instance,
      currentUserId: () => 'integration-test-luca-2',
    );
    await lucaRepo.joinRide(rideId, 'Luca');
    await lucaRepo.updateMyPosition(rideId, 0, 0);

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: marioRepo,
        locationService:
            LocationService(checkPermission: () async => LocationPermission.denied),
        pushService: PushService(
          tokenProvider: _FakeTokenProvider(),
          rideRepository: marioRepo,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Mario (the viewer) is the one who drifts away this time.
    await FirebaseFirestore.instance
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc(cred.user!.uid)
        .set({
      'lat': 10.0,
      'lng': 10.0,
      'thresholdExceededSince':
          DateTime.now().millisecondsSinceEpoch - 61000,
    }, SetOptions(merge: true));

    // Give the Cloud Function time to process and the client stream time to
    // reflect it; there is no banner to pump-until here since success means
    // it never appears, so we just wait out the window directly.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    final riderDoc = await FirebaseFirestore.instance
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc(cred.user!.uid)
        .get();
    expect(riderDoc.data()!['state'], 'dropped_off',
        reason: 'sanity check: the function did flag Mario as dropped_off');

    expect(find.byKey(const Key('dropoffAlertBanner')), findsNothing);
  });
}
