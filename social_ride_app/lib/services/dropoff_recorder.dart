import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:social_ride_app/services/dropoff_audio_service.dart';

/// Records a short in-app clip, automatically stopping at
/// [dropoffAudioMaxDuration] so a rider can't record past the limit.
class DropoffRecorder {
  final AudioRecorder _recorder;
  Timer? _autoStopTimer;

  DropoffRecorder({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/dropoff_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(dropoffAudioMaxDuration, () => _recorder.stop());
  }

  /// Returns the recorded file path, or null if nothing was recorded.
  Future<String?> stop() async {
    _autoStopTimer?.cancel();
    return _recorder.stop();
  }

  Future<void> dispose() async {
    _autoStopTimer?.cancel();
    await _recorder.dispose();
  }
}
