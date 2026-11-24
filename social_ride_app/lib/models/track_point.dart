import 'package:cloud_firestore/cloud_firestore.dart';

class TrackPoint {
  final double lat;
  final double lng;
  final DateTime? recordedAt;

  TrackPoint({required this.lat, required this.lng, this.recordedAt});

  factory TrackPoint.fromMap(Map<String, dynamic> data) {
    final rawTimestamp = data['recordedAt'];
    return TrackPoint(
      lat: (data['lat'] as num).toDouble(),
      lng: (data['lng'] as num).toDouble(),
      recordedAt:
          rawTimestamp is Timestamp ? rawTimestamp.toDate() : null,
    );
  }
}
