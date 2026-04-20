import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/focus_prefs.dart';
import '../../core/providers.dart';
import '../../core/session/session_controller.dart';
import '../../router.dart';
import '../focus/deep_focus_prep_sheet.dart';

class Day0Page extends ConsumerWidget {
  const Day0Page({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Text(
                'FocusFlow',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Tell me what to do now.\nOne tap from stuck to timer running.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
                    ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  final prep = await showDeepFocusPrepSheet(
                    context,
                    taskTitle: 'First focus',
                    maxDurationSec: 300,
                    suggestedDurationSec: 300,
                  );
                  if (!context.mounted || prep == null) return;
                  String? sessionId;
                  try {
                    final session = await ref.read(focusFlowClientProvider).createFocusSession(
                          plannedDurationSec: prep.durationSec,
                        );
                    sessionId = session['id'] as String?;
                  } catch (_) {}
                  if (!context.mounted) return;
                  final prefs = await ref.read(focusPrefsProvider.future);
                  if (!context.mounted) return;
                  context.push(
                    '/deep-focus',
                    extra: DeepFocusRouteArgs(
                      title: 'First focus',
                      plannedSeconds: prep.durationSec,
                      sessionId: sessionId,
                      audioAssetPath: prep.audioAssetPath,
                      markOnboardingComplete: true,
                      holdToExit: prefs.holdToExit,
                    ),
                  );
                },
                child: const Text('DO THIS NOW (5 MIN DEMO)'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  await ref.read(sessionProvider.notifier).completeOnboarding();
                  if (!context.mounted) return;
                  context.go('/now');
                },
                child: const Text('Skip for now'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
