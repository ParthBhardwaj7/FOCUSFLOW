import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Reads [API_BASE_URL] from `mobile/.env` (loaded in `main.dart`).
///
/// In **debug** builds, falls back to the Android emulator loopback when unset
/// so `flutter run` works without extra setup. In **release**, set `API_BASE_URL`
/// in `.env` (or build-time injection); if still unset, uses the same fallback
/// so the app does not crash (offline productivity still works).
String resolveApiBaseUrl() {
  final raw = dotenv.env['API_BASE_URL']?.trim();
  if (raw != null && raw.isNotEmpty) return raw;
  if (kDebugMode) {
    debugPrint(
      'API_BASE_URL not set; using Android emulator default. '
      'Set API_BASE_URL in mobile/.env for devices or production.',
    );
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
