import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crashlytics, release builds only (docs/ARCHITECTURE.md §0 and §6).
///
/// Collection is switched off in debug and profile, so developer machines
/// never reach the production dashboard, and the error hooks are only
/// installed in release: debug keeps Flutter's red screen and console dump.
/// Call after `Firebase.initializeApp`.
Future<void> installCrashReporting() async {
  final crashlytics = FirebaseCrashlytics.instance;
  try {
    await crashlytics.setCrashlyticsCollectionEnabled(kReleaseMode);
  } catch (e) {
    debugPrint('crash: setCrashlyticsCollectionEnabled failed: $e');
    return;
  }
  if (!kReleaseMode) return;

  // Framework errors (build/layout/paint, gesture callbacks).
  FlutterError.onError = crashlytics.recordFlutterFatalError;

  // Everything else that escapes to the root zone (async errors, platform
  // channel callbacks). Returning true marks the error as handled.
  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };
}
