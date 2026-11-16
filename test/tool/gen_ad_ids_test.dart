// tool/gen_ad_ids.dart: parses the ADMOB-NOTE.txt layout and renders
// ad_ids.dart in the same shape as the committed ad_ids.example.dart.
// Uses obviously fake ids only (the repo is public).
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/gen_ad_ids.dart';

const _note = '''
JADEWELL · ADMOB IDS
Fill in the values below from AdMob (apps.admob.com, publisher ca-app-pub-...).

---------------------------------------------------------------- ANDROID
App ID (ca-app-pub-...~...): ca-app-pub-1111111111111111~2222222222
Interstitial  (after a board is cleared): ca-app-pub-1111111111111111/0000000001
Rewarded               (extra hint, extra shuffle, unlock a layout, streak repair): ca-app-pub-1111111111111111/0000000002
Rewarded interstitial  ("Head start" / "Second chance" offers): ca-app-pub-1111111111111111/0000000003
App Open      (optional, on returning to the app; leave blank to skip):

---------------------------------------------------------------- iOS
App ID (ca-app-pub-...~...): ca-app-pub-1111111111111111~3333333333
Interstitial: ca-app-pub-1111111111111111/0000000011
Rewarded: ca-app-pub-1111111111111111/0000000012
Rewarded interstitial: ca-app-pub-1111111111111111/0000000013
App Open (optional): ca-app-pub-1111111111111111/0000000014

---------------------------------------------------------------- NOTES
- Remove Ads IAP product id: com.pranta.jadewell.remove_ads
''';

void main() {
  test('parses both sections; blanks and placeholders are not provided', () {
    final n = parseNote(_note);
    expect(n.android.appId, 'ca-app-pub-1111111111111111~2222222222');
    expect(n.android.interstitial, 'ca-app-pub-1111111111111111/0000000001');
    expect(n.android.rewarded, 'ca-app-pub-1111111111111111/0000000002');
    expect(n.android.rewardedInterstitial, 'ca-app-pub-1111111111111111/0000000003');
    expect(n.android.appOpen, '');
    expect(n.ios.appId, 'ca-app-pub-1111111111111111~3333333333');
    expect(n.ios.interstitial, 'ca-app-pub-1111111111111111/0000000011');
    expect(n.ios.rewarded, 'ca-app-pub-1111111111111111/0000000012');
    expect(n.ios.rewardedInterstitial, 'ca-app-pub-1111111111111111/0000000013');
    expect(n.ios.appOpen, 'ca-app-pub-1111111111111111/0000000014');
  });

  test('a malformed id is an error, not a silent empty', () {
    expect(
      () => parseNote('--- ANDROID\nInterstitial: ca-app-pub-1111111111111111~0000000001\n'),
      throwsFormatException,
    );
  });

  test('rendered ad_ids.dart declares exactly the members of ad_ids.example.dart', () {
    final decl = RegExp(r"static const String (\w+) = '");
    Set<String> members(String src) => decl.allMatches(src).map((m) => m.group(1)!).toSet();
    final example = File('lib/platform/ads/ad_ids.example.dart').readAsStringSync();
    final rendered = renderDart(parseNote(_note), fromNote: true);
    expect(members(example), hasLength(8));
    expect(members(rendered), members(example));
    expect(rendered, contains("androidAppOpen = ''"));
    expect(renderDart(const AdIdsNote(), fromNote: false), isNot(contains('ca-app-pub')));
  });

  test('every generated output is gitignored', () {
    for (final path in [kDartOut, kAndroidOut, kIosOut, kNotePath]) {
      expect(isGitIgnored(path), isTrue, reason: path);
    }
  });
}
