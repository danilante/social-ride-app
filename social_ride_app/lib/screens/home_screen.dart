import 'package:flutter/material.dart';
import 'package:social_ride_app/services/ride_repository.dart';

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

  Future<void> _createRide() async {
    final rideId = await widget.rideRepository
        .createRide(_rideNameController.text, _nameController.text);
    widget.onRideReady(rideId);
  }

  Future<void> _joinRide() async {
    final rideId = await widget.rideRepository
        .joinRide(_rideCodeController.text.trim(), _nameController.text);
    widget.onRideReady(rideId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Social Ride')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              key: const Key('displayNameField'),
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Il tuo nome'),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('rideNameField'),
              controller: _rideNameController,
              decoration: const InputDecoration(labelText: 'Nome ride'),
            ),
            ElevatedButton(
              key: const Key('createRideButton'),
              onPressed: _createRide,
              child: const Text('Crea ride'),
            ),
            const Divider(height: 32),
            TextField(
              key: const Key('rideCodeField'),
              controller: _rideCodeController,
              decoration: const InputDecoration(labelText: 'Codice ride'),
            ),
            ElevatedButton(
              key: const Key('joinRideButton'),
              onPressed: _joinRide,
              child: const Text('Unisciti'),
            ),
          ],
        ),
      ),
    );
  }
}
