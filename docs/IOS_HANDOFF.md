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

## Account deletion: Sign in with Apple token revocation (App Store 5.1.1(v))

Settings > Account > Delete account calls `AuthService.prepareAccountDeletion()`
before `DELETE /api/v1/auth/me`. On iOS, when the Firebase user has the
`apple.com` provider, `FirebaseAuthServiceImpl` re-authenticates with
`AppleAuthProvider` (`user.reauthenticateWithProvider`), takes
`credential.additionalUserInfo.authorizationCode` and calls
`FirebaseAuth.instance.revokeTokenWithAuthorizationCode(code)`. Backing out of the
Apple sheet cancels the whole deletion (nothing is deleted). Revocation itself is best
effort, as in the owner's other apps: if Firebase refuses (for example the Apple provider's
OAuth code flow config is incomplete), it is logged and the account is still deleted. Android and
non-Apple accounts skip this. Firebase's own user is deleted server-side (Admin
SDK), so there is no client `user.delete()`. Written blind (no iOS device on
Windows); verify on the Mac:

- [ ] Firebase console > Authentication > Sign-in method > Apple: the **Services ID,
      Apple Team ID, Key ID and private key (.p8)** are filled in. Token revocation
      needs them (without the key `revokeTokenWithAuthorizationCode` fails with
      `invalid-credential` / "missing client secret"); the native iOS sign-in itself
      works without them, so a working sign-in proves nothing here
- [ ] On an iPhone with a Sandbox/real Apple ID: Settings > Account > Continue with
      Apple (links the guest) → Delete account → confirm → the Apple sheet appears →
      approve → "Your account was deleted", Home shows a fresh guest with empty
      progress. Xcode console: no `session: delete account stopped` line
- [ ] Revocation really happened: iOS Settings > [your name] > Sign-In & Security >
      Sign in with Apple: **Jadewell is no longer listed** (may take a minute). Signing
      in with Apple again asks for name/email sharing from scratch
- [ ] Cancel the Apple sheet → nothing deleted (profile still on the Account screen,
      progress intact, no toast)
- [ ] Backend: the user row is gone (`GET /api/v1/admin/players?query=<username>`
      or the dashboard), and the Firebase console no longer lists the uid
- [ ] Edge case (known gap): an account created with Apple on iOS and deleted from an
      Android device can't revoke Apple tokens there (the authorization code only
      comes from the native iOS flow). The server data and Firebase user are still
      deleted; the user can remove Jadewell in iOS Settings > Sign in with Apple

## Orientation (portrait only)

- `Info.plist`: iPhone portrait only; iPad portrait + upside-down with `UIRequiresFullScreen = true` (required so iPad may restrict orientation; it also opts out of Split View/Slide Over, which suits a full-screen game). Verify on an iPad that rotation stays portrait and that App Store validation accepts it.
- Dart also calls `SystemChrome.setPreferredOrientations([portraitUp, portraitDown])` in `main.dart`.

## App icon (Clay Pop reskin)

`ios/Runner/Assets.xcassets/AppIcon.appiconset` was replaced with the Clay Pop
full legacy size set (20-1024, iPhone + iPad + marketing, opaque RGB). Verify it on
a simulator in light, dark and tinted home-screen modes on the Mac. If you prefer
the Xcode 15+ single-size format with dedicated dark and tinted variants, it lives
in the design package at `design/icons/ios/AppIcon-single-size.appiconset`.

## Daily reminder (local notifications)

`flutter_local_notifications` schedules a local reminder chain when the app goes to the background (policy in `lib/state/reminder_policy.dart`). No push, no APNs, no Info.plist keys and no background mode are needed. Done on Windows: `AppDelegate.swift` sets `UNUserNotificationCenter.current().delegate` (the plugin's setup step); the plugin is initialised with every `request*Permission` flag off, so iOS never asks at launch. Only the cleared-screen sheet ("Yes, remind me") and Settings → Daily reminder call `requestPermissions(alert, sound)`. Verify on the Mac:

- [ ] Fresh install: no notification permission alert at launch or during onboarding
- [ ] Clear the first board: the "Want a daily reminder?" sheet appears once (not with the review sheet); Yes shows the iOS alert; Allow → toast "Daily reminder is on"; Don't Allow → nothing more, Settings → Daily reminder stays off and switching it on shows "Notifications are off for Jadewell…" (iOS never re-shows the alert)
- [ ] Quick trigger: run with `--dart-define=JW_REMINDER_DELAY_SECONDS=20` (debug/profile only), allow notifications, play a board, go to the Home Screen: the day-1 reminder arrives ~20 s later, days 2 and 3 at 40 s and 60 s; reopening the app cancels the rest
- [ ] Tap the reminder with the app suspended (on Home): the Daily screen opens; with the app killed: the app launches to Home. Both log `reminder_open`
- [ ] Reminder shows the Jadewell app icon, title/body from `app_en.arb` (`reminder*` keys); no badge is set
- [ ] Settings → Daily reminder off → nothing arrives after backgrounding (`Settings → Notifications → Jadewell` in iOS still lists the app)
