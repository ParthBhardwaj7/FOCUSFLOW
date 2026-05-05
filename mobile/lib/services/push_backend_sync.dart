import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/session/session_controller.dart';

/// Sends a device push token to `POST /v1/notifications/register` so the admin
/// panel and backend can target this install (FCM / APNs).
///
/// Wire this from your FCM integration (`firebase_messaging` + `flutterfire
/// configure` → `FirebaseMessaging.instance.getToken()`), on sign-in, token
/// refresh, and [AppLifecycleState.resumed].
Future<void> registerPushTokenWithBackend(
  WidgetRef ref, {
  required String deviceToken,
}) async {
  final t = deviceToken.trim();
  if (t.length < 10) return;
  final user = ref.read(sessionProvider).value;
  if (user == null) return;
  final platform = Platform.isIOS ? 'IOS' : 'ANDROID';
  try {
    await ref.read(focusFlowClientProvider).registerPushDevice(
          deviceToken: t,
          platform: platform,
        );
  } catch (e, st) {
    debugPrint('registerPushTokenWithBackend failed: $e\n$st');
  }
}
