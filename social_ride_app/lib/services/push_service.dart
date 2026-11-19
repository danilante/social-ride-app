import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:social_ride_app/services/ride_repository.dart';

abstract class PushTokenProvider {
  Future<void> requestPermission();
  Future<String?> getToken();
}

class FirebaseMessagingTokenProvider implements PushTokenProvider {
  final FirebaseMessaging messaging;
  FirebaseMessagingTokenProvider(this.messaging);

  @override
  Future<void> requestPermission() async {
    await messaging.requestPermission();
  }

  @override
  Future<String?> getToken() => messaging.getToken();
}

class PushService {
  final PushTokenProvider tokenProvider;
  final RideRepository rideRepository;

  PushService({required this.tokenProvider, required this.rideRepository});

  Future<void> registerForRide(String rideId) async {
    await tokenProvider.requestPermission();
    final token = await tokenProvider.getToken();
    if (token != null) {
      await rideRepository.updateFcmToken(rideId, token);
    }
  }
}
