import 'package:flutter/material.dart';
import 'package:social_ride_app/theme.dart';

/// Bottom sheet body for editing drop-off threshold and dwell time.
/// Keys match existing tests (`dropoffThresholdSlider`, etc.).
class RideSettingsSheet extends StatefulWidget {
  final double initialThresholdMeters;
  final int initialDwellSeconds;
  final Future<void> Function(double meters, int seconds) onSave;

  const RideSettingsSheet({
    super.key,
    required this.initialThresholdMeters,
    required this.initialDwellSeconds,
    required this.onSave,
  });

  @override
  State<RideSettingsSheet> createState() => _RideSettingsSheetState();
}

class _RideSettingsSheetState extends State<RideSettingsSheet> {
  late double _meters;
  late int _seconds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _meters = widget.initialThresholdMeters;
    _seconds = widget.initialDwellSeconds;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_meters, _seconds);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, color: socialRideOrange),
              SizedBox(width: 8),
              Text(
                'Impostazioni ride',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Decidi quanto deve allontanarsi e per quanto tempo un rider '
            'prima di essere segnalato come staccato dal gruppo.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Text(
            'Distanza di stacco: ${_meters.round()}m',
            key: const Key('dropoffThresholdLabel'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Slider(
            key: const Key('dropoffThresholdSlider'),
            value: _meters,
            min: 50,
            max: 1000,
            divisions: 19,
            activeColor: socialRideOrange,
            label: '${_meters.round()}m',
            onChanged: (v) => setState(() => _meters = v),
          ),
          const SizedBox(height: 12),
          Text(
            'Tempo prima dello stacco: ${_seconds}s',
            key: const Key('dropoffDwellLabel'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Slider(
            key: const Key('dropoffDwellSlider'),
            value: _seconds.toDouble(),
            min: 10,
            max: 300,
            divisions: 29,
            activeColor: socialRideOrange,
            label: '${_seconds}s',
            onChanged: (v) => setState(() => _seconds = v.round()),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            key: const Key('saveRideSettingsButton'),
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(_saving ? 'Salvataggio…' : 'Salva impostazioni'),
          ),
        ],
      ),
    );
  }
}
