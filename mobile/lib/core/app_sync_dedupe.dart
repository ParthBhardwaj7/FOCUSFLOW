// Avoid stacking syncRuntimeRemote + urgent planner pull from both
// SessionController (post-frame) and TimelineNotificationSyncHost on the same
// cold start / resume within a short window.

int? _signedInRemoteBootstrapEpochMs;

void markSignedInRemoteBootstrapEnqueued() {
  _signedInRemoteBootstrapEpochMs = DateTime.now().millisecondsSinceEpoch;
}

/// When true, the shell may skip duplicate remote bootstrap (flags + planner
/// urgent pull) but should still run inbox outbox / local notification work.
bool signedInRemoteBootstrapRecentlyEnqueued({int withinMs = 4000}) {
  final t = _signedInRemoteBootstrapEpochMs;
  if (t == null) return false;
  return DateTime.now().millisecondsSinceEpoch - t < withinMs;
}
