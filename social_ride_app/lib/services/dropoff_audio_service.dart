import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:social_ride_app/services/ride_repository.dart';

const dropoffAudioMaxDuration = Duration(seconds: 6);

/// A small tolerance so a recording that lands at 6.0-6.2s (rounding,
/// encoder flush) isn't rejected for being a hair over the limit.
const _durationTolerance = Duration(milliseconds: 250);

class DropoffAudioTooLongException implements Exception {
  final Duration duration;
  DropoffAudioTooLongException(this.duration);

  @override
  String toString() =>
      'Audio too long: ${duration.inMilliseconds}ms (max ${dropoffAudioMaxDuration.inMilliseconds}ms)';
}

abstract class AudioDurationReader {
  Future<Duration?> durationOf(String filePath);
}

abstract class AudioUploader {
  Future<String> upload(String rideId, String userId, String filePath);
  Future<void> delete(String rideId, String userId);
}

class FirebaseAudioUploader implements AudioUploader {
  final FirebaseStorage storage;
  FirebaseAudioUploader({FirebaseStorage? storage})
      : storage = storage ?? FirebaseStorage.instance;

  Reference _refFor(String rideId, String userId) =>
      storage.ref('rides/$rideId/riders/$userId/dropoff_audio.m4a');

  @override
  Future<String> upload(String rideId, String userId, String filePath) async {
    final ref = _refFor(rideId, userId);
    await ref.putFile(File(filePath));
    return ref.getDownloadURL();
  }

  @override
  Future<void> delete(String rideId, String userId) async {
    try {
      await _refFor(rideId, userId).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }
}

/// Validates and uploads a rider's personal "I've dropped off" audio clip
/// (max [dropoffAudioMaxDuration]), played on other riders' phones when this
/// rider drops off from the group (see `functions/index.js`).
class DropoffAudioService {
  final RideRepository rideRepository;
  final AudioDurationReader durationReader;
  final AudioUploader uploader;

  DropoffAudioService({
    required this.rideRepository,
    required this.durationReader,
    AudioUploader? uploader,
  }) : uploader = uploader ?? FirebaseAudioUploader();

  /// Throws [DropoffAudioTooLongException] without uploading if [filePath]
  /// is longer than [dropoffAudioMaxDuration].
  Future<String> setDropoffAudio(String rideId, String filePath) async {
    final duration = await durationReader.durationOf(filePath);
    if (duration != null &&
        duration - _durationTolerance > dropoffAudioMaxDuration) {
      throw DropoffAudioTooLongException(duration);
    }

    final userId = rideRepository.currentUserId();
    // Delete any previous clip first so re-recording always gets a fresh
    // Storage object/token instead of risking another rider's player (or a
    // CDN) serving a cached copy of the old clip for the same path.
    await uploader.delete(rideId, userId);
    final url = await uploader.upload(rideId, userId, filePath);
    await rideRepository.updateDropoffAudioUrl(rideId, url);
    return url;
  }

  Future<void> clearDropoffAudio(String rideId) async {
    final userId = rideRepository.currentUserId();
    await uploader.delete(rideId, userId);
    await rideRepository.updateDropoffAudioUrl(rideId, null);
  }
}
