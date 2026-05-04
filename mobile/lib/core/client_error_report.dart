import 'dart:async';

import 'error_telemetry.dart';
import 'session/focusflow_client.dart';
import 'user_facing_errors.dart';

/// Sends a best-effort row to `POST /v1/errors/report` for the admin Errors page.
void scheduleClientErrorReport(
  FocusFlowClient? client,
  Object error, {
  required String errorType,
  String? screen,
}) {
  if (client == null) return;
  unawaited(
    client.reportClientError(
      errorType: errorType,
      message: describeErrorForAdmin(error),
      surfaceMessage: userFacingError(error),
      screen: screen,
    ),
  );
}

void scheduleClientErrorReportRaw(
  FocusFlowClient? client, {
  required String errorType,
  required String message,
  required String surfaceMessage,
  String? screen,
}) {
  if (client == null) return;
  unawaited(
    client.reportClientError(
      errorType: errorType,
      message: message,
      surfaceMessage: surfaceMessage,
      screen: screen,
    ),
  );
}
