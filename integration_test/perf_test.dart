// Frame-timing run of the real app in profile mode (docs/PERFORMANCE.md).
//
//   flutter drive --profile -d <device> \
//     --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart
//
// Each traced block becomes build/<key>.timeline_summary.json with average,
// 90th/99th percentile and worst frame build/raster times plus missed-frame
// counts (16.7 ms budget at 60 Hz).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jadewell_flutter_app/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Render every frame like a real session, not just the ones the test pumps.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Jadewell perf scenarios', (tester) async {
    final semantics = tester.ensureSemantics();

    // Real time passes (fullyLive); pump keeps the test's view of the tree fresh.
    Future<void> run(Duration d) async {
      await Future<void>.delayed(d);
      await tester.pump();
    }

    Finder label(String pattern) => find.bySemanticsLabel(RegExp(pattern));

    Future<void> waitFor(Finder f, {Duration timeout = const Duration(seconds: 20)}) async {
      final end = DateTime.now().add(timeout);
      while (f.evaluate().isEmpty) {
        if (DateTime.now().isAfter(end)) fail('timed out waiting for $f');
        await run(const Duration(milliseconds: 250));
      }
    }

    await app.main();
    await run(const Duration(seconds: 6));
    // First run on a fresh install lands on onboarding.
    if (label(r'^Skip$').evaluate().isNotEmpty) {
      await tester.tap(label(r'^Skip$').first);
      await run(const Duration(seconds: 3));
    }
    await waitFor(label(r'^Statistics$'));

    // 1. Home collection: fling down and back up (silhouettes, clay cards).
    await binding.traceAction(() async {
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 3; i++) {
        await tester.fling(list, const Offset(0, -900), 2600);
        await run(const Duration(milliseconds: 1200));
        await tester.fling(list, const Offset(0, 900), 2600);
        await run(const Duration(milliseconds: 1200));
      }
    }, reportKey: 'home_scroll');

    // 2. Board entry: 128 tiles drop in layer by layer.
    await waitFor(label(r'^Fortress'));
    // The card can sit below the fold on short phones: bring it into view.
    await tester.ensureVisible(label(r'^Fortress').first);
    await run(const Duration(milliseconds: 600));
    await binding.traceAction(() async {
      await tester.tap(label(r'^Fortress').first);
      await run(const Duration(seconds: 4));
    }, reportKey: 'board_entry');

    // 3. Hint bob + glow, then a confirmed shuffle (flatten / swap / spring).
    await waitFor(label(r'^Hint'));
    await binding.traceAction(() async {
      await tester.tap(label(r'^Hint').first);
      await run(const Duration(milliseconds: 2500));
      await tester.tap(label(r'^Shuffle$').first);
      await run(const Duration(milliseconds: 900));
      await tester.tap(label(r'^Shuffle$').last); // the dialog's confirm
      await run(const Duration(seconds: 2));
    }, reportKey: 'hint_shuffle');

    // 4. Matches with bead puffs and layer settling until the board clears,
    //    then the cleared-screen beat sheet (medal, stars, counter roll).
    await binding.traceAction(() async {
      await tester.longPress(label(r'^Pause'));
      await waitFor(label(r'cleared!?$|^Head start'), timeout: const Duration(seconds: 90));
      await run(const Duration(seconds: 4));
    }, reportKey: 'gameplay_clear');

    semantics.dispose();
  });
}
