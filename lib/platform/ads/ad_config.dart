import 'package:flutter/foundation.dart';

import 'ad_gate.dart';
import 'ad_ids.dart';

/// AdMob unit ids per format and platform.
///
/// Debug and profile builds ALWAYS use Google's official test units: serving
/// (or tapping) real ads during development is a policy violation that can
/// get the AdMob account suspended. Release builds use [AdIds] from the
/// gitignored `ad_ids.dart`, generated from `ADMOB-NOTE.txt` by
/// `dart run tool/gen_ad_ids.dart` (docs/ADS.md). An empty release id turns
/// that format off.
///
/// App ids are not here: the SDK reads them from the native manifests
/// (`android/ads.properties` → AndroidManifest, `ios/Flutter/Ads.xcconfig` →
/// Info.plist).
abstract final class AdConfig {
  static bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  // Google's published test units (developers.google.com/admob/{android,ios}/test-ads).
  static const _testAndroid = {
    AdFormat.interstitial: 'ca-app-pub-3940256099942544/1033173712',
    AdFormat.rewarded: 'ca-app-pub-3940256099942544/5224354917',
    AdFormat.rewardedInterstitial: 'ca-app-pub-3940256099942544/5354046379',
    AdFormat.appOpen: 'ca-app-pub-3940256099942544/9257395921',
  };
  static const _testIos = {
    AdFormat.interstitial: 'ca-app-pub-3940256099942544/4411468910',
    AdFormat.rewarded: 'ca-app-pub-3940256099942544/1712485313',
    AdFormat.rewardedInterstitial: 'ca-app-pub-3940256099942544/6978759866',
    AdFormat.appOpen: 'ca-app-pub-3940256099942544/5575463023',
  };

  static const _releaseAndroid = {
    AdFormat.interstitial: AdIds.androidInterstitial,
    AdFormat.rewarded: AdIds.androidRewarded,
    AdFormat.rewardedInterstitial: AdIds.androidRewardedInterstitial,
    AdFormat.appOpen: AdIds.androidAppOpen,
  };
  static const _releaseIos = {
    AdFormat.interstitial: AdIds.iosInterstitial,
    AdFormat.rewarded: AdIds.iosRewarded,
    AdFormat.rewardedInterstitial: AdIds.iosRewardedInterstitial,
    AdFormat.appOpen: AdIds.iosAppOpen,
  };

  /// The unit for [format] on this platform and build mode; empty = off.
  static String unitId(AdFormat format) {
    final table = kReleaseMode ? (_ios ? _releaseIos : _releaseAndroid) : (_ios ? _testIos : _testAndroid);
    return table[format] ?? '';
  }

  static bool hasUnit(AdFormat format) => unitId(format).isNotEmpty;
}
