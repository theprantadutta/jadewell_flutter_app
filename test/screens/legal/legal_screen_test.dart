import 'dart:io';

import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/services.dart' show ByteData, CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/ui/screens/legal/legal_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../ui/golden_helpers.dart' show loadJwFonts;
import '../meta_checks.dart';
import '../settings/harness.dart';

/// Reads the real files from disk without the shared asset cache, whose
/// futures don't survive from one test's fake-async zone into the next.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(File(key).readAsBytesSync());
}

void main() {
  setUpAll(loadJwFonts);

  Future<void> pump(WidgetTester tester, LegalDoc doc, {Size size = const Size(390, 844), Brightness brightness = Brightness.light}) async {
    await pumpScreen(tester, LegalScreen(doc: doc, bundle: _DiskBundle()), size: size, brightness: brightness);
    await tester.pumpAndSettle();
    expect(find.byType(LegalMarkdown), findsOneWidget);
  }

  group('parser', () {
    test('headings, paragraphs with hard breaks, bullets and tables', () {
      // Two trailing spaces are a markdown hard line break.
      final blocks = LegalMarkdownParser.parse('# Title\n\n**Version: 1.0**  \n**Date: today**\n' '''

## 1. Section

### Sub

First line
continues here.

- one
- two

| A | B | C |
|---|---|---|
| a1 | b1 | c1 |
| a2 | b2 | c2 |
''');
      expect(blocks[0], isA<LegalHeading>().having((h) => h.level, 'level', 1).having((h) => h.text, 'text', 'Title'));
      expect(blocks[1], isA<LegalParagraph>().having((p) => p.text, 'text', '**Version: 1.0**\n**Date: today**'));
      expect(blocks[2], isA<LegalHeading>().having((h) => h.level, 'level', 2));
      expect(blocks[3], isA<LegalHeading>().having((h) => h.level, 'level', 3));
      expect(blocks[4], isA<LegalParagraph>().having((p) => p.text, 'text', 'First line continues here.'));
      expect(blocks[5], isA<LegalBullet>().having((b) => b.text, 'text', 'one'));
      expect(blocks[6], isA<LegalBullet>().having((b) => b.text, 'text', 'two'));
      final table = blocks[7] as LegalTable;
      expect(table.header, ['A', 'B', 'C']);
      expect(table.rows, [
        ['a1', 'b1', 'c1'],
        ['a2', 'b2', 'c2'],
      ]);
      expect(blocks, hasLength(8));
    });
  });

  testWidgets('privacy: renders headings, the deletion section and tappable links', (tester) async {
    await pump(tester, LegalDoc.privacy);
    expect(find.text('Privacy policy'), findsOneWidget); // top bar
    expect(find.textContaining('Privacy Policy for Jadewell', findRichText: true), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);

    await tester.scrollUntilVisible(find.textContaining('9. Deleting your data', findRichText: true), 300);
    expect(find.textContaining('Settings > Account > Delete account', findRichText: true), findsOneWidget);

    // Bare URLs and emails become tappable spans; ** markers never show.
    final spans = <TextSpan>[];
    for (final t in tester.widgetList<RichText>(find.byType(RichText))) {
      t.text.visitChildren((s) {
        if (s is TextSpan) spans.add(s);
        return true;
      });
    }
    final links = spans.where((s) => s.recognizer is TapGestureRecognizer).map((s) => s.text).toSet();
    expect(links, contains('prantadutta1997@gmail.com'));
    expect(links, contains('https://firebase.google.com/support/privacy'));
    expect(spans.any((s) => (s.text ?? '').contains('**')), isFalse);
  });

  testWidgets('terms and refund load', (tester) async {
    await pump(tester, LegalDoc.terms);
    expect(find.text('Terms of use'), findsOneWidget);
    expect(find.textContaining('Terms of Use for Jadewell', findRichText: true), findsOneWidget);
    await resetApp(tester);
    await pump(tester, LegalDoc.refund);
    expect(find.text('Refund policy'), findsOneWidget);
    expect(find.textContaining('Refund Policy for Jadewell', findRichText: true), findsOneWidget);
  });

  test('route names map to documents', () {
    expect(LegalDoc.fromName('terms'), LegalDoc.terms);
    expect(LegalDoc.fromName('refund'), LegalDoc.refund);
    expect(LegalDoc.fromName('nope'), LegalDoc.privacy);
  });

  for (final size in layoutSizes.entries) {
    for (final scale in textScales) {
      testWidgets('legal layout · ${size.key} · text ${scale}x: no overflow', (tester) async {
        setTextScale(tester, scale);
        for (final doc in LegalDoc.values) {
          await resetApp(tester);
          await pump(tester, doc, size: size.value);
          await expectNoOverflow(tester);
        }
      });
    }
  }
  testWidgets('tablet: the document keeps a reading width', (tester) async {
    await pump(tester, LegalDoc.privacy, size: const Size(900, 1200));
    final card = tester.getSize(find.byType(LegalMarkdown));
    expect(card.width, lessThanOrEqualTo(720));
  });

  for (final b in Brightness.values) {
    testWidgets('legal shots ${b.name}', skip: !shotsEnabled, (tester) async {
      for (final doc in LegalDoc.values) {
        await resetApp(tester);
        await pump(tester, doc, brightness: b, size: const Size(390, 844));
        await maybeShot(tester, 'legal_${doc.name}_${b.name}');
      }
    });
  }
}
