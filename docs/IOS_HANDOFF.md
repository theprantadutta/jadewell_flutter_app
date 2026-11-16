# iOS handoff (for the macOS session)

All iOS code and config is written on Windows; building, signing and testing happen on the Mac. This file collects everything the Mac session needs. It grows as phases land.

## Secrets and IDs that are NOT in this public repo

| What | Where to get it | Where it goes |
|---|---|---|
| AdMob app IDs + ad unit IDs (Android and iOS) | Private backend repo: `jadewell-dotnet-api/docs/ADMOB-IDS.txt` (also `ADMOB-NOTE.txt` at this repo's root on the Windows machine, gitignored) | iOS app ID → the gitignored ads xcconfig read by `Info.plist` (`GADApplicationIdentifier`); unit IDs → `lib/platform/ads/ad_ids.dart` (gitignored, template `ad_ids.example.dart`) |
| `GoogleService-Info.plist` / `firebase_options.dart` | `flutterfire configure --project=jadewell-c6647` | `ios/Runner/`, `lib/` (both gitignored) |
| `config.env` (Google web client id, API URLs) | Copy `config.env.example` to `config.env`, fill from the Windows machine | repo root (gitignored, shipped as an asset) |

## Checklist (filled in as phases land)

- [ ] `flutterfire configure` for iOS
- [ ] Resolve Swift Package Manager dependencies, set the signing team
- [ ] Capabilities: Sign in with Apple, Push Notifications, Associated Domains (`applinks:jadewell.pranta.dev`), In-App Purchase
- [ ] Upload the APNs key to Firebase
- [ ] StoreKit product `com.pranta.jadewell.remove_ads` (non-consumable, $1.99)
- [ ] Ads (see `docs/ADS.md`): on the Mac, put `ADMOB-NOTE.txt` at the repo root (or use the backend copy) and run `dart run tool/gen_ad_ids.dart --note ../jadewell-dotnet-api/docs/ADMOB-IDS.txt`; it writes the gitignored `ios/Flutter/Ads.xcconfig` (`ADMOB_APP_ID`) and `lib/platform/ads/ad_ids.dart`. Without it the build compiles but uses Google's sample iOS app id (`ca-app-pub-3940256099942544~1458002511`, test ads only)
- [ ] Ads: if CocoaPods rewrites `Flutter/Debug.xcconfig` / `Release.xcconfig`, keep `ADMOB_APP_ID = <sample id>` **before** `#include? "Ads.xcconfig"` in both (later definitions win); the Profile configuration uses `Release.xcconfig`
- [ ] Ads: in a Release build, verify the built `Info.plist` has the real `GADApplicationIdentifier` (not `$(ADMOB_APP_ID)` and not the sample id); a wrong or missing one crashes the Google Mobile Ads SDK at launch
- [ ] Ads: review the ATT prompt text (`NSUserTrackingUsageDescription` in `Info.plist`) and, in AdMob → Privacy & messaging, create the IDFA explainer + GDPR messages for the iOS app
- [ ] Ads: `SKAdNetworkItems` holds Google's 50 published ids (Nov 2026, developers.google.com/admob/ios/3p-skadnetworks); re-check the list before release, no mediation partners are added
- [ ] Ads, on a device: first launch shows the UMP form (if required) then the ATT prompt once; a rewarded hint plays a test ad and grants the hint only after the reward; Settings → Ad privacy choices appears only when UMP requires it and opens the form; returning after 30+ minutes away (after 2 completed boards) may show a test App Open ad, never on a cold start
- [ ] Run the app on the simulator and a device; run goldens on macOS
- [ ] TestFlight upload
- [ ] Crashlytics: add the "Upload Crashlytics symbols" Run Script build phase to Runner (`"${PODS_ROOT}/FirebaseCrashlytics/run"`, or `${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run` with SPM) with input files `${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}`, `.../Contents/Resources/DWARF/${PRODUCT_NAME}`, `.../Contents/Info.plist`, `$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GoogleService-Info.plist`, `$(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)`; set Debug Information Format = "DWARF with dSYM File" for Release. Then force a test crash in a release build and check the Crashlytics dashboard (collection is off in debug/profile by design)
- [ ] Analytics: confirm events reach DebugView with `-FIRDebugEnabled` on a release-configured run (debug builds log to the console only via `DebugPrintAnalytics`)
- [ ] Audio: verify on a device that Jadewell's music **mixes** with Apple Music/Spotify (session = Ambient + mixWithOthers, set by `SoLoudAudioEngine`), respects the silent switch, resumes after a phone call / Siri, and pauses when backgrounded. No `UIBackgroundModes` audio entry is needed (we never play in the background)
- [ ] Haptics: check select (light), match (medium), blocked (two light ticks 60 ms apart), board cleared (success notification) on a real iPhone
- [ ] IAP (Remove ads, see `docs/IAP.md`): add the **In-App Purchase** capability to the Runner target (Signing & Capabilities); `flutter_inapp_purchase` 11.x pulls OpenIAP (StoreKit 2) through Swift Package Manager automatically, nothing to add to the project by hand (iOS 15 target is already set)
- [ ] App Store Connect: Paid Apps agreement active; create Non-Consumable `com.pranta.jadewell.remove_ads` at USD 1.99 with localization + review screenshot/notes; attach it to the first version submission
- [ ] App Store Connect: In-App Purchase key (`.p8`, Key ID, Issuer ID) → backend secrets for `POST /purchases/verify` (App Store Server API); optional App Store Server Notifications V2 URL → backend
- [ ] Optional: a StoreKit configuration file (`Products.storekit`) with `com.pranta.jadewell.remove_ads` selected in the Run scheme to test purchases on the simulator without App Store Connect
- [ ] Device test with a Sandbox account: Store shows the localized price; Buy → "Verifying…" → celebration; delete + reinstall → Restore (top right of the Remove ads screen) brings it back; with the product missing or StoreKit unavailable the screen shows "Not available yet" and nothing crashes
