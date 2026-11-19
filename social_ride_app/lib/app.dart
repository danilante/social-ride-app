import 'package:flutter/material.dart';
import 'package:social_ride_app/screens/home_screen.dart';
import 'package:social_ride_app/screens/ride_screen.dart';
import 'package:social_ride_app/services/location_service.dart';
import 'package:social_ride_app/services/ride_repository.dart';

class SocialRideApp extends StatefulWidget {
  final RideRepository rideRepository;

  const SocialRideApp({super.key, required this.rideRepository});

  @override
  State<SocialRideApp> createState() => _SocialRideAppState();
}

class _SocialRideAppState extends State<SocialRideApp> {
  String? _activeRideId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: _activeRideId == null
          ? HomeScreen(
              rideRepository: widget.rideRepository,
              onRideReady: (rideId) => setState(() => _activeRideId = rideId),
            )
          : RideScreen(
              rideId: _activeRideId!,
              rideRepository: widget.rideRepository,
              locationService: LocationService(),
            ),
    );
  }
}
