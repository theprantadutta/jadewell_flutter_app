import 'package:cupertino_ui/cupertino_ui.dart' as cupertino_ui show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_ui/material_ui.dart' as material_ui show GlobalMaterialLocalizations;

import 'ui/l10n/generated/app_localizations.dart';

/// Composition root widget. Theme, router and providers are wired here in Phase 6.
class JadewellApp extends StatelessWidget {
  const JadewellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        ...cupertino_ui.GlobalCupertinoLocalizations.delegates,
        ...material_ui.GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: Center(child: Text('Jadewell'))),
    );
  }
}
