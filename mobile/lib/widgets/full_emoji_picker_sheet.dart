import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

/// Full emoji grid (device / category picker). Returns selected emoji string or null.
Future<String?> showFullEmojiPickerSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.55,
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
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
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
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) {
                    Navigator.pop(ctx, emoji.emoji);
                  },
                  config: Config(
                    height: 256,
                    checkPlatformCompatibility: true,
                    emojiViewConfig: EmojiViewConfig(
                      backgroundColor: Theme.of(ctx).colorScheme.surface,
                    ),
                    skinToneConfig: const SkinToneConfig(),
                    categoryViewConfig: CategoryViewConfig(
                      backgroundColor: Theme.of(ctx).colorScheme.surface,
                      indicatorColor: Theme.of(ctx).colorScheme.primary,
                    ),
                    bottomActionBarConfig: BottomActionBarConfig(
                      backgroundColor: Theme.of(ctx).colorScheme.surface,
                      buttonColor: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      buttonIconColor: Theme.of(ctx).colorScheme.onSurface,
                    ),
                    searchViewConfig: SearchViewConfig(
                      backgroundColor: Theme.of(ctx).colorScheme.surface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
