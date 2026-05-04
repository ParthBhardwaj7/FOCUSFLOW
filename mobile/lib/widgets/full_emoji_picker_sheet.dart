import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import 'task_emoji_sections.dart';

/// Sectioned emoji picker for task icons + optional full Unicode grid.
/// Avoids the stock [EmojiPicker] category tab strip (often shows edge fade/gradient on the left).
Future<String?> showFullEmojiPickerSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.58,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Choose emoji',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, ''),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _SectionedEmojiBody(
                  onPick: (s) => Navigator.pop(ctx, s),
                  onOpenFullPicker: () => _openFullEmojiGrid(ctx),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _SectionedEmojiBody extends StatelessWidget {
  const _SectionedEmojiBody({
    required this.onPick,
    required this.onOpenFullPicker,
  });

  final ValueChanged<String> onPick;
  final VoidCallback onOpenFullPicker;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            itemCount: kTaskEmojiSections.length,
            itemBuilder: (context, index) {
              final sec = kTaskEmojiSections[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(sec.icon, size: 18, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sec.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: sec.emojis.map((e) {
                        return Material(
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.65,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: () => onPick(e),
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: Text(
                                  e,
                                  style: const TextStyle(fontSize: 24),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: OutlinedButton.icon(
            onPressed: onOpenFullPicker,
            icon: const Icon(Icons.grid_view_rounded, size: 18),
            label: const Text('More emojis (full keyboard)'),
          ),
        ),
      ],
    );
  }
}

Future<void> _openFullEmojiGrid(BuildContext outerSheetContext) async {
  await showModalBottomSheet<void>(
    context: outerSheetContext,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final surface = Theme.of(ctx).colorScheme.surface;
      return SafeArea(
        child: Theme(
          data: Theme.of(ctx).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            tabBarTheme: TabBarThemeData(
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              dividerColor: Colors.transparent,
              indicatorColor: Theme.of(ctx).colorScheme.primary,
            ),
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.5,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'All categories',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: EmojiPicker(
                    onEmojiSelected: (_, emoji) {
                      Navigator.pop(ctx);
                      Navigator.pop(outerSheetContext, emoji.emoji);
                    },
                    config: Config(
                      height: 256,
                      checkPlatformCompatibility: true,
                      skinToneConfig: SkinToneConfig(
                        enabled: false,
                        dialogBackgroundColor: surface,
                        indicatorColor: Theme.of(ctx).colorScheme.outline,
                      ),
                      emojiViewConfig: EmojiViewConfig(
                        backgroundColor: surface,
                        buttonMode: ButtonMode.NONE,
                      ),
                      categoryViewConfig: CategoryViewConfig(
                        backgroundColor: surface,
                        indicatorColor: Theme.of(ctx).colorScheme.primary,
                        iconColor: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        iconColorSelected: Theme.of(ctx).colorScheme.primary,
                        dividerColor: Colors.transparent,
                      ),
                      bottomActionBarConfig: BottomActionBarConfig(
                        backgroundColor: surface,
                        buttonColor: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        buttonIconColor: Theme.of(ctx).colorScheme.onSurface,
                      ),
                      searchViewConfig: SearchViewConfig(
                        backgroundColor: surface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
