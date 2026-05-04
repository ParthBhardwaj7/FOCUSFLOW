import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'connectivity_util.dart';
import 'session/focusflow_client.dart';

const _kPublicConfigJson = 'ff_runtime_public_config_json';
const _kFlagsJson = 'ff_runtime_flags_json';
const _kFlagsCachedAtMs = 'ff_runtime_flags_cached_at_ms';
/// Shorter window so admin flag changes propagate without waiting an hour;
/// still skipped when [forceFlags] is used on session / resume / reconnect.
const _kFlagsTtlMs = 15 * 60 * 1000;

/// After the first connection/send timeout we skip further sync attempts for
/// this long (background only — does **not** block the UI). Kept short so when
/// the server comes back without an OS connectivity toggle, we retry soon.
const _kServerUnreachableCooldownMs = 25 * 1000;

/// Epoch-ms until which all server attempts should be skipped.
/// Reset by [resetServerUnreachableBackoff] on a confirmed online transition.
int _serverUnreachableUntilMs = 0;

/// Optional callbacks invoked when reachability changes.
/// Registered once by [AppConnectivitySyncHost] / main so the reactive
/// [serverReachableProvider] stays in sync without importing a ProviderContainer here.
void Function()? _onServerReachable;
void Function()? _onServerUnreachable;

/// Register callbacks to be notified when server reachability changes.
/// Safe to call multiple times — new callbacks overwrite old ones.
void registerServerReachabilityCallbacks({
  required void Function() onReachable,
  required void Function() onUnreachable,
}) {
  _onServerReachable = onReachable;
  _onServerUnreachable = onUnreachable;
}

/// Returns true when a recent connection attempt timed-out (i.e. WiFi is up
/// but the API server is unreachable). All call sites should skip network
/// work while this is true and use cached local data instead.
bool isServerKnownUnreachable() =>
    DateTime.now().millisecondsSinceEpoch < _serverUnreachableUntilMs;

/// Call this when the device transitions from offline → online so the next
/// attempt to reach the server is allowed (typically from [AppConnectivitySyncHost]).
void resetServerUnreachableBackoff() {
  _serverUnreachableUntilMs = 0;
  _onServerReachable?.call();
}

void _setServerUnreachable() {
  _serverUnreachableUntilMs =
      DateTime.now().millisecondsSinceEpoch + _kServerUnreachableCooldownMs;
  _onServerUnreachable?.call();
}

void _logRuntimeSyncFailure(String label, Object e, StackTrace st) {
  if (!kDebugMode) return;
  if (e is DioException && isRecoverableNetworkDioError(e)) {
    final uri = e.requestOptions.uri;
    debugPrint(
      'runtime sync: $label failed (${e.type.name}) → $uri — '
      'offline, server down, or wrong API_BASE_URL for this device (see mobile/.env.example).',
    );
    return;
  }
  debugPrint('runtime sync: $label failed: $e\n$st');
}

/// Serialize syncs so rapid [syncRuntimeRemote] calls (login + resume + net)
/// do not overlap and hammer the same endpoints.
Future<void> _syncMutex = Future<void>.value();

/// Pulls public config whenever online; pulls flags when [signedIn] (1h cache).
Future<void> syncRuntimeRemote(
  FocusFlowClient client, {
  required bool signedIn,
  bool forceFlags = false,
}) {
  // Do not call _syncRuntimeRemoteBody() here — that would start work before the
  // mutex. Chain a closure so only one sync runs at a time.
  final chained = _syncMutex.then(
    (_) => _syncRuntimeRemoteBody(
      client,
      signedIn: signedIn,
      forceFlags: forceFlags,
    ),
  );
  _syncMutex = chained.catchError((Object e, StackTrace st) {});
  return chained;
}

Future<void> _syncRuntimeRemoteBody(
  FocusFlowClient client, {
  required bool signedIn,
  bool forceFlags = false,
}) async {
  try {
    final net = await Connectivity()
        .checkConnectivity()
        .timeout(const Duration(seconds: 2));
    if (connectivityLooksOfflineOnly(net)) {
      if (kDebugMode) {
        debugPrint(
          'runtime sync: skipped (no network); using cached public config / flags.',
        );
      }
      return;
    }
  } on TimeoutException {
    if (kDebugMode) {
      debugPrint('runtime sync: skipped (connectivity check timed out).');
    }
    return;
  } catch (_) {
    if (kDebugMode) {
      debugPrint('runtime sync: skipped (connectivity check failed).');
    }
    return;
  }

  // After a connection/send timeout the server is unreachable (WiFi up but
  // API down). Skip further attempts until the cooldown expires.
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  if (nowMs < _serverUnreachableUntilMs) {
    if (kDebugMode) {
      final sLeft = ((_serverUnreachableUntilMs - nowMs) / 1000).ceil();
      debugPrint(
        'runtime sync: skipped (server unreachable backoff ${sLeft}s remaining).',
      );
    }
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  try {
    final rows = await client.getPublicConfig();
    // Successful fetch — clear any previous backoff and notify listeners.
    _serverUnreachableUntilMs = 0;
    _onServerReachable?.call();
    await prefs.setString(_kPublicConfigJson, jsonEncode(rows));
  } catch (e, st) {
    _logRuntimeSyncFailure('public config', e, st);
    // Any API failure here means the host is down / wrong URL — back off so we
    // do not run three separate sync bodies in a row (each would log again).
    if (e is DioException) {
      _setServerUnreachable();
    }
    // Skip flags when public config already failed — same server.
    return;
  }
  if (!signedIn) return;
  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = prefs.getInt(_kFlagsCachedAtMs) ?? 0;
    if (!forceFlags && now - last < _kFlagsTtlMs) {
      return;
    }
    final flags = await client.getFeatureFlags();
    await prefs.setString(_kFlagsJson, jsonEncode(flags));
    await prefs.setInt(_kFlagsCachedAtMs, now);
  } catch (e, st) {
    _logRuntimeSyncFailure('flags', e, st);
    if (e is DioException) {
      _setServerUnreachable();
    }
  }
}

/// Reads cached public config map key -> value string.
Map<String, String> readCachedPublicConfigMap(SharedPreferences prefs) {
  final raw = prefs.getString(_kPublicConfigJson);
  if (raw == null || raw.isEmpty) return const {};
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    final out = <String, String>{};
    for (final row in list) {
      if (row is! Map) continue;
      final m = Map<String, dynamic>.from(row);
      final k = m['key'];
      final v = m['value'];
      if (k is String && v is String) out[k] = v;
    }
    return out;
  } catch (_) {
    return const {};
  }
}

/// Reads cached feature flags map key -> bool.
Map<String, bool> readCachedFlagsMap(SharedPreferences prefs) {
  final raw = prefs.getString(_kFlagsJson);
  if (raw == null || raw.isEmpty) return const {};
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return m.map((k, v) => MapEntry(k, v == true));
  } catch (_) {
    return const {};
  }
}
