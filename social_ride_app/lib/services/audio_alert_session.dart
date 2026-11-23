import 'package:audio_session/audio_session.dart';

/// Configures the device audio session so drop-off alerts are actually
/// heard. iOS gives apps no API to raise the system volume on their own —
/// only the playback category, which makes audio ignore the ring/silent
/// switch, is available without a user gesture.
abstract class AudioAlertSession {
  Future<void> configureForAlerts();
}

class DeviceAudioAlertSession implements AudioAlertSession {
  @override
  Future<void> configureForAlerts() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.duckOthers,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.sonification,
        usage: AndroidAudioUsage.alarm,
      ),
    ));
  }
}
