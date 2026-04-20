import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api_config.dart';
import '../models/note_model.dart';
import '../models/productivity_day_model.dart';
import '../models/task_model.dart';
import '../models/timeline_slot_model.dart';
import '../models/user_model.dart';

const _kAccess = 'ff_access_token';
const _kRefresh = 'ff_refresh_token';
const _kUserCache = 'ff_user_cache_json';

enum _RefreshOutcome { success, offlineOrTransient, revoked }

class FocusFlowClient {
  FocusFlowClient({required String baseUrl, required FlutterSecureStorage storage})
      : _storage = storage {
    // Tighter timeouts so cold start / offline fail fast; see tryRestoreSession
    // cache-first path so splash is not blocked on me() or refresh.
    const connect = Duration(seconds: 4);
    const receive = Duration(seconds: 18);
    _plain = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: connect,
        receiveTimeout: receive,
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _auth = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: connect,
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
  }

  final FlutterSecureStorage _storage;
  late final Dio _plain;
  late final Dio _auth;

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
      onboardingCompletedAt: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
    );
  }

  Future<UserModel?> _cachedOrJwtBootstrapUser() async {
    final cached = await _readCachedUser();
    if (cached != null) return cached;
    final boot = _userFromAccessTokenJwt(await _storage.read(key: _kAccess));
    if (boot != null) {
      await _persistUserCache(boot);
      return boot;
    }
    return null;
  }

  /// Rotates tokens when the server is reachable. Does **not** clear tokens on
  /// network errors so offline-first use keeps the signed-in user.
  Future<_RefreshOutcome> _refreshSession() async {
    final r = await _storage.read(key: _kRefresh);
    if (r == null || r.isEmpty) return _RefreshOutcome.revoked;
    try {
      final res = await _plain.post<Map<String, dynamic>>(
        '/v1/auth/refresh',
        data: {'refreshToken': r},
      );
      final data = res.data!;
      await _storage.write(key: _kAccess, value: data['accessToken'] as String);
      await _storage.write(key: _kRefresh, value: data['refreshToken'] as String);
      return _RefreshOutcome.success;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        return _RefreshOutcome.revoked;
      }
      if (isRecoverableNetworkDioError(e)) {
        return _RefreshOutcome.offlineOrTransient;
      }
      return _RefreshOutcome.revoked;
    } catch (_) {
      return _RefreshOutcome.offlineOrTransient;
    }
  }

  /// Restores the signed-in user from secure storage / JWT **before** blocking on
  /// `GET /v1/me`. When online, [SessionController] runs a silent `me()` refresh.
  Future<UserModel?> tryRestoreSession() async {
    final refresh = await _storage.read(key: _kRefresh);
    if (refresh == null || refresh.isEmpty) return null;

    final fastUser = await _cachedOrJwtBootstrapUser();
    if (fastUser != null) {
      return fastUser;
    }

    final outcome = await _refreshSession();
    if (outcome == _RefreshOutcome.revoked) {
      await _clearAuthData();
      return null;
    }
    if (outcome == _RefreshOutcome.success) {
      try {
        final user = await me();
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

  Future<void> logout() async {
    final r = await _storage.read(key: _kRefresh);
    if (r != null) {
      try {
        await _plain.post('/v1/auth/logout', data: {'refreshToken': r});
      } catch (_) {}
    }
    await _clearAuthData();
  }

  Future<void> _persistTokens(Map<String, dynamic> body) async {
    await _storage.write(key: _kAccess, value: body['accessToken'] as String);
    await _storage.write(key: _kRefresh, value: body['refreshToken'] as String);
  }

  Future<UserModel> me() async {
    final res = await _auth.get<Map<String, dynamic>>('/v1/me');
    final user = UserModel.fromJson(res.data!);
    await _persistUserCache(user);
    return user;
  }

  Future<UserModel> patchMe({
    DateTime? onboardingCompletedAt,
    String? timeZone,
    String? profileSummary,
  }) async {
    final body = <String, dynamic>{};
    if (onboardingCompletedAt != null) {
      body['onboardingCompletedAt'] = onboardingCompletedAt.toUtc().toIso8601String();
    }
    if (timeZone != null) body['timeZone'] = timeZone;
    if (profileSummary != null) body['profileSummary'] = profileSummary;
    final res = await _auth.patch<Map<String, dynamic>>('/v1/me', data: body);
    final user = UserModel.fromJson(res.data!);
    await _persistUserCache(user);
    return user;
  }

  Future<List<TaskModel>> listTasks(String on) async {
    final res = await _auth.get<List<dynamic>>('/v1/tasks', queryParameters: {'on': on});
    return (res.data ?? []).map((e) => TaskModel.fromJson(e as Map<String, dynamic>)).toList();
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
    final res = await _auth.patch<Map<String, dynamic>>('/v1/tasks/$id', data: body);
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
    final data = <String, dynamic>{
      'plannedDurationSec': plannedDurationSec,
    };
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

  Future<Map<String, dynamic>> patchFocusSession(String id, String outcome) async {
    final res = await _auth.patch<Map<String, dynamic>>(
      '/v1/focus-sessions/$id',
      data: {'outcome': outcome},
    );
    return res.data!;
  }

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
    final res = await _auth.post<Map<String, dynamic>>('/v1/timeline', data: body);
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
    final res = await _auth.patch<Map<String, dynamic>>('/v1/timeline/$id', data: body);
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
    return (res.data ?? [])
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
    bool pinned = false,
  }) async {
    final res = await _auth.post<Map<String, dynamic>>(
      '/v1/notes',
      data: {'title': title, 'body': body, 'pinned': pinned},
    );
    return NoteModel.fromJson(res.data!);
  }

  Future<NoteModel> updateNote(
    String id, {
    String? title,
    String? body,
    bool? pinned,
    DateTime? expectedUpdatedAt,
  }) async {
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (body != null) data['body'] = body;
    if (pinned != null) data['pinned'] = pinned;
    if (expectedUpdatedAt != null) {
      data['expectedUpdatedAt'] = expectedUpdatedAt.toUtc().toIso8601String();
    }
    final res = await _auth.patch<Map<String, dynamic>>('/v1/notes/$id', data: data);
    return NoteModel.fromJson(res.data!);
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

  Future<void> replayTimelineOutboxRow(Map<String, Object?> row) async {
    final path = row['pathSuffix'] as String;
    if (!path.startsWith('/v1/timeline')) {
      throw ArgumentError.value(path, 'pathSuffix', 'must start with /v1/timeline');
    }
    final method = (row['method'] as String).toUpperCase();
    final raw = row['bodyJson'] as String?;
    final Object? data =
        raw != null && raw.trim().isNotEmpty ? jsonDecode(raw) as Object? : null;
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
        throw ArgumentError.value(method, 'method', 'expected POST, PATCH, or DELETE');
    }
  }
}
