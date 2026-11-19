import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:social_ride_app/app.dart';
import 'package:social_ride_app/services/ride_repository.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final auth = FirebaseAuth.instance;
  final userCredential = await auth.signInAnonymously();
  final userId = userCredential.user!.uid;

  final repository = RideRepository(
    firestore: FirebaseFirestore.instance,
    currentUserId: () => userId,
  );

  runApp(SocialRideApp(rideRepository: repository));
}
