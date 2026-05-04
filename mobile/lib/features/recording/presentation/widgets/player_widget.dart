import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/session/focusflow_client.dart';
import '../../domain/recording_model.dart';

/// Plays local file first; optional [remoteUrl] with [authHeaderProvider] for online stream.
class RecordingPlayerWidget extends StatefulWidget {
  const RecordingPlayerWidget({
    super.key,
    required this.recording,
    this.remoteUrl,
    this.authHeaderProvider,
  });

  final RecordingModel recording;
  final String? remoteUrl;
  final Future<Map<String, String>> Function()? authHeaderProvider;

  @override
  State<RecordingPlayerWidget> createState() => _RecordingPlayerWidgetState();
}

class _RecordingPlayerWidgetState extends State<RecordingPlayerWidget> {
  late final AudioPlayer _player;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _load();
  }

  Future<void> _load() async {
    final local = File(widget.recording.localPath);
    if (await local.exists()) {
      await _player.setFilePath(widget.recording.localPath);
      return;
    }
    final remote = widget.remoteUrl;
    if (remote != null && remote.isNotEmpty) {
      final headers = await widget.authHeaderProvider?.call() ?? {};
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(remote), headers: headers),
      );
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StreamBuilder<PlayerState>(
          stream: _player.playerStateStream,
          initialData: _player.playerState,
          builder: (context, snap) {
            final playing = snap.data?.playing ?? false;
            return StreamBuilder<Duration?>(
              stream: _player.durationStream,
              initialData: _player.duration,
              builder: (context, durSnap) {
                final total = durSnap.data ?? Duration.zero;
                return StreamBuilder<Duration>(
                  stream: _player.positionStream,
                  initialData: _player.position,
                  builder: (context, posSnap) {
                    final cur = posSnap.data ?? Duration.zero;
                    final maxMs = total.inMilliseconds <= 0 ? 1 : total.inMilliseconds;
                    final v = cur.inMilliseconds / maxMs;
                    return Column(
                      children: [
                        Slider(
                          value: v.clamp(0.0, 1.0),
                          onChanged: (x) async {
                            final ms = (x * maxMs).round();
                            await _player.seek(Duration(milliseconds: ms));
                          },
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _fmt(cur),
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              _fmt(total),
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton.filledTonal(
                              iconSize: 40,
                              onPressed: () async {
                                if (playing) {
                                  await _player.pause();
                                } else {
                                  await _player.play();
                                }
                              },
                              icon: Icon(
                                playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }
}

Future<Map<String, String>> recordingStreamAuthHeaders(
  FocusFlowClient client,
) async {
  final t = await client.readAccessToken();
  if (t == null || t.isEmpty) return {};
  return {'Authorization': 'Bearer $t'};
}
