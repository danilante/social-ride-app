import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:social_ride_app/models/rider_doc.dart';
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

  const RideScreen({
    super.key,
    required this.rideId,
    required this.rideRepository,
    required this.locationService,
    required this.pushService,
  });

  @override
  State<RideScreen> createState() => _RideScreenState();
}

enum _LocationStatus { idle, requesting, sharing, denied }

class _RideScreenState extends State<RideScreen> {
  StreamSubscription? _positionSubscription;
  _LocationStatus _status = _LocationStatus.idle;

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
    super.dispose();
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
      appBar: AppBar(title: const Text('Ride in corso')),
      body: StreamBuilder<List<RiderDoc>>(
        stream: widget.rideRepository.streamRiders(widget.rideId),
        builder: (context, snapshot) {
          final riders = snapshot.data ?? [];
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
