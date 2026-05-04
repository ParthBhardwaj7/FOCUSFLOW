import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_connectivity_sync_host.dart';
import 'core/appearance_prefs.dart' show appearanceSettingsProvider, kAccentPalette;
import 'features/recording/presentation/recording_sync_host.dart';
import 'router.dart';
import 'theme/focusflow_theme.dart';

class FocusFlowApp extends ConsumerWidget {
  const FocusFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[DEBUG] FocusFlowApp.build starting');
    final sw = Stopwatch()..start();
    
    final router = ref.watch(goRouterProvider);
    debugPrint('[DEBUG] goRouterProvider loaded: ${sw.elapsedMilliseconds}ms');
    
    final accent = ref.watch(
      appearanceSettingsProvider.select(
        (a) => a.asData?.value.accent ?? kAccentPalette[0],
      ),
    );
    debugPrint('[DEBUG] appearanceSettingsProvider loaded: ${sw.elapsedMilliseconds}ms');
    
    final themeMode = ref.watch(
      appearanceSettingsProvider.select(
        (a) => a.asData?.value.themeMode ?? ThemeMode.dark,
      ),
    );
    debugPrint('[DEBUG] themeMode loaded: ${sw.elapsedMilliseconds}ms');
    
    debugPrint('[DEBUG] Building widget tree');
    return AppConnectivitySyncHost(
      child: RecordingSyncHost(
        child: MaterialApp.router(
          title: 'FocusFlow',
          theme: buildFocusFlowTheme(brightness: Brightness.light, accent: accent),
          darkTheme: buildFocusFlowTheme(
            brightness: Brightness.dark,
            accent: accent,
          ),
          themeMode: themeMode,
          routerConfig: router,
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
