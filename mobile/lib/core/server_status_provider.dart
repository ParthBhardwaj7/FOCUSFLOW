import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reactive mirror of [isServerKnownUnreachable] from [runtime_remote_sync.dart].
///
/// `true`  → server responded recently; sync + API calls are allowed.
/// `false` → a recent connection attempt timed-out; UI should use local data
///           and politely skip all outbound network calls until the flag resets.
///
/// Updated via [notifyServerReachable] / [notifyServerUnreachable] which are
/// called from [app_connectivity_sync_host.dart] (registered once via
/// [registerServerReachabilityCallbacks]) so there is no ProviderContainer
/// import needed inside [runtime_remote_sync.dart].
/// Any widget or provider can [watch] this to reactively show an offline banner
/// without triggering additional network calls.
class _ServerReachableNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setReachable() => state = true;
  void setUnreachable() => state = false;
}

final serverReachableProvider =
    NotifierProvider<_ServerReachableNotifier, bool>(
  _ServerReachableNotifier.new,
);
