import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:social_ride_app/models/rider_doc.dart';
import 'package:social_ride_app/services/audio_duration_reader.dart';
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

  const RideScreen({
    super.key,
    required this.rideId,
    required this.rideRepository,
    required this.locationService,
    required this.pushService,
    this.dropoffAudioService,
    this.recorder,
  });

  @override
  State<RideScreen> createState() => _RideScreenState();
}

enum _LocationStatus { idle, requesting, sharing, denied }

class _RideScreenState extends State<RideScreen> {
  StreamSubscription? _positionSubscription;
  _LocationStatus _status = _LocationStatus.idle;
  DropoffAudioService? _audioServiceCache;
  DropoffRecorder? _recorderCache;
  final _alertPlayer = AudioPlayer();
  final Set<String> _playedDropoffAlertFor = {};
  bool _isRecording = false;

  DropoffAudioService get _audioService =>
      widget.dropoffAudioService ??
      (_audioServiceCache ??= DropoffAudioService(
        rideRepository: widget.rideRepository,
        durationReader: JustAudioDurationReader(),
      ));

  DropoffRecorder get _recorder =>
      widget.recorder ?? (_recorderCache ??= DropoffRecorder());

  @override
  void initState() {
    super.initState();
    widget.pushService.registerForRide(widget.rideId);
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
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _alertPlayer.dispose();
    _recorderCache?.dispose();
    super.dispose();
  }

  void _maybePlayDropoffAlerts(List<RiderDoc> riders) {
    final currentUserId = widget.rideRepository.currentUserId();
    for (final r in riders) {
      if (r.state != RiderState.droppedOff) {
        _playedDropoffAlertFor.remove(r.userId);
        continue;
      }
      if (r.userId == currentUserId) continue;
      if (r.dropoffAudioUrl == null) continue;
      if (!_playedDropoffAlertFor.add(r.userId)) continue;
      _alertPlayer.setUrl(r.dropoffAudioUrl!).then((_) => _alertPlayer.play());
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
      setState(() => _isRecording = false);
      final path = await _recorder.stop();
      if (path != null) await _applyDropoffAudio(path);
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
    setState(() => _isRecording = true);
    Future.delayed(dropoffAudioMaxDuration, () async {
      if (!mounted || !_isRecording) return;
      setState(() => _isRecording = false);
      final path = await _recorder.stop();
      if (path != null) await _applyDropoffAudio(path);
    });
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

  void _openDropoffAudioSheet(String? currentAudioUrl) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
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
              const SizedBox(height: 20),
              ElevatedButton.icon(
                key: const Key('recordDropoffAudioButton'),
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
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('uploadDropoffAudioButton'),
                onPressed: () async {
                  await _pickAudioFile();
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Carica un file'),
              ),
              if (currentAudioUrl != null) ...[
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
        ),
      ),
    );
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F6EC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on_rounded, color: Color(0xFF2E9E53), size: 18),
              SizedBox(width: 6),
              Text(
                'Condivisione posizione attiva',
                style: TextStyle(
                  color: Color(0xFF1F7A3F),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
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
                Icon(Icons.location_off_rounded, color: Colors.redAccent, size: 18),
                SizedBox(width: 6),
                Text('Permesso posizione negato',
                    style: TextStyle(fontWeight: FontWeight.w600)),
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
          StreamBuilder<List<RiderDoc>>(
            stream: widget.rideRepository.streamRiders(widget.rideId),
            builder: (context, snapshot) {
              final me = (snapshot.data ?? []).where(
                  (r) => r.userId == widget.rideRepository.currentUserId());
              final myAudioUrl =
                  me.isEmpty ? null : me.first.dropoffAudioUrl;
              return IconButton(
                key: const Key('dropoffAudioSettingsButton'),
                icon: Icon(
                  myAudioUrl != null
                      ? Icons.graphic_eq_rounded
                      : Icons.mic_none_rounded,
                ),
                tooltip: 'Audio allontanamento',
                onPressed: () => _openDropoffAudioSheet(myAudioUrl),
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
              _buildDropoffAlert(riders),
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(0),
                  ),
                  child: GoogleMap(
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(45.0703, 7.6869),
                      zoom: 12,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    markers: buildMarkers(riders),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
