import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:social_ride_app/screens/home_screen.dart';
import 'package:social_ride_app/screens/ride_screen.dart';
import 'package:social_ride_app/services/audio_alert_session.dart';
import 'package:social_ride_app/services/location_service.dart';
import 'package:social_ride_app/services/push_service.dart';
import 'package:social_ride_app/services/recent_ride_store.dart';
import 'package:social_ride_app/services/ride_repository.dart';
import 'package:social_ride_app/services/volume_notice_store.dart';
import 'package:social_ride_app/theme.dart';

class SocialRideApp extends StatefulWidget {
  final RideRepository rideRepository;
  final LocationService Function()? locationServiceFactory;
  final PushService Function(RideRepository rideRepository)? pushServiceFactory;
  final RecentRideStore? recentRideStore;
  final AudioAlertSession? audioAlertSession;
  final VolumeNoticeStore? volumeNoticeStore;

  const SocialRideApp({
    super.key,
    required this.rideRepository,
    this.locationServiceFactory,
    this.pushServiceFactory,
    this.recentRideStore,
    this.audioAlertSession,
    this.volumeNoticeStore,
  });

  @override
  State<SocialRideApp> createState() => _SocialRideAppState();
}

class _SocialRideAppState extends State<SocialRideApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  AudioAlertSession get _audioAlertSession =>
      widget.audioAlertSession ?? DeviceAudioAlertSession();

  VolumeNoticeStore get _volumeNoticeStore =>
      widget.volumeNoticeStore ?? SharedPreferencesVolumeNoticeStore();

  @override
  void initState() {
    super.initState();
    _audioAlertSession.configureForAlerts();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowVolumeNotice());
  }

  Future<void> _maybeShowVolumeNotice() async {
    if (await _volumeNoticeStore.hasSeenNotice()) return;
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const Key('volumeNoticeDialog'),
        title: const Text('Avvisi sonori anche a telefono silenzioso'),
        content: const Text(
          'Quando un rider si stacca dal gruppo, l\'app riproduce un avviso '
          'sonoro anche se hai attivato la modalità silenziosa, così lo senti '
          'pure con il telefono in tasca.',
        ),
        actions: [
          TextButton(
            key: const Key('volumeNoticeAcceptButton'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Ho capito'),
          ),
        ],
      ),
    );
    await _volumeNoticeStore.markNoticeSeen();
  }

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
        recentRideStore: widget.recentRideStore,
      ),
    );
  }
}
