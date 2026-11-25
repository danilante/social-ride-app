import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:social_ride_app/models/ride.dart';
import 'package:social_ride_app/models/rider_doc.dart';
import 'package:social_ride_app/models/track_point.dart';
import 'package:social_ride_app/screens/dropoff_audio_sheet.dart';
import 'package:social_ride_app/services/audio_duration_reader.dart';
import 'package:social_ride_app/services/dropoff_alert_speaker.dart';
import 'package:social_ride_app/services/dropoff_audio_service.dart';
import 'package:social_ride_app/services/dropoff_recorder.dart';
import 'package:social_ride_app/services/location_service.dart';
import 'package:social_ride_app/services/position_queue.dart';
import 'package:social_ride_app/services/push_service.dart';
import 'package:social_ride_app/services/ride_repository.dart';
import 'package:social_ride_app/theme.dart';
import 'package:social_ride_app/util/geo.dart';
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

class _RideScreenState extends State<RideScreen> {
  StreamSubscription? _positionSubscription;
  StreamSubscription<Ride>? _rideStatusSubscription;
  bool _hasLeftOrEnded = false;
  _LocationStatus _status = _LocationStatus.idle;
  DropoffAudioService? _audioServiceCache;
  DropoffRecorder? _recorderCache;
  DropoffAlertSpeaker? _alertSpeakerCache;
  final _alertPlayer = AudioPlayer();
  final Set<String> _playedDropoffAlertFor = {};
  final Map<String, BitmapDescriptor> _markerIcons = {};
  final Set<String> _generatingMarkerIconKeys = {};
  LatLng? _initialCameraTarget;
  GoogleMapController? _mapController;

  /// Offline buffer: positions that failed to upload are kept here and
  /// flushed on the next successful write (or periodically).
  final PositionQueue _offlineQueue = PositionQueue(maxSize: 30);

  /// Last successfully recorded track point (for extra sampling safety).
  double? _lastTrackLat;
  double? _lastTrackLng;
  static const _trackMinDistanceMeters = 20.0;

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
    _positionSubscription = widget.locationService
        .throttledPositionStream(
          interval: const Duration(seconds: 10),
          minDistanceMeters: 15,
        )
        .listen(_onPositionUpdate);
  }

  Future<void> _onPositionUpdate(Position position) async {
    final lat = position.latitude;
    final lng = position.longitude;

    // 1. Try to push current position; on failure enqueue for later flush.
    try {
      await widget.rideRepository.updateMyPosition(widget.rideId, lat, lng);
      // Successful write → flush any buffered offline points.
      await _flushOfflineQueue();
    } catch (_) {
      _offlineQueue.enqueue(lat, lng);
    }

    // 2. Track sampling: only the creator records the trail, and only when
    //    the rider has moved enough since the last recorded point.
    final shouldRecordTrack = _lastTrackLat == null ||
        distanceMeters(_lastTrackLat!, _lastTrackLng!, lat, lng) >=
            _trackMinDistanceMeters;
    if (shouldRecordTrack) {
      try {
        await widget.rideRepository.addTrackPoint(widget.rideId, lat, lng);
        _lastTrackLat = lat;
        _lastTrackLng = lng;
      } catch (_) {
        // Track is best-effort; ignore transient failures.
      }
    }
  }

  Future<void> _flushOfflineQueue() async {
    while (_offlineQueue.isNotEmpty) {
      final p = _offlineQueue.dequeue();
      if (p == null) break;
      try {
        await widget.rideRepository
            .updateMyPosition(widget.rideId, p.lat, p.lng);
      } catch (_) {
        // Put it back and stop; we'll retry on the next successful write.
        _offlineQueue.enqueue(p.lat, p.lng);
        break;
      }
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _rideStatusSubscription?.cancel();
    _alertPlayer.dispose();
    _recorderCache?.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _centerMapOn(RiderDoc rider) {
    final controller = _mapController;
    if (controller == null || rider.lat == null || rider.lng == null) return;
    controller.animateCamera(
      CameraUpdate.newLatLng(LatLng(rider.lat!, rider.lng!)),
    );
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

  void _openDropoffAudioSheet(String? currentAudioUrl, String myDisplayName) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: DropoffAudioSheet(
          currentAudioUrl: currentAudioUrl,
          myDisplayName: myDisplayName,
          recorder: _recorder,
          onApply: (path) async {
            await _applyDropoffAudio(path);
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          },
          onRemove: () async {
            await _removeDropoffAudio();
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          },
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
              .map((r) => InkWell(
                    key: Key('riderChip_${r.userId}'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: r.lat != null && r.lng != null
                        ? () => _centerMapOn(r)
                        : null,
                    child: Chip(
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
                    ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: droppedOff.map((r) {
          final hasPosition = r.lat != null && r.lng != null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_rounded, color: Color(0xFFD9461E)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${r.displayName} si è staccato dal gruppo'
                    '${r.distanceFromGroupMeters != null ? " (~${r.distanceFromGroupMeters!.round()}m)" : ""}',
                    style: const TextStyle(
                      color: Color(0xFFD9461E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (hasPosition)
                  TextButton(
                    key: Key('centerOnDroppedRider_${r.userId}'),
                    onPressed: () => _centerMapOn(r),
                    child: const Text('Centra mappa'),
                  ),
              ],
            ),
          );
        }).toList(),
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
    return Padding(
      key: const Key('dropoffAudioCard'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDropoffAudioSheet(myAudioUrl, myDisplayName),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: hasAudio ? const Color(0xFFFFF1EB) : const Color(0xFFF3F3F5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasAudio ? socialRideOrange : const Color(0xFFE2E2E6),
            ),
          ),
          child: Row(
            children: [
              Icon(
                hasAudio ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
                color: socialRideOrange,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasAudio
                      ? 'Audio allontanamento impostato'
                      : 'Nessun audio allontanamento: tocca per registrarne uno',
                  style:
                      const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey.shade500, size: 20),
            ],
          ),
        ),
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
        title: StreamBuilder<Ride>(
          stream: widget.rideRepository.streamRide(widget.rideId),
          builder: (context, snapshot) {
            final name = snapshot.data?.name;
            return Text(name == null || name.isEmpty ? 'Ride in corso' : name);
          },
        ),
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
                        onMapCreated: (controller) =>
                            _mapController = controller,
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
