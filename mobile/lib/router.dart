import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/dev_config.dart';
import 'core/models/user_model.dart';
import 'core/session/session_controller.dart';
import 'features/add_task/add_task_page.dart';
import 'features/ai/ai_page.dart';
import 'features/auth/login_page.dart';
import 'features/auth/register_page.dart';
import 'features/focus/deep_focus_page.dart';
import 'features/focus/focus_page.dart';
import 'features/inbox/inbox_page.dart';
import 'features/inbox/note_editor_page.dart';
import 'features/onboarding/day0_page.dart';
import 'features/now/now_page.dart';
import 'features/settings/settings_page.dart';
import 'features/shell/main_shell_scaffold.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: kDevAuthBypass ? '/now' : '/splash',
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final async = ref.read(sessionProvider);

      if (loc == '/focus' ||
          loc == '/deep-focus' ||
          loc.startsWith('/inbox/notes')) {
        return null;
      }

      if (kDevAuthBypass) {
        if (loc == '/splash' || loc.startsWith('/auth') || loc == '/day0') {
          return '/now';
        }
        return null;
      }

      // Do not pull user off /auth/* during login/register — stay on the form while loading
      // so the session can settle to AsyncData(user) and redirect below can send them to /now.
      if (async.isLoading && loc != '/splash' && !loc.startsWith('/auth')) {
        return '/splash';
      }
      if (async.hasError && loc != '/splash' && !loc.startsWith('/auth')) {
        return '/auth/login';
      }
      if (!async.hasValue && loc != '/splash' && !loc.startsWith('/auth')) {
        return '/splash';
      }

      final user = async.asData?.value;
      final authRoute = loc.startsWith('/auth');

      if (user == null) {
        if (authRoute) return null;
        // Stay on splash only while session is still restoring; then send to login.
        if (async.isLoading) return null;
        return '/auth/login';
      }

      if (authRoute) {
        return user.needsOnboarding ? '/day0' : '/now';
      }

      if (user.needsOnboarding && loc != '/day0') {
        return '/day0';
      }

      if (!user.needsOnboarding && loc == '/day0') {
        return '/now';
      }

      if (!async.isLoading && loc == '/splash') {
        if (user.needsOnboarding) return '/day0';
        return '/now';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashPage(),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/day0',
        builder: (context, state) => const Day0Page(),
      ),
      GoRoute(
        path: '/inbox/notes/new',
        builder: (context, state) => const NoteEditorPage(),
      ),
      GoRoute(
        path: '/inbox/notes/:noteId',
        builder: (context, state) => NoteEditorPage(
          noteId: state.pathParameters['noteId']!,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShellScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/inbox',
                builder: (context, state) => const InboxPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/now',
                builder: (context, state) => const NowPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ai',
                builder: (context, state) => const AiPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/add-task',
        builder: (context, state) {
          final extra = state.extra as AddTaskRouteArgs?;
          return AddTaskPage(initialTitle: extra?.initialTitle);
        },
      ),
      GoRoute(
        path: '/focus',
        builder: (context, state) {
          final extra = state.extra as FocusRouteArgs?;
          return FocusPage(args: extra ?? const FocusRouteArgs.demo());
        },
      ),
      GoRoute(
        path: '/deep-focus',
        builder: (context, state) {
          final extra = state.extra as DeepFocusRouteArgs?;
          return DeepFocusPage(args: extra ?? const DeepFocusRouteArgs.demo());
        },
      ),
    ],
  );

  ref.listen<AsyncValue<UserModel?>>(sessionProvider, (previous, next) {
    router.refresh();
  });

  return router;
});

class FocusRouteArgs {
  const FocusRouteArgs({
    required this.title,
    required this.plannedSeconds,
    this.sessionId,
    this.taskId,
    this.markOnboardingComplete = false,
  });

  const FocusRouteArgs.demo()
      : title = 'Demo focus',
        plannedSeconds = 300,
        sessionId = null,
        taskId = null,
        markOnboardingComplete = true;

  final String title;
  final int plannedSeconds;
  final String? sessionId;
  final String? taskId;
  final bool markOnboardingComplete;
}

class DeepFocusRouteArgs {
  const DeepFocusRouteArgs({
    required this.title,
    required this.plannedSeconds,
    this.sessionId,
    this.taskId,
    this.audioAssetPath,
    this.markOnboardingComplete = false,
    this.holdToExit = false,
  });

  const DeepFocusRouteArgs.demo()
      : title = 'Demo deep focus',
        plannedSeconds = 300,
        sessionId = null,
        taskId = null,
        audioAssetPath = null,
        markOnboardingComplete = false,
        holdToExit = false;

  final String title;
  final int plannedSeconds;
  final String? sessionId;
  final String? taskId;
  final String? audioAssetPath;
  final bool markOnboardingComplete;
  final bool holdToExit;
}

class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(color: accent, strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text(
              'FocusFlow',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
