import 'package:flutter/services.dart';

import '../../services/google_identity_provider.dart';

bool isGoogleOAuthConfigured() {
  final id = googleWebClientId;
  return id != null && id.isNotEmpty;
}

/// User-visible explanation when Google Sign-In fails (never leaks tokens).
String messageForGoogleSignInFailure(Object error) {
  if (!isGoogleOAuthConfigured()) {
    return 'Google sign-in isn’t configured. Add GOOGLE_WEB_CLIENT_ID to your '
        'mobile .env (Web OAuth client ID from Google Cloud Console) and rebuild.';
  }
  final raw = error.toString();
  final lower = raw.toLowerCase();
  if (raw.contains('10)') ||
      (lower.contains('apiexception') && lower.contains('10')) ||
      lower.contains('developer_error') ||
      lower.contains('sign_in_failed')) {
    return 'Google sign-in failed (misconfigured OAuth). Check GOOGLE_WEB_CLIENT_ID '
        'matches your Firebase Web client ID and that your SHA-1 is registered.';
  }
  if (lower.contains('id token') ||
      lower.contains('id_token') ||
      raw.contains('Google did not return an ID token')) {
    return 'Google sign-in couldn’t verify this app — check GOOGLE_WEB_CLIENT_ID '
        '(Web client ID).';
  }
  if (lower.contains('network') || lower.contains('connection')) {
    return 'Network issue. Check your internet and try again.';
  }
  if (error is PlatformException) {
    if (lower.contains('canceled')) {
      return 'Sign-in canceled.';
    }
    return error.message ?? 'Google sign-in failed. Try again.';
  }
  return 'Could not sign in with Google. Please try again.';
}
