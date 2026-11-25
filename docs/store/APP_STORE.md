# App Store (iOS) setup

Set up 2026-11-21.

## Store names

- **App Store:** `Jadewell: Mahjong Tiles` (Apple wouldn't accept `Jadewell: Mahjong Solitaire`, another developer
  uses it). Subtitle `Mahjong Solitaire Tile Match` keeps the search term.
- **Google Play:** `Mahjong Solitaire: Jadewell`, short description `Mahjong solitaire tile matching: clear relaxing
  boards and a daily puzzle` (sent for review 2026-11-25). The names differ on purpose: almost all of Snake Classic's
  installs come from Play search on its lead keyword, so the Play title leads with "Mahjong Solitaire". Avoid
  "new", "free", "best" or prices in the short description: Play flags them as store-status/promotion keywords
  and may stop promoting the app.

## Identifiers

| | |
|---|---|
| App Store name | Jadewell: Mahjong Tiles |
| Apple ID (App Store Connect) | 6837629101 |
| Bundle ID | `com.pranta.jadewell` (explicit; In-App Purchase, Push Notifications, Sign in with Apple) |
| SKU | `jadewell-ios` |
| Primary language | English (U.S.) |
| Team | 9M6X7M798T |

## App Store Connect listing (set up 2026-11-21)

**Submitted for review 2026-11-21:** version 1.0.6 (build 8) together with the Remove ads in-app purchase.
Build 8 makes Apple token revocation best effort on account deletion, so no Services ID or private key is
needed in Firebase for deletion to work.

- Subtitle: `Mahjong Solitaire Tile Match`. Category: Games › Puzzle + Board, secondary Entertainment.
- Age rating 4+ (only "Advertising: yes"). Content rights: no third-party content.
- Free; available in 174 regions (all except China mainland, which needs an ICP filing and security assessment).
- Privacy Policy URL: https://legal.pranta.dev/jadewell/privacy. App Privacy labels published: linked to the user are
  email, user ID, gameplay content and purchase history (app functionality); used for tracking are device ID,
  advertising data and coarse location (AdMob, after ATT); not linked are product interaction, crash, performance
  and other diagnostic data.
- Support URL https://jadewell.pranta.dev/support, Marketing URL https://jadewell.pranta.dev/marketing
  (served by jadewell-dotnet-api `wwwroot`, commit 5d85694; live once deployed).
- Version 1.0.6: description, keywords, promo text, copyright "2026 Pranta Dutta", review contact and notes,
  sign-in not required. Screenshots: 8 × iPhone 6.3" (1206×2622) and 8 × iPad 13" (2064×2752) from
  `app-store-screenshots/marketing/`.
- In-app purchase "Remove ads": `com.pranta.jadewell.remove_ads`, non-consumable, $1.99, Apple ID 6837640005.
  It must go in with the 1.0.6 submission (first IAP ships with a new version).

## Firebase (iOS)

- iOS app: App Store ID 6837629101 and Team ID set.
- Auth > Apple: OAuth code flow config left empty (needs a Services ID). Optional: account deletion still works
  without it since build 8; filling it in only makes the Apple token revocation succeed.
- Cloud Messaging: upload the team-wide APNs key `D3QR552KKZ` when push notifications are added (not used today).

## Signing and keys

Kept in `~/Certificates & Documents/Apple Signing/` (not in this public repo):

- `Jadewell.mobileprovision`: App Store distribution profile "Jadewell App Store"
  (Apple Distribution certificate, expires 2027-06-09).
- `Jadewell_SignInWithApple_AuthKey_JKXMPGAMAY.p8`: Sign in with Apple key, Key ID `JKXMPGAMAY`,
  primary App ID `com.pranta.jadewell`. Goes into Firebase Console > Authentication > Apple
  (with Team ID 9M6X7M798T); needed for account-deletion token revocation (`docs/IOS_HANDOFF.md`).
- Push (APNs): the team has hit Apple's limit on team-scoped APNs keys, so use the existing
  team-wide key `D3QR552KKZ` (`~/MyAppsAppleKeys/All_App_APN_AuthKey_D3QR552KKZ.p8`) in Firebase.

## Building the IPA for Transporter

```sh
flutter build ipa --release --export-options-plist=<ExportOptions.plist>
```

ExportOptions: `method` app-store-connect, `signingStyle` manual, `teamID` 9M6X7M798T,
`signingCertificate` "Apple Distribution", `provisioningProfiles` { com.pranta.jadewell: "Jadewell App Store" }.
Output: `build/ios/ipa/Jadewell.ipa`. `ITSAppUsesNonExemptEncryption` is `false` in Info.plist,
so no export-compliance question per build.

## Screenshots

Raw captures in `app-store-screenshots/`:
- `iphone/`: 1320×2868 (6.9" display, iPhone 17 Pro Max)
- `ipad/`: 2064×2752 (13" display, iPad Pro 13" M5)
