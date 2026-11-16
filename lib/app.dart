import 'package:cupertino_ui/cupertino_ui.dart' as cupertino_ui show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_ui/material_ui.dart' as material_ui show GlobalMaterialLocalizations;

import 'data/models/settings.dart';
import 'state/data_providers.dart';
import 'state/platform_bridge.dart';
import 'ui/l10n/generated/app_localizations.dart';
import 'ui/router.dart';
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

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
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
          child: JwReduceMotion(enabled: settings.reduceMotion, child: child!),
        );
      },
    );
  }
}
