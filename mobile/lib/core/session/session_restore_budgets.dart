/// Upper bound for [FocusFlowClient.tryRestoreSession] during cold start.
/// OEM / secure-storage hangs must not block the router forever.
const Duration kSessionRestoreTimeout = Duration(seconds: 12);

/// Splash safety redirect must be **longer** than [kSessionRestoreTimeout] so we
/// never send the user to login while restore is still allowed to complete.
const Duration kSplashSafetyTimeout = Duration(seconds: 14);
