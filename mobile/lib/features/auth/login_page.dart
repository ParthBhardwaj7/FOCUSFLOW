import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/dio_errors.dart';
import '../../core/session/session_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final GoogleSignIn _googleSignIn;

  @override
  void initState() {
    super.initState();
    final serverClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID']?.trim();
    _googleSignIn = GoogleSignIn(
      scopes: const ['email', 'profile'],
      serverClientId: serverClientId != null && serverClientId.isNotEmpty
          ? serverClientId
          : null,
    );
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _googleErrorMessage(Object error) {
    final raw = error.toString();
    if (raw.contains('id token') || raw.contains('ID token')) {
      return 'Google sign-in is not configured. Check GOOGLE_WEB_CLIENT_ID.';
    }
    if (raw.contains('network') || raw.contains('connection')) {
      return 'Network issue. Please check your internet and try again.';
    }
    return 'Could not sign in with Google. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    ref.listen(sessionProvider, (prev, next) {
      next.whenOrNull(
        error: (e, _) => ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatDioError(e)))),
        data: (user) {
          if (user == null || !context.mounted) return;
          // Backup navigation if GoRouter redirect did not fire in the same frame.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            context.go(user.needsOnboarding ? '/day0' : '/now');
          });
        },
      );
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to continue',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: session.isLoading
                        ? null
                        : () async {
                            await ref
                                .read(sessionProvider.notifier)
                                .login(_email.text.trim(), _password.text);
                          },
                    child: session.isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign in'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: session.isLoading
                        ? null
                        : () async {
                            try {
                              final account = await _googleSignIn.signIn();
                              if (account == null) return;
                              final auth = await account.authentication;
                              final idToken = auth.idToken;
                              if (idToken == null || idToken.trim().isEmpty) {
                                throw StateError(
                                  'Google did not return an ID token. '
                                  'Set GOOGLE_WEB_CLIENT_ID in mobile/.env to your Firebase Web client ID.',
                                );
                              }
                              await ref
                                  .read(sessionProvider.notifier)
                                  .loginWithGoogleIdToken(idToken);
                            } catch (e) {
                              if (!context.mounted) return;
                              debugPrint('Google sign-in failed: $e');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(_googleErrorMessage(e))),
                              );
                            }
                          },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        _GoogleBrandIcon(size: 20),
                        SizedBox(width: 8),
                        Text('Sign in with Google'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.replace('/auth/register'),
                  child: const Text('Create an account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleBrandIcon extends StatelessWidget {
  const _GoogleBrandIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => const SweepGradient(
        colors: [
          Color(0xFF4285F4),
          Color(0xFF34A853),
          Color(0xFFFBBC05),
          Color(0xFFEA4335),
          Color(0xFF4285F4),
        ],
      ).createShader(rect),
      child: Icon(
        Icons.g_mobiledata_rounded,
        size: size * 1.35,
        color: Colors.white,
      ),
    );
  }
}
