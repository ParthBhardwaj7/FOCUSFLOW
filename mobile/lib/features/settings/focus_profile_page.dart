import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/coach_profile_sync.dart';
import '../../core/focus_prefs.dart';
import '../../core/profile_focus_prefs.dart';
import '../../router.dart';
import '../timeline/timeline_tokens.dart';
import 'profile_demographics_section.dart';

class FocusProfilePage extends ConsumerStatefulWidget {
  const FocusProfilePage({super.key});

  @override
  ConsumerState<FocusProfilePage> createState() => _FocusProfilePageState();
}

const _kSoundQuizOrder = <SoundPreference>[
  SoundPreference.silence,
  SoundPreference.rain,
  SoundPreference.ocean,
  SoundPreference.whiteNoise,
  SoundPreference.brownNoise,
  SoundPreference.music,
];

class _FocusProfilePageState extends ConsumerState<FocusProfilePage> {
  final _pageController = PageController();
  int _page = 0;
  var _seededFromSaved = false;

  DistractionLevel _distraction = DistractionLevel.sometimes;
  SoundPreference _sound = SoundPreference.rain;
  CommitmentLevel _commitment = CommitmentLevel.moderate;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _persistAndApplyPrefs({bool markFirstSession = false}) async {
    final focus = await ref.read(focusPrefsProvider.future);
    final prev = await ref.read(profileFocusAnswersProvider.future);
    final answers = ProfileFocusAnswers(
      distraction: _distraction,
      sound: _sound,
      commitment: _commitment,
      completed: true,
      firstSessionStarted: markFirstSession || prev.firstSessionStarted,
    );
    await saveProfileFocusAnswers(answers);
    await applyProfileToDevicePrefs(answers, focus);
    ref.invalidate(profileFocusAnswersProvider);
    ref.invalidate(focusPrefsProvider);
    unawaited(syncCoachProfileSummaryToServer(ref));
  }

  Future<void> _onStartNow() async {
    final router = GoRouter.of(context);
    await _persistAndApplyPrefs(markFirstSession: true);
    router.push(
      '/focus',
      extra: const FocusRouteArgs(
        title: 'Focus session',
        plannedSeconds: 300,
        markOnboardingComplete: false,
      ),
    );
  }

  void _next() {
    if (_page < 3) {
      _pageController.animateToPage(
        _page + 1,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pageController.animateToPage(
        4,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _back() {
    if (_page <= 0) {
      context.pop();
      return;
    }
    _pageController.animateToPage(
      _page - 1,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: TimelineTokens.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: TimelineTokens.scaffoldBg(context),
        surfaceTintColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: const Text('Focus profile'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: ref
          .watch(profileFocusAnswersProvider)
          .when(
            loading: () => Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            error: (Object error, StackTrace stackTrace) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load profile. Pull to refresh in Settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: TimelineTokens.adaptivePrimaryText(context),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            data: (saved) {
              if (!_seededFromSaved) {
                _seededFromSaved = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _distraction = saved.distraction;
                    _sound = saved.sound;
                    _commitment = saved.commitment;
                  });
                });
              }
              return Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: ProfileDemographicsSection(),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Row(
                      children: List.generate(5, (i) {
                        final active = i <= _page;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              height: 4,
                              decoration: BoxDecoration(
                                color: active
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .outline
                                        .withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (i) => setState(() => _page = i),
                      children: [
                        _IntroPage(
                          completed: saved.completed,
                          distraction: saved.distraction,
                          sound: saved.sound,
                          commitment: saved.commitment,
                          onContinue: _next,
                          onEdit: () {
                            setState(() => _page = 1);
                            _pageController.jumpToPage(1);
                          },
                        ),
                        _QuestionPage(
                          emoji: '🔕',
                          title: 'How easily do you get distracted?',
                          subtitle:
                              'We tune hard focus, reminders, and exit friction to match.',
                          options: const [
                            _Opt(
                              DistractionLevel.veryEasily,
                              'Very easily',
                              'Strong guardrails',
                            ),
                            _Opt(
                              DistractionLevel.sometimes,
                              'Sometimes',
                              'Balanced',
                            ),
                            _Opt(
                              DistractionLevel.rarely,
                              'Rarely',
                              'Lighter touch',
                            ),
                          ],
                          selectedIndex: _distraction.index,
                          onSelect: (i) => setState(
                            () => _distraction = DistractionLevel.values[i],
                          ),
                        ),
                        _QuestionPage(
                          emoji: '🎧',
                          title: 'What helps you focus?',
                          subtitle:
                              'Controls sound chips on the standard focus timer.',
                          options: const [
                            _Opt(
                              SoundPreference.silence,
                              'Silence',
                              'No ambience chips',
                            ),
                            _Opt(
                              SoundPreference.rain,
                              'Rain',
                              'Steady rain loop',
                            ),
                            _Opt(
                              SoundPreference.ocean,
                              'Ocean',
                              'Waves and depth',
                            ),
                            _Opt(
                              SoundPreference.whiteNoise,
                              'White noise',
                              'Steady texture',
                            ),
                            _Opt(
                              SoundPreference.brownNoise,
                              'Brown noise',
                              'Deeper steady texture',
                            ),
                            _Opt(
                              SoundPreference.music,
                              'Music',
                              'Café-style energy',
                            ),
                          ],
                          selectedIndex: _kSoundQuizOrder.contains(_sound)
                              ? _kSoundQuizOrder.indexOf(_sound)
                              : 1,
                          onSelect: (i) =>
                              setState(() => _sound = _kSoundQuizOrder[i]),
                        ),
                        _QuestionPage(
                          emoji: '🔥',
                          title: 'How serious are you about improving?',
                          subtitle:
                              'Shapes strict mode and reminder intensity.',
                          options: const [
                            _Opt(
                              CommitmentLevel.justTrying,
                              'Just trying',
                              'Gentle defaults',
                            ),
                            _Opt(
                              CommitmentLevel.moderate,
                              'Moderate',
                              'Steady nudges',
                            ),
                            _Opt(
                              CommitmentLevel.fullyCommitted,
                              'Fully committed',
                              'Strict + hold to exit',
                            ),
                          ],
                          selectedIndex: _commitment.index,
                          onSelect: (i) => setState(
                            () => _commitment = CommitmentLevel.values[i],
                          ),
                        ),
                        _FinalPage(
                          onStartNow: () async {
                            await _onStartNow();
                          },
                          onLater: () async {
                            await _persistAndApplyPrefs();
                            if (!context.mounted) return;
                            context.pop();
                          },
                        ),
                      ],
                    ),
                  ),
                  if (_page >= 1 && _page <= 3)
                    Padding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottom),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: _back,
                            child: const Text('Back'),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: _next,
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                            ),
                            child: Text(_page == 3 ? 'Continue' : 'Next'),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
    );
  }
}

class _Opt<T> {
  const _Opt(this.value, this.title, this.subtitle);
  final T value;
  final String title;
  final String subtitle;
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({
    required this.completed,
    required this.distraction,
    required this.sound,
    required this.commitment,
    required this.onContinue,
    required this.onEdit,
  });

  final bool completed;
  final DistractionLevel distraction;
  final SoundPreference sound;
  final CommitmentLevel commitment;
  final VoidCallback onContinue;
  final VoidCallback onEdit;

  String _dLabel(DistractionLevel d) {
    switch (d) {
      case DistractionLevel.veryEasily:
        return 'Very easily';
      case DistractionLevel.sometimes:
        return 'Sometimes';
      case DistractionLevel.rarely:
        return 'Rarely';
    }
  }

  String _sLabel(SoundPreference s) {
    switch (s) {
      case SoundPreference.silence:
        return 'Silence';
      case SoundPreference.rain:
        return 'Rain';
      case SoundPreference.whiteNoise:
        return 'White noise';
      case SoundPreference.music:
        return 'Music';
      case SoundPreference.ocean:
        return 'Ocean';
      case SoundPreference.brownNoise:
        return 'Brown noise';
    }
  }

  String _cLabel(CommitmentLevel c) {
    switch (c) {
      case CommitmentLevel.justTrying:
        return 'Just trying';
      case CommitmentLevel.moderate:
        return 'Moderate';
      case CommitmentLevel.fullyCommitted:
        return 'Fully committed';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (completed) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        children: [
          Text(
            'Your focus profile',
            style: TextStyle(
              color: TimelineTokens.adaptivePrimaryText(context),
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'These answers tune Focus mode in Settings. Tap below to change them.',
            style: TextStyle(
              color: TimelineTokens.adaptiveSecondaryText(context),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          _SummaryTile(label: 'Distraction', value: _dLabel(distraction)),
          _SummaryTile(label: 'Sound', value: _sLabel(sound)),
          _SummaryTile(label: 'Commitment', value: _cLabel(commitment)),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: onEdit,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Update answers'),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: [
        Text(
          'Personalize your focus',
          style: TextStyle(
            color: TimelineTokens.adaptivePrimaryText(context),
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Four quick questions. Your answers tune hard focus, soundscapes, and how strict the app feels — you can change them anytime.',
          style: TextStyle(
            color: TimelineTokens.adaptiveSecondaryText(context),
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: onContinue,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Get started'),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: TimelineTokens.adaptiveCardPanel(context),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: TimelineTokens.adaptiveSecondaryText(context),
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: TimelineTokens.adaptivePrimaryText(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionPage extends StatelessWidget {
  const _QuestionPage({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final List<_Opt<dynamic>> options;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(emoji, style: const TextStyle(fontSize: 36)),
        const SizedBox(height: 12),
        Text(
          title,
          style: TextStyle(
            color: TimelineTokens.adaptivePrimaryText(context),
            fontSize: 20,
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(
            color: TimelineTokens.adaptiveSecondaryText(context),
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 22),
        ...List.generate(options.length, (i) {
          final o = options[i];
          final sel = i == selectedIndex;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: sel
                  ? Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.12)
                  : TimelineTokens.adaptiveCardPanel(context),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSelect(i),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: sel
                          ? Theme.of(context).colorScheme.primary
                          : TimelineTokens.adaptiveBorder(context),
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.title,
                        style: TextStyle(
                          color: TimelineTokens.adaptivePrimaryText(context),
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        o.subtitle,
                        style: TextStyle(
                          color: TimelineTokens.adaptiveSecondaryText(context),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _FinalPage extends StatelessWidget {
  const _FinalPage({required this.onStartNow, required this.onLater});

  final Future<void> Function() onStartNow;
  final Future<void> Function() onLater;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: [
        Text(
          '🚀',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 48),
        ),
        const SizedBox(height: 20),
        Text(
          'Start your first session',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: TimelineTokens.adaptivePrimaryText(context),
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'You are set. Start a 5-minute focus now, or head back — your profile is saved either way.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: TimelineTokens.adaptiveSecondaryText(context),
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 36),
        FilledButton(
          onPressed: () => onStartNow(),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 18),
          ),
          child: const Text('Start now'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => onLater(),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outline,
            ),
            foregroundColor: TimelineTokens.adaptivePrimaryText(context),
          ),
          child: const Text('Maybe later'),
        ),
      ],
    );
  }
}
