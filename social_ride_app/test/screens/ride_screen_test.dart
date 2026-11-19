import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
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

void main() {
  late FakeFirebaseFirestore firestore;
  late RideRepository repository;
  late PushService pushService;
  late String rideId;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repository =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    pushService = PushService(
      tokenProvider: _FakeTokenProvider(),
      rideRepository: repository,
    );
    rideId = await repository.createRide('Giro', 'Mario');
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
      ),
    ));

    await tester.tap(find.byKey(const Key('startRideButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('retryLocationButton')), findsOneWidget);
    expect(find.textContaining('negato'), findsOneWidget);
  });
}
