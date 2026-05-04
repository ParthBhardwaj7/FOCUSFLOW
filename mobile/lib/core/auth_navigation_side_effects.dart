import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dev_config.dart';
import 'models/user_model.dart';
import 'planner_cloud_sync.dart';
import 'router_refresh.dart';

/// Call after any [sessionProvider] mutation so redirects re-run.
void notifyGoRouterAuthChanged(Ref ref) {
  ref.read(goRouterRefreshProvider).notify();
}

/// First successful session restore (cold start): debounced planner pull.
void scheduleInitialPlannerPullIfSignedIn(Ref ref, UserModel? user) {
  if (kDevAuthBypass) return;
  if (user == null) return;
  ref.read(plannerCloudSyncCoordinatorProvider).schedulePull();
}

/// Logged-in session updates (login, profile refresh, onboarding): urgent pull.
void scheduleUrgentPlannerPullIfSignedIn(Ref ref, UserModel? user) {
  if (kDevAuthBypass) return;
  if (user == null) return;
  ref.read(plannerCloudSyncCoordinatorProvider).schedulePull(urgent: true);
}
