import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:social_ride_app/app.dart';
import 'package:social_ride_app/services/audio_alert_session.dart';
import 'package:social_ride_app/services/location_service.dart';
import 'package:social_ride_app/services/push_service.dart';
import 'package:social_ride_app/services/recent_ride_store.dart';
import 'package:social_ride_app/services/ride_repository.dart';
import 'package:social_ride_app/services/volume_notice_store.dart';

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

  @override
  Future<void> clear() async => _ride = null;
}

class _FakeAudioAlertSession implements AudioAlertSession {
  bool configured = false;

  @override
  Future<void> configureForAlerts() async => configured = true;
}

class _FakeVolumeNoticeStore implements VolumeNoticeStore {
  bool seen;
  _FakeVolumeNoticeStore({this.seen = true});

  @override
  Future<bool> hasSeenNotice() async => seen;

  @override
  Future<void> markNoticeSeen() async => seen = true;
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
      audioAlertSession: _FakeAudioAlertSession(),
      volumeNoticeStore: _FakeVolumeNoticeStore(),
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

  testWidgets('shows the silent-mode alert notice once, on first launch',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final repository =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    final audioAlertSession = _FakeAudioAlertSession();
    final volumeNoticeStore = _FakeVolumeNoticeStore(seen: false);

    await tester.pumpWidget(SocialRideApp(
      rideRepository: repository,
      locationServiceFactory: () =>
          LocationService(checkPermission: () async => LocationPermission.denied),
      pushServiceFactory: (rideRepository) => PushService(
        tokenProvider: _FakeTokenProvider(),
        rideRepository: rideRepository,
      ),
      recentRideStore: _FakeRecentRideStore(),
      audioAlertSession: audioAlertSession,
      volumeNoticeStore: volumeNoticeStore,
    ));
    await tester.pumpAndSettle();

    expect(audioAlertSession.configured, isTrue);
    expect(find.byKey(const Key('volumeNoticeDialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('volumeNoticeAcceptButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('volumeNoticeDialog')), findsNothing);
    expect(await volumeNoticeStore.hasSeenNotice(), isTrue);
  });
}
