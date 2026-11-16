import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/ui/board/tile/tile_face_painter.dart';
import 'package:jadewell_flutter_app/ui/board/tile/tile_face_spec.dart';
import 'package:jadewell_flutter_app/ui/theme/jw_background.dart';
import 'package:jadewell_flutter_app/ui/theme/jw_fonts.dart';
import 'package:jadewell_flutter_app/ui/theme/jw_theme.dart';
import 'package:jadewell_flutter_app/ui/widgets/reduce_motion.dart';
import 'package:material_ui/material_ui.dart';

bool _fontsLoaded = false;

/// Loads the real bundled fonts so goldens render Outfit, JetBrains Mono and
/// Noto Sans SC instead of the test font.
Future<void> loadJwFonts() async {
  if (_fontsLoaded) return;
  for (final entry in JwFonts.assets.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
  TileFacePainter.clearTextCache();
  _fontsLoaded = true;
}

List<TileFaceSpec> loadFaces() {
  final faces = TileFaceSpec.parse(File(TileFaceSpec.assetPath).readAsStringSync());
  TileFaceSpec.prime(faces);
  return faces;
}

/// Wraps [child] in the Jadewell theme, background and a fixed-width canvas.
Widget goldenFrame({
  required Brightness brightness,
  required Widget child,
  double width = 420,
  bool greyscale = false,
}) {
  final theme = buildJwThemeData(brightness);
  Widget content = Theme(
    data: theme,
    child: JwReduceMotion(
      enabled: true,
      child: Builder(
        builder: (context) => DefaultTextStyle(
          style: context.jw.text.body,
          child: JwBackground(
            orbs: false,
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    ),
  );
  if (greyscale) {
    content = ColorFiltered(colorFilter: const ColorFilter.matrix(kGreyscaleMatrix), child: content);
  }
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    home: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: const ValueKey('golden'),
        child: SizedBox(width: width, child: content),
      ),
    ),
  );
}

/// Pumps [widget] on a tall surface, waits for async assets (SVG), and
/// compares the framed area with [goldenName].
Future<void> expectGolden(WidgetTester tester, Widget widget, String goldenName, {Size surface = const Size(420, 2400)}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(widget);
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump(const Duration(seconds: 2));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(seconds: 2));
  await expectLater(find.byKey(const ValueKey('golden')), matchesGoldenFile(goldenName));
}
