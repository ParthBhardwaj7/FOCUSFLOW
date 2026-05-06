import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/dev_config.dart';
import '../core/models/user_model.dart';
import '../core/session/session_controller.dart';
import 'notification_bootstrap.dart';
import 'push_backend_sync.dart';

/// Keeps `POST /v1/notifications/register` in sync with FCM after sign-in,
/// token rotation, and app resume. Shows admin pushes in the foreground on Android/iOS.
class FcmTokenSyncHost extends ConsumerStatefulWidget {
  const FcmTokenSyncHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<FcmTokenSyncHost> createState() => _FcmTokenSyncHostState();
}

class _FcmTokenSyncHostState extends ConsumerState<FcmTokenSyncHost>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _tokenRefreshSub;
  ProviderSubscription<AsyncValue<UserModel?>>? _sessionSub;
  StreamSubscription<RemoteMessage>? _fgSub;

  bool get _firebaseOk => !kIsWeb && Firebase.apps.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    if (!_firebaseOk) return;

    WidgetsBinding.instance.addObserver(this);

    _tokenRefreshSub =
        FirebaseMessaging.instance.onTokenRefresh.listen((t) {
          unawaited(_registerToken(t));
        });

    _sessionSub = ref.listenManual<AsyncValue<UserModel?>>(
      sessionProvider,
      (prev, next) {
        next.whenData((_) => unawaited(_ensureRegistered()));
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bindForegroundDisplay());
      unawaited(_ensureRegistered());
    });
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      WidgetsBinding.instance.removeObserver(this);
      final tr = _tokenRefreshSub;
      if (tr != null) unawaited(tr.cancel());
      final fg = _fgSub;
      if (fg != null) unawaited(fg.cancel());
      _sessionSub?.close();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_ensureRegistered());
    }
  }

  Future<void> _bindForegroundDisplay() async {
    if (!_firebaseOk || !mounted) return;
    await _fgSub?.cancel();
    _fgSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final rn = message.notification;
      final title = (rn?.title ?? message.data['title'] as String?)?.trim();
      final body = (rn?.body ?? message.data['body'] as String?)?.trim();
      if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
        return;
      }
      try {
        await NotificationBootstrap.plugin.show(
          id: message.hashCode.abs().clamp(1, 2147483647),
          title: title != null && title.isNotEmpty ? title : 'FocusFlow',
          body: body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              NotificationBootstrap.channelAdminPush,
              'Announcements',
              channelDescription: 'Messages from FocusFlow (push)',
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
        );
      } catch (e, st) {
        debugPrint('Foreground FCM display failed: $e\n$st');
      }
    });
  }

  Future<void> _ensureRegistered() async {
    if (!_firebaseOk || !mounted || kDevAuthBypass) return;
    final user = ref.read(sessionProvider).value;
    if (user == null) return;

    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e, st) {
      debugPrint('FirebaseMessaging.requestPermission: $e\n$st');
    }

    if (Platform.isAndroid) {
      final n = await Permission.notification.status;
      if (!n.isGranted) {
        await Permission.notification.request();
      }
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();
      await _registerToken(token);
    } catch (e, st) {
      debugPrint('FCM getToken/register failed: $e\n$st');
    }
  }

  Future<void> _registerToken(String? token) async {
    if (!_firebaseOk || !mounted || kDevAuthBypass) return;
    final t = token?.trim();
    if (t == null || t.length < 10) return;
    final user = ref.read(sessionProvider).value;
    if (user == null) return;
    await registerPushTokenWithBackend(ref, deviceToken: t);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
