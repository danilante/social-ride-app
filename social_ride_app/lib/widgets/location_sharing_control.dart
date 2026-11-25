import 'package:flutter/material.dart';

/// UI states for the "start sharing location" control on the ride screen.
enum LocationSharingStatus { idle, requesting, sharing, denied }

/// Button / status chip that starts GPS sharing or shows permission errors.
/// Keys are stable for existing widget tests (`startRideButton`,
/// `retryLocationButton`).
class LocationSharingControl extends StatelessWidget {
  final LocationSharingStatus status;
  final VoidCallback onStartOrRetry;

  const LocationSharingControl({
    super.key,
    required this.status,
    required this.onStartOrRetry,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case LocationSharingStatus.idle:
        return ElevatedButton.icon(
          key: const Key('startRideButton'),
          onPressed: onStartOrRetry,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Avvia ride'),
        );
      case LocationSharingStatus.requesting:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        );
      case LocationSharingStatus.sharing:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F6EC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on_rounded,
                  color: Color(0xFF2E9E53), size: 24),
              SizedBox(width: 8),
              Text(
                'Condivisione posizione attiva',
                style: TextStyle(
                  color: Color(0xFF1F7A3F),
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        );
      case LocationSharingStatus.denied:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_off_rounded,
                    color: Colors.redAccent, size: 24),
                SizedBox(width: 8),
                Text('Permesso posizione negato',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('retryLocationButton'),
              onPressed: onStartOrRetry,
              child: const Text('Riprova'),
            ),
          ],
        );
    }
  }
}
