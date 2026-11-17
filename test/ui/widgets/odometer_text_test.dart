import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/ui/widgets/odometer_text.dart';

Widget _host(String text, {bool reduce = false}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: OdometerText(text, style: const TextStyle(fontSize: 20), reduceMotion: reduce)),
    );

void main() {
  testWidgets('rolls only the changed digit, clipped to its slot, then settles', (tester) async {
    await tester.pumpWidget(_host('0:59'));
    expect(find.byType(ClipRect), findsNothing); // nothing animates on first frame

    await tester.pumpWidget(_host('1:00'));
    await tester.pump(const Duration(milliseconds: 100));
    // "0:59" -> "1:00": three digits change (the colon stays), each in its own clip.
    expect(find.byType(ClipRect), findsNWidgets(3));
    expect(find.text('5'), findsOneWidget); // outgoing digit still visible mid-roll

    await tester.pumpAndSettle();
    expect(find.byType(ClipRect), findsNothing);
    expect(find.text('5'), findsNothing);
  });

  testWidgets('length change keeps digits on their right-aligned tracks', (tester) async {
    await tester.pumpWidget(_host('9:59'));
    await tester.pumpWidget(_host('10:00'));
    await tester.pump(const Duration(milliseconds: 50));
    // 9->0, 5->0 and 9->0 roll; the new leading 1 just appears (no previous digit).
    expect(find.byType(ClipRect), findsNWidgets(3));
    await tester.pumpAndSettle();
  });

  testWidgets('reduce motion swaps instantly', (tester) async {
    await tester.pumpWidget(_host('0:01', reduce: true));
    await tester.pumpWidget(_host('0:02', reduce: true));
    await tester.pump();
    expect(find.byType(ClipRect), findsNothing);
    expect(find.text('0:02'), findsOneWidget);
  });
}
