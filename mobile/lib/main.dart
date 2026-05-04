import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  
  if (kDebugMode) {
    debugPrint('FocusFlow API base URL: ${resolveApiBaseUrl()}');
  }
  
  debugPrint('[DEBUG] About to runApp: ${sw.elapsedMilliseconds}ms');
  runApp(const ProviderScope(child: FocusFlowApp()));
  debugPrint('[DEBUG] runApp returned: ${sw.elapsedMilliseconds}ms');
  
  // Run after first frame so timezone + channel setup do not compete with initial
  // layout (reduces "Skipped N frames" / Davey warnings on cold start in debug).
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('[DEBUG] First frame callback executing: ${sw.elapsedMilliseconds}ms');
    unawaited(
      NotificationBootstrap.init().catchError((Object e, StackTrace st) {
        debugPrint('NotificationBootstrap.init failed: $e');
      }),
    );
  });
}
