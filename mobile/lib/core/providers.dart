import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_config.dart';
import 'session/focusflow_client.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

final baseUrlProvider = Provider<String>((ref) => resolveApiBaseUrl());

final focusFlowClientProvider = Provider<FocusFlowClient>((ref) {
  final base = ref.watch(baseUrlProvider);
  final storage = ref.watch(secureStorageProvider);
  return FocusFlowClient(baseUrl: base, storage: storage);
});
