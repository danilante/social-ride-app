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
import 'package:social_ride_app/services/battery_service.dart';
import 'package:social_ride_app/services/location_service.dart';
import 'package:social_ride_app/services/position_queue.dart';
import 'package:social_ride_app/services/push_service.dart';
import 'package:social_ride_app/services/ride_repository.dart';
import 'package:social_ride_app/theme.dart';
import 'package:social_ride_app/util/geo.dart';
import 'package:social_ride_app/util/markers.dart';
import 'package:social_ride_app/widgets/dropoff_alert_banner.dart';
import 'package:social_ride_app/widgets/location_sharing_control.dart';
import 'package:social_ride_app/widgets/ride_settings_sheet.dart';

class RideScreen extends StatefulWidget {
  final String rideId;
  final RideRepository rideRepository;
  final LocationService locationService;
  final PushService pushService;
  final DropoffAudioService? dropoffAudioService;
  final DropoffRecorder? recorder;
  final DropoffAlertSpeaker? alertSpeaker;
  final BatteryService? batteryService;

  /// When true (default), GPS sharing starts as soon as the screen opens.
  /// Tests can set false to exercise the manual "Avvia ride" control.
  final bool autoStartLocation;

  const RideScreen({
    super.key,
    required this.rideId,
    required this.rideRepository,
    required this.locationService,
    required this.pushService,
    this.dropoffAudioService,
    this.recorder,
    this.alertSpeaker,
    this.batteryService,
    this.autoStartLocation = true,
  });

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  StreamSubscription? _positionSubscription;
  StreamSubscription<Ride>? _rideStatusSubscription;
  bool _hasLeftOrEnded = false;
  LocationSharingStatus _status = LocationSharingStatus.idle;
  static const _lowBatteryThresholdPercent = 20;
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
    // UX for cycling: start sharing as soon as you enter the ride screen
    // (phone goes in the jersey pocket; no extra tap required).
    if (widget.autoStartLocation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _status != LocationSharingStatus.idle) return;
        _startSharingPosition();
      });
    }
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
    setState(() => _status = LocationSharingStatus.requesting);
    final granted = await widget.locationService.ensurePermission();
    if (!mounted) return;
    if (!granted) {
      setState(() => _status = LocationSharingStatus.denied);
      return;
    }
    setState(() => _status = LocationSharingStatus.sharing);

    // Spec: warn when battery is under 20% so the rider can plug in / adjust.
    final battery = widget.batteryService ?? BatteryService();
    if (await battery.isBelow(_lowBatteryThresholdPercent) && mounted) {
      final level = await battery.getBatteryLevel();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            level != null
                ? 'Batteria al $level%. Con la condivisione GPS si scarica più in fretta.'
                : 'Batteria bassa. Con la condivisione GPS si scarica più in fretta.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }

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
      _notifyOfflineQueueChanged();
    } catch (_) {
      _offlineQueue.enqueue(lat, lng);
      _notifyOfflineQueueChanged();
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

  void _notifyOfflineQueueChanged() {
    if (mounted) setState(() {});
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

  Widget _buildOfflineBanner() {
    if (_offlineQueue.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('offlineQueueBanner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD89A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFB86E00), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Offline — ${_offlineQueue.length} posizioni in coda',
              style: const TextStyle(
                color: Color(0xFF8A5200),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
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
    return LocationSharingControl(
      status: _status,
      onStartOrRetry: _startSharingPosition,
    );
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
    return DropoffAlertBanner(
      riders: riders,
      currentUserId: widget.rideRepository.currentUserId(),
      onCenterMap: _centerMapOn,
    );
  }

  void _openRideSettingsSheet(Ride ride) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => RideSettingsSheet(
        initialThresholdMeters: ride.dropoffThresholdMeters,
        initialDwellSeconds: ride.dropoffDwellSeconds,
        onSave: (meters, seconds) => widget.rideRepository.updateDropoffSettings(
          widget.rideId,
          dropoffThresholdMeters: meters,
          dropoffDwellSeconds: seconds,
        ),
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
              _buildOfflineBanner(),
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(0),
                  ),
                  child: StreamBuilder<List<TrackPoint>>(
                    stream: widget.rideRepository.streamTrack(widget.rideId),
                    builder: (context, trackSnapshot) {
                      final trackPoints = trackSnapshot.data ?? [];
                      final hasLivePositions = riders.any(
                        (r) => r.lat != null && r.lng != null,
                      );
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: _initialCameraTarget ??
                                  const LatLng(45.0703, 7.6869),
                              zoom: 12,
                            ),
                            onMapCreated: (controller) =>
                                _mapController = controller,
                            myLocationEnabled: true,
                            myLocationButtonEnabled: true,
                            markers:
                                buildMarkers(riders, icons: _markerIcons),
                            polylines: buildTrackPolyline(trackPoints),
                          ),
                          if (!hasLivePositions)
                            IgnorePointer(
                              child: Center(
                                child: Container(
                                  key: const Key('mapEmptyState'),
                                  margin: const EdgeInsets.all(24),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.08),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                  child: const Text(
                                    'In attesa delle posizioni del gruppo…',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: socialRideInk,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
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
