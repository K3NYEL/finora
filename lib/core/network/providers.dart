import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'finora_api_client.dart';

final finoraApiClientProvider = Provider<FinoraApiClient>((ref) {
  final client = FinoraApiClient();
  ref.onDispose(client.close);
  return client;
});

/// Indicates whether this build was configured with a remote API URL.
/// Local-first mode remains available when no URL is configured.
final finoraApiConfiguredProvider = Provider<bool>(
  (ref) => ref.watch(finoraApiClientProvider).isConfigured,
);

/// Holds the short-lived remote session in memory only. It is never persisted.
final remoteAuthSessionProvider = StateProvider<FinoraApiSession?>((ref) => null);
