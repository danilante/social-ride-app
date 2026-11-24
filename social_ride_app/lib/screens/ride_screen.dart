import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:social_ride_app/models/ride.dart';
import 'package:social_ride_app/models/rider_doc.dart';
import 'package:social_ride_app/models/track_point.dart';
import 'package:social_ride_app/services/audio_duration_reader.dart';
import 'package:social_ride_app/services/dropoff_alert_speaker.dart';
import 'package:social_ride_app/services/dropoff_audio_service.dart';
import 'package:social_ride_app/services/dropoff_recorder.dart';
import 'package:social_ride_app/services/location_service.dart';
import 'package:social_ride_app/services/push_service.dart';
import 'package:social_ride_app/services/ride_repository.dart';
import 'package:social_ride_app/theme.dart';
import 'package:social_ride_app/util/markers.dart';

class RideScreen extends StatefulWidget {
  final String rideId;
  final RideRepository rideRepository;
  final LocationService locationService;
  final PushService pushService;
  final DropoffAudioService? dropoffAudioService;
  final DropoffRecorder? recorder;
  final DropoffAlertSpeaker? alertSpeaker;

  const RideScreen({
    super.key,
    required this.rideId,
    required this.rideRepository,
    required this.locationService,
    required this.pushService,
    this.dropoffAudioService,
    this.recorder,
    this.alertSpeaker,
  });

  @override
  State<RideScreen> createState() => _RideScreenState();
}

enum _LocationStatus { idle, requesting, sharing, denied }

class _RideScreenState extends State<RideScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription? _positionSubscription;
  StreamSubscription<Ride>? _rideStatusSubscription;
  bool _hasLeftOrEnded = false;
  _LocationStatus _status = _LocationStatus.idle;
  DropoffAudioService? _audioServiceCache;
  DropoffRecorder? _recorderCache;
  DropoffAlertSpeaker? _alertSpeakerCache;
  final _alertPlayer = AudioPlayer();
  final _previewPlayer = AudioPlayer();
  final Set<String> _playedDropoffAlertFor = {};
  final Map<String, BitmapDescriptor> _markerIcons = {};
  final Set<String> _generatingMarkerIconKeys = {};
  bool _isRecording = false;
  int _recordingSession = 0;
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordingTicker;
  String? _pendingRecordingPath;
  bool _isPreviewPlaying = false;
  VoidCallback? _sheetRefresh;
  late final AnimationController _recordingPulseController =
      AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  LatLng? _initialCameraTarget;

  DropoffAudioService get _audioService =>
      widget.dropoffAudioService ??
      (_audioServiceCache ??= DropoffAudioService(
        rideRepository: widget.rideRepository,
        durationReader: JustAudioDurationReader(),
      ));

  DropoffRecorder get _recorder =>
      widget.recorder ?? (_recorderCache ??= DropoffRecorder());

  DropoffAlertSpeaker get _alertSpeaker =>
      widget.alertSpeaker ??
      (_alertSpeakerCache ??= FlutterTtsDropoffAlertSpeaker());

  @override
  void initState() {
    super.initState();
    widget.pushService.registerForRide(widget.rideId);
    _rideStatusSubscription =
        widget.rideRepository.streamRide(widget.rideId).listen((ride) {
      if (ride.status != 'ended' || _hasLeftOrEnded || !mounted) return;
      _hasLeftOrEnded = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La ride è stata terminata dal creatore')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    });
    widget.locationService.getCurrentPosition().then((position) {
      if (!mounted || position == null) return;
      setState(() {
        _initialCameraTarget = LatLng(position.latitude, position.longitude);
      });
    });
  }

  Future<bool> _confirmDestructive({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel,
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _endRide() async {
    final confirmed = await _confirmDestructive(
      title: 'Terminare la ride?',
      message:
          'La ride verrà chiusa per tutti i partecipanti e non sarà più '
          'possibile tornarci.',
      confirmLabel: 'Termina',
    );
    if (!confirmed) return;
    await widget.rideRepository.endRide(widget.rideId);
    // The status-change listener above handles the pop + snackbar for
    // everyone still viewing the ride, this user included.
  }

  Future<void> _leaveRide() async {
    final confirmed = await _confirmDestructive(
      title: 'Uscire dalla ride?',
      message: 'Smetterai di condividere la posizione e di vedere gli altri '
          'rider di questa ride.',
      confirmLabel: 'Esci',
    );
    if (!confirmed) return;
    _hasLeftOrEnded = true;
    await widget.rideRepository.leaveRide(widget.rideId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sei uscito dalla ride')),
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _startSharingPosition() async {
    setState(() => _status = _LocationStatus.requesting);
    final granted = await widget.locationService.ensurePermission();
    if (!mounted) return;
    if (!granted) {
      setState(() => _status = _LocationStatus.denied);
      return;
    }
    setState(() => _status = _LocationStatus.sharing);
    _positionSubscription =
        widget.locationService.throttledPositionStream().listen((position) {
      widget.rideRepository
          .updateMyPosition(widget.rideId, position.latitude, position.longitude);
      widget.rideRepository
          .addTrackPoint(widget.rideId, position.latitude, position.longitude);
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _rideStatusSubscription?.cancel();
    _recordingTicker?.cancel();
    _recordingPulseController.dispose();
    _alertPlayer.dispose();
    _previewPlayer.dispose();
    _recorderCache?.dispose();
    super.dispose();
  }

  /// Generates and caches a colored, initial-letter marker icon per rider so
  /// the map shows who each position belongs to instead of a plain dot.
  void _ensureMarkerIcons(List<RiderDoc> riders) {
    for (final r in riders) {
      final key = markerIconKey(r);
      if (_markerIcons.containsKey(key) ||
          _generatingMarkerIconKeys.contains(key)) {
        continue;
      }
      _generatingMarkerIconKeys.add(key);
      final color =
          r.state == RiderState.droppedOff ? Colors.redAccent : socialRideOrange;
      createInitialMarkerIcon(r.displayName, color).then((icon) {
        _generatingMarkerIconKeys.remove(key);
        if (!mounted) return;
        setState(() => _markerIcons[key] = icon);
      });
    }
  }

  void _maybePlayDropoffAlerts(List<RiderDoc> riders) {
    final currentUserId = widget.rideRepository.currentUserId();
    for (final r in riders) {
      if (r.state != RiderState.droppedOff) {
        _playedDropoffAlertFor.remove(r.userId);
        continue;
      }
      if (r.userId == currentUserId) continue;
      if (!_playedDropoffAlertFor.add(r.userId)) continue;
      if (r.dropoffAudioUrl != null) {
        _alertPlayer.setUrl(r.dropoffAudioUrl!).then((_) => _alertPlayer.play());
      } else {
        // Rider never recorded a personal clip: speak a default alert so a
        // drop-off is never silent.
        _alertSpeaker.speak('Il rider ${r.displayName} si è staccato dal gruppo.');
      }
    }
  }

  Future<void> _pickAudioFile() async {
    final file = await FilePicker.pickFile(type: FileType.audio);
    final path = file?.path;
    if (path == null) return;
    await _applyDropoffAudio(path);
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
      return;
    }
    final granted = await _recorder.hasPermission();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permesso microfono negato')),
      );
      return;
    }
    await _recorder.start();
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
      _sheetRefresh?.call();
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
    final path = await _recorder.stop();
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
    _sheetRefresh?.call();
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
      _sheetRefresh?.call();
      return;
    }
    await _previewPlayer.setFilePath(path);
    setState(() => _isPreviewPlaying = true);
    _sheetRefresh?.call();
    unawaited(_previewPlayer.play().then((_) {
      if (!mounted) return;
      setState(() => _isPreviewPlaying = false);
      _sheetRefresh?.call();
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
    _sheetRefresh?.call();
  }

  Future<void> _confirmRecording() async {
    final path = _pendingRecordingPath;
    if (path == null) return;
    await _previewPlayer.stop();
    await _applyDropoffAudio(path);
    if (!mounted) return;
    setState(() {
      _pendingRecordingPath = null;
      _isPreviewPlaying = false;
      _recordingElapsed = Duration.zero;
    });
    _sheetRefresh?.call();
  }

  String _formatElapsed(Duration d) {
    final seconds = d.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(1)}s';
  }

  Future<void> _applyDropoffAudio(String filePath) async {
    try {
      await _audioService.setDropoffAudio(widget.rideId, filePath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio allontanamento impostato')),
      );
    } on DropoffAudioTooLongException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio troppo lungo: massimo 6 secondi')),
      );
    }
  }

  Future<void> _removeDropoffAudio() async {
    await _audioService.clearDropoffAudio(widget.rideId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Audio allontanamento rimosso')),
    );
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

  Widget _buildRecordingPreview({required VoidCallback onConfirmed}) {
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
                  onPressed: () async {
                    await _confirmRecording();
                    onConfirmed();
                  },
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

  void _openDropoffAudioSheet(String? currentAudioUrl, String myDisplayName) {
    setState(() {
      _pendingRecordingPath = null;
      _isPreviewPlaying = false;
      _recordingElapsed = Duration.zero;
    });
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          _sheetRefresh = () => setSheetState(() {});
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
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
                          'vocale automatico: "Il rider $myDisplayName si è '
                          'staccato dal gruppo".',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12),
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
                  _buildRecordingPreview(
                    onConfirmed: () {
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                    },
                  ),
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
                    onPressed: () async {
                      await _toggleRecording();
                      setSheetState(() {});
                    },
                    icon: Icon(_isRecording
                        ? Icons.stop_circle_rounded
                        : Icons.mic_rounded),
                    label: Text(_isRecording
                        ? 'Stop registrazione'
                        : 'Registra in app'),
                  ),
                  if (!_isRecording) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const Key('uploadDropoffAudioButton'),
                      onPressed: () async {
                        await _pickAudioFile();
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Carica un file'),
                    ),
                  ],
                ],
                if (currentAudioUrl != null && _pendingRecordingPath == null) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    key: const Key('removeDropoffAudioButton'),
                    onPressed: () async {
                      await _removeDropoffAudio();
                      if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                    },
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.redAccent),
                    label: const Text('Rimuovi audio',
                        style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      _sheetRefresh = null;
      if (_isRecording) {
        unawaited(_stopRecording().then((_) => _discardRecording()));
      } else if (_pendingRecordingPath != null) {
        unawaited(_discardRecording());
      }
    });
  }

  Widget _buildLocationControl() {
    switch (_status) {
      case _LocationStatus.idle:
        return ElevatedButton.icon(
          key: const Key('startRideButton'),
          onPressed: _startSharingPosition,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Avvia ride'),
        );
      case _LocationStatus.requesting:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        );
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
      case _LocationStatus.denied:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_off_rounded, color: Colors.redAccent, size: 24),
                SizedBox(width: 8),
                Text('Permesso posizione negato',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('retryLocationButton'),
              onPressed: _startSharingPosition,
              child: const Text('Riprova'),
            ),
          ],
        );
    }
  }

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
              .map((r) => Chip(
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
                  ))
              .toList(),
        ),
      ],
    );
  }

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_rounded, color: Color(0xFFD9461E)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: droppedOff
                  .map((r) => Text(
                        '${r.displayName} si è staccato dal gruppo'
                        '${r.distanceFromGroupMeters != null ? " (~${r.distanceFromGroupMeters!.round()}m)" : ""}',
                        style: const TextStyle(
                          color: Color(0xFFD9461E),
                          fontWeight: FontWeight.w700,
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _openRideSettingsSheet(Ride ride) {
    double meters = ride.dropoffThresholdMeters;
    int seconds = ride.dropoffDwellSeconds;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24, 24, 24, 24 + MediaQuery.of(sheetContext).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.tune_rounded, color: socialRideOrange),
                    SizedBox(width: 8),
                    Text('Impostazioni ride',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Decidi quanto deve allontanarsi e per quanto tempo un rider '
                  'prima di essere segnalato come staccato dal gruppo.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 20),
                Text('Distanza di stacco: ${meters.round()}m',
                    key: const Key('dropoffThresholdLabel'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Slider(
                  key: const Key('dropoffThresholdSlider'),
                  value: meters,
                  min: 50,
                  max: 1000,
                  divisions: 19,
                  activeColor: socialRideOrange,
                  label: '${meters.round()}m',
                  onChanged: (v) => setSheetState(() => meters = v),
                ),
                const SizedBox(height: 12),
                Text('Tempo prima dello stacco: ${seconds}s',
                    key: const Key('dropoffDwellLabel'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Slider(
                  key: const Key('dropoffDwellSlider'),
                  value: seconds.toDouble(),
                  min: 10,
                  max: 300,
                  divisions: 29,
                  activeColor: socialRideOrange,
                  label: '${seconds}s',
                  onChanged: (v) => setSheetState(() => seconds = v.round()),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  key: const Key('saveRideSettingsButton'),
                  onPressed: () async {
                    await widget.rideRepository.updateDropoffSettings(
                      widget.rideId,
                      dropoffThresholdMeters: meters,
                      dropoffDwellSeconds: seconds,
                    );
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Salva impostazioni'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDropoffAudioCard(List<RiderDoc> riders) {
    final currentUserId = widget.rideRepository.currentUserId();
    final me = riders.where((r) => r.userId == currentUserId);
    final myAudioUrl = me.isEmpty ? null : me.first.dropoffAudioUrl;
    final myDisplayName = me.isEmpty ? '' : me.first.displayName;
    final hasAudio = myAudioUrl != null;
    return Container(
      key: const Key('dropoffAudioCard'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasAudio ? const Color(0xFFFFF1EB) : const Color(0xFFF3F3F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasAudio ? socialRideOrange : const Color(0xFFE2E2E6),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasAudio ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
            color: socialRideOrange,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasAudio
                      ? 'Audio allontanamento impostato'
                      : 'Registra un audio da mandare al gruppo quando ti stacchi',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Verrà riprodotto sul telefono degli altri quando ti stacchi dal gruppo',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const Key('dropoffAudioSettingsButton'),
            onPressed: () => _openDropoffAudioSheet(myAudioUrl, myDisplayName),
            child: Text(hasAudio ? 'Modifica' : 'Registra'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyRideCode() async {
    await Clipboard.setData(ClipboardData(text: widget.rideId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Codice copiato')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride in corso'),
        actions: [
          StreamBuilder<Ride>(
            stream: widget.rideRepository.streamRide(widget.rideId),
            builder: (context, snapshot) {
              final ride = snapshot.data;
              if (ride == null ||
                  ride.creatorId != widget.rideRepository.currentUserId()) {
                return const SizedBox.shrink();
              }
              return IconButton(
                key: const Key('rideSettingsButton'),
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'Impostazioni ride',
                onPressed: () => _openRideSettingsSheet(ride),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<RiderDoc>>(
        stream: widget.rideRepository.streamRiders(widget.rideId),
        builder: (context, snapshot) {
          final riders = snapshot.data ?? [];
          _maybePlayDropoffAlerts(riders);
          _ensureMarkerIcons(riders);
          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                decoration: const BoxDecoration(
                  color: socialRideInk,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.rideId,
                          key: const Key('rideCodeText'),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          key: const Key('copyRideCodeButton'),
                          icon: const Icon(Icons.copy_rounded,
                              color: socialRideOrange),
                          tooltip: 'Copia codice',
                          onPressed: _copyRideCode,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _buildLocationControl(),
                    const SizedBox(height: 12),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: DefaultTextStyle.merge(
                        style: const TextStyle(color: Colors.white),
                        child: _buildRidersSummary(riders),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildDropoffAudioCard(riders),
              _buildDropoffAlert(riders),
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(0),
                  ),
                  child: StreamBuilder<List<TrackPoint>>(
                    stream: widget.rideRepository.streamTrack(widget.rideId),
                    builder: (context, trackSnapshot) {
                      final trackPoints = trackSnapshot.data ?? [];
                      return GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _initialCameraTarget ??
                              const LatLng(45.0703, 7.6869),
                          zoom: 12,
                        ),
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        markers: buildMarkers(riders, icons: _markerIcons),
                        polylines: buildTrackPolyline(trackPoints),
                      );
                    },
                  ),
                ),
              ),
              StreamBuilder<Ride>(
                stream: widget.rideRepository.streamRide(widget.rideId),
                builder: (context, snapshot) {
                  final ride = snapshot.data;
                  if (ride == null) return const SizedBox.shrink();
                  final isCreator =
                      ride.creatorId == widget.rideRepository.currentUserId();
                  return SafeArea(
                    top: false,
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: OutlinedButton.icon(
                        key: const Key('endOrLeaveRideButton'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                        ),
                        icon: Icon(isCreator
                            ? Icons.stop_circle_outlined
                            : Icons.logout_rounded),
                        label: Text(
                            isCreator ? 'Termina ride' : 'Esci dalla ride'),
                        onPressed: isCreator ? _endRide : _leaveRide,
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
