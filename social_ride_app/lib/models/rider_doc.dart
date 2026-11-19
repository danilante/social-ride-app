// lib/models/rider_doc.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum RiderState { inGroup, droppedOff }

RiderState riderStateFromString(String value) =>
    value == 'dropped_off' ? RiderState.droppedOff : RiderState.inGroup;

String riderStateToString(RiderState state) =>
    state == RiderState.droppedOff ? 'dropped_off' : 'in_group';

class RiderDoc {
  final String userId;
  final String displayName;
  final double? lat;
  final double? lng;
  final DateTime? positionUpdatedAt;
  final RiderState state;
  final double? distanceFromGroupMeters;

  RiderDoc({
    required this.userId,
    required this.displayName,
    this.lat,
    this.lng,
    this.positionUpdatedAt,
    this.state = RiderState.inGroup,
    this.distanceFromGroupMeters,
  });

  factory RiderDoc.fromMap(String userId, Map<String, dynamic> data) {
    final rawTimestamp = data['positionUpdatedAt'];
    DateTime? updatedAt;
    if (rawTimestamp is Timestamp) {
      updatedAt = rawTimestamp.toDate();
    }
    return RiderDoc(
      userId: userId,
      displayName: data['displayName'] as String? ?? '',
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      positionUpdatedAt: updatedAt,
      state: riderStateFromString(data['state'] as String? ?? 'in_group'),
      distanceFromGroupMeters:
          (data['distanceFromGroupMeters'] as num?)?.toDouble(),
    );
  }
}
