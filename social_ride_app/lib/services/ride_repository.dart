import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:social_ride_app/models/rider_doc.dart';

const _rideCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String _generateRideCode() {
  final random = Random.secure();
  return List.generate(
    6,
    (_) => _rideCodeAlphabet[random.nextInt(_rideCodeAlphabet.length)],
  ).join();
}

class RideNotFoundException implements Exception {
  final String rideId;
  RideNotFoundException(this.rideId);

  @override
  String toString() => 'Ride not found: $rideId';
}

class RideCodeCollisionException implements Exception {
  final String rideId;
  RideCodeCollisionException(this.rideId);

  @override
  String toString() => 'Ride code collision: $rideId';
}

class RideRepository {
  final FirebaseFirestore firestore;
  final String Function() currentUserId;
  final String Function() codeGenerator;

  RideRepository({
    required this.firestore,
    required this.currentUserId,
    String Function()? codeGenerator,
  }) : codeGenerator = codeGenerator ?? _generateRideCode;

  Future<String> createRide(String rideName, String displayName) async {
    while (true) {
      final rideRef = firestore.collection('rides').doc(codeGenerator());
      try {
        await firestore.runTransaction((transaction) async {
          final snapshot = await transaction.get(rideRef);
          if (snapshot.exists) {
            throw RideCodeCollisionException(rideRef.id);
          }
          transaction.set(rideRef, {
            'name': rideName,
            'creatorId': currentUserId(),
            'status': 'active',
            'createdAt': FieldValue.serverTimestamp(),
            'dropoffThresholdMeters': 300,
          });
        });
      } on RideCodeCollisionException {
        continue;
      }
      await _addRider(rideRef.id, displayName);
      return rideRef.id;
    }
  }

  Future<String> joinRide(String rideId, String displayName) async {
    final normalizedId = rideId.toUpperCase();
    final rideDoc = await firestore.collection('rides').doc(normalizedId).get();
    if (!rideDoc.exists) {
      throw RideNotFoundException(normalizedId);
    }
    await _addRider(normalizedId, displayName);
    return normalizedId;
  }

  Future<void> _addRider(String rideId, String displayName) {
    return firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc(currentUserId())
        .set({
      'displayName': displayName,
      'state': 'in_group',
    }, SetOptions(merge: true));
  }

  Future<void> updateMyPosition(String rideId, double lat, double lng) {
    return firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc(currentUserId())
        .set({
      'lat': lat,
      'lng': lng,
      'positionUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateFcmToken(String rideId, String token) {
    return firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .doc(currentUserId())
        .set({'fcmToken': token}, SetOptions(merge: true));
  }

  Stream<List<RiderDoc>> streamRiders(String rideId) {
    return firestore
        .collection('rides')
        .doc(rideId)
        .collection('riders')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => RiderDoc.fromMap(d.id, d.data())).toList());
  }
}
