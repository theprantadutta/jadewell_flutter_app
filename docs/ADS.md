# Ads (AdMob)

AdMob only: **no mediation** for now (no `gma_mediation_*` packages; the owner's AppLovin account is disabled and Unity/Liftoff are not set up for Jadewell). **No banners**, anywhere. Rules from the brief §9 and `ARCHITECTURE.md` §7.

## Setup on a fresh clone

The repo is public, so the real AdMob ids are never committed. Three gitignored files carry them, all written by one tool:

```sh
# needs ADMOB-NOTE.txt at the repo root (gitignored). A copy lives in the
# private backend repo: jadewell-dotnet-api/docs/ADMOB-IDS.txt
dart run tool/gen_ad_ids.dart
# or point it at the backend copy:
dart run tool/gen_ad_ids.dart --note ../jadewell-dotnet-api/docs/ADMOB-IDS.txt
```

| Output (gitignored) | Contents | Read by |
|---|---|---|
| `lib/platform/ads/ad_ids.dart` | release unit ids (interstitial, rewarded, rewarded interstitial, app open × Android/iOS) | `ad_config.dart` |
| `android/ads.properties` | `admobAppId=` | `android/app/build.gradle.kts` → `manifestPlaceholders["admobAppId"]` → `AndroidManifest.xml` `com.google.android.gms.ads.APPLICATION_ID` |
| `ios/Flutter/Ads.xcconfig` | `ADMOB_APP_ID = ` | `#include?` from `Debug.xcconfig` / `Release.xcconfig` → `Info.plist` `GADApplicationIdentifier = $(ADMOB_APP_ID)` |

**`ad_ids.dart` must exist for the app to compile** (like `firebase_options.dart`). Without a note the tool still writes it, with empty ids in the shape of the committed `ad_ids.example.dart`, so any clone compiles after running the tool once; such a build is fully functional in debug (test ids) and simply requests no ads in release. The native app ids fall back on their own: Gradle uses Google's sample Android app id `ca-app-pub-3940256099942544~3347511713` when `ads.properties` is missing, and both xcconfigs define Google's sample iOS app id `ca-app-pub-3940256099942544~1458002511` before the optional include. The tool refuses to write any file git does not ignore, and `test/tool/gen_ad_ids_test.dart` checks the example and the generated file declare the same members.

Before every commit, grep the staged diff for `ca-app-pub-` followed by the owner's publisher number (the one in the app-ads.txt line below): nothing may match. Only Google's public sample/test ids (`ca-app-pub-3940256099942544`) belong in the repo.

## Which ids a build uses

| Build | Unit ids | App id |
|---|---|---|
| debug / profile | **always Google's official test units** (`AdConfig`, `kReleaseMode` false) | the real one if the generated files exist, else Google's sample (test units work with either) |
| release | `AdIds` from `ad_ids.dart`; an empty id turns that format off (e.g. App Open is optional) | the real one (check `ads.properties` / `Ads.xcconfig` exist before a store build) |

Serving or tapping real ads during development violates AdMob policy; debug builds cannot do it.

## Code map

| File | Role |
|---|---|
| `lib/platform/ads/ad_service.dart` | `AdService` interface, placements, `FakeAdService` (default provider, tests) |
| `lib/platform/ads/ad_service_impl.dart` | `AdServiceImpl`: consent, SDK, loading, showing (main.dart only) |
| `lib/platform/ads/ad_gate.dart` | Pure `AdGate.evaluate(AdGateContext) → (format?, reason)`, counters, store interface, reason strings |
| `lib/platform/ads/ad_gate_store_impl.dart` | Counters in SharedPreferences (`ads.*` keys, device-only) |
| `lib/platform/ads/ad_config.dart` | Unit id per format/platform/build mode |
| `tool/gen_ad_ids.dart` | Generates the id files from the note |

Wiring: `main.dart` overrides `adServiceProvider` with `AdServiceImpl` in every build mode and calls `init()` from a post-frame callback (start-up never waits on ads). The IAP layer feeds `Entitlement.removeAds` into `AdService.setAdsRemoved` (`startPurchases`, `docs/IAP.md`). `GameController` calls `onBoardStarted()` when a board is playable and `onBoardCleared()` when it is cleared.

## Consent

1. UMP: `requestConsentInfoUpdate` → `loadAndShowConsentFormIfRequired`. Only the status request has a 10 s timeout (a player reading the form is not a hang); on timeout or error `canRequestAds()` uses the status cached from earlier runs. A late answer still applies. A launch without network asks again on a later resume (never while a board is in progress).
2. iOS only: ATT `requestTrackingAuthorization` if `notDetermined` (a no-op when the UMP IDFA explainer already asked).
3. **Fail closed**: no ad request unless `canRequestAds()` is true; a platform error means no ads this session. `MobileAds.initialize()` runs only then.
4. `RequestConfiguration`: `maxAdContentRating = PG` (calm, family-friendly puzzle game); child-directed treatment left unspecified (the app is not directed at children).
5. Settings → "Ad privacy choices" appears only when UMP reports `PrivacyOptionsRequirementStatus.required` (EEA/UK etc.) and opens `ConsentForm.showPrivacyOptionsForm`; consent changes take effect at once (ads start, or held ads are dropped).

UMP messages (GDPR, US states, and the IDFA explainer for iOS) are configured in AdMob → Privacy & messaging for the Jadewell apps.

## Placements

| Format | Placement | Behaviour |
|---|---|---|
| Rewarded | Extra hint (after the free ones), extra shuffle, unlock a layout, streak repair | Opt-in button. Waits up to 5 s for a fill when none is loaded. Resolves **true only from `onUserEarnedReward`**, once, after the ad is dismissed (an earn event arriving after the dismiss is honoured for 1 s). Works with Remove ads. The game clock pauses because `GameController` awaits the ad in a busy state. |
| Rewarded interstitial | "Head start" on the cleared screen (intro sheet with Skip, built by the caller); "Second chance" placement exists in the interface | Same reward contract. Falls back to a rewarded video when no rewarded interstitial is loaded (the player accepted the intro). Not offered with Remove ads or after an interstitial. |
| Interstitial | After a **completed** board only | Gate below. Decided the moment the board clears; shown **1.6 s later** so it lands on the cleared screen (the game hands over about 1.3 s after the last match), never over the board's final animation. If the player starts the next board first, it is cancelled (`board_started`). |
| App open | On resume | Gate below. Requested on resume (held for the next qualifying return), never at start-up and never from the background. |

## Frequency rules (`AdGate`, unit-tested in `test/platform/ad_gate_test.dart`)

Interstitial, checked in this order (first failing rule is the logged reason):

1. `ads_removed`: Remove ads bought.
2. `ads_off`: no consent / SDK not ready.
3. `no_unit`: release id empty.
4. `first_boards`: none in a new install's first **2** completed boards (so the first possible one is board 3).
5. `cadence`: at most **1 per 3** completed boards.
6. `interstitial_gap`: at least **4 min** since the last interstitial.
7. `fullscreen_gap`: at least **2 min** since any full-screen ad (an opt-in rewarded watch is never chased by an interstitial).
8. `ad_showing`, `not_foreground`, `not_loaded`.
9. `shown`.

Restart, abandon, deadlock and leaving a board never reach the gate (only `onBoardCleared` counts boards). Daily boards are allowed, after their result is on screen (the delay above). Counters persisted in SharedPreferences: completed boards, boards since the last interstitial, last interstitial time, last full-screen ad time.

App open: `ads_removed`, `ads_off`, `no_unit`, `cold_start` (no `paused` → `resumed` trip; a cold start, first session or not, never shows one), `suppressed` (returning from the privacy form / ATT), `first_boards` (fewer than 2 completed boards), `short_away` (< **30 min** away, counted from `paused` only; our own ads' pauses are ignored), `app_open_gap` (< 30 min since the last one), `fullscreen_gap`, `ad_showing`, `not_loaded`, `shown`.

Tunables live in `AdGateRules`.

## Loading

Preloads after init, staggered 1.5 s apart (rewarded, rewarded interstitial, interstitial; requesting all at once exhausts WebView JS engines). The interstitial is requested only when the next clear could show it. Failed loads retry with jittered backoff (2 s, 10 s, 45 s, 3 min, 10 min); a tap on a watch button retries at once. Held ads expire (1 h; app open 4 h) and are replaced. Every shown ad is replaced right after it closes (app open: on the next resume).

## Analytics (no PII)

| Event | Params |
|---|---|
| `ad_gate` | `trigger` (`board_cleared` / `app_resumed`), `reason` (above, plus `board_started`, `show_failed`), `daily` |
| `ad_shown` | `format`, `placement` (`hint`, `shuffle`, `unlock_layout`, `streak_repair`, `head_start`, `second_chance`, `board_cleared`, `daily_cleared`, `resume`), `reason` |
| `jw_ad_reward` | `placement`, `format` (`ad_reward` is reserved by Firebase) |
| `ad_load_failed` | `format`, `code` (3 = no fill, 2 = network, 0/1 = request problem) |
| `ad_revenue` | `format`, `value_micros`, `currency`, `precision` (from `onPaidEvent`) |

## Testing

* Debug builds show Google's test ads ("Test Ad" label) on any device; no test device registration needed for ads.
* Consent form outside the EEA, debug builds only: `flutter run --dart-define=ADS_DEBUG_GEOGRAPHY=eea --dart-define=ADS_TEST_DEVICE_ID=<hashed id>` (the hashed id is printed by the UMP SDK in logcat / the Xcode console on the first run). Ignored in release.
* Rewarded: use Hint until the free ones run out; the hint appears only after the ad reports the reward. Closing the ad early grants nothing.
* Interstitial cadence and app open timing are covered by the gate tests (playing three boards by hand is slow).
* Release check before a store build: `android/ads.properties` and `ios/Flutter/Ads.xcconfig` exist, then confirm the merged manifest / built Info.plist carry the real app id.

## app-ads.txt

The developer site (the one listed on both store pages) must serve `/app-ads.txt` with:

```
google.com, pub-9242904787767394, DIRECT, f08c47fec0942fa0
```

(The same line as the owner's other apps. Add partner lines only if mediation is added later.)

## Mediation

Intentionally not added. If it is added later, read the owner's mediation notes first (shared across the owner's apps), add the `gma_mediation_*` adapters, map them in AdMob, add the partners' SKAdNetwork ids to `Info.plist` and their lines to app-ads.txt.
