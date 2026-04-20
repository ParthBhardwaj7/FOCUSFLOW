import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'focus_audio_handler.dart';

/// [AudioService.init] is slow on cold start (Android service bind). Call from
/// deep focus only so the rest of the app launches quickly.
class AudioServiceBootstrap {
  static Future<void>? _pending;

  static Future<void> ensureInitialized() {
    return _pending ??= _init();
  }

  static Future<void> _init() async {
    try {
      await AudioService.init(
        builder: FocusAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.focusflow.app.focus',
          androidNotificationChannelName: 'FocusFlow focus',
          androidNotificationOngoing: true,
        ),
      );
    } catch (e, st) {
      debugPrint('AudioService init skipped: $e\n$st');
    }
  }
}
