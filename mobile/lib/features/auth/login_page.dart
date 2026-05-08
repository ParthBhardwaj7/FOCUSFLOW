import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/dio_errors.dart';
import '../../core/models/user_model.dart';
import '../../core/providers.dart';
import '../../core/session/session_controller.dart';
import '../../services/google_identity_provider.dart';
import 'google_sign_in_helpers.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _showPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;
  bool _forgotMode = false;
  bool _forgotCodeSent = false;
  bool _forgotLoading = false;
  ProviderSubscription<AsyncValue<UserModel?>>? _sessionSub;

  @override
  void initState() {
    super.initState();
    // Single subscription (not per-frame [build]) so navigation / errors are not duplicated.
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
    _email.dispose();
    _password.dispose();
    _otp.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
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

  void _openForgotPasswordFlow() {
    setState(() {
      _forgotMode = true;
      _forgotCodeSent = false;
      _forgotLoading = false;
      _otp.clear();
      _newPassword.clear();
      _confirmPassword.clear();
    });
  }

  void _closeForgotPasswordFlow() {
    setState(() {
      _forgotMode = false;
      _forgotCodeSent = false;
      _forgotLoading = false;
      _showNewPassword = false;
      _showConfirmPassword = false;
      _otp.clear();
      _newPassword.clear();
      _confirmPassword.clear();
    });
  }

  Future<void> _requestResetCode() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter your email.')));
      return;
    }
    setState(() => _forgotLoading = true);
    try {
      await ref.read(focusFlowClientProvider).requestPasswordResetCode(email);
      if (!mounted) return;
      setState(() => _forgotCodeSent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP sent to your email.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(formatDioError(e))));
    } finally {
      if (mounted) setState(() => _forgotLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    final code = _otp.text.trim();
    final newPassword = _newPassword.text;
    final confirmPassword = _confirmPassword.text;
    if (email.isEmpty || code.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all reset password fields.')),
      );
      return;
    }
    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New password and confirm password must match.')),
      );
      return;
    }
    setState(() => _forgotLoading = true);
    try {
      await ref.read(focusFlowClientProvider).resetPasswordWithCode(
            email: email,
            code: code,
            newPassword: newPassword,
          );
      if (!mounted) return;
      _closeForgotPasswordFlow();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset successful. Please sign in with new password.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(formatDioError(e))));
    } finally {
      if (mounted) setState(() => _forgotLoading = false);
    }
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
                              "Don't have an account?",
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 12,
                              ),
                            ),
                            FilledButton.tonal(
                              onPressed: () => context.replace('/auth/register'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.24),
                                foregroundColor: Colors.white,
                                textStyle: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              child: const Text('Get Started'),
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
                                _forgotMode ? 'Reset Password' : 'Welcome Back',
                                style: TextStyle(
                                  fontSize: headingSize,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _forgotMode
                                    ? (_forgotCodeSent
                                          ? 'Enter OTP, new password, and confirm password'
                                          : 'Enter your email to get a 6-digit OTP')
                                    : 'Enter your details below',
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
                              if (!_forgotMode) ...[
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
                              ],
                              if (_forgotMode && _forgotCodeSent) ...[
                                TextField(
                                  controller: _otp,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: '6-digit OTP',
                                  ),
                                ),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: _newPassword,
                                  obscureText: !_showNewPassword,
                                  decoration: InputDecoration(
                                    labelText: 'New Password',
                                    suffixIcon: IconButton(
                                      onPressed: () {
                                        setState(
                                          () => _showNewPassword = !_showNewPassword,
                                        );
                                      },
                                      icon: Icon(
                                        _showNewPassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: _confirmPassword,
                                  obscureText: !_showConfirmPassword,
                                  decoration: InputDecoration(
                                    labelText: 'Confirm Password',
                                    suffixIcon: IconButton(
                                      onPressed: () {
                                        setState(
                                          () => _showConfirmPassword = !_showConfirmPassword,
                                        );
                                      },
                                      icon: Icon(
                                        _showConfirmPassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: (_forgotMode
                                          ? _forgotLoading
                                          : session.isLoading)
                                      ? null
                                      : () async {
                                          if (_forgotMode) {
                                            if (_forgotCodeSent) {
                                              await _resetPassword();
                                            } else {
                                              await _requestResetCode();
                                            }
                                            return;
                                          }
                                          await ref
                                              .read(sessionProvider.notifier)
                                              .login(_email.text.trim(), _password.text);
                                        },
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 15),
                                    textStyle: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  child: (_forgotMode
                                          ? _forgotLoading
                                          : session.isLoading)
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : Text(
                                          _forgotMode
                                              ? (_forgotCodeSent
                                                    ? 'Reset Password'
                                                    : 'Send OTP')
                                              : 'Sign in',
                                        ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextButton(
                                onPressed: () {
                                  if (_forgotMode) {
                                    _closeForgotPasswordFlow();
                                    return;
                                  }
                                  _openForgotPasswordFlow();
                                },
                                child: Text(
                                  _forgotMode ? 'Back to sign in' : 'Forgot password?',
                                  style: TextStyle(color: muted),
                                ),
                              ),
                              if (!_forgotMode) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Divider(color: muted.withValues(alpha: 0.35)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: Text(
                                        'Or sign in with',
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
                                            if (!isGoogleOAuthConfigured()) {
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    messageForGoogleSignInFailure(
                                                      StateError(
                                                        'GOOGLE_WEB_CLIENT_ID missing.',
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
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
                                              debugPrint('Google sign-in failed: $e');
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content:
                                                      Text(messageForGoogleSignInFailure(e)),
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
                              ],
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
