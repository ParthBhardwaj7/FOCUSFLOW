import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_config.dart';
import '../../core/connectivity_util.dart';
import '../../core/models/note_model.dart';
import '../../core/providers.dart';
import '../../core/runtime_remote_sync.dart'
    show alignServerReachableAfterBackoff, isServerKnownUnreachable;
import '../../core/server_status_provider.dart';
import '../../data/inbox_local_store.dart';

final inboxLocalStoreProvider = FutureProvider<InboxLocalStore>((ref) async {
  final s = InboxLocalStore();
  await s.db.timeout(
    const Duration(seconds: 12),
    onTimeout: () => throw TimeoutException('inbox SQLite open'),
  );
  return s;
});

/// Pending outbox rows only (SQLite). Used for the tab badge when we are not
/// definitely online so the shell never blocks on [inboxMergedProvider] / API.
final inboxLocalPendingCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final store = await ref.watch(inboxLocalStoreProvider.future);
  final rows = await store
      .listPendingRows()
      .timeout(
        const Duration(seconds: 8),
        onTimeout: () => const <Map<String, Object?>>[],
      );
  return rows.length;
});

/// Invalidate merged inbox + local badge counters together.
void invalidateInboxCachesRef(Ref ref) {
  ref.invalidate(inboxMergedProvider);
  ref.invalidate(inboxLocalPendingCountProvider);
}

/// Same as [invalidateInboxCachesRef] for widget build contexts (Riverpod 3
/// uses a distinct [WidgetRef] type).
void invalidateInboxCachesWidget(WidgetRef ref) {
  ref.invalidate(inboxMergedProvider);
  ref.invalidate(inboxLocalPendingCountProvider);
}

/// Latest connectivity snapshot (none → offline).
///
/// The first `checkConnectivity()` can hang on some OEM builds; if it never
/// completes, anything that `watch`es this provider (e.g. [inboxMergedProvider])
/// would stay loading forever. Time out hard and treat as offline until the
/// stream delivers a real update.
///
/// Subsequent updates use [debouncedConnectivityStream] so OEMs that fire
/// many connectivity events in a row do not re-run merge/sync on every tick.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) async* {
  try {
    yield await Connectivity().checkConnectivity().timeout(
      const Duration(seconds: 2),
    );
  } on TimeoutException {
    yield const [ConnectivityResult.none];
  } catch (_) {
    yield const [ConnectivityResult.none];
  }
  yield* debouncedConnectivityStream(Connectivity().onConnectivityChanged);
});

bool inboxConnectivityLooksOffline(List<ConnectivityResult>? results) {
  return connectivityLooksOfflineOnly(results);
}

/// Server + local outbox, newest first. Recoverable list failures still show locals.
///
/// Offline / API cooldown → returns local SQLite drafts AND cached server notes **immediately**
/// (no network timeout wait). When online and not in unreachable backoff, merges remote
/// notes on top of local drafts and updates the local cache. Rebuilds when
/// [connectivityProvider] or [serverReachableProvider] changes ([alignServerReachableAfterBackoff]
/// updates the latter when the backoff window ends).
final inboxMergedProvider = FutureProvider.autoDispose<List<NoteModel>>((
  ref,
) async {
  // Tab switches used to dispose this provider and re-hit `listNotes()` on
  // every return to Inbox — felt like constant buffering despite a warm cache.
  ref.keepAlive();

  final store = await ref.watch(inboxLocalStoreProvider.future);

  // Watch both connectivity and server status so we rebuild when either changes.
  final net = ref.watch(connectivityProvider);
  ref.watch(serverReachableProvider);

  /// Heal stale "server down" UI after the unreachable cooldown expires.
  alignServerReachableAfterBackoff();

  final offline = net.maybeWhen(
    data: (r) => inboxConnectivityLooksOffline(r),
    orElse: () => true, // treat unknown/loading as offline for safety
  );

  // Fetch local drafts and cached server notes — always available instantly from SQLite.
  final localRows = await store
      .listPendingRows()
      .timeout(
        const Duration(seconds: 8),
        onTimeout: () => const <Map<String, Object?>>[],
      );
  final localNotes = store.pendingAsNotes(localRows);
  
  final cachedServerRows = await store
      .listServerNotes()
      .timeout(
        const Duration(seconds: 8),
        onTimeout: () => const <Map<String, Object?>>[],
      );
  final cachedServerNotes = store.serverAsNotes(cachedServerRows);

  // Skip network when offline or in API unreachable cooldown (matches planner).
  if (offline || isServerKnownUnreachable()) {
    final byId = <String, NoteModel>{};
    for (final n in cachedServerNotes) {
      byId[n.id] = n;
    }
    for (final n in localNotes) {
      byId[n.id] = n;
    }
    return byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<NoteModel> remote = [];
  bool networkSuccess = false;
  try {
    remote = await ref
        .read(focusFlowClientProvider)
        .listNotes()
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => <NoteModel>[],
        );
    networkSuccess = true;
  } on DioException catch (e) {
    if (!isRecoverableNetworkDioError(e)) rethrow;
    remote = [];
  }

  // Update local cache with latest server notes
  if (networkSuccess) {
    try {
      await store.replaceServerNotes(remote);
    } catch (_) {}
  } else {
    // If network failed but didn't throw (timeout), fall back to cached
    remote = cachedServerNotes;
  }

  final byId = <String, NoteModel>{};
  for (final n in remote) {
    byId[n.id] = n;
  }
  for (final n in localNotes) {
    byId[n.id] = n;
  }
  return byId.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
});

/// Bottom-nav inbox dot: **pending outbox only** (captures not yet uploaded).
///
/// Never watches [inboxMergedProvider], so opening the shell does not trigger
/// `listNotes()` on every frame — that was a major source of jank and
/// unnecessary buffering while “online”.
final inboxTabBadgeCountProvider = Provider<int>((ref) {
  return ref
      .watch(inboxLocalPendingCountProvider)
      .maybeWhen(data: (c) => c, orElse: () => 0);
});

/// Uploads queued captures.
/// Skips when OS reports offline-only OR server is known unreachable.
Future<void> syncInboxOutbox(WidgetRef ref) async {
  if (isServerKnownUnreachable()) return;
  final netAsync = ref.read(connectivityProvider);
  final net = netAsync.value;
  // Treat unknown/loading connectivity as offline-safe: avoid noisy retries
  // while radios are still initializing after resume.
  if (net == null || inboxConnectivityLooksOffline(net)) return;

  final client = ref.read(focusFlowClientProvider);
  final store = await ref.read(inboxLocalStoreProvider.future);
  final rows = await store.listPendingRowsOldestFirst();
  for (final r in rows) {
    final id = r['id']! as String;
    final title = r['title']! as String;
    final body = r['body']! as String;
    final tags = r['tags']! as String;
    final audioPath = r['audio_path'] as String?;
    try {
      if (audioPath != null && audioPath.trim().isNotEmpty) {
        final f = File(audioPath.trim());
        if (f.existsSync()) {
          await client.createVoiceNote(
            title: title,
            transcript: body,
            tags: tags,
            audioFilePath: f.path,
          );
        } else {
          await client.createNote(title: title, body: body, tags: tags);
        }
      } else {
        await client.createNote(title: title, body: body, tags: tags);
      }
      if (audioPath != null && audioPath.trim().isNotEmpty) {
        try {
          final f = File(audioPath.trim());
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
      await store.deleteRow(id);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        break;
      }
      if (isRecoverableNetworkDioError(e)) {
        break;
      }
      break;
    } catch (_) {
      break;
    }
  }

  // Always invalidate and re-read the merged provider to trigger a background
  // fetch of the latest server notes and populate the offline SQLite cache.
  invalidateInboxCachesWidget(ref);
  try {
    await ref.read(inboxMergedProvider.future);
  } catch (_) {}
}

/// Legacy provider name — maps to merged inbox.
final notesListProvider = inboxMergedProvider;
