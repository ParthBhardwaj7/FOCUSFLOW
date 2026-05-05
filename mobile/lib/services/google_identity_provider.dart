import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Single [GoogleSignIn] wired like [LoginPage] so logout can clear Play Services
/// state and avoid silent re-login with the previously used account.
final googleSignInProvider = Provider<GoogleSignIn>((ref) {
  final serverClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID']?.trim();
  return GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: serverClientId != null && serverClientId.isNotEmpty
        ? serverClientId
        : null,
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
