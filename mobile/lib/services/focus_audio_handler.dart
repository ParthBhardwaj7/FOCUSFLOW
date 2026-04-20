import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// Foreground-capable handler for deep focus loops. Also exposed via [current]
/// for UI control when [AudioService] initialized successfully.
class FocusAudioHandler extends BaseAudioHandler with SeekHandler {
  FocusAudioHandler() {
    FocusAudioHandler.current = this;
    _player = AudioPlayer();
    _player.playbackEventStream.listen((_) => _syncPlaybackState());
    _player.playerStateStream.listen((_) => _syncPlaybackState());
    playbackState.add(
      playbackState.value.copyWith(
        controls: [MediaControl.pause, MediaControl.stop],
        processingState: AudioProcessingState.idle,
      ),
    );
  }

  /// Non-null while an instance exists (set in constructor).
  static FocusAudioHandler? current;

  late final AudioPlayer _player;
  String? _activeAssetPath;

  AudioPlayer get player => _player;

  bool get hasActiveAsset => _activeAssetPath != null;

  /// Looping asset for deep focus. Call [stopDeepFocus] when leaving the session.
  Future<void> playDeepFocusAsset({
    required String assetPath,
    required String title,
  }) async {
    _activeAssetPath = assetPath;
    mediaItem.add(
      MediaItem(
        id: assetPath,
        title: title,
        album: 'FocusFlow',
      ),
    );
    try {
      await _player.setAudioSource(AudioSource.asset(assetPath));
      await _player.setLoopMode(LoopMode.one);
      await _player.play();
    } catch (_) {
      _activeAssetPath = null;
      rethrow;
    }
    _syncPlaybackState();
  }

  Future<void> pauseDeepFocus() async {
    await _player.pause();
    _syncPlaybackState();
  }

  Future<void> resumeDeepFocus() async {
    if (_activeAssetPath == null) return;
    await _player.play();
    _syncPlaybackState();
  }

  Future<void> stopDeepFocus() async {
    _activeAssetPath = null;
    await _player.stop();
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  void _syncPlaybackState() {
    final playing = _player.playing;
    final proc = _player.processingState;
    AudioProcessingState p;
    switch (proc) {
      case ProcessingState.idle:
        p = AudioProcessingState.idle;
        break;
      case ProcessingState.loading:
        p = AudioProcessingState.loading;
        break;
      case ProcessingState.buffering:
        p = AudioProcessingState.buffering;
        break;
      case ProcessingState.ready:
        p = AudioProcessingState.ready;
        break;
      case ProcessingState.completed:
        p = AudioProcessingState.completed;
        break;
    }
    playbackState.add(
      playbackState.value.copyWith(
        controls: [MediaControl.pause, MediaControl.stop],
        processingState: p,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
      ),
    );
  }

  @override
  Future<void> play() async {
    await _player.play();
    _syncPlaybackState();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _syncPlaybackState();
  }

  @override
  Future<void> onTaskRemoved() async {
    await stopDeepFocus();
    await super.onTaskRemoved();
  }

  @override
  Future<void> stop() async {
    await stopDeepFocus();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);
}
