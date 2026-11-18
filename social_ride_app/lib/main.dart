import 'package:flutter/material.dart';

// TODO(firebase-setup): Once a Firebase console project has been created
// (plan Step 2) and `flutterfire configure` has been run (plan Step 3),
// this file must be updated to:
//   1. import 'package:firebase_core/firebase_core.dart';
//   2. import 'firebase_options.dart';
//   3. make `main` async, call `WidgetsFlutterBinding.ensureInitialized()`,
//      and `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`
//      before `runApp`.
// This is intentionally deferred because `firebase_options.dart` does not
// exist yet in this environment (no browser/Google-account access to run
// `flutterfire configure`).
void main() {
  runApp(const PlaceholderApp());
}

class PlaceholderApp extends StatelessWidget {
  const PlaceholderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('Social Ride'))),
    );
  }
}
