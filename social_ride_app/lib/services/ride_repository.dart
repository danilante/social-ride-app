import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:social_ride_app/models/rider_doc.dart';

class RideNotFoundException implements Exception {
  final String rideId;
  RideNotFoundException(this.rideId);

  @override
  String toString() => 'Ride not found: $rideId';
}

class RideRepository {
  final FirebaseFirestore firestore;
  final String Function() currentUserId;

  RideRepository({required this.firestore, required this.currentUserId});

  Future<String> createRide(String rideName, String displayName) async {
    final rideRef = firestore.collection('rides').doc();
    await rideRef.set({
      'name': rideName,
      'creatorId': currentUserId(),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'dropoffThresholdMeters': 300,
    });
    await _addRider(rideRef.id, displayName);
    return rideRef.id;
  }

  Future<void> joinRide(String rideId, String displayName) async {
    final rideDoc = await firestore.collection('rides').doc(rideId).get();
    if (!rideDoc.exists) {
      throw RideNotFoundException(rideId);
    }
    await _addRider(rideId, displayName);
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
