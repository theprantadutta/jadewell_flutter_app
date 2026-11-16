import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      // Docs/ARCHITECTURE.md §4 rule 2: no automatic retries by default.
      retry: (_, _) => null,
      child: const JadewellApp(),
    ),
  );
}
