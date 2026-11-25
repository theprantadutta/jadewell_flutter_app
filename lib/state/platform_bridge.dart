import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/settings.dart';
import '../platform/analytics/analytics_route_observer.dart';
import '../platform/analytics/analytics_service.dart';
import 'data_providers.dart';
import 'entitlement_providers.dart';
import 'platform_providers.dart';
import 'reminder_controller.dart';
import 'session_controller.dart';
import 'store_listing_controller.dart';

/// Screen-view tracking for the router: `observers: [ref.read(analyticsRouteObserverProvider)]`.
final analyticsRouteObserverProvider =
    Provider<AnalyticsRouteObserver>((ref) => AnalyticsRouteObserver(ref.watch(analyticsProvider)));

/// Wires settings and the app lifecycle into the audio and haptics services.
///
/// * Settings → `setMusicEnabled` / `setSfxEnabled` / haptics `setEnabled`,
///   on every change, instantly.
/// * Lifecycle → `audio.onBackground()` on paused/detached and
///   `audio.onForeground()` on resume.
/// * Settings → High refresh rate → the display service, on every change.
/// * Start-up: the audio engine starts after the first frame (it never delays
///   app start), and music starts once the saved settings have loaded, so a
///   player who turned music off never hears a note of it.
/// * Play in-app updates: checked a few seconds after start-up (never
///   competing with the first frames) and on every resume.
/// * Analytics user properties (account, ads_removed, onboarding_done,
///   theme), sent only when a value changes.
/// * Daily reminder: scheduled when the app goes to the background,
///   cancelled after the first frame and on every resume
///   (`ReminderController`, `ReminderPolicy`).
///
/// Created once in main.dart; [dispose] undoes everything.
class PlatformBridge {
  PlatformBridge._(this._container);

  final ProviderContainer _container;
  ProviderSubscription<AsyncValue<AppSettings>>? _settings;
  ProviderSubscription<AsyncValue<BackendSession>>? _session;
  ProviderSubscription<Entitlement>? _entitlement;
  final Map<String, String?> _userProperties = {};
  AppLifecycleListener? _lifecycle;
  bool _musicStarted = false;
  bool? _highRefresh;
  Timer? _updateCheck;

  static PlatformBridge start(ProviderContainer container) => PlatformBridge._(container).._attach();

  void _attach() {
    final audio = _container.read(audioProvider);
    final haptics = _container.read(hapticsProvider);
    final display = _container.read(displayServiceProvider);
    final reminders = _container.read(reminderControllerProvider);

    _settings = _container.listen<AsyncValue<AppSettings>>(settingsProvider, (_, next) {
      final s = next.value;
      if (s == null) return;
      audio.setMusicEnabled(s.music);
      audio.setSfxEnabled(s.soundEffects);
      haptics.setEnabled(s.haptics);
      if (s.highRefreshRate != _highRefresh) {
        // First value included: a fresh install stays on the OS default.
        _highRefresh = s.highRefreshRate;
        unawaited(display.setHighRefreshRate(s.highRefreshRate));
      }
      _setUserProperty(AnalyticsUserProperties.theme, s.theme.name);
      _setUserProperty(AnalyticsUserProperties.onboardingDone, s.onboardingDone ? '1' : '0');
      if (!_musicStarted) {
        // First real settings value: flags are now correct, music may start.
        // startMusic() only records the wish until the engine is ready, and
        // stays silent while music is disabled.
        _musicStarted = true;
        unawaited(audio.startMusic());
      }
    }, fireImmediately: true);

    _session = _container.listen<AsyncValue<BackendSession>>(sessionProvider, (_, next) {
      final identity = next.value?.identity;
      if (identity != null) _setUserProperty(AnalyticsUserProperties.account, accountKind(identity.providers));
    }, fireImmediately: true);

    _entitlement = _container.listen<Entitlement>(entitlementProvider, (_, next) {
      _setUserProperty(AnalyticsUserProperties.adsRemoved, next.removeAds ? '1' : '0');
    }, fireImmediately: true);

    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      switch (state) {
        case AppLifecycleState.paused:
        case AppLifecycleState.detached:
          audio.onBackground();
          if (state == AppLifecycleState.paused) unawaited(reminders.onBackground());
        case AppLifecycleState.resumed:
          audio.onForeground();
          _checkForUpdate();
          unawaited(reminders.onForeground());
          // The player may have changed it in system settings.
          _container.invalidate(reminderPermissionProvider);
        case AppLifecycleState.inactive:
        case AppLifecycleState.hidden:
          break; // shade pulled down, app switcher: keep playing
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Already backgrounded before the first frame? Let resume start it.
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) audio.onBackground();
      unawaited(audio.init());
      unawaited(reminders.start());
      _updateCheck = Timer(const Duration(seconds: 4), _checkForUpdate);
    });
  }

  /// `guest`, `google`, `apple` or `other`, from the Firebase providers.
  static String accountKind(List<String> providers) {
    if (providers.contains('apple.com')) return 'apple';
    if (providers.contains('google.com')) return 'google';
    return providers.isEmpty ? 'guest' : 'other';
  }

  void _setUserProperty(String name, String? value) {
    if (_userProperties.containsKey(name) && _userProperties[name] == value) return;
    _userProperties[name] = value;
    unawaited(_container.read(analyticsProvider).setUserProperty(name, value));
  }

  void _checkForUpdate() => unawaited(_container.read(appUpdateProvider.notifier).checkInBackground());

  void dispose() {
    _updateCheck?.cancel();
    _settings?.close();
    _session?.close();
    _entitlement?.close();
    _lifecycle?.dispose();
  }
}
