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
- [ ] ATT usage string, SKAdNetwork IDs, `GADApplicationIdentifier`
- [ ] Run the app on the simulator and a device; run goldens on macOS
- [ ] TestFlight upload
- [ ] Crashlytics: add the "Upload Crashlytics symbols" Run Script build phase to Runner (`"${PODS_ROOT}/FirebaseCrashlytics/run"`, or `${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run` with SPM) with input files `${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}`, `.../Contents/Resources/DWARF/${PRODUCT_NAME}`, `.../Contents/Info.plist`, `$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GoogleService-Info.plist`, `$(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)`; set Debug Information Format = "DWARF with dSYM File" for Release. Then force a test crash in a release build and check the Crashlytics dashboard (collection is off in debug/profile by design)
- [ ] Analytics: confirm events reach DebugView with `-FIRDebugEnabled` on a release-configured run (debug builds log to the console only via `DebugPrintAnalytics`)
- [ ] Audio: verify on a device that Jadewell's music **mixes** with Apple Music/Spotify (session = Ambient + mixWithOthers, set by `SoLoudAudioEngine`), respects the silent switch, resumes after a phone call / Siri, and pauses when backgrounded. No `UIBackgroundModes` audio entry is needed (we never play in the background)
- [ ] Haptics: check select (light), match (medium), blocked (two light ticks 60 ms apart), board cleared (success notification) on a real iPhone
