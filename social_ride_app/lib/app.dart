import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:social_ride_app/screens/home_screen.dart';
import 'package:social_ride_app/screens/ride_screen.dart';
import 'package:social_ride_app/services/location_service.dart';
import 'package:social_ride_app/services/push_service.dart';
import 'package:social_ride_app/services/ride_repository.dart';
import 'package:social_ride_app/theme.dart';

class SocialRideApp extends StatefulWidget {
  final RideRepository rideRepository;
  final LocationService Function()? locationServiceFactory;
  final PushService Function(RideRepository rideRepository)? pushServiceFactory;

  const SocialRideApp({
    super.key,
    required this.rideRepository,
    this.locationServiceFactory,
    this.pushServiceFactory,
  });

  @override
  State<SocialRideApp> createState() => _SocialRideAppState();
}

class _SocialRideAppState extends State<SocialRideApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  LocationService _buildLocationService() =>
      widget.locationServiceFactory?.call() ?? LocationService();

  PushService _buildPushService() =>
      widget.pushServiceFactory?.call(widget.rideRepository) ??
      PushService(
        tokenProvider:
            FirebaseMessagingTokenProvider(FirebaseMessaging.instance),
        rideRepository: widget.rideRepository,
      );

  void _openRide(String rideId) {
    _navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (_) => RideScreen(
          rideId: rideId,
          rideRepository: widget.rideRepository,
          locationService: _buildLocationService(),
          pushService: _buildPushService(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      theme: buildSocialRideTheme(),
      home: HomeScreen(
        rideRepository: widget.rideRepository,
        onRideReady: _openRide,
      ),
    );
  }
}
