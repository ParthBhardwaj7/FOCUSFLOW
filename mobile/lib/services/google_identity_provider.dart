import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Web OAuth client ID (Google Cloud Console) — required for `id_token` on Android.
/// See `.env.example` / `mobile/.env` key `GOOGLE_WEB_CLIENT_ID`.
String? get googleWebClientId {
  final v = dotenv.env['GOOGLE_WEB_CLIENT_ID']?.trim();
  if (v == null || v.isEmpty) return null;
  return v;
}

/// Single [GoogleSignIn] wired like [LoginPage] so logout can clear Play Services
/// state and avoid silent re-login with the previously used account.
final googleSignInProvider = Provider<GoogleSignIn>((ref) {
  final serverClientId = googleWebClientId;
  return GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: serverClientId,
  );
});

/// Called on app logout so the next Google tap shows the account picker instead of
/// reusing the last account without user confirmation.
Future<void> clearGoogleSignInSession(GoogleSignIn g) async {
  try {
    await g.signOut();
    await g.disconnect();
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('Google sign-out/disconnect failed: $e\n$st');
    }
  }
}
