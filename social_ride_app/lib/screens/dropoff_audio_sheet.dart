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
  final _previewPlayer = AudioPlayer();
  bool _isRecording = false;
  int _recordingSession = 0;
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordingTicker;
  String? _pendingRecordingPath;
  bool _isPreviewPlaying = false;
  late final AnimationController _recordingPulseController =
      AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void dispose() {
    _recordingTicker?.cancel();
    _recordingPulseController.dispose();
    if (_isRecording) {
      unawaited(widget.recorder.stop());
    }
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _pickAudioFile() async {
    final file = await FilePicker.pickFile(type: FileType.audio);
    final path = file?.path;
    if (path == null) return;
    widget.onApply(path);
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
      return;
    }
    final granted = await widget.recorder.hasPermission();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permesso microfono negato')),
      );
      return;
    }
    await widget.recorder.start();
    final session = ++_recordingSession;
    setState(() {
      _isRecording = true;
      _pendingRecordingPath = null;
      _recordingElapsed = Duration.zero;
    });
    _recordingPulseController.repeat(reverse: true);
    _recordingTicker?.cancel();
    _recordingTicker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        _recordingElapsed += const Duration(milliseconds: 100);
      });
    });
    Future.delayed(dropoffAudioMaxDuration, () async {
      // Guard against a stale timer from an earlier recording: if this one
      // was already stopped and a new one started before this fires, the
      // session id no longer matches, so don't truncate the new recording.
      if (!mounted || !_isRecording || session != _recordingSession) return;
      await _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    _recordingTicker?.cancel();
    _recordingPulseController.stop();
    final path = await widget.recorder.stop();
    final valid = path != null && await _isUsableRecording(path);
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _pendingRecordingPath = valid ? path : null;
    });
    if (!valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Registrazione vuota o non riuscita, riprova')),
      );
    }
  }

  /// Loads [path] into the preview player to confirm it actually holds
  /// audio, so a failed/empty recording (e.g. no mic signal) doesn't end up
  /// stuck as a pending clip that can't be played or confirmed.
  Future<bool> _isUsableRecording(String path) async {
    try {
      final duration = await _previewPlayer.setFilePath(path);
      return duration != null && duration > Duration.zero;
    } catch (_) {
      return false;
    }
  }

  Future<void> _togglePreviewPlayback() async {
    final path = _pendingRecordingPath;
    if (path == null) return;
    if (_isPreviewPlaying) {
      await _previewPlayer.stop();
      if (!mounted) return;
      setState(() => _isPreviewPlaying = false);
      return;
    }
    await _previewPlayer.setFilePath(path);
    setState(() => _isPreviewPlaying = true);
    unawaited(_previewPlayer.play().then((_) {
      if (!mounted) return;
      setState(() => _isPreviewPlaying = false);
    }));
  }

  Future<void> _discardRecording() async {
    await _previewPlayer.stop();
    if (!mounted) return;
    setState(() {
      _pendingRecordingPath = null;
      _isPreviewPlaying = false;
      _recordingElapsed = Duration.zero;
    });
  }

  void _confirmRecording() {
    final path = _pendingRecordingPath;
    if (path == null) return;
    unawaited(_previewPlayer.stop());
    widget.onApply(path);
    setState(() {
      _pendingRecordingPath = null;
      _isPreviewPlaying = false;
      _recordingElapsed = Duration.zero;
    });
  }

  String _formatElapsed(Duration d) {
    final seconds = d.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(1)}s';
  }

  Widget _buildRecordingIndicator() {
    final remaining =
        dropoffAudioMaxDuration - _recordingElapsed > Duration.zero
            ? dropoffAudioMaxDuration - _recordingElapsed
            : Duration.zero;
    final progress =
        (_recordingElapsed.inMilliseconds / dropoffAudioMaxDuration.inMilliseconds)
            .clamp(0.0, 1.0);
    return Column(
      key: const Key('recordingIndicator'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            FadeTransition(
              opacity: Tween(begin: 0.25, end: 1.0)
                  .animate(_recordingPulseController),
              child: const Icon(Icons.fiber_manual_record_rounded,
                  color: Colors.redAccent, size: 16),
            ),
            const SizedBox(width: 8),
            Text(
              'Sto registrando… ancora ${_formatElapsed(remaining)}',
              key: const Key('recordingElapsedText'),
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: const Color(0xFFFFE0D6),
            color: Colors.redAccent,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingPreview() {
    return Container(
      key: const Key('recordingPreview'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F3F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('playRecordingPreviewButton'),
                tooltip: _isPreviewPlaying ? 'Pausa' : 'Riproduci',
                icon: Icon(
                  _isPreviewPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  color: socialRideOrange,
                  size: 36,
                ),
                onPressed: _togglePreviewPlayback,
              ),
              Expanded(
                child: Text(
                  'Clip registrata (${_formatElapsed(_recordingElapsed)}): '
                  'riascoltala prima di usarla',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('discardRecordingButton'),
                  onPressed: _discardRecording,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Registra di nuovo'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  key: const Key('confirmRecordingButton'),
                  onPressed: _confirmRecording,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Usa questo audio'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.graphic_eq_rounded, color: socialRideOrange),
            SizedBox(width: 8),
            Text('Il tuo audio allontanamento',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Verrà riprodotto sul telefono degli altri quando ti stacchi '
          'dal gruppo. Max 6 secondi.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Container(
          key: const Key('defaultAudioNotice'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F3F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: Colors.grey.shade600, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Se non registri nulla, verrà usato un messaggio '
                  'vocale automatico: "Il rider ${widget.myDisplayName} si è '
                  'staccato dal gruppo".',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_isRecording) ...[
          _buildRecordingIndicator(),
          const SizedBox(height: 16),
        ],
        if (!_isRecording && _pendingRecordingPath != null) ...[
          _buildRecordingPreview(),
          const SizedBox(height: 16),
        ],
        if (_pendingRecordingPath == null) ...[
          ElevatedButton.icon(
            key: const Key('recordDropoffAudioButton'),
            style: _isRecording
                ? ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: _toggleRecording,
            icon: Icon(
                _isRecording ? Icons.stop_circle_rounded : Icons.mic_rounded),
            label:
                Text(_isRecording ? 'Stop registrazione' : 'Registra in app'),
          ),
          if (!_isRecording) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('uploadDropoffAudioButton'),
              onPressed: _pickAudioFile,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Carica un file'),
            ),
          ],
        ],
        if (widget.currentAudioUrl != null && _pendingRecordingPath == null) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            key: const Key('removeDropoffAudioButton'),
            onPressed: widget.onRemove,
            icon: const Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent),
            label: const Text('Rimuovi audio',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ],
    );
  }
}
