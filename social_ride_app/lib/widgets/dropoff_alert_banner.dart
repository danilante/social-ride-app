import 'package:flutter/material.dart';
import 'package:social_ride_app/models/rider_doc.dart';

/// Banner listing riders (other than [currentUserId]) currently marked
/// `dropped_off`, with optional "Centra mappa" actions.
class DropoffAlertBanner extends StatelessWidget {
  final List<RiderDoc> riders;
  final String currentUserId;
  final void Function(RiderDoc rider) onCenterMap;

  const DropoffAlertBanner({
    super.key,
    required this.riders,
    required this.currentUserId,
    required this.onCenterMap,
  });

  @override
  Widget build(BuildContext context) {
    final droppedOff = riders
        .where((r) =>
            r.state == RiderState.droppedOff && r.userId != currentUserId)
        .toList();
    if (droppedOff.isEmpty) return const SizedBox.shrink();

    return Container(
      key: const Key('dropoffAlertBanner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE9E4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFC7B8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: droppedOff.map((r) {
          final hasPosition = r.lat != null && r.lng != null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_rounded, color: Color(0xFFD9461E)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${r.displayName} si è staccato dal gruppo'
                    '${r.distanceFromGroupMeters != null ? " (~${r.distanceFromGroupMeters!.round()}m)" : ""}',
                    style: const TextStyle(
                      color: Color(0xFFD9461E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (hasPosition)
                  TextButton(
                    key: Key('centerOnDroppedRider_${r.userId}'),
                    onPressed: () => onCenterMap(r),
                    child: const Text('Centra mappa'),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
