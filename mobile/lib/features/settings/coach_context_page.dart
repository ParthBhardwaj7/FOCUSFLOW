import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/coach_context_prefs.dart';
import '../../core/coach_profile_sync.dart';
import '../../core/user_facing_errors.dart';
import '../timeline/timeline_tokens.dart';

class CoachContextPage extends ConsumerStatefulWidget {
  const CoachContextPage({super.key});

  @override
  ConsumerState<CoachContextPage> createState() => _CoachContextPageState();
}

class _CoachContextPageState extends ConsumerState<CoachContextPage> {
  final _habits = TextEditingController();
  final _goals = TextEditingController();
  final _obstacles = TextEditingController();
  final _focusWindow = TextEditingController();
  final _notes = TextEditingController();
  var _seeded = false;
  var _saving = false;

  @override
  void dispose() {
    _habits.dispose();
    _goals.dispose();
    _obstacles.dispose();
    _focusWindow.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final fields = CoachContextFields(
      habitsToBuild: _habits.text,
      goalsThisQuarter: _goals.text,
      commonObstacles: _obstacles.text,
      bestFocusWindow: _focusWindow.text,
      extraNotesForCoach: _notes.text,
    );
    await saveCoachContextFields(fields);
    ref.invalidate(coachContextFieldsProvider);
    final synced = await syncCoachProfileSummaryToServer(ref);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          synced
              ? 'Saved. Your coach will use this on your next message.'
              : 'Saved on this device. Sync to coach failed — check connection and try again.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(coachContextFieldsProvider);

    return Scaffold(
      backgroundColor: TimelineTokens.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: TimelineTokens.scaffoldBg(context),
        surfaceTintColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: const Text('Coach context'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: async.when(
        loading: () => Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  userFacingError(e),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.95),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(coachContextFieldsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (saved) {
          if (!_seeded) {
            _seeded = true;
            _habits.text = saved.habitsToBuild;
            _goals.text = saved.goalsThisQuarter;
            _obstacles.text = saved.commonObstacles;
            _focusWindow.text = saved.bestFocusWindow;
            _notes.text = saved.extraNotesForCoach;
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                'What you write here is combined with your focus quiz and sent to the AI coach as your profile. Be specific — it helps with tailored advice.',
                style: TextStyle(
                  color: TimelineTokens.adaptiveSecondaryText(context),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              _fieldLabel(
                context,
                'Habits to build',
                'One per line or short bullets — e.g. morning planning, no phone in bed.',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _habits,
                maxLines: 6,
                maxLength: kMaxHabitsLength,
                style: TextStyle(
                  color: TimelineTokens.adaptivePrimaryText(context),
                ),
                cursorColor: Theme.of(context).colorScheme.primary,
                decoration: _fieldDecoration(
                  context,
                  hint: 'e.g. Deep work 4×/week · Inbox zero Fridays',
                ),
              ),
              const SizedBox(height: 20),
              _fieldLabel(
                context,
                'Goals (this quarter)',
                'Outcomes you care about right now.',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _goals,
                maxLines: 3,
                maxLength: kMaxCoachFieldLength,
                style: TextStyle(
                  color: TimelineTokens.adaptivePrimaryText(context),
                ),
                cursorColor: Theme.of(context).colorScheme.primary,
                decoration: _fieldDecoration(
                  context,
                  hint: 'e.g. Finish certification · Ship MVP',
                ),
              ),
              const SizedBox(height: 20),
              _fieldLabel(
                context,
                'What usually gets in the way',
                'So the coach can suggest realistic guardrails.',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _obstacles,
                maxLines: 3,
                maxLength: kMaxCoachFieldLength,
                style: TextStyle(
                  color: TimelineTokens.adaptivePrimaryText(context),
                ),
                cursorColor: Theme.of(context).colorScheme.primary,
                decoration: _fieldDecoration(
                  context,
                  hint: 'e.g. Back-to-back meetings · Evening fatigue',
                ),
              ),
              const SizedBox(height: 20),
              _fieldLabel(
                context,
                'Best time / way to focus',
                'When and how you work best.',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _focusWindow,
                maxLines: 2,
                maxLength: kMaxCoachFieldLength,
                style: TextStyle(
                  color: TimelineTokens.adaptivePrimaryText(context),
                ),
                cursorColor: Theme.of(context).colorScheme.primary,
                decoration: _fieldDecoration(
                  context,
                  hint: 'e.g. 6–8am quiet blocks · 25/5 Pomodoros',
                ),
              ),
              const SizedBox(height: 20),
              _fieldLabel(
                context,
                'Anything else for the coach',
                'Optional: tools, constraints, values.',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                maxLines: 3,
                maxLength: kMaxCoachFieldLength,
                style: TextStyle(
                  color: TimelineTokens.adaptivePrimaryText(context),
                ),
                cursorColor: Theme.of(context).colorScheme.primary,
                decoration: _fieldDecoration(
                  context,
                  hint: 'e.g. ADHD-friendly tips · Prefer short lists',
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _saving
                    ? SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : const Text('Save & update coach'),
              ),
            ],
          );
        },
      ),
    );
  }

}

Widget _fieldLabel(BuildContext context, String title, String subtitle) {
  final on = Theme.of(context).colorScheme.onSurface;
  final sub = Theme.of(context).colorScheme.onSurfaceVariant;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          color: on,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: TextStyle(
          color: sub.withValues(alpha: 0.92),
          fontSize: 12,
          height: 1.35,
        ),
      ),
    ],
  );
}

InputDecoration _fieldDecoration(BuildContext context, {required String hint}) {
  final cs = Theme.of(context).colorScheme;
  final muted = cs.onSurfaceVariant;
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: muted.withValues(alpha: 0.8)),
    filled: true,
    fillColor: cs.surfaceContainerHighest,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.primary, width: 1.2),
    ),
    contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
  );
}
