import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/settings.dart';
import '../platform/analytics/analytics_route_observer.dart';
import 'data_providers.dart';
import 'platform_providers.dart';
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
///
/// Created once in main.dart; [dispose] undoes everything.
class PlatformBridge {
  PlatformBridge._(this._container);

  final ProviderContainer _container;
  ProviderSubscription<AsyncValue<AppSettings>>? _settings;
  AppLifecycleListener? _lifecycle;
  bool _musicStarted = false;
  bool? _highRefresh;
  Timer? _updateCheck;

  static PlatformBridge start(ProviderContainer container) => PlatformBridge._(container).._attach();

  void _attach() {
    final audio = _container.read(audioProvider);
    final haptics = _container.read(hapticsProvider);
    final display = _container.read(displayServiceProvider);

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
      if (!_musicStarted) {
        // First real settings value: flags are now correct, music may start.
        // startMusic() only records the wish until the engine is ready, and
        // stays silent while music is disabled.
        _musicStarted = true;
        unawaited(audio.startMusic());
      }
    }, fireImmediately: true);

    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      switch (state) {
        case AppLifecycleState.paused:
        case AppLifecycleState.detached:
          audio.onBackground();
        case AppLifecycleState.resumed:
          audio.onForeground();
          _checkForUpdate();
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
      _updateCheck = Timer(const Duration(seconds: 4), _checkForUpdate);
    });
  }

  void _checkForUpdate() => unawaited(_container.read(appUpdateProvider.notifier).checkInBackground());

  void dispose() {
    _updateCheck?.cancel();
    _settings?.close();
    _lifecycle?.dispose();
  }
}
