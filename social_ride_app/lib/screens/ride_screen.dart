import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:social_ride_app/models/rider_doc.dart';
import 'package:social_ride_app/services/location_service.dart';
import 'package:social_ride_app/services/ride_repository.dart';
import 'package:social_ride_app/util/markers.dart';

class RideScreen extends StatefulWidget {
  final String rideId;
  final RideRepository rideRepository;
  final LocationService locationService;

  const RideScreen({
    super.key,
    required this.rideId,
    required this.rideRepository,
    required this.locationService,
  });

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  StreamSubscription? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _startSharingPosition();
  }

  Future<void> _startSharingPosition() async {
    final granted = await widget.locationService.ensurePermission();
    if (!granted) return;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ride in corso')),
      body: StreamBuilder<List<RiderDoc>>(
        stream: widget.rideRepository.streamRiders(widget.rideId),
        builder: (context, snapshot) {
          final riders = snapshot.data ?? [];
          return GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(45.0703, 7.6869),
              zoom: 12,
            ),
            markers: buildMarkers(riders),
          );
        },
      ),
    );
  }
}
