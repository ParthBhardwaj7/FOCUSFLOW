import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../timeline/timeline_tokens.dart';
import 'deep_focus_tracks.dart';

/// User-chosen session length and optional bundled track.
class DeepFocusPrepResult {
  const DeepFocusPrepResult({
    required this.durationSec,
    this.audioAssetPath,
  });

  final int durationSec;
  final String? audioAssetPath;
}

const _kDurationOptionsMin = [15, 25, 30, 45, 60, 90, 120];

/// Returns null if dismissed without starting.
Future<DeepFocusPrepResult?> showDeepFocusPrepSheet(
  BuildContext context, {
  required String taskTitle,
  required int maxDurationSec,
  int? suggestedDurationSec,
}) {
  return showModalBottomSheet<DeepFocusPrepResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TimelineTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _DeepFocusPrepBody(
      taskTitle: taskTitle,
      maxDurationSec: maxDurationSec,
      suggestedDurationSec: suggestedDurationSec,
    ),
  );
}

class _DeepFocusPrepBody extends ConsumerStatefulWidget {
  const _DeepFocusPrepBody({
    required this.taskTitle,
    required this.maxDurationSec,
    required this.suggestedDurationSec,
  });

  final String taskTitle;
  final int maxDurationSec;
  final int? suggestedDurationSec;

  @override
  ConsumerState<_DeepFocusPrepBody> createState() => _DeepFocusPrepBodyState();
}

class _DeepFocusPrepBodyState extends ConsumerState<_DeepFocusPrepBody> {
  late int _selectedMin;
  String? _trackPath;

  List<int> get _chips {
    if (widget.maxDurationSec < 60) {
      return [1];
    }
    final maxM = (widget.maxDurationSec / 60).floor().clamp(1, 10000);
    final out = _kDurationOptionsMin.where((m) => m <= maxM).toList();
    if (out.isEmpty) {
      return [maxM];
    }
    if (!out.contains(maxM)) {
      out.add(maxM);
      out.sort();
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    final chips = _chips;
    final suggestedMin = widget.suggestedDurationSec != null
        ? (widget.suggestedDurationSec! / 60).round().clamp(1, 10000)
        : null;
    var pick = chips.last;
    if (suggestedMin != null) {
      for (final c in chips) {
        if (c <= suggestedMin) pick = c;
      }
    }
    if (!chips.contains(pick)) pick = chips.last;
    _selectedMin = pick;
  }

  @override
  Widget build(BuildContext context) {
    final tracksAsync = ref.watch(deepFocusTracksProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: TimelineTokens.muted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Deep focus',
            style: TextStyle(
              color: TimelineTokens.text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.taskTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: TimelineTokens.muted,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Duration',
            style: TextStyle(
              color: TimelineTokens.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _chips.map((m) {
              final sel = m == _selectedMin;
              final label = widget.maxDurationSec < 60
                  ? '${widget.maxDurationSec}s'
                  : '${m}m';
              return ChoiceChip(
                label: Text(label),
                selected: sel,
                onSelected: (_) => setState(() => _selectedMin = m),
                selectedColor: TimelineTokens.accent,
                labelStyle: TextStyle(
                  color: sel ? Colors.white : TimelineTokens.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                backgroundColor: TimelineTokens.card,
                side: BorderSide(
                  color: sel ? TimelineTokens.accent : TimelineTokens.border,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text(
            'Sound (loops for whole session)',
            style: TextStyle(
              color: TimelineTokens.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          tracksAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => Text(
              'Could not load track list: $err',
              style: TextStyle(color: TimelineTokens.muted),
            ),
            data: (tracks) {
              if (tracks.isEmpty) {
                return Text(
                  'Add audio files to assets/deep_focus_audio/ in the project, then rebuild the app.',
                  style: TextStyle(
                    color: TimelineTokens.muted.withValues(alpha: 0.95),
                    fontSize: 13,
                    height: 1.35,
                  ),
                );
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      title: Text('No sound', style: TextStyle(color: TimelineTokens.text)),
                      selected: _trackPath == null,
                      selectedTileColor: TimelineTokens.accent.withValues(alpha: 0.12),
                      onTap: () => setState(() => _trackPath = null),
                      trailing: _trackPath == null
                          ? const Icon(Icons.check, color: TimelineTokens.accent)
                          : null,
                    ),
                    ...tracks.map(
                      (t) => ListTile(
                        title: Text(t.displayName, style: const TextStyle(color: TimelineTokens.text)),
                        selected: _trackPath == t.assetPath,
                        selectedTileColor: TimelineTokens.accent.withValues(alpha: 0.12),
                        onTap: () => setState(() => _trackPath = t.assetPath),
                        trailing: _trackPath == t.assetPath
                            ? const Icon(Icons.check, color: TimelineTokens.accent)
                            : null,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final sec = widget.maxDurationSec < 60
                  ? widget.maxDurationSec
                  : (_selectedMin * 60).clamp(60, widget.maxDurationSec);
              Navigator.pop(
                context,
                DeepFocusPrepResult(durationSec: sec, audioAssetPath: _trackPath),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: TimelineTokens.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Start deep focus'),
          ),
        ],
      ),
    );
  }
}
