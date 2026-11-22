// Real end-to-end check of the create/join UI flows against the actual
// Firebase emulators. Requires:
//   firebase emulators:start --only firestore,auth,functions
// On a physical device (not Simulator), the emulators must also bind to
// 0.0.0.0 (see firebase.json) and 'localhost' below must be replaced with
// the Mac's LAN IP, since the phone can't reach the Mac's loopback address.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:social_ride_app/app.dart';
import 'package:social_ride_app/firebase_options.dart';
import 'package:social_ride_app/services/location_service.dart';
import 'package:social_ride_app/services/push_service.dart';
import 'package:social_ride_app/services/ride_repository.dart';

class _FakeTokenProvider implements PushTokenProvider {
  @override
  Future<void> requestPermission() async {}
  @override
  Future<String?> getToken() async => null;
}

Widget _appFor(RideRepository repo) => SocialRideApp(
      rideRepository: repo,
      locationServiceFactory: () =>
          LocationService(checkPermission: () async => LocationPermission.denied),
      pushServiceFactory: (r) =>
          PushService(tokenProvider: _FakeTokenProvider(), rideRepository: r),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  });

  testWidgets('creating a ride through the UI opens the ride screen with a real code',
      (tester) async {
    final cred = await FirebaseAuth.instance.signInAnonymously();
    final repo = RideRepository(
      firestore: FirebaseFirestore.instance,
      currentUserId: () => cred.user!.uid,
    );

    await tester.pumpWidget(_appFor(repo));
    await tester.enterText(find.byKey(const Key('displayNameField')), 'Mario');
    await tester.enterText(find.byKey(const Key('rideNameField')), 'Giro reale');
    await tester.tap(find.byKey(const Key('createRideButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rideCodeText')), findsOneWidget);
    final codeWidget =
        tester.widget<Text>(find.byKey(const Key('rideCodeText')));
    expect(codeWidget.data, matches(RegExp(r'^[A-Z0-9]{6}$')));
    expect(find.text('Mario'), findsOneWidget);
  });

  testWidgets(
      'a second user joining through the UI with the real code sees both riders',
      (tester) async {
    final marioCred = await FirebaseAuth.instance.signInAnonymously();
    final marioRepo = RideRepository(
      firestore: FirebaseFirestore.instance,
      currentUserId: () => marioCred.user!.uid,
    );
    final rideId = await marioRepo.createRide('Giro reale', 'Mario');

    await FirebaseAuth.instance.signOut();
    final lucaCred = await FirebaseAuth.instance.signInAnonymously();
    final lucaRepo = RideRepository(
      firestore: FirebaseFirestore.instance,
      currentUserId: () => lucaCred.user!.uid,
    );

    await tester.pumpWidget(_appFor(lucaRepo));
    await tester.enterText(find.byKey(const Key('displayNameField')), 'Luca');
    await tester.enterText(find.byKey(const Key('rideCodeField')), rideId);
    await tester.tap(find.byKey(const Key('joinRideButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rideCodeText')), findsOneWidget);
    expect(find.text('Mario'), findsOneWidget);
    expect(find.text('Luca'), findsOneWidget);
  });

  testWidgets('joining with a code that does not exist stays on the home '
      'screen and shows an error', (tester) async {
    final cred = await FirebaseAuth.instance.signInAnonymously();
    final repo = RideRepository(
      firestore: FirebaseFirestore.instance,
      currentUserId: () => cred.user!.uid,
    );

    await tester.pumpWidget(_appFor(repo));
    await tester.enterText(find.byKey(const Key('displayNameField')), 'Luca');
    await tester.enterText(find.byKey(const Key('rideCodeField')), 'ZZZZZZ');
    await tester.tap(find.byKey(const Key('joinRideButton')));
    await tester.pumpAndSettle();

    // Still on the home screen, with an error shown via SnackBar.
    expect(find.byKey(const Key('rideCodeField')), findsOneWidget);
    expect(find.byKey(const Key('rideCodeText')), findsNothing);
    expect(find.textContaining('non trovat'), findsWidgets);
  });
}
