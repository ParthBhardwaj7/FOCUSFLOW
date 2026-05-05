import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api_config.dart';
import '../connectivity_util.dart';
import '../error_telemetry.dart';
import '../user_facing_errors.dart';
import '../models/note_model.dart';
import '../models/productivity_day_model.dart';
import '../models/task_model.dart';
import '../models/timeline_slot_model.dart';
import '../models/user_model.dart';

const _kAccess = 'ff_access_token';
const _kRefresh = 'ff_refresh_token';
const _kUserCache = 'ff_user_cache_json';

/// When there is no local user cache, [tryRestoreSession] may hit the network.
/// Very tight caps so splash never sits ~10s when the server is down but Wi‑Fi
/// is up (wrong API_BASE_URL, dev machine off, etc.).
const Duration _kColdRestoreNetworkBudget = Duration(seconds: 5);
final Options _kColdRestoreRequestOptions = Options(
  connectTimeout: const Duration(seconds: 2),
  receiveTimeout: const Duration(seconds: 4),
  sendTimeout: const Duration(seconds: 4),
);

/// Public config + flags on launch: must fail fast when LAN/Wi‑Fi is up but API is down.
final Options _kRuntimeSyncRequestOptions = Options(
  connectTimeout: const Duration(seconds: 3),
  receiveTimeout: const Duration(seconds: 5),
  sendTimeout: const Duration(seconds: 5),
);

enum _RefreshOutcome { success, offlineOrTransient, revoked }

class FocusFlowClient {
  FocusFlowClient({
    required String baseUrl,
    required FlutterSecureStorage storage,
  }) : _storage = storage {
    // Tight-but-fair defaults: fast enough to fail when the dev server is down
    // (Wi-Fi up, wrong IP, server off) without dragging the UI. User-initiated
    // actions still have explicit error handling; background sync uses even
    // tighter _kRuntimeSyncRequestOptions (3s/5s).
    const connect = Duration(seconds: 8);
    const receive = Duration(seconds: 20);
    const send = Duration(seconds: 20);
    _plain = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: connect,
        sendTimeout: send,
        receiveTimeout: receive,
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _auth = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: connect,
        sendTimeout: send,
        receiveTimeout: receive,
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _auth.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final t = await _storage.read(key: _kAccess);
          if (t != null && t.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $t';
          }
          handler.next(options);
        },
        onError: (err, handler) async {
          final req = err.requestOptions;
          final isRefresh = req.path.endsWith('/v1/auth/refresh');
          if (err.response?.statusCode == 401 && !isRefresh) {
            final outcome = await _refreshSession();
            if (outcome == _RefreshOutcome.success) {
              final t = await _storage.read(key: _kAccess);
              req.headers['Authorization'] = 'Bearer $t';
              try {
                final res = await _auth.fetch(req);
                return handler.resolve(res);
              } catch (e) {
                return handler.next(err);
              }
            }
            if (outcome == _RefreshOutcome.revoked) {
              await _clearAuthData();
            }
          }
          handler.next(err);
        },
      ),
    );
    _attachTelemetryInterceptors();
  }

  final FlutterSecureStorage _storage;
  late final Dio _plain;
  late final Dio _auth;

  static const int _telemetryDedupeTtlMs = 20_000;
  final Map<String, int> _telemetryDedupeAtMs = {};

  void _attachTelemetryInterceptors() {
    void attach(Dio d) {
      d.interceptors.add(
        InterceptorsWrapper(
          onError: (err, handler) {
            _queueDioFailureReport(err);
            handler.next(err);
          },
        ),
      );
    }

    attach(_auth);
    attach(_plain);
  }

  void _queueDioFailureReport(DioException err) {
    if (!_dioFailureWorthReporting(err)) return;
    unawaited(_sendDioFailureReport(err));
  }

  bool _dioFailureWorthReporting(DioException err) {
    final path = err.requestOptions.path;
    if (path.contains('/v1/errors/report')) return false;
    if (path.contains('/v1/auth/refresh')) return false;
    final code = err.response?.statusCode;
    if (path.contains('/v1/auth/login') || path.contains('/v1/auth/register')) {
      if (code == 401 || code == 400) return false;
    }
    final key = '${err.requestOptions.method} $path ${code ?? err.type.name}';
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _telemetryDedupeAtMs[key] ?? 0;
    if (now - last < _telemetryDedupeTtlMs) return false;
    _telemetryDedupeAtMs[key] = now;
    if (_telemetryDedupeAtMs.length > 200) {
      _telemetryDedupeAtMs.removeWhere((_, v) => now - v > 120000);
    }
    return true;
  }

  Future<void> _sendDioFailureReport(DioException err) async {
    final surface = userFacingError(err);
    final technical = describeErrorForAdmin(err);
    await reportClientError(
      errorType: 'api_${err.type.name}',
      message: technical,
      surfaceMessage: surface,
    );
  }

  Future<String?> readAccessToken() => _storage.read(key: _kAccess);

  Future<void> _clearAuthData() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kUserCache);
  }

  Future<void> _persistUserCache(UserModel user) async {
    await _storage.write(key: _kUserCache, value: jsonEncode(user.toJson()));
  }

  Future<UserModel?> _readCachedUser() async {
    final raw = await _storage.read(key: _kUserCache);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Best-effort decode of JWT payload (no signature verify). Same trust as the
  /// stored access token; used only to rebuild [UserModel] when offline and
  /// the encrypted user cache row is missing (e.g. first launch after an update).
  Map<String, dynamic>? _decodeJwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
        case 1:
          return null;
      }
      final jsonStr = utf8.decode(base64.decode(payload));
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  UserModel? _userFromAccessTokenJwt(String? token) {
    if (token == null || token.isEmpty) return null;
    final m = _decodeJwtPayload(token);
    if (m == null) return null;
    final sub = m['sub'];
    final email = m['email'];
    if (sub is! String || email is! String) return null;
    // JWT does not carry onboarding; non-null sentinel skips Day 0 when restoring
    // offline without a user cache row (upgrade path). Real profile syncs on next /me.
    return UserModel(
      id: sub,
      email: email,
      onboardingCompletedAt: DateTime.fromMillisecondsSinceEpoch(
        1,
        isUtc: true,
      ),
    );
  }

  Future<UserModel?> _cachedOrJwtBootstrapUser() async {
    if (kDebugMode) debugPrint('[DEBUG] _cachedOrJwtBootstrapUser: starting');
    final sw = Stopwatch()..start();
    
    final cached = await _readCachedUser();
    if (kDebugMode) debugPrint('[DEBUG] _cachedOrJwtBootstrapUser: _readCachedUser (${cached != null ? "found" : "null"}): ${sw.elapsedMilliseconds}ms');
    
    if (cached != null) return cached;
    
    if (kDebugMode) debugPrint('[DEBUG] _cachedOrJwtBootstrapUser: reading access token');
    final accessToken = await _storage.read(key: _kAccess);
    if (kDebugMode) debugPrint('[DEBUG] _cachedOrJwtBootstrapUser: access token read: ${sw.elapsedMilliseconds}ms');
    
    final boot = _userFromAccessTokenJwt(accessToken);
    if (kDebugMode) debugPrint('[DEBUG] _cachedOrJwtBootstrapUser: JWT bootstrap (${boot != null ? "found" : "null"}): ${sw.elapsedMilliseconds}ms');
    
    if (boot != null) {
      await _persistUserCache(boot);
      if (kDebugMode) debugPrint('[DEBUG] _cachedOrJwtBootstrapUser: persisted cache: ${sw.elapsedMilliseconds}ms');
      return boot;
    }
    
    if (kDebugMode) debugPrint('[DEBUG] _cachedOrJwtBootstrapUser: returning null: ${sw.elapsedMilliseconds}ms');
    return null;
  }

  /// Rotates tokens when the server is reachable. Does **not** clear tokens on
  /// network errors so offline-first use keeps the signed-in user.
  Future<_RefreshOutcome> _refreshSession({bool coldStart = false}) async {
    final r = await _storage.read(key: _kRefresh);
    if (r == null || r.isEmpty) return _RefreshOutcome.revoked;
    try {
      final res = await _plain.post<Map<String, dynamic>>(
        '/v1/auth/refresh',
        data: {'refreshToken': r},
        options: coldStart ? _kColdRestoreRequestOptions : null,
      );
      final data = res.data!;
      await _storage.write(key: _kAccess, value: data['accessToken'] as String);
      await _storage.write(
        key: _kRefresh,
        value: data['refreshToken'] as String,
      );
      return _RefreshOutcome.success;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        return _RefreshOutcome.revoked;
      }
      if (isRecoverableNetworkDioError(e)) {
        return _RefreshOutcome.offlineOrTransient;
      }
      // Other 4xx (e.g. 400) or unexpected responses: keep session; likely transient/server bug.
      if (code != null && code >= 400 && code < 500) {
        return _RefreshOutcome.offlineOrTransient;
      }
      return _RefreshOutcome.offlineOrTransient;
    } catch (_) {
      return _RefreshOutcome.offlineOrTransient;
    }
  }

  /// Restores the signed-in user from secure storage / JWT **before** blocking on
  /// `GET /v1/me`. When online, [SessionController] runs a silent `me()` refresh.
  Future<UserModel?> tryRestoreSession() async {
    if (kDebugMode) debugPrint('[DEBUG] tryRestoreSession: reading refresh token from storage');
    final sw = Stopwatch()..start();
    
    final refresh = await _storage.read(key: _kRefresh);
    if (kDebugMode) debugPrint('[DEBUG] tryRestoreSession: refresh token read (${refresh != null ? "found" : "null"}): ${sw.elapsedMilliseconds}ms');
    
    if (refresh == null || refresh.isEmpty) return null;

    if (kDebugMode) debugPrint('[DEBUG] tryRestoreSession: calling _cachedOrJwtBootstrapUser');
    final fastUser = await _cachedOrJwtBootstrapUser();
    if (kDebugMode) debugPrint('[DEBUG] tryRestoreSession: _cachedOrJwtBootstrapUser returned (${fastUser != null ? "user" : "null"}): ${sw.elapsedMilliseconds}ms');
    if (fastUser != null) {
      return fastUser;
    }

    // No cached user / JWT bootstrap — cold path needs the API. If the OS says
    // there is no data path, skip network entirely so the router can leave
    // splash immediately (login) instead of waiting on connection timeouts.
    try {
      final net = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 2));
      if (connectivityLooksOfflineOnly(net)) {
        if (kDebugMode) {
          debugPrint(
            'session restore: skip cold network (OS reports offline); '
            'no local user snapshot — go to login.',
          );
        }
        return null;
      }
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint(
          'session restore: connectivity check timed out — skip cold network.',
        );
      }
      return null;
    } catch (_) {}

    try {
      return await _restoreSessionColdNetworkPath().timeout(
        _kColdRestoreNetworkBudget,
        onTimeout: () => _cachedOrJwtBootstrapUser(),
      );
    } on DioException catch (e) {
      if (isRecoverableNetworkDioError(e)) {
        return await _cachedOrJwtBootstrapUser();
      }
      if (e.response?.statusCode == 401) {
        await _clearAuthData();
        return null;
      }
      rethrow;
    }
  }

  /// Refresh + `/me` with short per-request timeouts and bounded total wait.
  Future<UserModel?> _restoreSessionColdNetworkPath() async {
    final outcome = await _refreshSession(coldStart: true);
    if (outcome == _RefreshOutcome.revoked) {
      await _clearAuthData();
      return null;
    }
    if (outcome == _RefreshOutcome.success) {
      try {
        final user = await me(coldStart: true);
        await _persistUserCache(user);
        return user;
      } on DioException catch (e) {
        if (isRecoverableNetworkDioError(e)) {
          return await _cachedOrJwtBootstrapUser();
        }
        if (e.response?.statusCode == 401) {
          await _clearAuthData();
          return null;
        }
        rethrow;
      }
    }
    return await _cachedOrJwtBootstrapUser();
  }

  Future<UserModel> register(String email, String password) async {
    final res = await _plain.post<Map<String, dynamic>>(
      '/v1/auth/register',
      data: {'email': email, 'password': password},
    );
    await _persistTokens(res.data!);
    final user = UserModel.fromJson(res.data!['user'] as Map<String, dynamic>);
    await _persistUserCache(user);
    return user;
  }

  Future<UserModel> login(String email, String password) async {
    final res = await _plain.post<Map<String, dynamic>>(
      '/v1/auth/login',
      data: {'email': email, 'password': password},
    );
    await _persistTokens(res.data!);
    final user = UserModel.fromJson(res.data!['user'] as Map<String, dynamic>);
    await _persistUserCache(user);
    return user;
  }

  Future<UserModel> loginWithGoogleTokens({
    required String idToken,
    String? accessToken,
  }) async {
    final res = await _plain.post<Map<String, dynamic>>(
      '/v1/auth/google',
      data: {
        'idToken': idToken,
        if (accessToken != null && accessToken.trim().isNotEmpty)
          'accessToken': accessToken.trim(),
      },
    );
    await _persistTokens(res.data!);
    final user = UserModel.fromJson(res.data!['user'] as Map<String, dynamic>);
    await _persistUserCache(user);
    return user;
  }

  Future<void> logout() async {
    final r = await _storage.read(key: _kRefresh);
    if (r != null) {
      try {
        await _plain.post('/v1/auth/logout', data: {'refreshToken': r});
      } catch (_) {}
    }
    await _clearAuthData();
  }

  /// Deletes the authenticated user on the server, then clears local tokens.
  Future<void> deleteAccount() async {
    await _auth.delete<void>('/v1/me');
    await _clearAuthData();
  }

  Future<void> _persistTokens(Map<String, dynamic> body) async {
    await _storage.write(key: _kAccess, value: body['accessToken'] as String);
    await _storage.write(key: _kRefresh, value: body['refreshToken'] as String);
  }

  Future<UserModel> me({bool coldStart = false}) async {
    final res = await _auth.get<Map<String, dynamic>>(
      '/v1/me',
      options: coldStart ? _kColdRestoreRequestOptions : null,
    );
    final user = UserModel.fromJson(res.data!);
    await _persistUserCache(user);
    return user;
  }

  /// Bulk planner snapshots for [from]…[to] inclusive (`YYYY-MM-DD`).
  Future<Map<String, dynamic>> bulkPlannerSnapshots(
    String from,
    String to,
  ) async {
    final res = await _auth.get<Map<String, dynamic>>(
      '/v1/planner/snapshots/range',
      queryParameters: {'from': from, 'to': to},
    );
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  /// Upserts one calendar day of slots (compact maps). Returns `{ updatedAt }`.
  Future<Map<String, dynamic>> putPlannerDaySnapshot(
    String dayOn,
    List<Map<String, dynamic>> slots,
  ) async {
    final res = await _auth.put<Map<String, dynamic>>(
      '/v1/planner/snapshots/day/$dayOn',
      data: {'slots': slots},
    );
    return Map<String, dynamic>.from(res.data!);
  }

  Future<UserModel> patchMe({
    DateTime? onboardingCompletedAt,
    String? timeZone,
    String? profileSummary,
  }) async {
    final body = <String, dynamic>{};
    if (onboardingCompletedAt != null) {
      body['onboardingCompletedAt'] = onboardingCompletedAt
          .toUtc()
          .toIso8601String();
    }
    if (timeZone != null) body['timeZone'] = timeZone;
    if (profileSummary != null) body['profileSummary'] = profileSummary;
    final res = await _auth.patch<Map<String, dynamic>>('/v1/me', data: body);
    final user = UserModel.fromJson(res.data!);
    await _persistUserCache(user);
    return user;
  }

  Future<List<TaskModel>> listTasks(String on) async {
    final res = await _auth.get<List<dynamic>>(
      '/v1/tasks',
      queryParameters: {'on': on},
    );
    return (res.data ?? [])
        .map((e) => TaskModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TaskModel> createTask({
    required String title,
    String? notes,
    required String scheduledOn,
    int sortOrder = 0,
    bool isMit = false,
  }) async {
    final data = <String, dynamic>{
      'title': title,
      'scheduledOn': scheduledOn,
      'sortOrder': sortOrder,
      'isMit': isMit,
    };
    if (notes != null) {
      data['notes'] = notes;
    }
    final res = await _auth.post<Map<String, dynamic>>('/v1/tasks', data: data);
    return TaskModel.fromJson(res.data!);
  }

  Future<TaskModel> updateTask(
    String id, {
    String? title,
    String? notes,
    String? scheduledOn,
    int? sortOrder,
    bool? isMit,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (notes != null) body['notes'] = notes;
    if (scheduledOn != null) body['scheduledOn'] = scheduledOn;
    if (sortOrder != null) body['sortOrder'] = sortOrder;
    if (isMit != null) body['isMit'] = isMit;
    final res = await _auth.patch<Map<String, dynamic>>(
      '/v1/tasks/$id',
      data: body,
    );
    return TaskModel.fromJson(res.data!);
  }

  Future<void> deleteTask(String id) async {
    await _auth.delete('/v1/tasks/$id');
  }

  Future<Map<String, dynamic>> createFocusSession({
    String? taskId,
    required int plannedDurationSec,
    Map<String, dynamic>? subtasksSnapshot,
  }) async {
    final data = <String, dynamic>{'plannedDurationSec': plannedDurationSec};
    if (taskId != null) {
      data['taskId'] = taskId;
    }
    if (subtasksSnapshot != null) {
      data['subtasksSnapshot'] = subtasksSnapshot;
    }
    final res = await _auth.post<Map<String, dynamic>>(
      '/v1/focus-sessions',
      data: data,
    );
    return res.data!;
  }

  Future<Map<String, dynamic>> patchFocusSession(
    String id,
    String outcome,
  ) async {
    final res = await _auth.patch<Map<String, dynamic>>(
      '/v1/focus-sessions/$id',
      data: {'outcome': outcome},
    );
    return res.data!;
  }

  /// Lists server [TimelineSlot] rows for calendar day [on] (`YYYY-MM-DD`).
  ///
  /// When `User.timeZone` is set on the server (synced from this device), the API
  /// treats [on] as that **local calendar** day. If `timeZone` is absent, the
  /// server uses a **UTC** calendar day. The shipped client uses planner
  /// snapshots + local SQLite as source of truth; this call is mainly for APIs
  /// and tooling.
  Future<List<TimelineSlotModel>> listTimeline(String on) async {
    final res = await _auth.get<List<dynamic>>(
      '/v1/timeline',
      queryParameters: {'on': on},
    );
    return (res.data ?? [])
        .map((e) => TimelineSlotModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TimelineSlotModel> createTimelineSlot({
    required String startsAtIso,
    required String endsAtIso,
    required String title,
    String? iconKey,
    String? tag,
    String? soundLabel,
    String? status,
    String? linkedTaskId,
    int sortOrder = 0,
  }) async {
    final body = <String, dynamic>{
      'startsAt': startsAtIso,
      'endsAt': endsAtIso,
      'title': title,
      'sortOrder': sortOrder,
    };
    if (iconKey != null) body['iconKey'] = iconKey;
    if (tag != null) body['tag'] = tag;
    if (soundLabel != null) body['soundLabel'] = soundLabel;
    if (status != null) body['status'] = status;
    if (linkedTaskId != null) body['linkedTaskId'] = linkedTaskId;
    final res = await _auth.post<Map<String, dynamic>>(
      '/v1/timeline',
      data: body,
    );
    return TimelineSlotModel.fromJson(res.data!);
  }

  Future<TimelineSlotModel> patchTimelineSlot(
    String id, {
    String? startsAtIso,
    String? endsAtIso,
    String? title,
    String? iconKey,
    String? tag,
    String? soundLabel,
    String? status,
    String? linkedTaskId,
    int? sortOrder,
  }) async {
    final body = <String, dynamic>{};
    if (startsAtIso != null) body['startsAt'] = startsAtIso;
    if (endsAtIso != null) body['endsAt'] = endsAtIso;
    if (title != null) body['title'] = title;
    if (iconKey != null) body['iconKey'] = iconKey;
    if (tag != null) body['tag'] = tag;
    if (soundLabel != null) body['soundLabel'] = soundLabel;
    if (status != null) body['status'] = status;
    if (linkedTaskId != null) body['linkedTaskId'] = linkedTaskId;
    if (sortOrder != null) body['sortOrder'] = sortOrder;
    final res = await _auth.patch<Map<String, dynamic>>(
      '/v1/timeline/$id',
      data: body,
    );
    return TimelineSlotModel.fromJson(res.data!);
  }

  Future<void> deleteTimelineSlot(String id) async {
    await _auth.delete('/v1/timeline/$id');
  }

  /// Replay one queued timeline mutation from [TimelineLocalStore] outbox.
  /// Row keys: `method` (POST|PATCH|DELETE), `pathSuffix` (`/v1/timeline` or `/v1/timeline/:id`),
  /// optional `bodyJson` for POST/PATCH.
  Future<List<NoteModel>> listNotes() async {
    final res = await _auth.get<List<dynamic>>('/v1/notes');
    final raw = res.data;
    if (raw == null) return [];
    return raw
        .map((e) => NoteModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<NoteModel> getNote(String id) async {
    final res = await _auth.get<Map<String, dynamic>>('/v1/notes/$id');
    return NoteModel.fromJson(res.data!);
  }

  Future<NoteModel> createNote({
    String title = '',
    String body = '',
    String tags = '',
    bool pinned = false,
  }) async {
    final res = await _auth.post<Map<String, dynamic>>(
      '/v1/notes',
      data: {'title': title, 'body': body, 'tags': tags, 'pinned': pinned},
    );
    final d = res.data;
    if (d == null) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        type: DioExceptionType.badResponse,
        message: 'Empty response from server',
      );
    }
    return NoteModel.fromJson(d);
  }

  /// Multipart voice note (audio file + metadata). Uses multipart content type.
  Future<NoteModel> createVoiceNote({
    required String title,
    required String transcript,
    required String tags,
    required String audioFilePath,
  }) async {
    final form = FormData.fromMap({
      'title': title,
      if (transcript.trim().isNotEmpty) 'transcript': transcript.trim(),
      'tags': tags,
      'audio': await MultipartFile.fromFile(audioFilePath, filename: 'voice.m4a'),
    });
    final res = await _auth.post<Map<String, dynamic>>(
      '/v1/notes/voice',
      data: form,
      options: Options(contentType: Headers.multipartFormDataContentType),
    );
    final d = res.data;
    if (d == null) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        type: DioExceptionType.badResponse,
        message: 'Empty response from server',
      );
    }
    return NoteModel.fromJson(d);
  }

  /// Downloads synced voice audio to [destPath] (overwrites if exists).
  Future<void> downloadNoteAudio(String noteId, String destPath) async {
    await _auth.download('/v1/notes/$noteId/audio', destPath);
  }

  Future<NoteModel> updateNote(
    String id, {
    String? title,
    String? body,
    String? tags,
    bool? pinned,
    DateTime? expectedUpdatedAt,
  }) async {
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (body != null) data['body'] = body;
    if (tags != null) data['tags'] = tags;
    if (pinned != null) data['pinned'] = pinned;
    if (expectedUpdatedAt != null) {
      data['expectedUpdatedAt'] = expectedUpdatedAt.toUtc().toIso8601String();
    }
    final res = await _auth.patch<Map<String, dynamic>>(
      '/v1/notes/$id',
      data: data,
    );
    final d = res.data;
    if (d == null) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        type: DioExceptionType.badResponse,
        message: 'Empty response from server',
      );
    }
    return NoteModel.fromJson(d);
  }

  Future<void> deleteNote(String id) async {
    await _auth.delete('/v1/notes/$id');
  }

  Future<ProductivityPayload> getProductivity({required int range}) async {
    final res = await _auth.get<Map<String, dynamic>>(
      '/v1/analytics/productivity',
      queryParameters: {'range': '$range'},
    );
    final d = res.data!;
    return ProductivityPayload(
      timeZone: d['timeZone'] as String,
      range: (d['range'] as num).toInt(),
      days: (d['days'] as List<dynamic>)
          .map((e) => ProductivityDayModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<String> aiChat(List<Map<String, String>> messages) async {
    final res = await _auth.post<Map<String, dynamic>>(
      '/v1/ai/chat',
      data: {
        'messages': messages
            .map((m) => {'role': m['role'], 'content': m['content']})
            .toList(),
      },
    );
    return res.data!['message'] as String;
  }

  Future<void> ingestMemory({
    required String content,
    String source = 'NOTE',
  }) async {
    await _auth.post<dynamic>(
      '/v1/ai/memory/ingest',
      data: {'content': content, 'source': source},
    );
  }

  /// Remote public config (no auth). Used on launch / resume.
  Future<List<dynamic>> getPublicConfig() async {
    final res = await _plain.get<List<dynamic>>(
      '/v1/config/public',
      options: _kRuntimeSyncRequestOptions,
    );
    return res.data ?? const [];
  }

  /// Feature flags for the signed-in user (auth).
  Future<Map<String, dynamic>> getFeatureFlags() async {
    final res = await _auth.get<Map<String, dynamic>>(
      '/v1/flags',
      options: _kRuntimeSyncRequestOptions,
    );
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  /// Best-effort client error reporting. Uses [_plain] with an optional Bearer
  /// so this does not recurse through [_auth] interceptors.
  Future<void> reportClientError({
    required String errorType,
    required String message,
    String? surfaceMessage,
    String? screen,
    String? appVersion,
    String? deviceOs,
  }) async {
    try {
      final token = await _storage.read(key: _kAccess);
      final headers = <String, dynamic>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      String clip(String s, int max) =>
          s.length <= max ? s : '${s.substring(0, max)}…';
      final payload = <String, dynamic>{
        'errorType': errorType,
        'message': clip(message, 7500),
        'surfaceMessage': surfaceMessage != null
            ? clip(surfaceMessage, 500)
            : null,
        'screen': screen,
        'appVersion': appVersion,
        'deviceOs': deviceOs,
      }..removeWhere((_, v) => v == null);
      await _plain.post<void>(
        '/v1/errors/report',
        data: payload,
        options: Options(headers: headers),
      );
    } catch (_) {}
  }

  /// Registers FCM/APNs token for targeted pushes (auth).
  Future<void> registerPushDevice({
    required String deviceToken,
    required String platform,
  }) async {
    await _auth.post<void>(
      '/v1/notifications/register',
      data: {'deviceToken': deviceToken, 'platform': platform},
    );
  }

  Future<void> replayTimelineOutboxRow(Map<String, Object?> row) async {
    final path = row['pathSuffix'] as String;
    if (!path.startsWith('/v1/timeline')) {
      throw ArgumentError.value(
        path,
        'pathSuffix',
        'must start with /v1/timeline',
      );
    }
    final method = (row['method'] as String).toUpperCase();
    final raw = row['bodyJson'] as String?;
    final Object? data = raw != null && raw.trim().isNotEmpty
        ? jsonDecode(raw) as Object?
        : null;
    switch (method) {
      case 'POST':
        await _auth.post<dynamic>(path, data: data ?? <String, dynamic>{});
        break;
      case 'PATCH':
        await _auth.patch<dynamic>(path, data: data ?? <String, dynamic>{});
        break;
      case 'DELETE':
        await _auth.delete<dynamic>(path);
        break;
      default:
        throw ArgumentError.value(
          method,
          'method',
          'expected POST, PATCH, or DELETE',
        );
    }
  }

  /// Standalone voice recording upload (`multipart/form-data`, field `audio`).
  /// Server returns `{ "url": "<full or relative stream URL>" }`.
  Future<String> uploadStandaloneRecording({
    required String absoluteFilePath,
    required String recordingId,
  }) async {
    final normalized = absoluteFilePath.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    final form = FormData.fromMap({
      'audio': await MultipartFile.fromFile(absoluteFilePath, filename: name),
    });
    final res = await _auth.post<Map<String, dynamic>>(
      '/v1/recordings/upload',
      data: form,
      queryParameters: {'id': recordingId},
    );
    final data = res.data;
    var url = data?['url'] as String?;
    if (url == null || url.trim().isEmpty) {
      throw StateError('Server returned no recording url');
    }
    url = url.trim();
    if (!url.startsWith('http')) {
      final b = resolveApiBaseUrl().replaceAll(RegExp(r'/+$'), '');
      url = '$b${url.startsWith('/') ? '' : '/'}$url';
    }
    return url;
  }
}
