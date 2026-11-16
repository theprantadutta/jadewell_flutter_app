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
