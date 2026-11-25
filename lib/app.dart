import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' as cupertino_ui show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_ui/material_ui.dart' as material_ui show GlobalMaterialLocalizations;

import 'data/models/settings.dart';
import 'platform/store_listing/store_listing_service.dart';
import 'state/data_providers.dart';
import 'state/platform_bridge.dart';
import 'state/reminder_controller.dart';
import 'state/reminder_policy.dart';
import 'state/store_listing_controller.dart';
import 'ui/demo/demo_driver.dart';
import 'ui/l10n/generated/app_localizations.dart';
import 'ui/router.dart';
import 'ui/screens/settings/screen_chrome.dart' show showJwToast;
import 'ui/theme/jw_tablet_scale.dart';
import 'ui/theme/jw_theme.dart';
import 'ui/widgets/reduce_motion.dart';

/// Composition root widget: theme mode, reduce motion, text-scale clamp and router.
class JadewellApp extends ConsumerStatefulWidget {
  const JadewellApp({super.key});

  @override
  ConsumerState<JadewellApp> createState() => _JadewellAppState();
}

class _JadewellAppState extends ConsumerState<JadewellApp> {
  late final GoRouter _router = createAppRouter(observers: [ref.read(analyticsRouteObserverProvider)]);
  StreamSubscription<ReminderPayload>? _reminderTaps;

  @override
  void initState() {
    super.initState();
    // A reminder tapped while Jadewell was in the background: from Home, open
    // the daily board's screen; anywhere else (a board in play) stay put. A
    // cold launch from a reminder goes through the splash to Home as usual.
    _reminderTaps = ref.read(reminderControllerProvider).taps.listen((_) {
      if (_router.routerDelegate.currentConfiguration.uri.path == AppRoutes.home) {
        unawaited(_router.push(AppRoutes.daily));
      }
    });
  }

  @override
  void dispose() {
    _reminderTaps?.cancel();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    // A background (flexible) update finished downloading: say so once.
    // Installing restarts the app, so it waits for the player's tap in Settings.
    ref.listen(appUpdateProvider, (prev, next) {
      final ctx = rootNavigatorKey.currentContext;
      if (prev == UpdateState.downloading && next == UpdateState.downloaded && ctx != null) {
        showJwToast(ctx, AppLocalizations.of(ctx).updateReadyToast);
      }
    });
    return MaterialApp.router(
      routerConfig: _router,
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        ...cupertino_ui.GlobalCupertinoLocalizations.delegates,
        ...material_ui.GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildJwThemeData(Brightness.light),
      darkTheme: buildJwThemeData(Brightness.dark),
      themeMode: switch (settings.theme) {
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
        ThemePreference.system => ThemeMode.system,
      },
      builder: (context, child) {
        // UI text follows the OS scale up to 130% (DESIGN_SYSTEM §3).
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3)),
          // A transparent Material above every route gives all text (splash,
          // custom-painted screens, overlays) a DefaultTextStyle, so nothing
          // falls back to the yellow-underlined "no Material" debug style.
          // Large tablets lay out at a 768 pt short side and scale up.
          child: JwTabletScale(
            child: Material(
              type: MaterialType.transparency,
              child: JwReduceMotion(
                enabled: settings.reduceMotion,
                child: kDemoMode ? DemoDriver(child: child!) : child!,
              ),
            ),
          ),
        );
      },
    );
  }
}
