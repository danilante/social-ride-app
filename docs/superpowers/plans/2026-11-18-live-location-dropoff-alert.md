# Live Location + Auto Drop-off Alert — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the MVP of the social ride app — create/join a ride, share live
location on a map, and auto-detect + notify the group when a rider falls
behind.

**Architecture:** Flutter app (Android + iOS, single codebase) talking
directly to Firestore for ride/rider data, with a Firebase Cloud Function
computing drop-off state server-side and sending push notifications via
Firebase Cloud Messaging. No custom backend server.

**Tech Stack:** Flutter/Dart, Firebase (Firestore, Cloud Functions v2,
Cloud Messaging), Node.js (Cloud Functions runtime), google_maps_flutter,
geolocator, fake_cloud_firestore (tests).

**Spec:** `docs/superpowers/specs/2026-11-18-social-ride-app-design.md`

## Global Constraints

- Target group size: 5-15 riders per ride.
- Platforms: Android and iOS from the first release.
- No custom server: Firebase only (Firestore, Cloud Functions, Cloud
  Messaging). Firebase Storage is reserved for voice messages (phase 2).
- Budget: stay within Firebase free tier.
- Position updates: approximately every 10 seconds per rider.
- Drop-off threshold: default 300 meters, must persist for 60 consecutive
  seconds before a rider is marked `dropped_off` (filters false positives
  like a red light).
- Voice messages are **out of scope for this plan** — covered by a
  separate future plan (see spec's "Fuori scope per v1" / phase 2 items).
- Ride TTL cleanup (auto-delete after 24h) is **out of scope for this
  plan** — rides stay `active` until manually closed; cleanup is a phase 2
  item.

---

## File Structure

```
social_ride_app/                    (Flutter app root)
  pubspec.yaml
  lib/
    main.dart
    app.dart                        (root widget: Home <-> Ride switch)
    models/
      ride.dart
      rider_doc.dart
    services/
      ride_repository.dart
      location_service.dart
      push_service.dart
    screens/
      home_screen.dart
      ride_screen.dart
    util/
      markers.dart                  (buildMarkers pure function)
  test/
    models/ride_test.dart
    models/rider_doc_test.dart
    services/ride_repository_test.dart
    services/location_service_test.dart
    services/push_service_test.dart
    screens/home_screen_test.dart
    util/markers_test.dart

functions/                          (Firebase Cloud Functions, separate from Flutter app)
  package.json
  geo.js
  geo.test.js
  dropoff.js
  dropoff.test.js
  index.js
```

---

### Task 1: Project scaffold — Flutter app + Firebase project

**Files:**
- Create: `social_ride_app/` (entire Flutter project via `flutter create`)
- Modify: `social_ride_app/pubspec.yaml`
- Create: `social_ride_app/lib/main.dart`

**Interfaces:**
- Produces: a runnable Flutter app named `social_ride_app`, Firebase
  initialized, ready for `models/`, `services/`, `screens/` to be added in
  later tasks.

- [ ] **Step 1: Create the Flutter project**

```bash
cd ~/social-ride-app
flutter create --org com.danielelanteri social_ride_app
```

- [ ] **Step 2: Create a Firebase project**

In the Firebase console (console.firebase.google.com): create a new
project, e.g. `social-ride-app`. Enable: Firestore (production mode),
Cloud Messaging (enabled by default), Anonymous Authentication (under
Authentication > Sign-in method, enable "Anonymous").

- [ ] **Step 3: Install FlutterFire CLI and configure the app**

```bash
dart pub global activate flutterfire_cli
cd ~/social-ride-app/social_ride_app
flutterfire configure --project=social-ride-app
```

Select Android and iOS platforms when prompted. This generates
`lib/firebase_options.dart` and registers both platform apps in Firebase.

- [ ] **Step 4: Add dependencies**

Edit `social_ride_app/pubspec.yaml`, add under `dependencies`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^3.6.0
  firebase_auth: ^5.3.1
  cloud_firestore: ^5.4.4
  firebase_messaging: ^15.1.3
  google_maps_flutter: ^2.9.0
  geolocator: ^13.0.1
```

Add under `dev_dependencies`:

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  fake_cloud_firestore: ^3.1.0
  flutter_lints: ^4.0.0
```

Run:

```bash
flutter pub get
```

- [ ] **Step 5: Initialize Firebase in `main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const PlaceholderApp());
}

class PlaceholderApp extends StatelessWidget {
  const PlaceholderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('Social Ride'))),
    );
  }
}
```

- [ ] **Step 6: Verify the app runs**

```bash
flutter run
```

Expected: app launches on a connected device/emulator and shows the
"Social Ride" placeholder text with no Firebase initialization errors in
the console.

- [ ] **Step 7: Commit**

```bash
cd ~/social-ride-app
git add social_ride_app
git commit -m "chore: scaffold Flutter app with Firebase initialized"
```

---

### Task 2: Data models — `Ride` and `RiderDoc`

**Files:**
- Create: `social_ride_app/lib/models/ride.dart`
- Create: `social_ride_app/lib/models/rider_doc.dart`
- Test: `social_ride_app/test/models/ride_test.dart`
- Test: `social_ride_app/test/models/rider_doc_test.dart`

**Interfaces:**
- Produces: `Ride.fromMap(id, data)`, `Ride` fields (`id`, `name`,
  `creatorId`, `status`, `dropoffThresholdMeters`); `RiderDoc.fromMap(id,
  data)`, `RiderDoc` fields (`userId`, `displayName`, `lat`, `lng`,
  `positionUpdatedAt`, `state`, `distanceFromGroupMeters`); `RiderState`
  enum (`inGroup`, `droppedOff`) with `riderStateFromString` /
  `riderStateToString` helpers. Later tasks (repository, screens) consume
  these exact names.

- [ ] **Step 1: Write failing test for `Ride`**

```dart
// test/models/ride_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/models/ride.dart';

void main() {
  test('Ride.fromMap parses known fields with defaults', () {
    final ride = Ride.fromMap('ride1', {
      'name': 'Giro domenicale',
      'creatorId': 'user1',
      'status': 'active',
      'dropoffThresholdMeters': 250,
    });

    expect(ride.id, 'ride1');
    expect(ride.name, 'Giro domenicale');
    expect(ride.creatorId, 'user1');
    expect(ride.status, 'active');
    expect(ride.dropoffThresholdMeters, 250);
  });

  test('Ride.fromMap defaults dropoffThresholdMeters to 300', () {
    final ride = Ride.fromMap('ride1', {'name': 'X', 'creatorId': 'u'});
    expect(ride.dropoffThresholdMeters, 300);
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

```bash
cd ~/social-ride-app/social_ride_app
flutter test test/models/ride_test.dart
```

Expected: FAIL — `package:social_ride_app/models/ride.dart` not found.

- [ ] **Step 3: Implement `Ride`**

```dart
// lib/models/ride.dart
class Ride {
  final String id;
  final String name;
  final String creatorId;
  final String status;
  final double dropoffThresholdMeters;

  Ride({
    required this.id,
    required this.name,
    required this.creatorId,
    required this.status,
    required this.dropoffThresholdMeters,
  });

  factory Ride.fromMap(String id, Map<String, dynamic> data) {
    return Ride(
      id: id,
      name: data['name'] as String? ?? '',
      creatorId: data['creatorId'] as String? ?? '',
      status: data['status'] as String? ?? 'active',
      dropoffThresholdMeters:
          (data['dropoffThresholdMeters'] as num?)?.toDouble() ?? 300,
    );
  }
}
```

- [ ] **Step 4: Run test, verify it passes**

```bash
flutter test test/models/ride_test.dart
```

Expected: PASS.

- [ ] **Step 5: Write failing test for `RiderDoc`**

```dart
// test/models/rider_doc_test.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/models/rider_doc.dart';

void main() {
  test('RiderDoc.fromMap parses position and state', () {
    final rider = RiderDoc.fromMap('user1', {
      'displayName': 'Mario',
      'lat': 45.07,
      'lng': 7.68,
      'positionUpdatedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
      'state': 'dropped_off',
      'distanceFromGroupMeters': 350.5,
    });

    expect(rider.userId, 'user1');
    expect(rider.displayName, 'Mario');
    expect(rider.lat, 45.07);
    expect(rider.lng, 7.68);
    expect(rider.positionUpdatedAt, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(rider.state, RiderState.droppedOff);
    expect(rider.distanceFromGroupMeters, 350.5);
  });

  test('RiderDoc.fromMap defaults state to inGroup when missing', () {
    final rider = RiderDoc.fromMap('user1', {'displayName': 'Mario'});
    expect(rider.state, RiderState.inGroup);
    expect(rider.lat, isNull);
    expect(rider.positionUpdatedAt, isNull);
  });
}
```

- [ ] **Step 6: Run test, verify it fails**

```bash
flutter test test/models/rider_doc_test.dart
```

Expected: FAIL — `package:social_ride_app/models/rider_doc.dart` not found.

- [ ] **Step 7: Implement `RiderDoc` and `RiderState`**

```dart
// lib/models/rider_doc.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum RiderState { inGroup, droppedOff }

RiderState riderStateFromString(String value) =>
    value == 'dropped_off' ? RiderState.droppedOff : RiderState.inGroup;

String riderStateToString(RiderState state) =>
    state == RiderState.droppedOff ? 'dropped_off' : 'in_group';

class RiderDoc {
  final String userId;
  final String displayName;
  final double? lat;
  final double? lng;
  final DateTime? positionUpdatedAt;
  final RiderState state;
  final double? distanceFromGroupMeters;

  RiderDoc({
    required this.userId,
    required this.displayName,
    this.lat,
    this.lng,
    this.positionUpdatedAt,
    this.state = RiderState.inGroup,
    this.distanceFromGroupMeters,
  });

  factory RiderDoc.fromMap(String userId, Map<String, dynamic> data) {
    final rawTimestamp = data['positionUpdatedAt'];
    DateTime? updatedAt;
    if (rawTimestamp is Timestamp) {
      updatedAt = rawTimestamp.toDate();
    }
    return RiderDoc(
      userId: userId,
      displayName: data['displayName'] as String? ?? '',
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      positionUpdatedAt: updatedAt,
      state: riderStateFromString(data['state'] as String? ?? 'in_group'),
      distanceFromGroupMeters:
          (data['distanceFromGroupMeters'] as num?)?.toDouble(),
    );
  }
}
```

- [ ] **Step 8: Run test, verify it passes**

```bash
flutter test test/models/rider_doc_test.dart
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
cd ~/social-ride-app
git add social_ride_app/lib/models social_ride_app/test/models
git commit -m "feat: add Ride and RiderDoc models"
```

---

### Task 3: `RideRepository` — Firestore access for rides and riders

**Files:**
- Create: `social_ride_app/lib/services/ride_repository.dart`
- Test: `social_ride_app/test/services/ride_repository_test.dart`

**Interfaces:**
- Consumes: `Ride.fromMap`, `RiderDoc.fromMap`, `riderStateToString`
  (Task 2).
- Produces: `RideRepository(firestore:, currentUserId:)` with methods
  `createRide(String rideName, String displayName) -> Future<String>`,
  `joinRide(String rideId, String displayName) -> Future<void>`,
  `updateMyPosition(String rideId, double lat, double lng) ->
  Future<void>`, `streamRiders(String rideId) -> Stream<List<RiderDoc>>`,
  `updateFcmToken(String rideId, String token) -> Future<void>`, and
  `RideNotFoundException`. Later tasks (screens, push service) consume
  these exact signatures.

- [ ] **Step 1: Write failing test for `createRide` and `joinRide`**

```dart
// test/services/ride_repository_test.dart
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
```

- [ ] **Step 2: Run test, verify it fails**

```bash
flutter test test/services/ride_repository_test.dart
```

Expected: FAIL — `package:social_ride_app/services/ride_repository.dart`
not found.

- [ ] **Step 3: Implement `RideRepository`**

```dart
// lib/services/ride_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:social_ride_app/models/rider_doc.dart';

class RideNotFoundException implements Exception {
  final String rideId;
  RideNotFoundException(this.rideId);

  @override
  String toString() => 'Ride not found: $rideId';
}

class RideRepository {
  final FirebaseFirestore firestore;
  final String Function() currentUserId;

  RideRepository({required this.firestore, required this.currentUserId});

  Future<String> createRide(String rideName, String displayName) async {
    final rideRef = firestore.collection('rides').doc();
    await rideRef.set({
      'name': rideName,
      'creatorId': currentUserId(),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'dropoffThresholdMeters': 300,
    });
    await _addRider(rideRef.id, displayName);
    return rideRef.id;
  }

  Future<void> joinRide(String rideId, String displayName) async {
    final rideDoc = await firestore.collection('rides').doc(rideId).get();
    if (!rideDoc.exists) {
      throw RideNotFoundException(rideId);
    }
    await _addRider(rideId, displayName);
  }

  Future<void> _addRider(String rideId, String displayName) {
    return firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc(currentUserId())
        .set({
      'displayName': displayName,
      'state': 'in_group',
    }, SetOptions(merge: true));
  }

  Future<void> updateMyPosition(String rideId, double lat, double lng) {
    return firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc(currentUserId())
        .set({
      'lat': lat,
      'lng': lng,
      'positionUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateFcmToken(String rideId, String token) {
    return firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc(currentUserId())
        .set({'fcmToken': token}, SetOptions(merge: true));
  }

  Stream<List<RiderDoc>> streamRiders(String rideId) {
    return firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => RiderDoc.fromMap(d.id, d.data())).toList());
  }
}
```

- [ ] **Step 4: Run test, verify it passes**

```bash
flutter test test/services/ride_repository_test.dart
```

Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/social-ride-app
git add social_ride_app/lib/services/ride_repository.dart social_ride_app/test/services/ride_repository_test.dart
git commit -m "feat: add RideRepository for ride/rider Firestore access"
```

---

### Task 4: `LocationService` — throttled position stream

**Files:**
- Create: `social_ride_app/lib/services/location_service.dart`
- Test: `social_ride_app/test/services/location_service_test.dart`

**Interfaces:**
- Produces: `LocationService({positionStreamFactory})` with
  `ensurePermission() -> Future<bool>` and
  `throttledPositionStream({Duration interval}) -> Stream<Position>`.
  `positionStreamFactory` is `Stream<Position> Function()`, injectable for
  tests. Later tasks (ride screen) consume `throttledPositionStream`.

- [ ] **Step 1: Write failing test for throttling**

```dart
// test/services/location_service_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:social_ride_app/services/location_service.dart';

Position _fakePosition(DateTime timestamp, {double lat = 45.0, double lng = 7.0}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: timestamp,
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  test('throttledPositionStream only emits positions at least interval apart', () async {
    final controller = StreamController<Position>();
    final service = LocationService(
      positionStreamFactory: () => controller.stream,
    );

    final emitted = <Position>[];
    final subscription = service
        .throttledPositionStream(interval: const Duration(seconds: 10))
        .listen(emitted.add);

    final base = DateTime(2026, 1, 1, 12, 0, 0);
    controller.add(_fakePosition(base));
    controller.add(_fakePosition(base.add(const Duration(seconds: 3))));
    controller.add(_fakePosition(base.add(const Duration(seconds: 11))));
    controller.add(_fakePosition(base.add(const Duration(seconds: 15))));
    await Future.delayed(Duration.zero);

    expect(emitted.length, 2);
    expect(emitted[0].timestamp, base);
    expect(emitted[1].timestamp, base.add(const Duration(seconds: 11)));

    await subscription.cancel();
    await controller.close();
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

```bash
flutter test test/services/location_service_test.dart
```

Expected: FAIL — `package:social_ride_app/services/location_service.dart`
not found.

- [ ] **Step 3: Implement `LocationService`**

```dart
// lib/services/location_service.dart
import 'package:geolocator/geolocator.dart';

class LocationService {
  final Stream<Position> Function() positionStreamFactory;

  LocationService({Stream<Position> Function()? positionStreamFactory})
      : positionStreamFactory =
            positionStreamFactory ?? Geolocator.getPositionStream;

  Future<bool> ensurePermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
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

- [ ] **Step 4: Run test, verify it passes**

```bash
flutter test test/services/location_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/social-ride-app
git add social_ride_app/lib/services/location_service.dart social_ride_app/test/services/location_service_test.dart
git commit -m "feat: add LocationService with throttled position stream"
```

---

### Task 5: Home screen — create/join ride

**Files:**
- Create: `social_ride_app/lib/screens/home_screen.dart`
- Test: `social_ride_app/test/screens/home_screen_test.dart`

**Interfaces:**
- Consumes: `RideRepository.createRide`, `RideRepository.joinRide` (Task 3).
- Produces: `HomeScreen({rideRepository, onRideReady})` where
  `onRideReady` is `void Function(String rideId)`, called once a ride is
  created or joined. Task 6 (app-level widget) consumes this callback to
  switch to `RideScreen`.

- [ ] **Step 1: Write failing test for create flow**

```dart
// test/screens/home_screen_test.dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/screens/home_screen.dart';
import 'package:social_ride_app/services/ride_repository.dart';

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
      ),
    ));

    await tester.enterText(find.byKey(const Key('displayNameField')), 'Luca');
    await tester.enterText(find.byKey(const Key('rideCodeField')), rideId);
    await tester.tap(find.byKey(const Key('joinRideButton')));
    await tester.pumpAndSettle();

    expect(readyRideId, rideId);
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

```bash
flutter test test/screens/home_screen_test.dart
```

Expected: FAIL — `package:social_ride_app/screens/home_screen.dart` not
found.

- [ ] **Step 3: Implement `HomeScreen`**

```dart
// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:social_ride_app/services/ride_repository.dart';

class HomeScreen extends StatefulWidget {
  final RideRepository rideRepository;
  final void Function(String rideId) onRideReady;

  const HomeScreen({
    super.key,
    required this.rideRepository,
    required this.onRideReady,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nameController = TextEditingController();
  final _rideNameController = TextEditingController();
  final _rideCodeController = TextEditingController();

  Future<void> _createRide() async {
    final rideId = await widget.rideRepository
        .createRide(_rideNameController.text, _nameController.text);
    widget.onRideReady(rideId);
  }

  Future<void> _joinRide() async {
    final rideId = _rideCodeController.text.trim();
    await widget.rideRepository.joinRide(rideId, _nameController.text);
    widget.onRideReady(rideId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Social Ride')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              key: const Key('displayNameField'),
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Il tuo nome'),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('rideNameField'),
              controller: _rideNameController,
              decoration: const InputDecoration(labelText: 'Nome ride'),
            ),
            ElevatedButton(
              key: const Key('createRideButton'),
              onPressed: _createRide,
              child: const Text('Crea ride'),
            ),
            const Divider(height: 32),
            TextField(
              key: const Key('rideCodeField'),
              controller: _rideCodeController,
              decoration: const InputDecoration(labelText: 'Codice ride'),
            ),
            ElevatedButton(
              key: const Key('joinRideButton'),
              onPressed: _joinRide,
              child: const Text('Unisciti'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test, verify it passes**

```bash
flutter test test/screens/home_screen_test.dart
```

Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/social-ride-app
git add social_ride_app/lib/screens/home_screen.dart social_ride_app/test/screens/home_screen_test.dart
git commit -m "feat: add home screen for creating/joining a ride"
```

---

### Task 6: `buildMarkers` + Ride screen — live map

**Files:**
- Create: `social_ride_app/lib/util/markers.dart`
- Create: `social_ride_app/lib/screens/ride_screen.dart`
- Create: `social_ride_app/lib/app.dart`
- Modify: `social_ride_app/lib/main.dart`
- Test: `social_ride_app/test/util/markers_test.dart`

**Interfaces:**
- Consumes: `RiderDoc`, `RiderState` (Task 2); `RideRepository.streamRiders`,
  `RideRepository.updateMyPosition` (Task 3); `LocationService` (Task 4).
- Produces: `buildMarkers(List<RiderDoc>) -> Set<Marker>`;
  `RideScreen({rideId, rideRepository, locationService})`;
  `SocialRideApp({rideRepository, locationServiceFactory})` as the new app
  root, replacing `PlaceholderApp` from Task 1.

- [ ] **Step 1: Write failing test for `buildMarkers`**

```dart
// test/util/markers_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/models/rider_doc.dart';
import 'package:social_ride_app/util/markers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildMarkers skips riders without a position', () {
    final riders = [
      RiderDoc(userId: 'u1', displayName: 'Mario'),
      RiderDoc(userId: 'u2', displayName: 'Luca', lat: 45.0, lng: 7.0),
    ];

    final markers = buildMarkers(riders);

    expect(markers.length, 1);
    expect(markers.first.markerId.value, 'u2');
  });

  test('buildMarkers marks dropped_off riders distinctly', () {
    final riders = [
      RiderDoc(
        userId: 'u1',
        displayName: 'Mario',
        lat: 45.0,
        lng: 7.0,
        state: RiderState.droppedOff,
        distanceFromGroupMeters: 350,
      ),
    ];

    final markers = buildMarkers(riders);

    expect(markers.length, 1);
    expect(markers.first.infoWindow.snippet, contains('350'));
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

```bash
flutter test test/util/markers_test.dart
```

Expected: FAIL — `package:social_ride_app/util/markers.dart` not found.

- [ ] **Step 3: Implement `buildMarkers`**

```dart
// lib/util/markers.dart
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:social_ride_app/models/rider_doc.dart';

Set<Marker> buildMarkers(List<RiderDoc> riders) {
  return riders
      .where((r) => r.lat != null && r.lng != null)
      .map((r) => Marker(
            markerId: MarkerId(r.userId),
            position: LatLng(r.lat!, r.lng!),
            infoWindow: InfoWindow(
              title: r.displayName,
              snippet: r.state == RiderState.droppedOff
                  ? 'Staccato${r.distanceFromGroupMeters != null ? " ~${r.distanceFromGroupMeters!.round()}m" : ""}'
                  : null,
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              r.state == RiderState.droppedOff
                  ? BitmapDescriptor.hueRed
                  : BitmapDescriptor.hueGreen,
            ),
          ))
      .toSet();
}
```

- [ ] **Step 4: Run test, verify it passes**

```bash
flutter test test/util/markers_test.dart
```

Expected: PASS (2 tests).

- [ ] **Step 5: Implement `RideScreen` (manual verification, no automated test)**

`google_maps_flutter`'s map widget needs a real platform view, so this
screen is verified manually (Step 7), not with `flutter test`.

```dart
// lib/screens/ride_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:social_ride_app/models/rider_doc.dart';
import 'package:social_ride_app/services/location_service.dart';
import 'package:social_ride_app/services/ride_repository.dart';
import 'package:social_ride_app/util/markers.dart';

class RideScreen extends StatefulWidget {
  final String rideId;
  final RideRepository rideRepository;
  final LocationService locationService;

  const RideScreen({
    super.key,
    required this.rideId,
    required this.rideRepository,
    required this.locationService,
  });

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  StreamSubscription? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _startSharingPosition();
  }

  Future<void> _startSharingPosition() async {
    final granted = await widget.locationService.ensurePermission();
    if (!granted) return;
    _positionSubscription =
        widget.locationService.throttledPositionStream().listen((position) {
      widget.rideRepository
          .updateMyPosition(widget.rideId, position.latitude, position.longitude);
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ride in corso')),
      body: StreamBuilder<List<RiderDoc>>(
        stream: widget.rideRepository.streamRiders(widget.rideId),
        builder: (context, snapshot) {
          final riders = snapshot.data ?? [];
          return GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(45.0703, 7.6869),
              zoom: 12,
            ),
            markers: buildMarkers(riders),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 6: Implement `SocialRideApp` root widget and wire `main.dart`**

```dart
// lib/app.dart
import 'package:flutter/material.dart';
import 'package:social_ride_app/screens/home_screen.dart';
import 'package:social_ride_app/screens/ride_screen.dart';
import 'package:social_ride_app/services/location_service.dart';
import 'package:social_ride_app/services/ride_repository.dart';

class SocialRideApp extends StatefulWidget {
  final RideRepository rideRepository;

  const SocialRideApp({super.key, required this.rideRepository});

  @override
  State<SocialRideApp> createState() => _SocialRideAppState();
}

class _SocialRideAppState extends State<SocialRideApp> {
  String? _activeRideId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: _activeRideId == null
          ? HomeScreen(
              rideRepository: widget.rideRepository,
              onRideReady: (rideId) => setState(() => _activeRideId = rideId),
            )
          : RideScreen(
              rideId: _activeRideId!,
              rideRepository: widget.rideRepository,
              locationService: LocationService(),
            ),
    );
  }
}
```

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:social_ride_app/app.dart';
import 'package:social_ride_app/services/ride_repository.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final auth = FirebaseAuth.instance;
  final userCredential = await auth.signInAnonymously();
  final userId = userCredential.user!.uid;

  final repository = RideRepository(
    firestore: FirebaseFirestore.instance,
    currentUserId: () => userId,
  );

  runApp(SocialRideApp(rideRepository: repository));
}
```

- [ ] **Step 7: Manual verification**

```bash
flutter run
```

Expected: home screen appears; enter a name and ride name, tap "Crea
ride"; the ride screen opens showing a Google Map (requires a Maps API
key — see Task 1's `flutterfire configure` output and add the key to
`android/app/src/main/AndroidManifest.xml` and
`ios/Runner/AppDelegate.swift` per the `google_maps_flutter` setup docs).
Your own marker should appear once location permission is granted.

- [ ] **Step 8: Commit**

```bash
cd ~/social-ride-app
git add social_ride_app/lib/util/markers.dart social_ride_app/lib/screens/ride_screen.dart social_ride_app/lib/app.dart social_ride_app/lib/main.dart social_ride_app/test/util/markers_test.dart
git commit -m "feat: add ride screen with live map and marker rendering"
```

---

### Task 7: Cloud Functions scaffold + `geo.js`

**Files:**
- Create: `functions/package.json`
- Create: `functions/geo.js`
- Create: `functions/geo.test.js`

**Interfaces:**
- Produces: `distanceMeters(lat1, lng1, lat2, lng2) -> number` (meters,
  haversine formula), `centroid(positions: {lat, lng}[]) -> {lat, lng}`.
  Task 8 consumes both.

- [ ] **Step 1: Scaffold the Functions project**

```bash
cd ~/social-ride-app
mkdir functions
cd functions
npm init -y
npm install firebase-admin firebase-functions
npm install --save-dev firebase-functions-test
```

Edit `functions/package.json`, add under `"scripts"`:

```json
"scripts": {
  "test": "node --test"
}
```

- [ ] **Step 2: Write failing test for `geo.js`**

```js
// functions/geo.test.js
const test = require('node:test');
const assert = require('node:assert');
const { distanceMeters, centroid } = require('./geo');

test('distanceMeters returns 0 for identical points', () => {
  assert.strictEqual(distanceMeters(45.07, 7.68, 45.07, 7.68), 0);
});

test('distanceMeters returns ~111km for 1 degree latitude difference', () => {
  const d = distanceMeters(0, 0, 1, 0);
  assert.ok(Math.abs(d - 111195) < 100);
});

test('centroid averages positions', () => {
  const c = centroid([{ lat: 0, lng: 0 }, { lat: 2, lng: 2 }]);
  assert.strictEqual(c.lat, 1);
  assert.strictEqual(c.lng, 1);
});
```

- [ ] **Step 3: Run test, verify it fails**

```bash
cd ~/social-ride-app/functions
node --test geo.test.js
```

Expected: FAIL — `Cannot find module './geo'`.

- [ ] **Step 4: Implement `geo.js`**

```js
// functions/geo.js
function distanceMeters(lat1, lng1, lat2, lng2) {
  const toRad = (deg) => (deg * Math.PI) / 180;
  const R = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function centroid(positions) {
  const sum = positions.reduce(
    (acc, p) => ({ lat: acc.lat + p.lat, lng: acc.lng + p.lng }),
    { lat: 0, lng: 0 }
  );
  return { lat: sum.lat / positions.length, lng: sum.lng / positions.length };
}

module.exports = { distanceMeters, centroid };
```

- [ ] **Step 5: Run test, verify it passes**

```bash
node --test geo.test.js
```

Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/social-ride-app
git add functions/package.json functions/package-lock.json functions/geo.js functions/geo.test.js
git commit -m "feat: add geo distance/centroid helpers for Cloud Functions"
```

---

### Task 8: Drop-off detection + push notification (Cloud Function)

**Files:**
- Create: `functions/dropoff.js`
- Create: `functions/dropoff.test.js`
- Create: `functions/index.js`

**Interfaces:**
- Consumes: `distanceMeters`, `centroid` (Task 7).
- Produces: `evaluateRider(rider, otherRiders, now, thresholdMeters) ->
  {state, distanceFromGroupMeters, thresholdExceededSince}`; the deployed
  `onRiderPositionWritten` Firestore trigger.

- [ ] **Step 1: Write failing test for `evaluateRider`**

```js
// functions/dropoff.test.js
const test = require('node:test');
const assert = require('node:assert');
const { evaluateRider } = require('./dropoff');

test('stays in_group under threshold', () => {
  const rider = { lat: 0, lng: 0, thresholdExceededSince: null };
  const others = [{ lat: 0.0001, lng: 0.0001 }];
  const result = evaluateRider(rider, others, Date.now());
  assert.strictEqual(result.state, 'in_group');
});

test('marks dropped_off after dwell time over threshold', () => {
  const now = Date.now();
  const rider = { lat: 10, lng: 10, thresholdExceededSince: now - 61000 };
  const others = [{ lat: 0, lng: 0 }];
  const result = evaluateRider(rider, others, now, 300);
  assert.strictEqual(result.state, 'dropped_off');
});

test('does not mark dropped_off before dwell time elapses', () => {
  const now = Date.now();
  const rider = { lat: 10, lng: 10, thresholdExceededSince: now - 5000 };
  const others = [{ lat: 0, lng: 0 }];
  const result = evaluateRider(rider, others, now, 300);
  assert.strictEqual(result.state, 'in_group');
});

test('resets exceededSince when back under threshold', () => {
  const rider = { lat: 0, lng: 0.0001, thresholdExceededSince: Date.now() - 70000 };
  const others = [{ lat: 0, lng: 0 }];
  const result = evaluateRider(rider, others, Date.now(), 300);
  assert.strictEqual(result.thresholdExceededSince, null);
});

test('stays in_group with no other riders to compare against', () => {
  const rider = { lat: 10, lng: 10, thresholdExceededSince: null };
  const result = evaluateRider(rider, [], Date.now());
  assert.strictEqual(result.state, 'in_group');
});
```

- [ ] **Step 2: Run test, verify it fails**

```bash
cd ~/social-ride-app/functions
node --test dropoff.test.js
```

Expected: FAIL — `Cannot find module './dropoff'`.

- [ ] **Step 3: Implement `dropoff.js`**

```js
// functions/dropoff.js
const { distanceMeters, centroid } = require('./geo');

const DEFAULT_THRESHOLD_METERS = 300;
const DWELL_MS = 60 * 1000;

function evaluateRider(rider, otherRiders, now, thresholdMeters = DEFAULT_THRESHOLD_METERS) {
  if (otherRiders.length === 0) {
    return { state: 'in_group', distanceFromGroupMeters: 0, thresholdExceededSince: null };
  }

  const groupCenter = centroid(otherRiders.map((r) => ({ lat: r.lat, lng: r.lng })));
  const distance = distanceMeters(rider.lat, rider.lng, groupCenter.lat, groupCenter.lng);
  const overThreshold = distance > thresholdMeters;

  let exceededSince = rider.thresholdExceededSince;
  if (!overThreshold) {
    exceededSince = null;
  } else if (!exceededSince) {
    exceededSince = now;
  }

  const droppedOff = overThreshold && exceededSince && now - exceededSince >= DWELL_MS;

  return {
    state: droppedOff ? 'dropped_off' : 'in_group',
    distanceFromGroupMeters: distance,
    thresholdExceededSince: overThreshold ? exceededSince : null,
  };
}

module.exports = { evaluateRider, DEFAULT_THRESHOLD_METERS, DWELL_MS };
```

- [ ] **Step 4: Run test, verify it passes**

```bash
node --test dropoff.test.js
```

Expected: PASS (5 tests).

- [ ] **Step 5: Implement the Firestore trigger (`index.js`)**

This part needs the Firebase Admin SDK against a real or emulated
Firestore instance, so it is verified manually in Step 6, not with
`node --test`.

```js
// functions/index.js
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { evaluateRider } = require('./dropoff');

initializeApp();

exports.onRiderPositionWritten = onDocumentWritten(
  'rides/{rideId}/riders/{userId}',
  async (event) => {
    const { rideId, userId } = event.params;
    const db = getFirestore();
    const ridersSnap = await db
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .get();

    const riders = ridersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
    const rider = riders.find((r) => r.id === userId);
    if (!rider || rider.lat == null || rider.lng == null) return;

    const others = riders.filter(
      (r) => r.id !== userId && r.lat != null && r.lng != null
    );
    const previousState = rider.state || 'in_group';
    const result = evaluateRider(rider, others, Date.now());

    await db
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc(userId)
        .set(
          {
            distanceFromGroupMeters: result.distanceFromGroupMeters,
            thresholdExceededSince: result.thresholdExceededSince,
            state: result.state,
          },
          { merge: true }
        );

    if (result.state !== previousState) {
      const tokens = others.map((r) => r.fcmToken).filter(Boolean);
      if (tokens.length > 0) {
        const title =
          result.state === 'dropped_off'
            ? `${rider.displayName} si è staccato`
            : `${rider.displayName} è rientrato nel gruppo`;
        const body =
          result.state === 'dropped_off'
            ? `~${Math.round(result.distanceFromGroupMeters)}m dal gruppo`
            : '';
        await getMessaging().sendEachForMulticast({
          tokens,
          notification: { title, body },
        });
      }
    }
  }
);
```

- [ ] **Step 6: Manual verification with the Firebase Emulator Suite**

```bash
cd ~/social-ride-app/functions
npm install -g firebase-tools
firebase init emulators   # select Firestore + Functions emulators
firebase emulators:start
```

With the emulator running, use the Firestore emulator UI
(`http://localhost:4000`) to manually write two rider documents under
`rides/test-ride/riders/` more than 300m apart, wait 60+ seconds, write
one of them again, and confirm its `state` field flips to `dropped_off`
and the function logs show a (simulated, no real device) multicast send
attempt.

- [ ] **Step 7: Deploy**

```bash
cd ~/social-ride-app/functions
firebase deploy --only functions
```

- [ ] **Step 8: Commit**

```bash
cd ~/social-ride-app
git add functions/dropoff.js functions/dropoff.test.js functions/index.js
git commit -m "feat: add drop-off detection and push notification Cloud Function"
```

---

### Task 9: `PushService` — register for push notifications

**Files:**
- Create: `social_ride_app/lib/services/push_service.dart`
- Test: `social_ride_app/test/services/push_service_test.dart`
- Modify: `social_ride_app/lib/screens/ride_screen.dart`
- Modify: `social_ride_app/lib/app.dart`

**Interfaces:**
- Consumes: `RideRepository.updateFcmToken` (Task 3).
- Produces: `PushTokenProvider` interface
  (`requestPermission()`/`getToken()`), `FirebaseMessagingTokenProvider`,
  `PushService({tokenProvider, rideRepository})` with
  `registerForRide(String rideId) -> Future<void>`.

- [ ] **Step 1: Add `updateFcmToken` was already added in Task 3 — confirm it compiles**

`RideRepository.updateFcmToken` already exists from Task 3's
implementation. No change needed here; it's listed in Task 3's
Interfaces block for this reason.

- [ ] **Step 2: Write failing test for `PushService`**

```dart
// test/services/push_service_test.dart
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
```

- [ ] **Step 3: Run test, verify it fails**

```bash
cd ~/social-ride-app/social_ride_app
flutter test test/services/push_service_test.dart
```

Expected: FAIL — `package:social_ride_app/services/push_service.dart` not
found.

- [ ] **Step 4: Implement `PushService`**

```dart
// lib/services/push_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:social_ride_app/services/ride_repository.dart';

abstract class PushTokenProvider {
  Future<void> requestPermission();
  Future<String?> getToken();
}

class FirebaseMessagingTokenProvider implements PushTokenProvider {
  final FirebaseMessaging messaging;
  FirebaseMessagingTokenProvider(this.messaging);

  @override
  Future<void> requestPermission() async {
    await messaging.requestPermission();
  }

  @override
  Future<String?> getToken() => messaging.getToken();
}

class PushService {
  final PushTokenProvider tokenProvider;
  final RideRepository rideRepository;

  PushService({required this.tokenProvider, required this.rideRepository});

  Future<void> registerForRide(String rideId) async {
    await tokenProvider.requestPermission();
    final token = await tokenProvider.getToken();
    if (token != null) {
      await rideRepository.updateFcmToken(rideId, token);
    }
  }
}
```

- [ ] **Step 5: Run test, verify it passes**

```bash
flutter test test/services/push_service_test.dart
```

Expected: PASS (2 tests).

- [ ] **Step 6: Wire `PushService` into the ride screen**

Modify `lib/screens/ride_screen.dart`: add a `PushService pushService`
required field to `RideScreen`, and call it from `initState`:

```dart
  final PushService pushService;

  const RideScreen({
    super.key,
    required this.rideId,
    required this.rideRepository,
    required this.locationService,
    required this.pushService,
  });
```

```dart
  @override
  void initState() {
    super.initState();
    widget.pushService.registerForRide(widget.rideId);
    _startSharingPosition();
  }
```

Modify `lib/app.dart`: construct a `PushService` alongside
`LocationService` when building `RideScreen`:

```dart
          : RideScreen(
              rideId: _activeRideId!,
              rideRepository: widget.rideRepository,
              locationService: LocationService(),
              pushService: PushService(
                tokenProvider:
                    FirebaseMessagingTokenProvider(FirebaseMessaging.instance),
                rideRepository: widget.rideRepository,
              ),
            ),
```

Add the needed import to `lib/app.dart`:

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:social_ride_app/services/push_service.dart';
```

- [ ] **Step 7: Manual verification**

```bash
flutter run
```

Expected: no compile errors; on a real device, accepting the
notification permission prompt and then checking the rider's Firestore
document shows a populated `fcmToken` field.

- [ ] **Step 8: Commit**

```bash
cd ~/social-ride-app
git add social_ride_app/lib/services/push_service.dart social_ride_app/test/services/push_service_test.dart social_ride_app/lib/screens/ride_screen.dart social_ride_app/lib/app.dart
git commit -m "feat: register FCM token on ride join so drop-off alerts can be delivered"
```

---

### Task 10: End-to-end manual QA

**Files:** none (verification only).

- [ ] **Step 1: Two-device drop-off test**

Install the app on two physical devices (or one device + one emulator
with simulated GPS). Device A creates a ride; Device B joins with the
code. Both grant location permission. Move Device B's (simulated)
location more than 300m from Device A's and hold it there for over 60
seconds.

Expected: Device A receives a push notification "<nome B> si è
staccato" with an approximate distance; Device B's marker turns red on
both maps.

- [ ] **Step 2: Rejoin test**

Move Device B's location back within 300m of Device A.

Expected: Device B's marker turns green again on both maps (no push
notification required for rejoin per the spec).

- [ ] **Step 3: Permission-denied test**

On a fresh install, deny the location permission prompt.

Expected: app shows a clear blocking message explaining location is
required, no crash.

- [ ] **Step 4: Record results**

Note the outcome of each check (pass/fail + notes) in the PR description
or commit message for this task.

- [ ] **Step 5: Commit**

```bash
cd ~/social-ride-app
git commit --allow-empty -m "test: manual QA pass for live location + drop-off alert MVP"
```
