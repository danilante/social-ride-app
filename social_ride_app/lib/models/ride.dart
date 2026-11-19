// lib/models/ride.dart
class Ride {
  final String id;
  final String name;
  final String creatorId;
  final String status;
  final double dropoffThresholdMeters;

  Ride({
    required this.id,
    required this.name,
    required this.creatorId,
    required this.status,
    required this.dropoffThresholdMeters,
  });

  factory Ride.fromMap(String id, Map<String, dynamic> data) {
    return Ride(
      id: id,
      name: data['name'] as String? ?? '',
      creatorId: data['creatorId'] as String? ?? '',
      status: data['status'] as String? ?? 'active',
      dropoffThresholdMeters:
          (data['dropoffThresholdMeters'] as num?)?.toDouble() ?? 300,
    );
  }
}
