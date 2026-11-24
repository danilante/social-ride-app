import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_ride_app/screens/dropoff_audio_sheet.dart';
import 'package:social_ride_app/services/dropoff_recorder.dart';

class _FakeRecorder implements DropoffRecorder {
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<String?> stop() async => null;
  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('shows the record and upload actions when no audio is set',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DropoffAudioSheet(
          currentAudioUrl: null,
          myDisplayName: 'Mario',
          recorder: _FakeRecorder(),
          onApply: (_) {},
          onRemove: () {},
        ),
      ),
    ));

    expect(find.byKey(const Key('recordDropoffAudioButton')), findsOneWidget);
    expect(find.byKey(const Key('uploadDropoffAudioButton')), findsOneWidget);
    expect(find.byKey(const Key('removeDropoffAudioButton')), findsNothing);
  });
}
