import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:social_ride_app/models/rider_doc.dart';
import 'package:social_ride_app/services/location_service.dart';
import 'package:social_ride_app/services/push_service.dart';
import 'package:social_ride_app/services/ride_repository.dart';
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
        return ElevatedButton(
          key: const Key('startRideButton'),
          onPressed: _startSharingPosition,
          child: const Text('Avvia ride'),
        );
      case _LocationStatus.requesting:
        return const CircularProgressIndicator();
      case _LocationStatus.sharing:
        return const Text('Condivisione posizione attiva');
      case _LocationStatus.denied:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Permesso posizione negato'),
            const SizedBox(height: 8),
            ElevatedButton(
              key: const Key('retryLocationButton'),
              onPressed: _startSharingPosition,
              child: const Text('Riprova'),
            ),
          ],
        );
    }
  }

  Widget _buildRidersSummary(List<RiderDoc> riders) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Text(
            '${riders.length} in ride',
            key: const Key('ridersCountText'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: riders
                .map((r) => Chip(label: Text(r.displayName)))
                .toList(),
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
              Padding(
                padding: const EdgeInsets.all(12),
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
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                          ),
                        ),
                        IconButton(
                          key: const Key('copyRideCodeButton'),
                          icon: const Icon(Icons.copy),
                          tooltip: 'Copia codice',
                          onPressed: _copyRideCode,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildLocationControl(),
                    const SizedBox(height: 8),
                    _buildRidersSummary(riders),
                  ],
                ),
              ),
              Expanded(
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
            ],
          );
        },
      ),
    );
  }
}
