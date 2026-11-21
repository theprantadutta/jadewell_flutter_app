import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/ui/theme/jw_tablet_scale.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('phones and small tablets are not scaled', () {
    expect(JwTabletScale.factorFor(const Size(402, 874)), 1); // iPhone 17
    expect(JwTabletScale.factorFor(const Size(744, 1133)), 1); // iPad mini
    expect(JwTabletScale.factorFor(const Size(800, 1280)), 1); // 10" Android tablet
  });

  test('large tablets lay out at a 768 pt short side', () {
    expect(JwTabletScale.factorFor(const Size(1032, 1376)), closeTo(1032 / 768, 1e-9)); // iPad Pro 13"
    expect(JwTabletScale.factorFor(const Size(834, 1210)), closeTo(834 / 768, 1e-9)); // iPad 11"
  });

  testWidgets('on an iPad Pro 13" the UI sees a 768 pt canvas, taps still land', (tester) async {
    tester.view.physicalSize = const Size(2064, 2752);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    late Size seen;
    late double seenDpr;
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => JwTabletScale(child: child!),
        home: Builder(
          builder: (context) {
            seen = MediaQuery.sizeOf(context);
            seenDpr = MediaQuery.devicePixelRatioOf(context);
            return Align(
              alignment: Alignment.bottomRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox(width: 100, height: 100),
              ),
            );
          },
        ),
      ),
    );

    expect(seen.width, closeTo(768, 1e-6));
    expect(seenDpr, closeTo(2 * 1032 / 768, 1e-6));
    // The 100 pt box in the bottom-right corner is drawn 1.34x bigger.
    final box = tester.getRect(find.byType(SizedBox).last);
    expect(box.width, closeTo(100 * 1032 / 768, 0.01));
    expect(box.bottomRight.dx, closeTo(1032, 0.01));
    await tester.tapAt(const Offset(1032 - 20, 1376 - 20));
    expect(taps, 1);
  });
}
