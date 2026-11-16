// Template for lib/platform/ads/ad_ids.dart, which is GITIGNORED (the repo is
// public). Don't copy this by hand: `dart run tool/gen_ad_ids.dart` writes
// ad_ids.dart from ADMOB-NOTE.txt, or with empty ids when the note is absent
// (docs/ADS.md). Nothing imports this file; it documents the shape.
//
// Release-only AdMob unit ids; debug/profile builds always use Google's test
// ids (ad_config.dart). An empty id turns that format off in release.

abstract final class AdIds {
  static const String androidInterstitial = '';
  static const String androidRewarded = '';
  static const String androidRewardedInterstitial = '';
  static const String androidAppOpen = '';
  static const String iosInterstitial = '';
  static const String iosRewarded = '';
  static const String iosRewardedInterstitial = '';
  static const String iosAppOpen = '';
}
