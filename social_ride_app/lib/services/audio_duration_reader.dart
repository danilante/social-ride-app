import 'package:just_audio/just_audio.dart';
import 'package:social_ride_app/services/dropoff_audio_service.dart';

class JustAudioDurationReader implements AudioDurationReader {
  @override
  Future<Duration?> durationOf(String filePath) async {
    final player = AudioPlayer();
    try {
      return await player.setFilePath(filePath);
    } finally {
      await player.dispose();
    }
  }
}
