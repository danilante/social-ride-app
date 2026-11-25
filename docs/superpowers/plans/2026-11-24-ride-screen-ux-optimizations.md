# Ride/Home Screen UX Optimizations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the UX/UI improvements identified in the functional analysis of `HomeScreen` and `RideScreen`, excluding "auto-start location sharing" and "dropoff threshold presets" (explicitly out of scope per user request).

**Architecture:** Each improvement is a small, independent change to `home_screen.dart`, `ride_screen.dart`, `recent_ride_store.dart` (read-only, already supports what's needed), `markers.dart`, and `location_service.dart`. No new services are introduced except a single-shot "get current position" method on `LocationService`. Changes are additive/surgical — no redesign of existing flows.

**Tech Stack:** Flutter (Material 3), `google_maps_flutter`, `geolocator`, `shared_preferences`, `flutter_test`.

**Spec:** This plan's spec is the UX analysis delivered in-conversation (no separate spec file). Point numbers below map to that analysis, points 2 ("Avvia ride" auto-start) and 3 (dropoff threshold presets) excluded by explicit user instruction.

## Global Constraints

- All user-facing strings stay in Italian, matching existing copy style in both screens.
- No new third-party dependencies.
- Preserve all existing `Key(...)` widget keys used by current tests; add new keys only for new interactive widgets.
- Each task must leave `flutter test` green before moving to the next task.

---

### Task 1: Single-shot current position + map initial camera (Point 10)

**Files:**
- Modify: `lib/services/location_service.dart`
- Test: `test/services/location_service_test.dart`
- Modify: `lib/screens/ride_screen.dart:919-1028` (build method, GoogleMap widget)
- Test: `test/screens/ride_screen_test.dart`

**Interfaces:**
- Produces: `LocationService.getCurrentPosition() -> Future<Position?>` (returns `null` if permission not granted or lookup fails)
- Consumes (Task 1 only): `widget.locationService.ensurePermission()` (existing), `widget.locationService.getCurrentPosition()` (new)

- [ ] **Step 1: Write failing test for `getCurrentPosition`**

```dart
// test/services/location_service_test.dart (add to existing file)
test('getCurrentPosition returns null when permission denied', () async {
  final service = LocationService(
    checkPermission: () async => LocationPermission.denied,
    requestPermission: () async => LocationPermission.denied,
  );
  final position = await service.getCurrentPosition();
  expect(position, isNull);
});

test('getCurrentPosition returns a position when permission granted', () async {
  final fakePosition = Position(
    latitude: 45.07,
    longitude: 7.68,
    timestamp: DateTime.now(),
    accuracy: 1,
    altitude: 0,
    altitudeAccuracy: 1,
    heading: 0,
    headingAccuracy: 1,
    speed: 0,
    speedAccuracy: 0,
  );
  final service = LocationService(
    checkPermission: () async => LocationPermission.whileInUse,
    getCurrentPositionFn: () async => fakePosition,
  );
  final position = await service.getCurrentPosition();
  expect(position, fakePosition);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/location_service_test.dart`
Expected: FAIL — `getCurrentPositionFn` named parameter and `getCurrentPosition()` method don't exist yet.

- [ ] **Step 3: Implement `getCurrentPosition`**

```dart
// lib/services/location_service.dart
import 'package:geolocator/geolocator.dart';

class LocationService {
  final Stream<Position> Function() positionStreamFactory;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final Future<Position> Function() _getCurrentPosition;

  LocationService({
    Stream<Position> Function()? positionStreamFactory,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<Position> Function()? getCurrentPositionFn,
  })  : positionStreamFactory =
            positionStreamFactory ?? Geolocator.getPositionStream,
        _checkPermission = checkPermission ?? Geolocator.checkPermission,
        _requestPermission = requestPermission ?? Geolocator.requestPermission,
        _getCurrentPosition = getCurrentPositionFn ?? Geolocator.getCurrentPosition;

  Future<bool> ensurePermission() async {
    LocationPermission permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Best-effort current position for centering the map on open. Returns
  /// null (never throws) so a missing permission or a platform lookup
  /// failure just falls back to the map's default camera.
  Future<Position?> getCurrentPosition() async {
    final permission = await _checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return null;
    }
    try {
      return await _getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  Stream<Position> throttledPositionStream(
      {Duration interval = const Duration(seconds: 10)}) {
    DateTime? lastEmitted;
    return positionStreamFactory().where((position) {
      if (lastEmitted == null ||
          position.timestamp.difference(lastEmitted!) >= interval) {
        lastEmitted = position.timestamp;
        return true;
      }
      return false;
    });
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/location_service_test.dart`
Expected: PASS

- [ ] **Step 5: Use it in `RideScreen` to pick the initial camera position**

Add state in `_RideScreenState`:

```dart
LatLng? _initialCameraTarget; // null until resolved, falls back to default
```

In `initState`, after the existing `pushService.registerForRide` call:

```dart
widget.locationService.getCurrentPosition().then((position) {
  if (!mounted || position == null) return;
  setState(() {
    _initialCameraTarget = LatLng(position.latitude, position.longitude);
  });
});
```

In `build`, replace the hardcoded `GoogleMap`'s `initialCameraPosition`:

```dart
GoogleMap(
  initialCameraPosition: CameraPosition(
    target: _initialCameraTarget ?? const LatLng(45.0703, 7.6869),
    zoom: 14,
  ),
  ...
)
```

Note: `GoogleMap.initialCameraPosition` is only read once at creation. Because `_initialCameraTarget` is usually resolved within the first frame (before the `GoogleMap` widget is actually mounted on most devices), this is good enough without needing `GoogleMapController.animateCamera` for this task — Task 3/4 below introduce the controller for rider-centering, and at that point this task's camera can be set via the controller instead if testing shows the race is real.

- [ ] **Step 6: Add widget test asserting the service is queried on load**

```dart
// test/screens/ride_screen_test.dart (add to existing file)
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
```

- [ ] **Step 7: Run full test suite**

Run: `flutter test`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add lib/services/location_service.dart test/services/location_service_test.dart lib/screens/ride_screen.dart test/screens/ride_screen_test.dart
git commit -m "feat: center ride map on user's current position instead of a hardcoded city"
```

---

### Task 2: Larger, more legible location-status indicator (Point 9)

**Files:**
- Modify: `lib/screens/ride_screen.dart:644-687` (`_buildLocationControl`, `sharing`/`denied` cases)
- Test: `test/screens/ride_screen_test.dart`

**Interfaces:**
- Consumes: existing `_status` enum (`_LocationStatus`), no signature changes.

- [ ] **Step 1: Write failing test for icon size**

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/ride_screen_test.dart`
Expected: FAIL — current icon size is 18.

- [ ] **Step 3: Enlarge the sharing/denied indicator (icon + text)**

Replace the `sharing` case body:

```dart
case _LocationStatus.sharing:
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFE8F6EC),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on_rounded, color: Color(0xFF2E9E53), size: 24),
        SizedBox(width: 8),
        Text(
          'Condivisione posizione attiva',
          style: TextStyle(
            color: Color(0xFF1F7A3F),
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ],
    ),
  );
```

Replace the `denied` case's icon/text row the same way (`size: 24`, label `fontSize: 15`), keep the `Riprova` button unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/ride_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/screens/ride_screen.dart test/screens/ride_screen_test.dart
git commit -m "feat: enlarge location status indicator for glance readability while riding"
```

---

### Task 3: Persist and prefill display name on Home (Point 5)

**Files:**
- Modify: `lib/screens/home_screen.dart:22-38` (`_HomeScreenState.initState`)
- Test: `test/screens/home_screen_test.dart`

**Interfaces:**
- Consumes: existing `RecentRideStore.load() -> Future<RecentRide?>` (already carries `displayName`).

- [ ] **Step 1: Write failing test**

```dart
// test/screens/home_screen_test.dart (add to existing file)
testWidgets('prefills the name field from the last saved ride', (tester) async {
  final store = _FakeRecentRideStore(
    initial: const RecentRide(rideId: 'ABC123', displayName: 'Mario'),
  );

  await tester.pumpWidget(MaterialApp(
    home: HomeScreen(
      rideRepository: repository,
      onRideReady: (_) {},
      recentRideStore: store,
    ),
  ));
  await tester.pumpAndSettle();

  final field =
      tester.widget<TextField>(find.byKey(const Key('displayNameField')));
  expect(field.controller!.text, 'Mario');
});
```

(If the test file doesn't already have a `_FakeRecentRideStore`, check — it's used by existing "continue recent ride" tests; reuse it.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/home_screen_test.dart`
Expected: FAIL — name field stays empty.

- [ ] **Step 3: Prefill `_nameController` once the recent ride loads**

```dart
@override
void initState() {
  super.initState();
  _recentRideStore.load().then((ride) {
    if (!mounted || ride == null) return;
    setState(() {
      _recentRide = ride;
      _nameController.text = ride.displayName;
    });
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/home_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/screens/home_screen.dart test/screens/home_screen_test.dart
git commit -m "feat: prefill display name from the last ride instead of asking again"
```

---

### Task 4: Map controller + tap-rider-to-center (Point 6)

**Files:**
- Modify: `lib/screens/ride_screen.dart` (add controller field, `GoogleMap.onMapCreated`, make rider chips tappable)
- Test: `test/screens/ride_screen_test.dart`

**Interfaces:**
- Produces: `_RideScreenState._mapController` (`GoogleMapController?`), `_RideScreenState._centerMapOn(RiderDoc rider)` — used by Task 5 (dropoff banner) too.
- Consumes: `RiderDoc.lat`, `RiderDoc.lng` (existing, nullable).

- [ ] **Step 1: Write failing test**

```dart
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

  // Chip exists and is wrapped in a tappable InkWell/GestureDetector.
  expect(find.byKey(const Key('riderChip_user1')), findsOneWidget);
  await tester.tap(find.byKey(const Key('riderChip_user1')));
  await tester.pumpAndSettle();
  // No crash and no exception thrown is the behavioral assertion here;
  // GoogleMapController.animateCamera cannot be asserted directly in a
  // widget test without a platform view, so this guards wiring, not the
  // camera move itself.
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/ride_screen_test.dart`
Expected: FAIL — key `riderChip_user1` doesn't exist (chips currently have no key, no tap handler).

- [ ] **Step 3: Add the map controller and centering method**

Add field:

```dart
GoogleMapController? _mapController;
```

In the `GoogleMap` widget inside `build`, add:

```dart
onMapCreated: (controller) => _mapController = controller,
```

Add method:

```dart
void _centerMapOn(RiderDoc rider) {
  final controller = _mapController;
  if (controller == null || rider.lat == null || rider.lng == null) return;
  controller.animateCamera(
    CameraUpdate.newLatLng(LatLng(rider.lat!, rider.lng!)),
  );
}
```

Dispose it in `dispose()`:

```dart
_mapController?.dispose();
```

- [ ] **Step 4: Make rider chips tappable with keys**

Update `_buildRidersSummary`:

```dart
Widget _buildRidersSummary(List<RiderDoc> riders) {
  return Column(
    children: [
      Text(
        '${riders.length} in ride',
        key: const Key('ridersCountText'),
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: riders
            .map((r) => InkWell(
                  key: Key('riderChip_${r.userId}'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: r.lat != null && r.lng != null
                      ? () => _centerMapOn(r)
                      : null,
                  child: Chip(
                    avatar: CircleAvatar(
                      radius: 11,
                      backgroundColor: r.state == RiderState.droppedOff
                          ? Colors.redAccent
                          : socialRideOrange,
                      child: Text(
                        r.displayName.isNotEmpty
                            ? r.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    label: Text(r.displayName),
                  ),
                ))
            .toList(),
      ),
    ],
  );
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/screens/ride_screen_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/screens/ride_screen.dart test/screens/ride_screen_test.dart
git commit -m "feat: tap a rider chip to center the map on them"
```

---

### Task 5: Dropoff banner gets a "center map" action (Point 7)

**Files:**
- Modify: `lib/screens/ride_screen.dart:729-770` (`_buildDropoffAlert`)
- Test: `test/screens/ride_screen_test.dart`

**Interfaces:**
- Consumes: `_centerMapOn(RiderDoc rider)` from Task 4.

- [ ] **Step 1: Write failing test**

```dart
testWidgets('dropoff banner has a button to center the map on the dropped rider',
    (tester) async {
  await repository.updateMyPosition(rideId, 46.0, 8.0);
  await repository.updateRiderState(rideId, 'user1', RiderState.droppedOff);
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
```

Check `RideRepository` for the exact method name to flip a rider's state (`updateRiderState`, or similar) before writing this test — grep `lib/services/ride_repository.dart` for `droppedOff`/`state` setters and use the real signature; the name above is illustrative.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/ride_screen_test.dart`
Expected: FAIL — no such key yet.

- [ ] **Step 3: Add the action button per dropped rider**

```dart
Widget _buildDropoffAlert(List<RiderDoc> riders) {
  final currentUserId = widget.rideRepository.currentUserId();
  final droppedOff = riders
      .where((r) =>
          r.state == RiderState.droppedOff && r.userId != currentUserId)
      .toList();
  if (droppedOff.isEmpty) return const SizedBox.shrink();
  return Container(
    key: const Key('dropoffAlertBanner'),
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE9E4),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFFFC7B8)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: droppedOff.map((r) {
        final hasPosition = r.lat != null && r.lng != null;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_rounded, color: Color(0xFFD9461E)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${r.displayName} si è staccato dal gruppo'
                  '${r.distanceFromGroupMeters != null ? " (~${r.distanceFromGroupMeters!.round()}m)" : ""}',
                  style: const TextStyle(
                    color: Color(0xFFD9461E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hasPosition)
                TextButton(
                  key: Key('centerOnDroppedRider_${r.userId}'),
                  onPressed: () => _centerMapOn(r),
                  child: const Text('Centra mappa'),
                ),
            ],
          ),
        );
      }).toList(),
    ),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/ride_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/screens/ride_screen.dart test/screens/ride_screen_test.dart
git commit -m "feat: add a center-map action to the dropoff alert banner"
```

---

### Task 6: Show ride name in the AppBar (Point 8)

**Files:**
- Modify: `lib/screens/ride_screen.dart:919-923` (`AppBar` title)
- Test: `test/screens/ride_screen_test.dart`

**Interfaces:**
- Consumes: `Ride.name` (existing field, already populated by `createRide`), `widget.rideRepository.streamRide(widget.rideId)` (existing stream, already used elsewhere in this file).

- [ ] **Step 1: Write failing test**

```dart
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

  expect(find.text('Giro'), findsOneWidget); // ride created with name 'Giro' in setUp
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/ride_screen_test.dart`
Expected: FAIL — AppBar title is the static "Ride in corso".

- [ ] **Step 3: Replace the static title with a `StreamBuilder`**

```dart
appBar: AppBar(
  title: StreamBuilder<Ride>(
    stream: widget.rideRepository.streamRide(widget.rideId),
    builder: (context, snapshot) {
      final name = snapshot.data?.name;
      return Text(name == null || name.isEmpty ? 'Ride in corso' : name);
    },
  ),
  actions: [
    // unchanged
  ],
),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/ride_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/screens/ride_screen.dart test/screens/ride_screen_test.dart
git commit -m "feat: show the ride's own name in the app bar"
```

---

### Task 7: Reclaim vertical space above the map (Point 1)

**Files:**
- Modify: `lib/screens/ride_screen.dart:1003-1005` (where `_buildDropoffAudioCard` and `_buildDropoffAlert` are placed in `build`)
- Modify: `lib/screens/ride_screen.dart:856-909` (`_buildDropoffAudioCard`)
- Test: `test/screens/ride_screen_test.dart`

**Rationale:** the "set your dropoff audio" card is a one-time setup action, not something a rider needs to see every time they glance at the ride — it's currently permanently docked above the map, competing with it for space together with the (occasional) dropoff banner. Move it behind the existing settings affordance pattern: keep a compact one-line entry point, collapse the full explanatory copy.

**Interfaces:**
- Consumes: `widget.rideRepository.currentUserId()` (existing), `_openDropoffAudioSheet` (existing, unchanged).

- [ ] **Step 1: Write failing test for the compact form**

```dart
testWidgets('dropoff audio card is a single compact row, not a full explainer block',
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

  // The long explainer sentence should be gone from the docked card;
  // it still exists inside the bottom sheet (opened on tap), not here.
  expect(
    find.text(
        'Verrà riprodotto sul telefono degli altri quando ti stacchi dal gruppo'),
    findsNothing,
  );
  expect(find.byKey(const Key('dropoffAudioCard')), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/ride_screen_test.dart`
Expected: FAIL — the explainer text is currently always shown.

- [ ] **Step 3: Shrink `_buildDropoffAudioCard` to a single compact row**

```dart
Widget _buildDropoffAudioCard(List<RiderDoc> riders) {
  final currentUserId = widget.rideRepository.currentUserId();
  final me = riders.where((r) => r.userId == currentUserId);
  final myAudioUrl = me.isEmpty ? null : me.first.dropoffAudioUrl;
  final myDisplayName = me.isEmpty ? '' : me.first.displayName;
  final hasAudio = myAudioUrl != null;
  return Padding(
    key: const Key('dropoffAudioCard'),
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openDropoffAudioSheet(myAudioUrl, myDisplayName),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: hasAudio ? const Color(0xFFFFF1EB) : const Color(0xFFF3F3F5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasAudio ? socialRideOrange : const Color(0xFFE2E2E6),
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasAudio ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
              color: socialRideOrange,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasAudio
                    ? 'Audio allontanamento impostato'
                    : 'Nessun audio allontanamento: tocca per registrarne uno',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.grey.shade500, size: 20),
          ],
        ),
      ),
    ),
  );
}
```

This removes the always-visible two-line explainer and the separate "Modifica"/"Registra" `TextButton`, replacing both with one tappable row that opens the same existing bottom sheet (which still carries the full explanation there, where it belongs — read once, not every time).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/ride_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Run full suite to check nothing else referenced the removed `TextButton` key**

Run: `flutter test`
Expected: PASS. If `dropoffAudioSettingsButton` key is referenced by another test, update that test to tap the `dropoffAudioCard` `InkWell` instead (e.g. `find.byKey(const Key('dropoffAudioCard'))`).

- [ ] **Step 6: Commit**

```bash
git add lib/screens/ride_screen.dart test/screens/ride_screen_test.dart
git commit -m "feat: compact the dropoff audio card to free vertical space above the map"
```

---

### Task 8: Extract the dropoff-audio bottom sheet into its own widget (Point 4)

**Files:**
- Create: `lib/screens/dropoff_audio_sheet.dart`
- Modify: `lib/screens/ride_screen.dart:423-624` (remove `_buildRecordingIndicator`, `_buildRecordingPreview`, `_openDropoffAudioSheet` bodies from `RideScreen`, replace with a call to the new widget)
- Test: `test/screens/dropoff_audio_sheet_test.dart`

**Rationale:** this is the most complex piece of UI in the file (recording, preview, upload, remove, all state-machined through one `StatefulBuilder`). Pulling it into its own `StatefulWidget` doesn't change any behavior but makes each state transition reviewable on its own, separate from the rest of `RideScreen`.

**Interfaces:**
- Produces: `DropoffAudioSheet` widget with constructor `DropoffAudioSheet({required String? currentAudioUrl, required String myDisplayName, required DropoffRecorder recorder, required DropoffAudioService audioService, required void Function(String filePath) onApply, required VoidCallback onRemove})`.
- Consumes: existing `DropoffRecorder`, `DropoffAudioService`, `dropoffAudioMaxDuration` (from `dropoff_audio_service.dart`), `AudioPlayer` (via `just_audio`).

- [ ] **Step 1: Write a failing widget test for the extracted sheet**

```dart
// test/screens/dropoff_audio_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/screens/dropoff_audio_sheet.dart';
import 'package:social_ride_app/services/dropoff_audio_service.dart';
import 'package:social_ride_app/services/dropoff_recorder.dart';

class _FakeRecorder implements DropoffRecorder {
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<String?> stop() async => null;
  @override
  void dispose() {}
}

void main() {
  testWidgets('shows the record and upload actions when no audio is set',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DropoffAudioSheet(
          currentAudioUrl: null,
          myDisplayName: 'Mario',
          recorder: _FakeRecorder(),
          onApply: (_) {},
          onRemove: () {},
        ),
      ),
    ));

    expect(find.byKey(const Key('recordDropoffAudioButton')), findsOneWidget);
    expect(find.byKey(const Key('uploadDropoffAudioButton')), findsOneWidget);
    expect(find.byKey(const Key('removeDropoffAudioButton')), findsNothing);
  });
}
```

Check the real `DropoffRecorder`/`DropoffAudioService`/`DropoffAlertSpeaker` interfaces in `lib/services/` before writing the fake — match exact method signatures.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/dropoff_audio_sheet_test.dart`
Expected: FAIL — `lib/screens/dropoff_audio_sheet.dart` doesn't exist.

- [ ] **Step 3: Create `DropoffAudioSheet`**

Move the body of `_openDropoffAudioSheet`'s `builder`, plus `_buildRecordingIndicator`, `_buildRecordingPreview`, `_toggleRecording`, `_stopRecording`, `_isUsableRecording`, `_togglePreviewPlayback`, `_discardRecording`, `_confirmRecording`, `_formatElapsed`, and `_pickAudioFile` out of `RideScreen` into a new `StatefulWidget`:

```dart
// lib/screens/dropoff_audio_sheet.dart
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:social_ride_app/services/dropoff_audio_service.dart';
import 'package:social_ride_app/services/dropoff_recorder.dart';
import 'package:social_ride_app/theme.dart';

class DropoffAudioSheet extends StatefulWidget {
  final String? currentAudioUrl;
  final String myDisplayName;
  final DropoffRecorder recorder;
  final void Function(String filePath) onApply;
  final VoidCallback onRemove;

  const DropoffAudioSheet({
    super.key,
    required this.currentAudioUrl,
    required this.myDisplayName,
    required this.recorder,
    required this.onApply,
    required this.onRemove,
  });

  @override
  State<DropoffAudioSheet> createState() => _DropoffAudioSheetState();
}

class _DropoffAudioSheetState extends State<DropoffAudioSheet>
    with SingleTickerProviderStateMixin {
  // ... fields moved verbatim from _RideScreenState: _isRecording,
  // _recordingSession, _recordingElapsed, _recordingTicker,
  // _pendingRecordingPath, _isPreviewPlaying, _previewPlayer,
  // _recordingPulseController.

  // ... methods moved verbatim: _toggleRecording, _stopRecording,
  // _isUsableRecording, _togglePreviewPlayback, _discardRecording,
  // _confirmRecording (calls widget.onApply instead of _applyDropoffAudio),
  // _formatElapsed, _pickAudioFile, _buildRecordingIndicator,
  // _buildRecordingPreview.
  //
  // build() returns exactly the Column currently built inline in
  // _openDropoffAudioSheet's StatefulBuilder, minus the StatefulBuilder
  // wrapper (this widget's own State replaces it) and using
  // widget.currentAudioUrl / widget.myDisplayName / widget.onRemove in
  // place of the closure parameters.

  @override
  void dispose() {
    _recordingTicker?.cancel();
    _recordingPulseController.dispose();
    _previewPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // moved body
    throw UnimplementedError();
  }
}
```

(The step above is written as a relocation, not new logic — copy the existing bodies character-for-character from `ride_screen.dart`, adjusting only the few call sites noted.)

In `RideScreen`, replace `_openDropoffAudioSheet`'s contents with:

```dart
void _openDropoffAudioSheet(String? currentAudioUrl, String myDisplayName) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.all(24),
      child: DropoffAudioSheet(
        currentAudioUrl: currentAudioUrl,
        myDisplayName: myDisplayName,
        recorder: _recorder,
        onApply: (path) async {
          await _applyDropoffAudio(path);
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        },
        onRemove: () async {
          await _removeDropoffAudio();
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        },
      ),
    ),
  );
}
```

Delete the now-unused `_alertPlayer`/`_previewPlayer`/recording fields and methods from `_RideScreenState` that moved to `DropoffAudioSheet` — keep `_alertPlayer` (still used by `_maybePlayDropoffAlerts`) and `_recorder`/`_audioService` getters (still needed to construct the sheet and to apply/remove audio).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/dropoff_audio_sheet_test.dart`
Expected: PASS

- [ ] **Step 5: Run the full suite — this is a refactor, nothing behavioral should break**

Run: `flutter test`
Expected: PASS. Existing tests in `ride_screen_test.dart` that poked recording-sheet keys (`recordDropoffAudioButton`, `playRecordingPreviewButton`, etc.) must still find them, since the keys are unchanged — only their owning widget moved.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/dropoff_audio_sheet.dart lib/screens/ride_screen.dart test/screens/dropoff_audio_sheet_test.dart
git commit -m "refactor: extract the dropoff audio recording sheet into its own widget"
```

---

## Task Order & Dependencies

Tasks 1–3 and 6–8 are independent of each other. Task 5 depends on Task 4 (`_centerMapOn`). Recommended order: 1, 2, 3, 4, 5, 6, 7, 8 (8 last since it's the largest refactor and benefits from the screen already being in its final shape).
