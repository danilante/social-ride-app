import 'package:flutter_tts/flutter_tts.dart';

/// Speaks the default drop-off alert when a rider never recorded a personal
/// clip, so the alert still names who dropped off instead of staying silent.
abstract class DropoffAlertSpeaker {
  Future<void> speak(String text);
}

class FlutterTtsDropoffAlertSpeaker implements DropoffAlertSpeaker {
  final FlutterTts _tts;
  bool _languageSet = false;

  FlutterTtsDropoffAlertSpeaker({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  @override
  Future<void> speak(String text) async {
    if (!_languageSet) {
      await _tts.setLanguage('it-IT');
      _languageSet = true;
    }
    await _tts.speak(text);
  }
}
