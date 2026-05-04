import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// True when the OS reports no usable data path (e.g. airplane mode).
/// Empty / null lists are treated as "unknown" (not forced offline) to match
/// [inboxConnectivityLooksOffline] behaviour elsewhere.
bool connectivityLooksOfflineOnly(List<ConnectivityResult>? results) {
  if (results == null || results.isEmpty) return false;
  return results.every((e) => e == ConnectivityResult.none);
}

/// Dampens [Connectivity().onConnectivityChanged], which can spam rapid events
/// on some devices (Wi‑Fi/cellular handoff) and rebuild every provider that
/// watches connectivity — inbox merge, shell, AI tab, etc.
Stream<List<ConnectivityResult>> debouncedConnectivityStream(
  Stream<List<ConnectivityResult>> source, {
  Duration debounce = const Duration(milliseconds: 400),
}) {
  final controller = StreamController<List<ConnectivityResult>>();
  Timer? timer;
  List<ConnectivityResult>? pending;

  final sub = source.listen(
    (event) {
      pending = event;
      timer?.cancel();
      timer = Timer(debounce, () {
        final v = pending;
        pending = null;
        if (v != null && !controller.isClosed) controller.add(v);
      });
    },
    onError: controller.addError,
    onDone: () {
      timer?.cancel();
      unawaited(controller.close());
    },
  );

  controller.onCancel = () {
    timer?.cancel();
    sub.cancel();
  };

  return controller.stream;
}
