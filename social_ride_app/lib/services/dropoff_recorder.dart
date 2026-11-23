import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Records a short in-app clip. The caller (the recording UI) is
/// responsible for calling [stop] at [dropoffAudioMaxDuration] — this class
/// does not run its own auto-stop timer, since a second independent timer
/// racing the caller's own stop call made `stop()` return null for a clip
/// that had actually recorded fine, discarding it silently.
class DropoffRecorder {
  final AudioRecorder _recorder;

  DropoffRecorder({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/dropoff_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
  }

  /// Returns the recorded file path, or null if nothing was recorded.
  Future<String?> stop() => _recorder.stop();

  Future<void> dispose() => _recorder.dispose();
}
