import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_config.dart';

/// True if [message] looks like an internal/config error string we should not show verbatim.
bool _looksTechnical(String message) {
  final m = message.toUpperCase();
  return m.contains('LLM_') ||
      m.contains('DATABASE') ||
      m.contains('JWT_') ||
      m.contains('PRISMA') ||
      m.contains('OPENROUTER') ||
      m.contains('GROQ') ||
      m.contains('GEMINI') ||
      m.contains('API_KEY') ||
      m.contains('STACK') ||
      m.contains('ECONNREFUSED') ||
      m.contains('SQLITE');
}

/// Single entry point for SnackBars, banners, and inline error text.
String userFacingError(Object error) {
  if (error is AsyncError) {
    return userFacingError(error.error);
  }
  if (error is DioException) {
    return _dioExceptionMessage(error);
  }
  final s = error.toString();
  if (_looksTechnical(s)) {
    return 'Something went wrong. Please try again.';
  }
  return s;
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
      return "Can't connect. Check your internet and try again.";
    case DioExceptionType.badResponse:
      return _badResponseMessage(e);
    default:
      break;
  }
  final msg = e.message?.trim();
  if (msg != null && msg.isNotEmpty && !_looksTechnical(msg)) {
    return msg;
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
    case 400:
      return 'That request was not accepted. Check your input and try again.';
    case 401:
      return 'Sign-in failed. Check your email and password.';
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
          return serverMessage;
        }
        return 'Something went wrong. Please try again.';
      }
      break;
  }
  if (serverMessage != null && !_looksTechnical(serverMessage)) {
    return serverMessage;
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
