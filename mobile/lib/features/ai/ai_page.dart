import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/user_model.dart';
import '../../core/providers.dart';
import '../../core/session/session_controller.dart';
import '../../core/user_facing_errors.dart';
import '../add_task/add_task_page.dart';
import '../recovery/reset_day_sheet.dart';
import '../settings/settings_providers.dart';
import '../timeline/timeline_providers.dart';
import '../timeline/timeline_tokens.dart';

const _kCoachName = 'FocusFlow Coach';

String _firstNameFromEmail(String email) {
  final local = email.split('@').first.trim();
  if (local.isEmpty) return 'there';
  final word = local.split(RegExp(r'[._-]')).firstWhere((s) => s.isNotEmpty, orElse: () => local);
  if (word.isEmpty) return 'there';
  return '${word[0].toUpperCase()}${word.length > 1 ? word.substring(1).toLowerCase() : ''}';
}

MarkdownStyleSheet _coachMarkdownStyle(BuildContext context) {
  final base = Theme.of(context).textTheme;
  return MarkdownStyleSheet(
    p: base.bodyMedium?.copyWith(
          color: TimelineTokens.text,
          fontSize: 14,
          height: 1.45,
        ) ??
        const TextStyle(color: TimelineTokens.text, fontSize: 14, height: 1.45),
    h1: base.titleLarge?.copyWith(
          color: TimelineTokens.text,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ) ??
        const TextStyle(color: TimelineTokens.text, fontWeight: FontWeight.w900, fontSize: 18),
    h2: base.titleMedium?.copyWith(
          color: TimelineTokens.text,
          fontWeight: FontWeight.w800,
          fontSize: 16,
          height: 1.25,
        ) ??
        const TextStyle(color: TimelineTokens.text, fontWeight: FontWeight.w800, fontSize: 16),
    h3: base.titleSmall?.copyWith(
          color: TimelineTokens.text,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ) ??
        const TextStyle(color: TimelineTokens.text, fontWeight: FontWeight.w800, fontSize: 15),
    strong: const TextStyle(
      color: TimelineTokens.text,
      fontWeight: FontWeight.w800,
    ),
    listBullet: const TextStyle(color: TimelineTokens.text, fontSize: 14),
    listIndent: 20,
    blockSpacing: 10,
    a: const TextStyle(color: TimelineTokens.blue, decoration: TextDecoration.underline),
  );
}

class _ChatTurn {
  const _ChatTurn({required this.isUser, required this.text});
  final bool isUser;
  final String text;
}

class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});

  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage> {
  final _controller = TextEditingController();
  final _scrollChat = ScrollController();
  final _turns = <_ChatTurn>[];
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _scrollChat.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type a message first.')),
      );
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _turns.add(_ChatTurn(isUser: true, text: text));
    });
    _controller.clear();
    _scrollChatToEnd();

    final payload = <Map<String, String>>[
      for (final t in _turns)
        {
          'role': t.isUser ? 'user' : 'assistant',
          'content': t.text,
        },
    ];

    try {
      final reply = await ref.read(focusFlowClientProvider).aiChat(payload);
      if (!mounted) return;
      setState(() {
        _turns.add(_ChatTurn(isUser: false, text: reply));
        _busy = false;
      });
      _scrollChatToEnd();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = userFacingError(e);
        _turns.removeLast();
      });
      _controller.text = text;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = userFacingError(e);
        _turns.removeLast();
      });
      _controller.text = text;
    }
  }

  void _scrollChatToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollChat.hasClients) return;
      _scrollChat.animateTo(
        _scrollChat.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  String _headerSubtitle(AsyncValue<UserModel?> session) {
    return session.maybeWhen(
      data: (user) {
        if (user == null) return 'Ideas and nudges for your day';
        final email = user.email;
        if (email.isEmpty) return 'Ideas and nudges for your day';
        return 'Hi ${_firstNameFromEmail(email)} — here’s your snapshot';
      },
      orElse: () => 'Ideas and nudges for your day',
    );
  }

  @override
  Widget build(BuildContext context) {
    final slotsAsync = ref.watch(timelineSlotsProvider);
    final prodAsync = ref.watch(productivityProvider(7));
    final session = ref.watch(sessionProvider);

    return Scaffold(
      backgroundColor: TimelineTokens.bg,
      appBar: AppBar(
        backgroundColor: TimelineTokens.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('AI Coach'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _headerSubtitle(session),
              style: TextStyle(
                color: TimelineTokens.muted.withValues(alpha: 0.95),
                fontSize: 12,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Material(
              color: TimelineTokens.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: TimelineTokens.accent.withValues(alpha: 0.95)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: TimelineTokens.muted.withValues(alpha: 0.98),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _error = null),
                      icon: const Icon(Icons.close, size: 20),
                      color: TimelineTokens.muted,
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  slotsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(color: TimelineTokens.accent)),
                    ),
                    error: (e, _) => Text(
                      userFacingError(e),
                      style: const TextStyle(color: TimelineTokens.text),
                    ),
                    data: (slots) {
                      final missed = slots.where((s) => s.isMissed).length;
                      final active = slots.where((s) => s.isActive).length;
                      final upcoming = slots.where((s) => s.isUpcoming).length;
                      final done = slots.where((s) => s.isDone).length;
                      final rate = slots.isEmpty
                          ? 0
                          : ((done / slots.length) * 100).round();

                      final insightTitle = missed > 0
                          ? 'Day needs a reset'
                          : active > 0
                              ? 'In a live block'
                              : rate >= 50
                                  ? 'Solid momentum'
                                  : 'Room to execute';

                      final insightBody = missed > 0
                          ? '$missed block${missed == 1 ? '' : 's'} slipped on the timeline. Triage or compress what is left instead of stacking guilt.'
                          : active > 0
                              ? 'You have an active focus window. Finish strong, then plan the next block from Timeline.'
                              : 'Planned ${slots.length} blocks today ($done done, $upcoming upcoming). Small wins compound.';

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionLabel(text: "Today's insight"),
                          const SizedBox(height: 8),
                          _InsightCard(
                            title: insightTitle,
                            body: insightBody,
                            warn: missed > 0,
                            onFixDay: () async {
                              final choice = await showResetDaySheet(context);
                              if (choice != null && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Got it — we noted your reset choice.')),
                                );
                                ref.invalidate(timelineSlotsProvider);
                              }
                            },
                          ),
                          const SizedBox(height: 22),
                          _SectionLabel(text: 'Smart suggestions'),
                          const SizedBox(height: 4),
                          Text(
                            'Tap a card for a quick tip. These use your local week on device.',
                            style: TextStyle(
                              color: TimelineTokens.muted.withValues(alpha: 0.88),
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 12),
                          prodAsync.when(
                            data: (prod) {
                              final last = prod.days.isNotEmpty ? prod.days.last : null;
                              final streakHint = last != null && last.rate >= 60
                                  ? 'You are finishing ${last.rate.toStringAsFixed(0)}% of planned blocks recently.'
                                  : 'Pick one must-do block and protect it with a timer — execution beats replanning.';
                              return Column(
                                children: [
                                  _SuggestionTile(
                                    icon: '🧠',
                                    title: 'Best deep work: morning first',
                                    subtitle: upcoming > 2
                                        ? '$upcoming upcoming blocks — tackle the hardest before noon.'
                                        : 'Stack deep work before notifications ramp up.',
                                  ),
                                  _SuggestionTile(
                                    icon: '🌧️',
                                    title: 'Sound anchors focus',
                                    subtitle:
                                        'Rain or brown noise in Focus mode reduces context switching for study-shaped blocks.',
                                  ),
                                  _SuggestionTile(
                                    icon: '🔋',
                                    title: streakHint,
                                    subtitle: 'Based on your last 7 days in the local planner.',
                                  ),
                                ],
                              );
                            },
                            loading: () => const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator(color: TimelineTokens.accent)),
                            ),
                            error: (_, _) => const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 20),
                          _SectionLabel(text: 'One-tap actions'),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _AiActionChip(
                                icon: '🔀',
                                label: 'Rearrange my day',
                                onTap: () async {
                                  final choice = await showResetDaySheet(context);
                                  if (choice != null && context.mounted) {
                                    ref.invalidate(timelineSlotsProvider);
                                    if (context.mounted) context.go('/now');
                                  }
                                },
                              ),
                              _AiActionChip(
                                icon: '🎯',
                                label: 'Add focus blocks',
                                onTap: () => context.push('/add-task', extra: const AddTaskRouteArgs()),
                              ),
                              _AiActionChip(
                                icon: '📉',
                                label: 'Reduce overload',
                                onTap: () async {
                                  await showResetDaySheet(context);
                                  if (context.mounted) ref.invalidate(timelineSlotsProvider);
                                },
                              ),
                              _AiActionChip(
                                icon: '⏰',
                                label: 'Review timeline',
                                onTap: () => context.go('/now'),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _SectionLabel(text: 'Chat with your coach'),
          ),
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: TimelineTokens.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: TimelineTokens.border2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: TimelineTokens.border.withValues(alpha: 0.85)),
                          ),
                        ),
                        child: Text(
                          'Messages stay on this device until sent. When you are online, $_kCoachName can reply in more detail.',
                          style: TextStyle(
                            color: TimelineTokens.muted.withValues(alpha: 0.92),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollChat,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          itemCount: _turns.isEmpty ? 1 : _turns.length,
                          itemBuilder: (context, i) {
                            if (_turns.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8, bottom: 16),
                                child: Text(
                                  'Ask anything about your day, energy, or habits. When you are connected, '
                                  'your coach reads your saved context and replies here.',
                                  style: TextStyle(
                                    color: TimelineTokens.muted.withValues(alpha: 0.95),
                                    fontSize: 13,
                                    height: 1.45,
                                  ),
                                ),
                              );
                            }
                            final t = _turns[i];
                            if (t.isUser) {
                              return Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                                  ),
                                  decoration: BoxDecoration(
                                    color: TimelineTokens.accent.withValues(alpha: 0.9),
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(16),
                                      topRight: Radius.circular(16),
                                      bottomLeft: Radius.circular(16),
                                      bottomRight: Radius.circular(4),
                                    ),
                                    border: Border.all(color: TimelineTokens.border.withValues(alpha: 0.35)),
                                  ),
                                  child: Text(
                                    t.text,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 14,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              );
                            }
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _kCoachName,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.6,
                                        color: TimelineTokens.muted.withValues(alpha: 0.95),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      constraints: BoxConstraints(
                                        maxWidth: MediaQuery.sizeOf(context).width * 0.88,
                                      ),
                                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                                      decoration: BoxDecoration(
                                        color: TimelineTokens.card,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(4),
                                          topRight: Radius.circular(16),
                                          bottomLeft: Radius.circular(16),
                                          bottomRight: Radius.circular(16),
                                        ),
                                        border: Border.all(
                                          color: TimelineTokens.border.withValues(alpha: 0.65),
                                        ),
                                      ),
                                      child: MarkdownBody(
                                        data: t.text,
                                        shrinkWrap: true,
                                        selectable: true,
                                        styleSheet: _coachMarkdownStyle(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_busy)
            const LinearProgressIndicator(minHeight: 2, color: TimelineTokens.accent),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.paddingOf(context).bottom),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_busy,
                    style: const TextStyle(color: TimelineTokens.text),
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Ask your coach anything…',
                      hintStyle: TextStyle(color: TimelineTokens.muted.withValues(alpha: 0.8)),
                      filled: true,
                      fillColor: TimelineTokens.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: TimelineTokens.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: TimelineTokens.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: TimelineTokens.accent, width: 1.2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _send,
                  style: FilledButton.styleFrom(
                    backgroundColor: TimelineTokens.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Icon(Icons.arrow_upward, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: TimelineTokens.muted.withValues(alpha: 0.9),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.body,
    required this.warn,
    required this.onFixDay,
  });

  final String title;
  final String body;
  final bool warn;
  final VoidCallback onFixDay;

  @override
  Widget build(BuildContext context) {
    final border = warn ? TimelineTokens.accent.withValues(alpha: 0.45) : TimelineTokens.border;
    final bg = warn ? TimelineTokens.accent.withValues(alpha: 0.08) : TimelineTokens.card;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(warn ? '⚠️' : '✨', style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: TimelineTokens.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        body,
                        style: TextStyle(
                          color: TimelineTokens.muted.withValues(alpha: 0.95),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onFixDay,
              icon: const Icon(Icons.bolt_rounded, size: 20),
              label: const Text('Fix my day'),
              style: FilledButton.styleFrom(
                backgroundColor: TimelineTokens.accent,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final String icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: TimelineTokens.card,
        elevation: 2,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(title)),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: TimelineTokens.border2.withValues(alpha: 0.9)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(icon, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: TimelineTokens.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: TimelineTokens.muted.withValues(alpha: 0.94),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.chevron_right, color: TimelineTokens.muted.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AiActionChip extends StatelessWidget {
  const _AiActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TimelineTokens.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: (MediaQuery.sizeOf(context).width - 12 * 2 - 10) / 2,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TimelineTokens.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
