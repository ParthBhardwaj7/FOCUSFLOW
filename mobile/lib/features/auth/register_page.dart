import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/dio_errors.dart';
import '../../core/models/user_model.dart';
import '../../core/session/session_controller.dart';
import '../../services/google_identity_provider.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  ProviderSubscription<AsyncValue<UserModel?>>? _sessionSub;

  @override
  void initState() {
    super.initState();
    _sessionSub = ref.listenManual<AsyncValue<UserModel?>>(sessionProvider, (
      prev,
      next,
    ) {
      next.whenOrNull(
        error: (e, _) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(formatDioError(e))));
        },
        data: (user) {
          if (user == null || !context.mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            context.go(user.needsOnboarding ? '/day0' : '/now');
          });
        },
      );
    });
  }

  @override
  void dispose() {
    _sessionSub?.close();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _openSupportEmail(String supportEmail) async {
    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      queryParameters: const {'subject': 'FocusFlow support'},
    );
    final launched = await launchUrl(uri);
    if (!mounted || launched) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open email app right now.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final supportEmail = dotenv.env['SUPPORT_EMAIL']?.trim() ?? '';
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 360;
    final cozy = screenWidth < 400;
    final brandSize = compact ? 36.0 : (cozy ? 40.0 : 46.0);
    final headingSize = compact ? 34.0 : (cozy ? 38.0 : 44.0);
    final cardPadding = compact
        ? const EdgeInsets.fromLTRB(16, 18, 16, 20)
        : const EdgeInsets.fromLTRB(20, 22, 20, 24);
    final shellPadding = compact
        ? const EdgeInsets.fromLTRB(14, 0, 14, 16)
        : const EdgeInsets.fromLTRB(20, 0, 20, 20);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 26),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1E1E28), Color(0xFFFF5F5F)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Text(
                              'Already have an account?',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 12,
                              ),
                            ),
                            FilledButton.tonal(
                              onPressed: () => context.replace('/auth/login'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.24),
                                foregroundColor: Colors.white,
                                textStyle: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              child: const Text('Sign In'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'FocusFlow',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: brandSize,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: shellPadding,
                    child: Transform.translate(
                      offset: const Offset(0, -14),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 22,
                              offset: const Offset(0, 10),
                              color: Colors.black.withValues(alpha: 0.12),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: cardPadding,
                          child: Column(
                            children: [
                              Text(
                                'Get started free.',
                                style: TextStyle(
                                  fontSize: headingSize,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Free forever. No credit card needed.',
                                style: TextStyle(color: muted, fontSize: 15),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 22),
                              TextField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Email Address',
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _name,
                                decoration: const InputDecoration(
                                  labelText: 'Your name',
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _password,
                                obscureText: !_showPassword,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  suffixIcon: IconButton(
                                    onPressed: () {
                                      setState(() => _showPassword = !_showPassword);
                                    },
                                    icon: Icon(
                                      _showPassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: session.isLoading
                                      ? null
                                      : () async {
                                          await ref
                                              .read(sessionProvider.notifier)
                                              .register(_email.text.trim(), _password.text);
                                        },
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 15),
                                    textStyle: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  child: session.isLoading
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('Sign up'),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: Divider(color: muted.withValues(alpha: 0.35)),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: Text(
                                      'Or sign up with',
                                      style: TextStyle(color: muted, fontSize: 12),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(color: muted.withValues(alpha: 0.35)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: compact ? double.infinity : 180,
                                child: OutlinedButton(
                                  onPressed: session.isLoading
                                      ? null
                                      : () async {
                                          try {
                                            final g = ref.read(googleSignInProvider);
                                            final account = await g.signIn();
                                            if (account == null) return;
                                            final auth = await account.authentication;
                                            final idToken = auth.idToken;
                                            final accessToken = auth.accessToken;
                                            if (idToken == null || idToken.trim().isEmpty) {
                                              throw StateError(
                                                'Google did not return an ID token.',
                                              );
                                            }
                                            await ref
                                                .read(sessionProvider.notifier)
                                                .loginWithGoogle(
                                                  idToken: idToken,
                                                  accessToken: accessToken,
                                                );
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Could not continue with Google. Please try again.',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      _GoogleBrandIcon(size: 20),
                                      SizedBox(width: 10),
                                      Text('Google'),
                                    ],
                                  ),
                                ),
                              ),
                              if (supportEmail.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 4,
                                  children: [
                                    Text(
                                      'For any queries,',
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    InkWell(
                                      onTap: () => _openSupportEmail(supportEmail),
                                      child: Text(
                                        supportEmail,
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.primary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          decoration: TextDecoration.underline,
                                          decorationThickness: 1.2,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
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
