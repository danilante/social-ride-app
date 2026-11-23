// Real end-to-end test of the custom drop-off audio feature against the
// actual Firebase Storage emulator (not fakes), on a real device/simulator.
// Requires:
//   firebase emulators:start --only firestore,auth,functions,storage
// before `flutter test integration_test/storage_audio_test.dart -d <device>`.
// On a physical device, 'localhost' below must be the Mac's LAN IP (see
// dropoff_flow_test.dart for the same requirement and why).
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:social_ride_app/firebase_options.dart';
import 'package:social_ride_app/services/dropoff_audio_service.dart';
import 'package:social_ride_app/services/ride_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseFirestore.instance.useFirestoreEmulator('192.168.1.13', 8080);
    await FirebaseAuth.instance.useAuthEmulator('192.168.1.13', 9099);
    await FirebaseStorage.instance.useStorageEmulator('192.168.1.13', 9199);
  });

  Future<String> _writeDummyAudioFile() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/dropoff_test_clip.m4a');
    await file.writeAsBytes(List<int>.filled(1024, 1));
    return file.path;
  }

  testWidgets(
      'uploading a drop-off clip stores it in the real Storage emulator and '
      'writes the download URL to Firestore', (tester) async {
    final cred = await FirebaseAuth.instance.signInAnonymously();
    final repo = RideRepository(
      firestore: FirebaseFirestore.instance,
      currentUserId: () => cred.user!.uid,
    );
    final rideId = await repo.createRide('Giro storage', 'Mario');

    final service = DropoffAudioService(
      rideRepository: repo,
      durationReader: _FixedDurationReader(const Duration(seconds: 3)),
    );

    final filePath = await _writeDummyAudioFile();
    final url = await service.setDropoffAudio(rideId, filePath);

    expect(url, contains('dropoff_audio.m4a'));

    final doc = await FirebaseFirestore.instance
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc(cred.user!.uid)
        .get();
    expect(doc.data()?['dropoffAudioUrl'], url);

    await service.clearDropoffAudio(rideId);
    final afterClear = await FirebaseFirestore.instance
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc(cred.user!.uid)
        .get();
    expect(afterClear.data()?['dropoffAudioUrl'], isNull);
  });

  testWidgets(
      'storage.rules reject a user writing to another user\'s drop-off '
      'audio path', (tester) async {
    final cred = await FirebaseAuth.instance.signInAnonymously();
    final otherUserId = 'storage-test-someone-else';
    final ref = FirebaseStorage.instance
        .ref('rides/rule-test-ride/riders/$otherUserId/dropoff_audio.m4a');

    final filePath = await _writeDummyAudioFile();
    await expectLater(
      ref.putFile(File(filePath)),
      throwsA(isA<FirebaseException>()),
    );

    // sanity: the signed-in user id really isn't the path owner.
    expect(cred.user!.uid, isNot(otherUserId));
  });
}

class _FixedDurationReader implements AudioDurationReader {
  final Duration duration;
  _FixedDurationReader(this.duration);

  @override
  Future<Duration?> durationOf(String filePath) async => duration;
}
