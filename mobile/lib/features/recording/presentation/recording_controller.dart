import 'dart:async';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../../core/client_error_report.dart';
import '../../../core/session/focusflow_client.dart';
import '../../../core/user_facing_errors.dart';
import '../data/recording_repository.dart';
import '../domain/recording_model.dart';
import '../domain/recording_state.dart';

/// Session capture: same core flow as inbox ([AudioRecorder], AAC, stop flushes file),
/// but files live under **app documents** and metadata is persisted for sync.
class RecordingController extends ChangeNotifier {
  RecordingController({
    required RecordingRepository repository,
    FocusFlowClient? telemetryClient,
  }) : _repository = repository,
       _telemetryClient = telemetryClient,
       _recorder = AudioRecorder();

  final RecordingRepository _repository;
  final FocusFlowClient? _telemetryClient;
  final AudioRecorder _recorder;

  RecordingUiState _ui = RecordingUiState.idle;
  String? _errorMessage;
  RecordingModel? _lastSaved;
  String? _activePath;
  String? _activeId;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _tick;

  /// UI timer only — avoids rebuilding the whole screen every second.
  final ValueNotifier<Duration> elapsedListenable = ValueNotifier(Duration.zero);

  RecordingUiState get uiState => _ui;
  String? get errorMessage => _errorMessage;
  RecordingModel? get lastSaved => _lastSaved;
  Duration get elapsed => _stopwatch.elapsed;

  static const maxDuration = Duration(minutes: 5);
  static const minBytes = 1000;

  Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    if (status.isPermanentlyDenied) {
      await AppSettings.openAppSettings();
      return false;
    }
    return status.isGranted;
  }

  Future<void> startRecording() async {
    if (_ui == RecordingUiState.recording) return;
    _errorMessage = null;
    _lastSaved = null;

    final ok = await requestMicPermission();
    if (!ok) {
      _ui = RecordingUiState.error;
      _errorMessage = 'Microphone permission is required to record.';
      notifyListeners();
      return;
    }

    final (id, path) = await _repository.allocateNewRecordingPath();
    _activeId = id;
    _activePath = path;

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
      _activePath = null;
      _activeId = null;
      _ui = RecordingUiState.error;
      _errorMessage = userFacingError(e);
      scheduleClientErrorReport(
        _telemetryClient,
        e,
        errorType: 'recording_start',
        screen: 'VoiceRecordings',
      );
      notifyListeners();
      return;
    }

    _stopwatch.reset();
    elapsedListenable.value = Duration.zero;
    _stopwatch.start();
    _ui = RecordingUiState.recording;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsedListenable.value = _stopwatch.elapsed;
      if (_stopwatch.elapsed >= maxDuration) {
        unawaited(stopRecording(hitMaxDuration: true));
      }
    });
    notifyListeners();
  }

  Future<void> stopRecording({bool hitMaxDuration = false}) async {
    if (_ui != RecordingUiState.recording) return;

    _tick?.cancel();
    _tick = null;
    _stopwatch.stop();
    elapsedListenable.value = _stopwatch.elapsed;

    final startedPath = _activePath;
    final id = _activeId;

    String? path = startedPath;
    try {
      final stopped = await _recorder.stop();
      if (stopped != null && stopped.trim().isNotEmpty) {
        path = stopped.trim();
      }
    } catch (_) {
      path = startedPath;
    }

    _activePath = null;
    _activeId = null;
    _ui = RecordingUiState.idle;

    if (path == null || path.isEmpty || id == null) {
      _errorMessage = 'Recording did not produce a file.';
      _ui = RecordingUiState.error;
      scheduleClientErrorReportRaw(
        _telemetryClient,
        errorType: 'recording_stop_empty',
        message: 'stop() empty path; startedPath=$startedPath id=$id',
        surfaceMessage: _errorMessage!,
        screen: 'VoiceRecordings',
      );
      notifyListeners();
      return;
    }

    final file = File(path);
    if (!await file.exists()) {
      _errorMessage = 'Recording file was not found on disk.';
      _ui = RecordingUiState.error;
      scheduleClientErrorReportRaw(
        _telemetryClient,
        errorType: 'recording_file_missing',
        message: 'Missing file at path=$path',
        surfaceMessage: _errorMessage!,
        screen: 'VoiceRecordings',
      );
      notifyListeners();
      return;
    }

    final size = await file.length();
    if (size < minBytes) {
      try {
        await file.delete();
      } catch (_) {}
      _errorMessage = hitMaxDuration
          ? 'Recording was too short to save.'
          : null;
      _ui = _errorMessage != null ? RecordingUiState.error : RecordingUiState.idle;
      notifyListeners();
      return;
    }

    final secs = _stopwatch.elapsed.inSeconds.clamp(1, 99999);
    final model = RecordingModel(
      id: id,
      localPath: path,
      fileName: path.replaceAll('\\', '/').split('/').last,
      durationSeconds: secs,
      fileSizeBytes: size,
      createdAt: DateTime.now(),
      isSynced: false,
    );
    await _repository.saveNew(model);
    _lastSaved = model;
    _ui = RecordingUiState.recorded;
    _errorMessage = null;
    elapsedListenable.value = Duration.zero;
    notifyListeners();
  }

  void clearRecordedPreview() {
    _lastSaved = null;
    _ui = RecordingUiState.idle;
    notifyListeners();
  }

  void acknowledgeError() {
    _errorMessage = null;
    _ui = RecordingUiState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _tick?.cancel();
    elapsedListenable.dispose();
    unawaited(_recorder.dispose());
    super.dispose();
  }
}
