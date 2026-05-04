import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'coach_context_prefs.dart';
import 'dev_config.dart';
import 'providers.dart';
import 'session/session_controller.dart';

/// Pushes [buildCoachProfileSummaryForAi] to the server as `profileSummary`
/// so the AI coach can use it (see backend `AiService.chat`).
Future<bool> syncCoachProfileSummaryToServer(WidgetRef ref) async {
  if (kDevAuthBypass) return false;
  try {
    final summary = await buildCoachProfileSummaryForAi();
    await ref.read(focusFlowClientProvider).patchMe(profileSummary: summary);
    await ref.read(sessionProvider.notifier).refreshMe();
    return true;
  } catch (_) {
    return false;
  }
}
