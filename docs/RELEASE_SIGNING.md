# Release signing (Android)

Jadewell is signed with an **upload key** and published with **Play App Signing**
(Google holds the app signing key; we sign uploads).

## Where the key lives (never in git)

`C:\android-keys\jadewell\` on the owner's PC, same layout as the other apps:

| File | What |
|---|---|
| `upload-keystore.jks` | PKCS12 keystore, alias `upload`, RSA 2048, valid 10,000 days |
| `key.properties` | `storePassword`, `keyPassword`, `keyAlias`, `storeFile` (copy this into `android/`) |
| `keystore-credentials.txt` | Passwords, certificate details and backup notes |
| `upload_certificate.pem` | Public upload certificate (Play Console asks for it if the upload key is ever reset) |

Upload certificate fingerprints (public, safe to share):

- SHA-1: `20:83:B3:B1:48:EF:3F:7D:30:FC:13:AB:A7:48:C0:95:5B:92:5A:59`
- SHA-256: `65:8E:3A:FC:94:DD:CA:2A:F2:88:FB:90:95:9B:60:EE:A5:45:92:CC:D4:AC:62:19:B2:B0:BB:9E:72:DA:AA:B8`

Back up the whole folder somewhere safe (encrypted drive / password manager).
With Play App Signing a lost upload key can be reset in Play Console, but it
takes days.

## How the build uses it

`android/app/build.gradle.kts` reads the gitignored `android/key.properties`
(same pattern as snake-classic). On a new machine copy
`C:\android-keys\jadewell\key.properties` to `android/key.properties`.

- With the file present, release builds are signed with the upload key.
- Without it, `flutter run --release` falls back to the debug key so local
  release runs still work.
- Store builds pass `requireReleaseKey`, which fails the build instead of
  falling back:

```sh
flutter build appbundle --release --android-project-arg=requireReleaseKey=true
# → build/app/outputs/bundle/release/app-release.aab
```

Check the signer: `keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab`
(SHA-1 above).

## Firebase / Google Sign-In

Google Sign-In on Android only works for signing certificates registered on
the Firebase Android app (`com.pranta.jadewell`, project `jadewell-c6647`):

1. Add the **upload key** SHA-1 and SHA-256 above (Project settings → Your apps
   → Android → Add fingerprint), so locally built release APKs can sign in.
2. After the first upload to Play, copy the **app signing key** SHA-1 and
   SHA-256 from Play Console (Test and release → App integrity → App signing)
   and add those too; this is the certificate Play-installed copies are signed
   with.
3. Re-run `flutterfire configure` (or re-download `google-services.json`) only
   if Firebase asks; the OAuth client is created server-side.

## iOS

iOS signing is handled in Xcode on the Mac (automatic signing with the team);
see `docs/IOS_HANDOFF.md`.
