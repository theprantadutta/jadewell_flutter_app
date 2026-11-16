import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/api/install_identity.dart';
import 'firebase_options.dart';
import 'platform/ads/ad_gate_store_impl.dart';
import 'platform/ads/ad_service_impl.dart';
import 'platform/analytics/debug_print_analytics_impl.dart';
import 'platform/analytics/firebase_analytics_impl.dart';
import 'platform/audio/audio_service_impl.dart';
import 'platform/audio/soloud_engine_impl.dart';
import 'platform/auth/auth_service_impl.dart';
import 'platform/crash/crashlytics_impl.dart';
import 'platform/haptics/haptic_service_impl.dart';
import 'platform/iap/openiap_store_adapter_impl.dart';
import 'platform/iap/pending_verifications.dart';
import 'platform/iap/purchase_service_impl.dart';
import 'state/app_providers.dart';
import 'state/data_providers.dart';
import 'state/entitlement_providers.dart';
import 'state/platform_bridge.dart';
import 'state/platform_providers.dart';
import 'state/session_controller.dart';
import 'ui/theme/jw_fonts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only, phones and tablets (docs/ARCHITECTURE.md §0).
  unawaited(SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]));
  registerFontLicenses();

  // Everything here is local (asset, disk, Firebase config); nothing waits on
  // the network. The backend session starts in the background below.
  // TEMP: config.env, not .env, until flutter/flutter#196444 ships (Android drops dotfile assets).
  await dotenv.load(fileName: 'config.env');
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  // Crashlytics + Analytics collect in release builds only (ARCHITECTURE §0).
  await installCrashReporting();
  unawaited(FirebaseAnalyticsImpl.configureCollection());
  final prefs = await SharedPreferences.getInstance();
  final identity = await InstallIdentity.load();

  final config = AppConfig(
    apiBaseUrl: kReleaseMode
        ? dotenv.env['PROD_API_BACKEND_URL'] ?? 'https://jadewell.pranta.dev/api/v1'
        : dotenv.env['DEV_API_BACKEND_URL'] ?? 'http://127.0.0.1:8393/api/v1',
    googleWebClientId: _nonEmpty(dotenv.env['GOOGLE_WEB_CLIENT_ID']),
  );

  final container = ProviderContainer(
    // docs/ARCHITECTURE.md §4 rule 2: no automatic retries by default.
    retry: (_, _) => null,
    overrides: [
      appConfigProvider.overrideWithValue(config),
      sharedPreferencesProvider.overrideWithValue(prefs),
      installIdentityProvider.overrideWithValue(identity),
      authServiceProvider.overrideWithValue(FirebaseAuthServiceImpl(googleWebClientId: config.googleWebClientId)),
      analyticsProvider.overrideWithValue(kReleaseMode ? FirebaseAnalyticsImpl() : DebugPrintAnalytics()),
      audioProvider.overrideWithValue(AudioServiceImpl(SoLoudAudioEngine())),
      hapticsProvider.overrideWithValue(HapticServiceImpl()),
      adServiceProvider.overrideWith((ref) {
        final ads = AdServiceImpl(store: SharedPrefsAdGateStore(prefs), analytics: ref.watch(analyticsProvider));
        ref.onDispose(ads.dispose);
        return ads;
      }),
      settingsRepositoryProvider.overrideWith((ref) => ref.watch(driftSettingsRepositoryProvider)),
      progressRepositoryProvider.overrideWith((ref) => ref.watch(driftProgressRepositoryProvider)),
      statsRepositoryProvider.overrideWith((ref) => ref.watch(driftStatsRepositoryProvider)),
      dailyRepositoryProvider.overrideWith((ref) => ref.watch(driftDailyRepositoryProvider.future)),
      entitlementRepositoryProvider.overrideWith((ref) => ref.watch(driftEntitlementRepositoryProvider)),
      purchaseServiceProvider.overrideWith((ref) {
        final store = ref.watch(sessionStoreProvider);
        final service = PurchaseServiceImpl(
          store: OpenIapStoreAdapter(),
          entitlements: ref.watch(entitlementRepositoryProvider),
          api: ref.watch(purchasesApiProvider),
          pending: PrefsPendingVerificationStore(prefs),
          analytics: ref.watch(analyticsProvider),
          hasSession: () => store.token != null,
          accountId: () => store.userId,
        );
        ref.onDispose(service.dispose);
        return service;
      }),
    ],
  );
  startBackgroundSync(container); // outbox → backend; never blocks

  // Guest sign-in + backend exchange, fire-and-forget.
  unawaited(container.read(sessionProvider.future).then((_) {}, onError: (Object e) {
    debugPrint('session: start-up sign-in failed: $e');
  }));

  startPurchases(container); // store connect + reconcile in the background; entitlement → ad service

  PlatformBridge.start(container); // settings + lifecycle → audio/haptics; audio starts after first frame

  // Ads: consent (UMP/ATT), SDK and preloads start after the first frame, never blocking start-up.
  WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(container.read(adServiceProvider).init()));

  runApp(UncontrolledProviderScope(container: container, child: const JadewellApp()));
}

String? _nonEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
