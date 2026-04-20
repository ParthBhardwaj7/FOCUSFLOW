import 'package:flutter/material.dart';

enum ResetDayChoice { compress, tomorrow, mitOnly }

Future<ResetDayChoice?> showResetDaySheet(BuildContext context) {
  return showModalBottomSheet<ResetDayChoice>(
    context: context,
    backgroundColor: const Color(0xFF16161F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reset your day',
            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Pick a forward path — no guilt, just next steps.',
            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.65),
                ),
          ),
          const SizedBox(height: 20),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, ResetDayChoice.compress),
            child: const Text('Compress what is left'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, ResetDayChoice.tomorrow),
            child: const Text('Move non-essentials to tomorrow'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, ResetDayChoice.mitOnly),
            child: const Text('MIT only for the rest of today'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}
