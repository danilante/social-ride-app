import 'package:flutter/material.dart';
import 'package:social_ride_app/services/ride_repository.dart';
import 'package:social_ride_app/theme.dart';

class HomeScreen extends StatefulWidget {
  final RideRepository rideRepository;
  final void Function(String rideId) onRideReady;

  const HomeScreen({
    super.key,
    required this.rideRepository,
    required this.onRideReady,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nameController = TextEditingController();
  final _rideNameController = TextEditingController();
  final _rideCodeController = TextEditingController();

  bool _requireName() {
    if (_nameController.text.trim().isNotEmpty) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Inserisci il tuo nome')),
    );
    return false;
  }

  Future<void> _createRide() async {
    if (!_requireName()) return;
    final rideId = await widget.rideRepository
        .createRide(_rideNameController.text, _nameController.text.trim());
    widget.onRideReady(rideId);
  }

  Future<void> _joinRide() async {
    if (!_requireName()) return;
    try {
      final rideId = await widget.rideRepository.joinRide(
          _rideCodeController.text.trim(), _nameController.text.trim());
      widget.onRideReady(rideId);
    } on RideNotFoundException {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride non trovata, controlla il codice')),
      );
    }
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: socialRideInk,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.pedal_bike_rounded,
                        color: socialRideOrange, size: 30),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Social Ride',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: socialRideInk,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Pedalate insieme, senza perdervi di vista.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              const SizedBox(height: 28),
              TextField(
                key: const Key('displayNameField'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Il tuo nome',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 24),
              _sectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.add_circle_outline_rounded,
                            color: socialRideOrange),
                        SizedBox(width: 8),
                        Text('Crea una nuova ride',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('rideNameField'),
                      controller: _rideNameController,
                      decoration: const InputDecoration(
                        labelText: 'Nome ride',
                        prefixIcon: Icon(Icons.route_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      key: const Key('createRideButton'),
                      onPressed: _createRide,
                      child: const Text('Crea ride'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _sectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.group_add_outlined,
                            color: socialRideOrange),
                        SizedBox(width: 8),
                        Text('Unisciti a una ride',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('rideCodeField'),
                      controller: _rideCodeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Codice ride',
                        prefixIcon: Icon(Icons.tag_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      key: const Key('joinRideButton'),
                      onPressed: _joinRide,
                      child: const Text('Unisciti'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
