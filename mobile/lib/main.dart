import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/api_config.dart';
import 'core/dev_config.dart';
import 'services/notification_bootstrap.dart';

Future<void> main() async {
  final sw = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[DEBUG] WidgetsFlutterBinding.ensureInitialized: ${sw.elapsedMilliseconds}ms');
  
  assertDevAuthBypassNotEnabledInRelease();
  if (kDebugMode && kDevAuthBypass) {
    debugPrint('WARNING: FF_DEV_AUTH_BYPASS is enabled — API auth is skipped.');
  }
  
  await dotenv.load(fileName: '.env', isOptional: true);
  debugPrint('[DEBUG] dotenv.load: ${sw.elapsedMilliseconds}ms');

  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      debugPrint('[DEBUG] Firebase.initializeApp OK: ${sw.elapsedMilliseconds}ms');
    } catch (e, st) {
      debugPrint('Firebase.initializeApp failed (remote push unavailable): $e\n$st');
    }
    try {
      await NotificationBootstrap.init();
    } catch (e, st) {
      debugPrint('NotificationBootstrap.init failed: $e\n$st');
    }
  }
  
  if (kDebugMode) {
    debugPrint('FocusFlow API base URL: ${resolveApiBaseUrl()}');
  }
  
  debugPrint('[DEBUG] About to runApp: ${sw.elapsedMilliseconds}ms');
  runApp(const ProviderScope(child: FocusFlowApp()));
  debugPrint('[DEBUG] runApp returned: ${sw.elapsedMilliseconds}ms');
}
