import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_config.dart';
import 'user_facing_errors.dart' show messageLooksLeakedOrTechnical;

const _unreachableTitle = '😔 FocusFlow is unreachable';
const _unreachableBody = 'Check your internet connection and try again.';
const _restartHint = "Still can't connect? Try restarting the app.";

/// Shown for network / leaked-config style failures with retry (max 3 attempts per sheet).
Future<void> showFocusFlowUnreachableSheet(
  BuildContext context, {
  required Future<void> Function() onRetry,
}) async {
  if (!context.mounted) return;
  var attempts = 0;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final on = cs.onSurface;
      final muted = cs.onSurfaceVariant;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _unreachableTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: on,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  attempts >= 3 ? _restartHint : _unreachableBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: muted.withValues(alpha: 0.95),
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                if (attempts < 3)
                  FilledButton(
                    onPressed: () async {
                      try {
                        await onRetry();
                        if (context.mounted) Navigator.pop(context);
                      } catch (_) {
                        attempts++;
                        if (context.mounted) setModalState(() {});
                      }
                    },
                    child: const Text('Retry'),
                  )
                else
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
              ],
            );
          },
        ),
      );
    },
  );
}

void showSessionExpiredSnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Session expired. Please log in again.'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Generic issue with optional bug report (mailto).
Future<void> showUnknownIssueSnackBar(
  BuildContext context, {
  String message = 'Something went wrong. Please try again.',
}) async {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'Report',
        onPressed: () async {
          final uri = Uri(
            scheme: 'mailto',
            path: 'support@focusflow.app',
            queryParameters: {'subject': 'FocusFlow bug report'},
          );
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        },
      ),
    ),
  );
}

/// Whether this failure should use the unreachable + retry sheet (not raw Dio text).
bool shouldPresentUnreachableSheet(Object error) {
  if (error is DioException) {
    if (isRecoverableNetworkDioError(error)) return true;
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return true;
    }
    if (error.type == DioExceptionType.connectionError) return true;
    final msg = '${error.message} ${error.toString()}';
    if (messageLooksLeakedOrTechnical(msg)) return true;
  }
  if (error is StateError && error.message.contains('API_BASE_URL')) {
    return true;
  }
  return messageLooksLeakedOrTechnical(error.toString());
}
