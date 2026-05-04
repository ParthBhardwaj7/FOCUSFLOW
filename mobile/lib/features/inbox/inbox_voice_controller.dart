import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Voice capture: parallel file recording + speech-to-text (hi-IN / en-US).
/// UI binds to [InboxVoiceState] via [ValueNotifier] or listens to [notifyListeners].
class InboxVoiceController extends ChangeNotifier {
  InboxVoiceController()
    : _speech = stt.SpeechToText(),
      _recorder = AudioRecorder();

  final stt.SpeechToText _speech;
  final AudioRecorder _recorder;

  InboxVoiceState _state = InboxVoiceState.idle;
  String _interim = '';
  String _finalText = '';
  String? _audioPath;
  Duration _elapsed = Duration.zero;
  Timer? _tick;
  bool _micPermanentlyDenied = false;
  bool _initialized = false;

  InboxVoiceState get voiceState => _state;
  String get interimTranscript => _interim;
  String? get recordedAudioPath => _audioPath;
  Duration get elapsed => _elapsed;
  bool get micPermanentlyDenied => _micPermanentlyDenied;

  static const maxDuration = Duration(seconds: 60);

  Future<bool> ensureSpeechEngine() async {
    if (_initialized) return _speech.isAvailable;
    _initialized = await _speech.initialize(
      onStatus: (s) {
        if (kDebugMode) debugPrint('speech_to_text status: $s');
      },
      onError: (e) {
        if (kDebugMode) debugPrint('speech_to_text error: $e');
      },
    );
    return _initialized && _speech.isAvailable;
  }

  Future<String> _pickLocaleId() async {
    final localesList = await _speech.locales();
    final locales = localesList.map((e) => e.localeId).toList();
    if (locales.contains('hi-IN')) return 'hi-IN';
    if (locales.contains('en-US')) return 'en-US';
    if (locales.isNotEmpty) return locales.first;
    return 'en-US';
  }

  Future<PermissionStatus> requestMicPermission() async {
    final s = await Permission.microphone.request();
    if (s == PermissionStatus.permanentlyDenied) {
      _micPermanentlyDenied = true;
      notifyListeners();
    }
    return s;
  }

  /// After the user returns from system settings, clear the stuck “permanent” flag if mic is on.
  void refreshMicPermissionFlag() {
    unawaited(
      Permission.microphone.status.then((st) {
        if (st.isGranted && _micPermanentlyDenied) {
          _micPermanentlyDenied = false;
          notifyListeners();
        }
      }),
    );
  }

  Future<void> startSession() async {
    if (_state == InboxVoiceState.recording) return;
    final perm = await requestMicPermission();
    if (perm != PermissionStatus.granted) {
      _state = InboxVoiceState.permissionDenied;
      notifyListeners();
      return;
    }

    await ensureSpeechEngine();
    _interim = '';
    _finalText = '';
    _audioPath = null;
    _elapsed = Duration.zero;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/ff_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('record start failed: $e');
      _state = InboxVoiceState.error;
      notifyListeners();
      return;
    }

    _audioPath = path;
    _state = InboxVoiceState.recording;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += const Duration(seconds: 1);
      notifyListeners();
      if (_elapsed >= maxDuration) {
        unawaited(stopSession(hitMaxDuration: true));
      }
    });

    final localeId = await _pickLocaleId();
    if (_speech.isAvailable) {
      unawaited(
        _speech.listen(
          onResult: (r) {
            _interim = r.recognizedWords;
            if (r.finalResult) {
              _finalText = r.recognizedWords;
            }
            notifyListeners();
          },
          listenOptions: stt.SpeechListenOptions(
            listenMode: stt.ListenMode.dictation,
            partialResults: true,
            cancelOnError: false,
          ),
          localeId: localeId,
        ),
      );
    }

    notifyListeners();
  }

  Future<InboxVoiceStopResult> stopSession({
    bool hitMaxDuration = false,
  }) async {
    if (_state != InboxVoiceState.recording) {
      return const InboxVoiceStopResult(
        text: '',
        hadRecording: false,
        hitMaxDuration: false,
      );
    }

    _tick?.cancel();
    _tick = null;

    // Capture path before stopping — [AudioRecorder.stop] may return the path
    // or null on some devices; temp path from [start] is the fallback.
    final startedPath = _audioPath;

    // Stop **recorder first** so the m4a is flushed and closed. Stopping STT
    // first can starve or reset mic capture on some Android devices, yielding
    // an empty or missing file while transcript still updates.
    String? path = startedPath;
    try {
      final stopped = await _recorder.stop();
      if (stopped != null && stopped.trim().isNotEmpty) {
        path = stopped.trim();
      }
    } catch (_) {
      path = startedPath;
    }

    try {
      await _speech.stop();
    } catch (_) {}

    _state = InboxVoiceState.idle;
    final text = (_finalText.trim().isNotEmpty ? _finalText : _interim).trim();
    _interim = '';
    _finalText = '';
    _audioPath = null;
    _elapsed = Duration.zero;
    notifyListeners();

    return InboxVoiceStopResult(
      text: text,
      audioPath: path,
      hadRecording: path != null && path.isNotEmpty,
      hitMaxDuration: hitMaxDuration,
      // Transcription is optional / coming soon — never treat empty STT as a user-facing failure.
      transcriptionFailed: false,
    );
  }

  Future<void> discardSession() async {
    _tick?.cancel();
    _tick = null;
    try {
      await _speech.stop();
    } catch (_) {}
    try {
      await _recorder.stop();
    } catch (_) {}
    final p = _audioPath;
    _state = InboxVoiceState.idle;
    _interim = '';
    _finalText = '';
    _audioPath = null;
    _elapsed = Duration.zero;
    notifyListeners();
    if (p != null) {
      try {
        final f = File(p);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }
}

enum InboxVoiceState { idle, recording, permissionDenied, error }

class InboxVoiceStopResult {
  const InboxVoiceStopResult({
    required this.text,
    this.audioPath,
    required this.hadRecording,
    required this.hitMaxDuration,
    this.transcriptionFailed = false,
  });

  final String text;
  final String? audioPath;
  final bool hadRecording;
  final bool hitMaxDuration;
  final bool transcriptionFailed;
}
