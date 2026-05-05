import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Voice capture for inbox quick entry: **audio only** (same pattern as
/// [RecordingController] / Voice recordings). Parallel STT competed for the mic
/// on some Android builds and broke recording.
class InboxVoiceController extends ChangeNotifier {
  InboxVoiceController() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;

  InboxVoiceState _state = InboxVoiceState.idle;
  String? _audioPath;
  Duration _elapsed = Duration.zero;
  Timer? _tick;
  bool _micPermanentlyDenied = false;

  InboxVoiceState get voiceState => _state;
  String? get recordedAudioPath => _audioPath;
  Duration get elapsed => _elapsed;
  bool get micPermanentlyDenied => _micPermanentlyDenied;

  static const maxDuration = Duration(seconds: 60);

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

    notifyListeners();
  }

  Future<InboxVoiceStopResult> stopSession({
    bool hitMaxDuration = false,
  }) async {
    if (_state != InboxVoiceState.recording) {
      return const InboxVoiceStopResult(
        hadRecording: false,
        hitMaxDuration: false,
      );
    }

    _tick?.cancel();
    _tick = null;

    final startedPath = _audioPath;

    String? path = startedPath;
    try {
      final stopped = await _recorder.stop();
      if (stopped != null && stopped.trim().isNotEmpty) {
        path = stopped.trim();
      }
    } catch (_) {
      path = startedPath;
    }

    _state = InboxVoiceState.idle;
    _audioPath = null;
    _elapsed = Duration.zero;
    notifyListeners();

    return InboxVoiceStopResult(
      audioPath: path,
      hadRecording: path != null && path.isNotEmpty,
      hitMaxDuration: hitMaxDuration,
    );
  }

  Future<void> discardSession() async {
    _tick?.cancel();
    _tick = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    final p = _audioPath;
    _state = InboxVoiceState.idle;
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
    required this.hadRecording,
    required this.hitMaxDuration,
    this.audioPath,
  });

  final String? audioPath;
  final bool hadRecording;
  final bool hitMaxDuration;
}
