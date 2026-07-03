import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speaks short warning phrases using the device text-to-speech engine,
/// preferring an English female voice. Used for the dew-point out-of-range
/// alert on the home screen.
class VoiceAlertService {
  static final VoiceAlertService _instance = VoiceAlertService._internal();
  factory VoiceAlertService() => _instance;
  VoiceAlertService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5); // ~normal pace on Android
      await _tts.setPitch(1.05); // slightly brighter, reads as female
      await _tts.setVolume(1.0);
      await _selectFemaleVoice();
      _ready = true;
    } catch (e) {
      // TTS engine may be missing/disabled — alerts just won't be spoken.
      debugPrint('VoiceAlertService init failed: $e');
    }
  }

  /// Try to pick an English "female" voice if the engine exposes one.
  Future<void> _selectFemaleVoice() async {
    try {
      final voices = await _tts.getVoices;
      if (voices is List) {
        for (final v in voices) {
          if (v is Map) {
            final name = (v['name'] ?? '').toString().toLowerCase();
            final locale = (v['locale'] ?? '').toString().toLowerCase();
            if (locale.startsWith('en') && name.contains('female')) {
              await _tts.setVoice({
                'name': v['name'].toString(),
                'locale': v['locale'].toString(),
              });
              return;
            }
          }
        }
      }
    } catch (e) {
      // Fall back to the default voice (usually female for en-US).
      debugPrint('VoiceAlertService voice selection failed: $e');
    }
  }

  Future<void> speak(String text) async {
    if (!_ready) await init();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('VoiceAlertService speak failed: $e');
    }
  }

  /// Spoken when the dew point leaves the permitted range.
  Future<void> speakDewPointOutOfRange() =>
      speak('Warning. Dew point is out of range.');

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
