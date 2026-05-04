import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../inbox/inbox_providers.dart';
import '../domain/recording_model.dart';
import '../domain/recording_state.dart';
import 'recording_controller.dart';
import 'recording_providers.dart';
import 'widgets/player_widget.dart';
import 'widgets/recording_list_tile.dart';
import 'widgets/waveform_widget.dart';

class RecordingScreen extends ConsumerStatefulWidget {
  const RecordingScreen({super.key});

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen> {
  Future<void> _openPlayer(RecordingModel r) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(r.fileName, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              RecordingPlayerWidget(
                recording: r,
                remoteUrl: r.remoteUrl,
                authHeaderProvider: () async {
                  final c = ref.read(focusFlowClientProvider);
                  return recordingStreamAuthHeaders(c);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _afterSaveSync() async {
    final net = ref.read(connectivityProvider).value;
    if (net != null && inboxConnectivityLooksOffline(net)) return;
    await ref.read(recordingRepositoryProvider).syncPendingUploads();
    ref.invalidate(recordingsListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ctrl = ref.watch(recordingControllerProvider);
    final listAsync = ref.watch(recordingsListProvider);

    ref.listen<RecordingController>(recordingControllerProvider, (prev, next) {
      final was = prev?.lastSaved?.id;
      final now = next.lastSaved?.id;
      if (now != null && now != was) {
        ref.invalidate(recordingsListProvider);
        unawaited(_afterSaveSync());
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice recordings'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            'Offline-first: files stay on this device. When you are signed in and online, uploads run in the background.',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          _buildMainCard(context, ctrl, scheme),
          const SizedBox(height: 28),
          Text(
            'LIBRARY',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          listAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Text('$e'),
            data: (items) {
              if (items.isEmpty) {
                return Text(
                  'No recordings yet.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                );
              }
              return Column(
                children: [
                  for (final r in items)
                    RecordingListTile(
                      recording: r,
                      onPlay: () => _openPlayer(r),
                      onUpload: r.isSynced || r.permanentlyFailed
                          ? null
                          : () async {
                              await ref.read(recordingRepositoryProvider).uploadNow(r);
                              if (context.mounted) {
                                ref.invalidate(recordingsListProvider);
                              }
                            },
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMainCard(
    BuildContext context,
    RecordingController ctrl,
    ColorScheme scheme,
  ) {
    switch (ctrl.uiState) {
      case RecordingUiState.error:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ctrl.errorMessage ?? 'Something went wrong',
                  style: TextStyle(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: ctrl.acknowledgeError,
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        );
      case RecordingUiState.recording:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const RecordingWaveformWidget(active: true),
                const SizedBox(height: 16),
                ValueListenableBuilder<Duration>(
                  valueListenable: ctrl.elapsedListenable,
                  builder: (_, d, _) {
                    final m = d.inMinutes.remainder(1000).toString().padLeft(2, '0');
                    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
                    return Text(
                      '$m:$s',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: scheme.onSurface,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Max ${RecordingController.maxDuration.inMinutes} min',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 20),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error.withValues(alpha: 0.15),
                    foregroundColor: scheme.error,
                  ),
                  onPressed: () => ctrl.stopRecording(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'STOP',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case RecordingUiState.recorded:
        final r = ctrl.lastSaved!;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Saved',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                RecordingPlayerWidget(
                  recording: r,
                  remoteUrl: r.remoteUrl,
                  authHeaderProvider: () async {
                    final c = ref.read(focusFlowClientProvider);
                    return recordingStreamAuthHeaders(c);
                  },
                ),
                const SizedBox(height: 16),
                Consumer(
                  builder: (context, ref, _) {
                    final net = ref.watch(connectivityProvider).value;
                    final offline =
                        net != null && inboxConnectivityLooksOffline(net);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (offline)
                          Text(
                            'Will sync when you are online.',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          )
                        else
                          FilledButton(
                            onPressed: () async {
                              await ref.read(recordingRepositoryProvider).uploadNow(r);
                              ref.invalidate(recordingsListProvider);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Upload started'),
                                  ),
                                );
                              }
                            },
                            child: const Text('Upload now'),
                          ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: ctrl.clearRecordedPreview,
                          child: const Text('Record again'),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      case RecordingUiState.idle:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.mic_rounded, size: 56, color: scheme.primary),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ctrl.startRecording(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    child: Text(
                      'Start recording',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}
