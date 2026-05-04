import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Reads [API_BASE_URL] from `mobile/.env` (loaded in `main.dart`).
///
/// In **debug** / **profile** when unset: Android defaults to the **emulator**
/// host (`10.0.2.2`). **Physical phones** must set `API_BASE_URL` (e.g. your PC’s
/// LAN IP) — see [mobile/.env.example]. In **release**, [API_BASE_URL] is required.
String resolveApiBaseUrl() {
  final raw = dotenv.env['API_BASE_URL']?.trim();
  if (raw != null && raw.isNotEmpty) {
    // Avoid Dio joining paths as `host//v1/...` when `.env` has a trailing slash.
    return raw.replaceAll(RegExp(r'/+$'), '');
  }
  if (kReleaseMode) {
    throw StateError(
      'API_BASE_URL must be set in mobile/.env for release builds.',
    );
  }
  if (kDebugMode) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      debugPrint(
        'API_BASE_URL not set — using http://10.0.2.2:3000 (Android emulator → host). '
        'On a real phone, create mobile/.env with API_BASE_URL=http://<PC_LAN_IP>:3000 '
        '(same Wi‑Fi as the phone). Example: API_BASE_URL=http://192.168.1.10:3000',
      );
      return 'http://10.0.2.2:3000';
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      debugPrint(
        'API_BASE_URL not set — using http://127.0.0.1:3000 (iOS simulator → host). '
        'On a real device, set API_BASE_URL in mobile/.env.',
      );
      return 'http://127.0.0.1:3000';
    }
    debugPrint(
      'API_BASE_URL not set — using http://127.0.0.1:3000. '
      'Set API_BASE_URL in mobile/.env if the API is elsewhere.',
    );
    return 'http://127.0.0.1:3000';
  }
  return 'http://10.0.2.2:3000';
}

/// Errors where we should **keep** refresh/access tokens and allow offline use.
bool isRecoverableNetworkDioError(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
    case DioExceptionType.badCertificate:
    case DioExceptionType.cancel:
      return true;
    case DioExceptionType.unknown:
      return e.response == null;
    case DioExceptionType.badResponse:
      final code = e.response?.statusCode;
      if (code == null) return true;
      if (code == 408 || code == 425) return true;
      return code >= 500;
  }
}
