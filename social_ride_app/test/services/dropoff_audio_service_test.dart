import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/services/dropoff_audio_service.dart';
import 'package:social_ride_app/services/ride_repository.dart';

class _FakeDurationReader implements AudioDurationReader {
  final Duration? durationToReturn;
  _FakeDurationReader(this.durationToReturn);

  @override
  Future<Duration?> durationOf(String filePath) async => durationToReturn;
}

class _FakeUploader implements AudioUploader {
  String? uploadedPath;
  String? deletedForRide;
  final String urlToReturn;
  _FakeUploader([this.urlToReturn = 'https://example.com/audio.m4a']);

  @override
  Future<String> upload(String rideId, String userId, String filePath) async {
    uploadedPath = filePath;
    return urlToReturn;
  }

  @override
  Future<void> delete(String rideId, String userId) async {
    deletedForRide = rideId;
  }
}

void main() {
  test('setDropoffAudio uploads and stores the URL when under the limit',
      () async {
    final firestore = FakeFirebaseFirestore();
    final repo =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    final rideId = await repo.createRide('Giro', 'Mario');
    final uploader = _FakeUploader('https://example.com/mine.m4a');
    final service = DropoffAudioService(
      rideRepository: repo,
      durationReader: _FakeDurationReader(const Duration(seconds: 5)),
      uploader: uploader,
    );

    final url = await service.setDropoffAudio(rideId, '/tmp/clip.m4a');

    expect(url, 'https://example.com/mine.m4a');
    expect(uploader.uploadedPath, '/tmp/clip.m4a');
    final riderDoc = await firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc('user1')
        .get();
    expect(riderDoc.data()!['dropoffAudioUrl'], 'https://example.com/mine.m4a');
  });

  test('setDropoffAudio rejects a clip longer than 6 seconds without uploading',
      () async {
    final firestore = FakeFirebaseFirestore();
    final repo =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    final rideId = await repo.createRide('Giro', 'Mario');
    final uploader = _FakeUploader();
    final service = DropoffAudioService(
      rideRepository: repo,
      durationReader: _FakeDurationReader(const Duration(seconds: 9)),
      uploader: uploader,
    );

    expect(
      () => service.setDropoffAudio(rideId, '/tmp/clip.m4a'),
      throwsA(isA<DropoffAudioTooLongException>()),
    );
    expect(uploader.uploadedPath, isNull);
  });

  test('setDropoffAudio allows a clip just barely over 6s within tolerance',
      () async {
    final firestore = FakeFirebaseFirestore();
    final repo =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    final rideId = await repo.createRide('Giro', 'Mario');
    final service = DropoffAudioService(
      rideRepository: repo,
      durationReader:
          _FakeDurationReader(const Duration(seconds: 6, milliseconds: 100)),
      uploader: _FakeUploader(),
    );

    await expectLater(
      service.setDropoffAudio(rideId, '/tmp/clip.m4a'),
      completes,
    );
  });

  test('setDropoffAudio allows unknown duration through (best effort)',
      () async {
    final firestore = FakeFirebaseFirestore();
    final repo =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    final rideId = await repo.createRide('Giro', 'Mario');
    final service = DropoffAudioService(
      rideRepository: repo,
      durationReader: _FakeDurationReader(null),
      uploader: _FakeUploader(),
    );

    await expectLater(
      service.setDropoffAudio(rideId, '/tmp/clip.m4a'),
      completes,
    );
  });

  test('clearDropoffAudio deletes the file and clears the URL', () async {
    final firestore = FakeFirebaseFirestore();
    final repo =
        RideRepository(firestore: firestore, currentUserId: () => 'user1');
    final rideId = await repo.createRide('Giro', 'Mario');
    final uploader = _FakeUploader();
    final service = DropoffAudioService(
      rideRepository: repo,
      durationReader: _FakeDurationReader(const Duration(seconds: 1)),
      uploader: uploader,
    );
    await service.setDropoffAudio(rideId, '/tmp/clip.m4a');

    await service.clearDropoffAudio(rideId);

    expect(uploader.deletedForRide, rideId);
    final riderDoc = await firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc('user1')
        .get();
    expect(riderDoc.data()!['dropoffAudioUrl'], isNull);
  });
}
