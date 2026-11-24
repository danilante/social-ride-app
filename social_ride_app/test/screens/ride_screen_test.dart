import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:social_ride_app/screens/ride_screen.dart';
import 'package:social_ride_app/services/dropoff_alert_speaker.dart';
import 'package:social_ride_app/services/location_service.dart';
import 'package:social_ride_app/services/push_service.dart';
import 'package:social_ride_app/services/ride_repository.dart';

class _FakeTokenProvider implements PushTokenProvider {
  @override
  Future<void> requestPermission() async {}

  @override
  Future<String?> getToken() async => null;
}

class _FakeDropoffAlertSpeaker implements DropoffAlertSpeaker {
  final List<String> spoken = [];

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }
}

void main() {
  late FakeFirebaseFirestore firestore;
  late RideRepository repository;
  late PushService pushService;
  late String rideId;
  late _FakeDropoffAlertSpeaker alertSpeaker;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repository =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    pushService = PushService(
      tokenProvider: _FakeTokenProvider(),
      rideRepository: repository,
    );
    rideId = await repository.createRide('Giro', 'Mario');
    alertSpeaker = _FakeDropoffAlertSpeaker();
  });

  testWidgets('shows how many riders are in the ride and updates live',
      (tester) async {
    final locationService =
        LocationService(checkPermission: () async => LocationPermission.denied);

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: repository,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('1'), findsWidgets);
    expect(find.text('Mario'), findsOneWidget);

    final joinerRepo =
        RideRepository(firestore: firestore, currentUserId: () => 'user2');
    await joinerRepo.joinRide(rideId, 'Luca');
    await tester.pumpAndSettle();

    expect(find.text('Luca'), findsOneWidget);
    expect(find.textContaining('2'), findsWidgets);
  });

  testWidgets('shows a banner when a rider drops off, hides it when back',
      (tester) async {
    final locationService =
        LocationService(checkPermission: () async => LocationPermission.denied);

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: repository,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dropoffAlertBanner')), findsNothing);

    await firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc('user2')
        .set({
      'displayName': 'Luca',
      'state': 'dropped_off',
      'distanceFromGroupMeters': 350.0,
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dropoffAlertBanner')), findsOneWidget);
    expect(find.textContaining('Luca'), findsWidgets);
    expect(find.textContaining('350'), findsWidgets);
    expect(alertSpeaker.spoken, ['Il rider Luca si è staccato dal gruppo.']);

    await firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc('user2')
        .set({
      'displayName': 'Luca',
      'state': 'in_group',
    }, SetOptions(merge: true));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dropoffAlertBanner')), findsNothing);
  });

  testWidgets('ride creator can open settings and save a custom dropoff threshold',
      (tester) async {
    final locationService =
        LocationService(checkPermission: () async => LocationPermission.denied);

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: repository,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rideSettingsButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('rideSettingsButton')));
    await tester.pumpAndSettle();

    final slider =
        tester.widget<Slider>(find.byKey(const Key('dropoffThresholdSlider')));
    slider.onChanged!(150);
    await tester.pump();

    await tester.tap(find.byKey(const Key('saveRideSettingsButton')));
    await tester.pumpAndSettle();

    final rideDoc = await firestore.collection('rides').doc(rideId).get();
    expect(rideDoc.data()!['dropoffThresholdMeters'], lessThan(300));
  });

  testWidgets('a non-creator does not see the ride settings button',
      (tester) async {
    final joinerRepo =
        RideRepository(firestore: firestore, currentUserId: () => 'user2');
    await joinerRepo.joinRide(rideId, 'Luca');
    final locationService =
        LocationService(checkPermission: () async => LocationPermission.denied);

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: joinerRepo,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rideSettingsButton')), findsNothing);
  });

  testWidgets(
      'the record sheet tells the rider what default message plays if they skip recording',
      (tester) async {
    final locationService =
        LocationService(checkPermission: () async => LocationPermission.denied);

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: repository,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dropoffAudioCard')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defaultAudioNotice')), findsOneWidget);
    expect(
        find.textContaining('Il rider Mario si è staccato dal gruppo'),
        findsOneWidget);
  });

  testWidgets('copy button puts the ride code on the clipboard',
      (tester) async {
    final locationService =
        LocationService(checkPermission: () async => LocationPermission.denied);
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: repository,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));

    await tester.tap(find.byKey(const Key('copyRideCodeButton')));
    await tester.pumpAndSettle();

    expect(copiedText, rideId);
  });

  testWidgets('shows the ride code so it can be shared', (tester) async {
    final locationService =
        LocationService(checkPermission: () async => LocationPermission.denied);

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: repository,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));

    expect(find.textContaining(rideId), findsOneWidget);
  });

  testWidgets('tapping start shares position once permission is granted',
      (tester) async {
    final locationService = LocationService(
      checkPermission: () async => LocationPermission.whileInUse,
      positionStreamFactory: () => const Stream.empty(),
    );

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: repository,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));

    expect(find.byKey(const Key('startRideButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('startRideButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('startRideButton')), findsNothing);
    expect(find.text('Condivisione posizione attiva'), findsOneWidget);
  });

  testWidgets('shows a retry option when location permission is denied',
      (tester) async {
    final locationService =
        LocationService(checkPermission: () async => LocationPermission.deniedForever);

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: repository,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));

    await tester.tap(find.byKey(const Key('startRideButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('retryLocationButton')), findsOneWidget);
    expect(find.textContaining('negato'), findsOneWidget);
  });

  testWidgets('creator sees end-ride button and ending it sets status ended',
      (tester) async {
    final locationService =
        LocationService(checkPermission: () async => LocationPermission.denied);

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: repository,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

    await tester.tap(find.byKey(const Key('endOrLeaveRideButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Termina'));
    await tester.pumpAndSettle();

    final rideDoc = await firestore.collection('rides').doc(rideId).get();
    expect(rideDoc.data()!['status'], 'ended');
    expect(find.textContaining('terminata dal creatore'), findsOneWidget);
  });

  testWidgets('non-creator sees leave-ride button and leaving removes their rider doc',
      (tester) async {
    final joinerRepo =
        RideRepository(firestore: firestore, currentUserId: () => 'user2');
    await joinerRepo.joinRide(rideId, 'Luca');
    final locationService =
        LocationService(checkPermission: () async => LocationPermission.denied);

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: joinerRepo,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.logout_rounded), findsOneWidget);

    await tester.tap(find.byKey(const Key('endOrLeaveRideButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esci'));
    await tester.pumpAndSettle();

    final riderDoc = await firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc('user2')
        .get();
    expect(riderDoc.exists, isFalse);
    expect(find.textContaining('Sei uscito dalla ride'), findsOneWidget);
  });

  testWidgets(
      'a rider still viewing the ride gets kicked back when the creator ends it',
      (tester) async {
    final joinerRepo =
        RideRepository(firestore: firestore, currentUserId: () => 'user2');
    await joinerRepo.joinRide(rideId, 'Luca');
    final locationService =
        LocationService(checkPermission: () async => LocationPermission.denied);

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: joinerRepo,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));
    await tester.pumpAndSettle();

    await repository.endRide(rideId);
    await tester.pumpAndSettle();

    expect(find.textContaining('terminata dal creatore'), findsOneWidget);
  });

  testWidgets('requests current position on load to center the map',
      (tester) async {
    var requested = false;
    final locationService = LocationService(
      checkPermission: () async => LocationPermission.whileInUse,
      getCurrentPositionFn: () async {
        requested = true;
        return Position(
          latitude: 41.9,
          longitude: 12.5,
          timestamp: DateTime.now(),
          accuracy: 1,
          altitude: 0,
          altitudeAccuracy: 1,
          heading: 0,
          headingAccuracy: 1,
          speed: 0,
          speedAccuracy: 0,
        );
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: repository,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));
    await tester.pump();

    expect(requested, isTrue);
  });

  testWidgets('sharing status indicator uses a large, glance-readable icon',
      (tester) async {
    final locationService =
        LocationService(checkPermission: () async => LocationPermission.whileInUse);

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: repository,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startRideButton')));
    await tester.pumpAndSettle();

    final icon = tester.widget<Icon>(find.byIcon(Icons.location_on_rounded));
    expect(icon.size, greaterThanOrEqualTo(24));
  });

  testWidgets('tapping a rider chip centers the map on that rider',
      (tester) async {
    await repository.updateMyPosition(rideId, 46.0, 8.0);
    final locationService =
        LocationService(checkPermission: () async => LocationPermission.denied);

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: repository,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('riderChip_user1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('riderChip_user1')));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'dropoff banner has a button to center the map on the dropped rider',
      (tester) async {
    await repository.updateMyPosition(rideId, 46.0, 8.0);
    await firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc('user1')
        .update({'state': 'dropped_off'});
    final locationService =
        LocationService(checkPermission: () async => LocationPermission.denied);

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: RideRepository(
            firestore: firestore, currentUserId: () => 'user2'),
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('centerOnDroppedRider_user1')), findsOneWidget);
  });

  testWidgets('shows the ride name in the app bar instead of a generic title',
      (tester) async {
    final locationService =
        LocationService(checkPermission: () async => LocationPermission.denied);

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: repository,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Giro'), findsOneWidget);
  });

  testWidgets(
      'dropoff audio card is a single compact row, not a full explainer block',
      (tester) async {
    final locationService =
        LocationService(checkPermission: () async => LocationPermission.denied);

    await tester.pumpWidget(MaterialApp(
      home: RideScreen(
        rideId: rideId,
        rideRepository: repository,
        locationService: locationService,
        pushService: pushService,
        alertSpeaker: alertSpeaker,
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.text(
          'Verrà riprodotto sul telefono degli altri quando ti stacchi dal gruppo'),
      findsNothing,
    );
    expect(find.byKey(const Key('dropoffAudioCard')), findsOneWidget);
  });
}
