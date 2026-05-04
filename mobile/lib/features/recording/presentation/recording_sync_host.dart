import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/runtime_remote_sync.dart' show isServerKnownUnreachable;
import '../../inbox/inbox_providers.dart';
import 'recording_providers.dart';

/// Triggers recording uploads when connectivity is available (additive to inbox outbox).
class RecordingSyncHost extends ConsumerStatefulWidget {
  const RecordingSyncHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RecordingSyncHost> createState() => _RecordingSyncHostState();
}

class _RecordingSyncHostState extends ConsumerState<RecordingSyncHost> {
  ProviderSubscription<AsyncValue<List<ConnectivityResult>>>? _sub;

  @override
  void initState() {
    super.initState();
    
    // Defer sync until after first frame to avoid blocking main thread during cold start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sub = ref.listenManual<AsyncValue<List<ConnectivityResult>>>(
        connectivityProvider,
        (prev, next) {
          final list = next.value;
          if (list == null) return;
          if (inboxConnectivityLooksOffline(list)) return;
          if (isServerKnownUnreachable()) return;
          _runSync();
        },
        fireImmediately: true,
      );
    });
  }

  Future<void> _runSync() async {
    try {
      await ref.read(recordingRepositoryProvider).syncPendingUploads();
      ref.invalidate(recordingsListProvider);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
