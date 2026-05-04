import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_config.dart';

bool isAuthLoginRequest(DioException e) {
  final p = e.requestOptions.path;
  return p.contains('/v1/auth/login') || p.contains('/v1/auth/register');
}

/// Substrings that must never be shown verbatim to end users.
bool messageLooksLeakedOrTechnical(String message) {
  final m = message.toUpperCase();
  if (m.isEmpty) return false;
  const needles = [
    'API_BASE_URL',
    '.ENV',
    'LAN IP',
    '192.168.',
    '10.0.2.2',
    'EMULATOR',
    'MOBILE/.ENV',
    'LOCALHOST',
    ':3000',
    ' 3000',
    'FETCH FAILED',
    'NETWORK REQUEST FAILED',
    'ECONNREFUSED',
    'TIMEOUT',
    'SOCKETEXCEPTION',
    'FAILED HOST LOOKUP',
    'CERTIFICATE_VERIFY_FAILED',
    'HANDSHAKE',
    'LLM_',
    'DATABASE',
    'JWT_',
    'PRISMA',
    'OPENROUTER',
    'GROQ',
    'GEMINI',
    'API_KEY',
    'STACK',
    'SQLITE',
    'DIOEXCEPTION',
    'BASEOPTIONS',
  ];
  for (final n in needles) {
    if (m.contains(n)) return true;
  }
  return false;
}

bool _looksTechnical(String message) {
  return messageLooksLeakedOrTechnical(message) ||
      message.toUpperCase().contains('ECONNREFUSED'); // redundant but explicit
}

String _sanitizeFreeform(String s) {
  final t = s.trim();
  if (t.isEmpty) return 'Something went wrong. Please try again.';
  if (_looksTechnical(t)) return 'Something went wrong. Please try again.';
  return t;
}

/// Single entry point for SnackBars, banners, and inline error text.
String userFacingError(Object error) {
  if (error is AsyncError) {
    return userFacingError(error.error);
  }
  if (error is StateError) {
    final msg = error.message;
    if (msg.contains('API_BASE_URL')) {
      return "Can't reach FocusFlow right now. Check your internet and try again.";
    }
  }
  if (error is DioException) {
    return _dioExceptionMessage(error);
  }
  if (error is PlatformException) {
    return "That didn't work on this device. Please try again.";
  }
  if (error is FileSystemException) {
    return 'Could not read that file. If it was just saved, wait a second and try again.';
  }
  if (error is FormatException) {
    return 'That content could not be read. Try again or use a different file.';
  }
  if (error is TypeError) {
    return 'Saved planner data could not be read for this day. Try again or reset the day.';
  }
  final s = error.toString();
  return _sanitizeFreeform(s);
}

String _dioExceptionMessage(DioException e) {
  if (isRecoverableNetworkDioError(e)) {
    return "Can't reach FocusFlow right now. Check your internet and try again.";
  }

  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'The request took too long. Check your connection and try again.';
    case DioExceptionType.connectionError:
      return "Can't reach FocusFlow right now. Check your internet and try again.";
    case DioExceptionType.badResponse:
      return _badResponseMessage(e);
    default:
      break;
  }
  final msg = e.message?.trim();
  if (msg != null && msg.isNotEmpty && !_looksTechnical(msg)) {
    return _sanitizeFreeform(msg);
  }
  return 'Something went wrong. Please try again.';
}

String _badResponseMessage(DioException e) {
  final code = e.response?.statusCode;
  final data = e.response?.data;
  String? serverMessage;
  if (data is Map<String, dynamic>) {
    final m = data['message'];
    if (m is String && m.trim().isNotEmpty) serverMessage = m.trim();
  } else if (data is String && data.trim().isNotEmpty) {
    serverMessage = data.trim();
  }

  switch (code) {
    case 401:
      if (isAuthLoginRequest(e)) {
        return 'Sign-in failed. Check your email and password.';
      }
      return 'Session expired. Please log in again.';
    case 400:
      return 'That request was not accepted. Check your input and try again.';
    case 403:
      return "You don't have access to this. Sign in again if the problem continues.";
    case 404:
      return 'We could not find that. It may have been removed.';
    case 409:
      return 'This was changed elsewhere. Refresh and try again.';
    case 422:
      return 'Some information looks invalid. Check the highlighted fields.';
    case 429:
      return 'Too many requests. Wait a moment and try again.';
    case 503:
      if (serverMessage != null &&
          !serverMessage.toLowerCase().contains('llm') &&
          !_looksTechnical(serverMessage)) {
        return serverMessage;
      }
      return "The coach isn't available right now. Your planner on this device still works.";
    default:
      if (code != null && code >= 500) {
        return 'FocusFlow is having a server problem. Please try again in a few minutes.';
      }
      if (code != null && code >= 400 && code < 500) {
        if (serverMessage != null && !_looksTechnical(serverMessage)) {
          return _sanitizeFreeform(serverMessage);
        }
        return 'Something went wrong. Please try again.';
      }
      break;
  }
  if (serverMessage != null && !_looksTechnical(serverMessage)) {
    return _sanitizeFreeform(serverMessage);
  }
  return 'Something went wrong. Please try again.';
}

/// Legacy name used by auth screens — same as [userFacingError].
String formatDioError(Object error) {
  if (kDebugMode) {
    debugPrint('FocusFlow error (debug): $error');
  }
  return userFacingError(error);
}
