import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api/api_client.dart';
import '../data/api/auth_api.dart';
import '../data/api/install_identity.dart';
import '../data/api/session_store.dart';
import '../platform/auth/auth_service.dart';
import 'session_controller.dart';

/// Values read from `.env` at start-up (public values only).
class AppConfig {
  const AppConfig({required this.apiBaseUrl, this.googleWebClientId});

  /// Includes `/api/v1`.
  final String apiBaseUrl;
  final String? googleWebClientId;
}

// Overridden in main.dart (and in tests). Throwing defaults make a missing
// override fail loudly instead of silently using a wrong implementation.
final appConfigProvider = Provider<AppConfig>((ref) => throw UnimplementedError('appConfigProvider'));
final sharedPreferencesProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError('sharedPreferencesProvider'));
final installIdentityProvider = Provider<InstallIdentity>((ref) => throw UnimplementedError('installIdentityProvider'));
final authServiceProvider = Provider<AuthService>((ref) => throw UnimplementedError('authServiceProvider'));

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore(ref.watch(sharedPreferencesProvider)));

final apiClientProvider = Provider<ApiClient>((ref) {
  final store = ref.watch(sessionStoreProvider);
  final client = ApiClient(
    baseUrl: ref.watch(appConfigProvider).apiBaseUrl,
    identity: ref.watch(installIdentityProvider),
    tokenProvider: () => store.token,
    onUnauthorized: () => ref.read(sessionProvider.notifier).onUnauthorized(),
  );
  ref.onDispose(client.close);
  return client;
});

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));
