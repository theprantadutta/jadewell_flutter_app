# Jadewell · Flutter app architecture

Phase 3 deliverable. Status: **awaiting approval**. Backend counterpart: `jadewell-dotnet-api/docs/ARCHITECTURE.md`.

## 0. Decisions from Phase 2

| Topic | Decision |
|---|---|
| Identity | Bundle/app id `com.pranta.jadewell`; home-screen name **Jadewell**; store title **Jadewell: Mahjong Solitaire** |
| Hosts | API `https://jadewell.pranta.dev/api/v1`, dashboard `jadewell-dashboard.pranta.dev` |
| Min OS | Android 7.0 (API 24), iOS 15 (Firebase minimums) |
| Orientation | Portrait only, phones and tablets (board scales up on tablets) |
| Material | `package:material_ui` / `package:cupertino_ui` from day one; nothing deprecated; latest package versions, changelogs checked when adding |
| State | Riverpod 3, manual providers only (no codegen); no Bloc, no get_it |
| Persistence | Drift (SQLite) + SharedPreferences for device-only flags |
| Auth | Anonymous Firebase guest with auto-generated display name; link Google, Apple, or email/password later (snake-classic flow) |
| Analytics / crashes | Firebase Analytics + Crashlytics, **release builds only**; no Sentry |
| Hints / shuffles | 3 free hints per board, 2 free shuffles per board, then rewarded video; deadlock shuffle always free |
| Scoring | **Stars (1–3) + time.** Rankings: stars desc, then time asc |
| Unlocks | Clear the previous layout in a chapter to unlock the next; next chapter at ~70% of the current; **any locked layout can be unlocked by a rewarded ad** |
| Daily | Same deal for everyone; **first clear of the day is the ranked result**; server replays the move log |
| Leaderboard tabs | Today · This week · **Friends** (friend codes + invite links) |
| Audio | Royalty-free music + SFX; separate **Music** and **Sound effects** toggles; mixes with the user's music |
| Languages | English only, but every string goes through `gen-l10n` ARB files from the start |
| Ads | AdMob only, no mediation yet. Test IDs in debug; real IDs from `ADMOB-NOTE.txt` (gitignored) |
| iOS | All code and config written now; built and tested later on a Mac (`docs/IOS_HANDOFF.md`) |
| CI | **None** (no GitHub Actions). Layer check runs in a pre-commit hook and in `flutter test` |

## 1. Module layout

```
lib/
  engine/        PURE DART. Only dart:core/dart:collection/dart:convert/dart:math(no Random)/dart:typed_data
    tiles.dart           42 faces, matchKey (FL/SE shared), 144-tile set
    layout.dart          Layout model, half-tile grid, validation, neighbour precompute
    prng.dart            xoshiro128** seeded PRNG (+ string hash → seed)
    dealer.dart          reverse-construction dealer, generatorVersion
    solver.dart          forward DFS solver, bitset memo, node budget
    game_state.dart      immutable GameState, history entries (match | shuffle)
    commands.dart        select / match / undo / shuffle / hint → (GameState, List<GameEvent>)
    events.dart          sealed GameEvent: Selected, Deselected, Matched, Mismatch, Blocked, Shuffled, Undone, Hint, Deadlock, Cleared
    scoring.dart         stars from (time, par, hints, paidShuffles)
    move_log.dart        compact move log for daily verification (shared format with C#)
    daily.dart           daily seed = hash(YYYY-MM-DD UTC, layoutId, generatorVersion)
  data/
    db/                  Drift database, tables, DAOs, migrations
    layouts/             asset loader for assets/layouts/*.json + index.json
    api/                 ApiClient (http), ApiResult/ApiFailure, DTOs
    sync/                SyncOutbox + SyncEngine (only pusher)
    repositories/        progress, stats, settings, daily, leaderboard, friends, entitlements
  state/                 Riverpod providers (manual): game controller, settings, progress, daily, leaderboard, friends, auth, ads gate
  ui/
    theme/               jw_tokens.dart (generated, untouched), JwTheme ThemeExtension, ClayDecoration + picture cache
    widgets/             clay buttons, chips, pills, toggles, segmented, list groups, sheets, dialogs, toasts, tool knobs, silhouettes
    board/               BoardView, TileWidget, TileFacePainter (from tile-faces.json), animations driven by GameEvents
    screens/             splash, how to play×3 (the old onboarding), home/layout select, game, cleared, daily, leaderboard, stats, settings, store, friends, account
    motion/              JwMotion helpers, reduce-motion resolver
    l10n/                ARB files (app_en.arb) → generated AppLocalizations
  platform/
    analytics/           AnalyticsService interface + NoOp, DebugPrint, Firebase impls
    crash/               Crashlytics wrapper (release only)
    ads/                 AdService, AdGate (pure), ad_ids.example.dart (committed) / ad_ids.dart (gitignored)
    iap/                 PurchaseService (remove_ads)
    auth/                FirebaseAuthService (anon, Google, Apple, email) + backend token exchange
    audio/               AudioService (SoLoud), audio session config
    haptics/             HapticService
    notifications/       FCM + local daily reminder
  app.dart, main.dart, router.dart
assets/
  layouts/*.json, layouts/index.json
  tile-faces.json
  fonts/ (Outfit, JetBrains Mono, Noto Sans SC subset) + OFL licences
  audio/music/*.ogg, audio/sfx/*.wav
  icons/*.svg
tool/
  check_layers.dart, layer_fixtures/, gen_turtle.dart, validate_layouts.dart, deal.dart, subset_fonts.md
test/ (flutter) and test_engine/ via `dart test` (pure)
```

### Layering rule (enforced)

| Layer | May import |
|---|---|
| `engine` | `dart:` core libs (not `dart:io`, `dart:ui`, `dart:math` Random usage flagged), other `engine` files |
| `data` | `engine`, packages |
| `state` | `engine`, `data`, `platform` **interfaces** |
| `ui` | `engine`, `data` models, `state`, `platform` interfaces |
| `platform` | `engine` models, packages; never `ui` |
| anything | never `ui` (except `ui` itself, `app.dart`, `main.dart`) |

`platform/<x>/<x>_service.dart` is the interface file; implementation files are `*_impl.dart` and only `main.dart` / provider overrides import them. `tool/check_layers.dart` parses every import under `lib/`, prints `file:line rule` and exits 1 on violation. `tool/layer_fixtures/` holds deliberate violations; `test/tool/check_layers_test.dart` asserts the exact violation list. A `.githooks/pre-commit` (enabled with `git config core.hooksPath .githooks`) runs the checker and the engine tests.

The engine lives under `lib/engine` but is tested with plain `dart test test_engine/` (no Flutter harness), which proves it stays pure.

## 2. Engine

Follows the brief §5 exactly; summary of the parts that shape everything else:

- **Coordinates**: half-tile grid, tile covers `[x,x+2)×[y,y+2)`, `z` layer. Neighbour lists (covers, coveredBy, left, right) precomputed per layout.
- **Free rule**: not covered by any tile on `z+1` with `|dx|<2 && |dy|<2`, and not (left neighbour at `dx==−2` and right at `dx==+2`, `|dy|<2`).
- **Dealer**: simulated removal on the full layout with xoshiro128**; bounded backtracking, reseed on failure; optional spread bias (off in tests). `generatorVersion = 1` stored with every deal.
- **Solver**: DFS over matching free pairs, memo on a 144-bit remaining-set (three ints / BigInt-free `Uint32List`), heuristic ordering (prefer tiles that free the most), node budget → `solvable | unsolvable | unknown`.
- **Every deal and shuffle is solver-verified before display.** Tests: 5,000 seeds per bundled layout, dealer/solver agreement, known-unsolvable fixtures, budget overruns fail.
- **GameState** is immutable: positions, faces, removed bitset, selection, history, counters (hintsUsed, freeHintsLeft, shufflesUsed, freeShufflesLeft, undos, longestStreak), elapsed handled outside the engine (the controller owns the clock and passes it in).
- **Commands** return `(GameState, List<GameEvent>)`. The UI animates events; the engine never waits.
- **Stars** (`scoring.dart`), par per layout in `index.json` (derived from tile count × difficulty, tunable):
  - 3★: time ≤ par **and** hints ≤ 1 **and** no rewarded/paid shuffles
  - 2★: time ≤ 1.5 × par **or** hints ≤ 3
  - 1★: cleared
  - Undo never costs stars; the free deadlock shuffle never costs stars.
- **Move log**: list of `(a,b)` position-index pairs plus shuffle markers and per-move elapsed ms; encoded compactly (varint base64). The C# port replays it.

## 3. Data and persistence

**Drift tables** (one store per datum, per snake-classic's rule):

| Table | Purpose |
|---|---|
| `settings` | theme, music, sfx, haptics, show timer, tile size, reduce motion (also mirrored in a provider) |
| `layout_progress` | layoutId, unlocked(by: clear/ad/chapter), bestTimeMs, bestStars, clears, lastPlayedAt |
| `saved_game` | in-progress board per layout (seed, generatorVersion, faces, removed, history, elapsed) for Resume |
| `game_results` | every finished/abandoned game: layout, seed, outcome, timeMs, stars, hints, undos, shuffles, tiles matched, longest streak, playedAt (feeds stats + 7-day chart) |
| `daily_entries` | date, layoutId, seed, firstClearTimeMs, stars, moveLog, submitted, verified |
| `streak` | current, best, lastDailyDate, repairsUsedThisWeek |
| `entitlements` | removeAds (local trust when offline), source, verifiedAt |
| `sync_outbox` | id, kind, payload JSON, attempts, nextAttemptAt (written in the same transaction as the change) |
| `cached_leaderboards` / `friends` | last fetched snapshots for offline display |

SharedPreferences only for device-only flags (onboarding done, JWT, install id, ad timestamps).

**SyncEngine** is the only thing that talks to the backend for writes: drains `sync_outbox` with debounce (3 s), periodic (2 min), exponential backoff, and on resume/pause. Reads (leaderboards, friends) are fetched on screen open, cached, and fall back to the cache. **No network call ever blocks start-up or gameplay.**

Drift's generated `*.g.dart` files are gitignored: after a fresh clone (or any table/DAO change) run `dart run build_runner build` before building or testing.

**Layouts as data**: `assets/layouts/index.json` defines chapters (Classics, Creatures, Wonders, …), order, unlock thresholds, par times, daily pool. Layout JSON per §5.2 of the brief. `tool/validate_layouts.dart` runs validation + 500 seeds each.

## 4. State (Riverpod)

**Decision: Riverpod 3 (latest 3.x), manual providers, no codegen.** Chosen over Bloc after comparing both (Nov 2026):

- One library covers state, async caching **and** DI with overrides (debug/no-op/release platform services, test fakes). Bloc would need get_it alongside it, the mix snake-classic ended up with.
- The engine already is the event/state machine (`command → (GameState, events)`); a Bloc on top would restate the same events. A `Notifier` is a thin adapter.
- Drift streams, leaderboards, friends and auth map directly onto `StreamProvider` / `AsyncNotifier`.
- Tests use `ProviderContainer(overrides: …)` without widget scaffolding.

**Rules:**
1. Only `Provider`, `Notifier`, `AsyncNotifier`, `StreamNotifier`, `FutureProvider`, `StreamProvider` (+ `.family`, `.autoDispose`). No legacy `StateProvider` / `StateNotifierProvider` / `ChangeNotifierProvider`; no experimental mutations or offline persistence (Drift owns persistence).
2. Automatic retry is **disabled globally** (`ProviderScope(retry: (_, _) => null)`); network read providers opt in with their own retry policy.
3. Platform services are `Provider<Interface>` that throw by default and are overridden in `main.dart` (release vs debug impls) and in tests.
4. The game controller is kept alive for the board's lifetime (`ref.keepAlive()` link released on exit); its clock pauses on `AppLifecycleState` changes, not on provider pausing.
5. Animations subscribe to the controller's `Stream<GameEvent>` (`ref.listen` / subscription in the board's `State`) and drive `AnimationController`s; widgets `select` the minimal slice of state, so the board never rebuilds per frame.
6. No `ref.read` in `build`; `ref.watch` for rendering, `ref.read` in callbacks, `ref.listen` for side effects (navigation, sheets, haptics).
7. Providers live in `lib/state/`, one file per feature, named `xxxProvider`; notifiers are classes named `XxxController`.

- `gameControllerProvider(layoutId | daily)`: `Notifier` holding `GameState` + clock + an event stream for the board. Owns the timer (pauses on background/pause sheet), fires analytics, writes results through repositories.
- `settingsProvider`, `progressProvider`, `dailyProvider`, `leaderboardProvider(tab)`, `friendsProvider`, `authProvider`, `entitlementProvider`, `adGateProvider`.
- Platform services exposed via providers with interface types; `main.dart` overrides them with real impls (release) or debug/no-op impls.

## 5. UI

- **Theme**: `jw_tokens.dart` copied verbatim → `JwTheme extends ThemeExtension` for light/dark; system/light/dark from settings. Outfit (UI), JetBrains Mono (all numerals, tabular), Noto Sans SC subset to the 25 glyphs. All bundled.
- **ClayDecoration**: custom `Decoration` painting outer shadows with `MaskFilter.blur` and inset shadows as blurred inverse paths; cached per (size, level, theme) via `PictureRecorder`. Tiles reuse three cached pictures.
- **Board**: `Stack` of `Positioned` tiles sorted (z, y, x), `RepaintBoundary` per tile, fit-to-area scaling (0.8×–1.25×), pinch-zoom up to 2× only below 0.8×. Faces painted from `tile-faces.json` by `TileFacePainter` (beads, capsules) + text glyphs. Four-channel playable/blocked distinction; goldens for the full board in both themes + greyscale.
- **Motion**: every entry of `MOTION_SPEC.md` with `JwMotion` durations/curves, reduce-motion from the setting **or** `MediaQuery.disableAnimations`; shared-element layout → board, cleared beat sheet, combo chips, counter rolls. Input never blocked except the first 60% of board entry.
- **Stars in the UI** (new vs the design, in the same clay language): three star beads on the cleared screen (drop in with the medal beat), small star row on layout cards next to Best, star column on leaderboard rows.
- **Friends**: a Friends screen (your code, share invite link, add by code, pending requests) reached from the leaderboard's Friends tab and Settings → Account.
- **Splash**: `flutter_native_splash` (static final frame of option A, both themes) → Flutter continuation (beads pop + wordmark fade, ≈600 ms) → home, or the starter board on first run (play first; no intro pages).
- **Back navigation**: go_router with Android predictive back enabled and iOS edge-swipe (Cupertino page transitions on iOS).
- **Responsive**: portrait-only; `responsive.dart` (snake-classic pattern) scales layout on tablets; text scale clamped to 1.3× at the root.

## 6. Platform services

- **Auth** (snake-classic flow): on first launch sign in anonymously → `getIdToken()` → `POST /auth/firebase` → backend JWT in SharedPreferences. Account screen offers Google (`google_sign_in` v7 with `GOOGLE_WEB_CLIENT_ID` from `.env` as serverClientId), Apple (`AppleAuthProvider`), and email/password (sign up, sign in, reset password), each via `linkWithCredential` so guest progress is kept. 401 → coalesced `ensureBackendSession()`. All of this is off the critical path.
- **Analytics**: `AnalyticsService` interface; `NoOpAnalytics`, `DebugPrintAnalytics` (debug/profile), `FirebaseAnalyticsService` (release only). Events from brief §7 incl. `board_abandon` on `AppLifecycleState.paused/detached` with a board in progress, plus `stars_earned`, `layout_unlock_ad`, `friend_added`, `streak_repaired`, `ad_*`, `iap_*`. No PII.
- **Crashlytics**: enabled only when `kReleaseMode`; `FlutterError.onError` + `PlatformDispatcher.onError` routed to it.
- **Audio**: `flutter_soloud`, serial queue, all assets preloaded in memory; music loop crossfades between 2–3 royalty-free tracks; SFX for select, match, mismatch, blocked, shuffle, undo, hint, clear, star, button. Audio session (`audio_session`) configured to **mix with others** (ambient) by default.
- **Haptics**: `HapticService` with semantic methods matching the motion spec (light, medium, selection-error double tick).
- **Notifications**: FCM token registered silently; permission soft-asked after the first daily clear; optional local daily reminder.

## 7. Ads and IAP (built in Phase 8, designed now)

Placements (AdMob, no banners anywhere):

| Format | Placement | Rule |
|---|---|---|
| **Rewarded** | Extra hint (after 3 free) | Offered only if a matching pair exists; reward granted only in the SDK reward callback; hint applied immediately |
| **Rewarded** | Extra shuffle (after 2 free) | Same; the deadlock shuffle is always free and never shows an ad |
| **Rewarded** | Unlock a locked layout | Unlock persisted locally (and synced) on reward |
| **Rewarded** | Streak repair | Missed exactly one daily → keep the streak; max once per 7 days |
| **Rewarded interstitial** | "Head start" on the cleared screen → next board | Intro sheet with reward stated ("+2 hints on your next board"), 5 s countdown and a Skip button (Google policy); only on boards that didn't get an interstitial |
| **Rewarded interstitial** | "Second chance" on returning to an abandoned/deadlocked board | Intro: "+1 free shuffle and +1 hint"; opt-out always available |
| **Interstitial** | After a board is cleared only | Max 1 per 3 cleared boards, ≥ 4 min apart, none in a new install's first 2 boards, never on restart/abandon/failure, never mid-board, never on the daily before its result is shown |
| **App open** | Optional, on resume after ≥ 30 min away (counted from `paused`) | Only if an ID is provided in `ADMOB-NOTE.txt`; never on cold start of a first session |

- `AdGate.evaluate(context) → (format?, reason)` is pure and unit-tested; the reason is logged to analytics (snake-classic pattern).
- Consent: UMP first (10 s timeout, cached fallback) → ATT on iOS → fail closed on `canRequestAds()`. Privacy options entry in Settings.
- **Remove ads** ($1.99, non-consumable `com.pranta.jadewell.remove_ads`, both stores): disables interstitials, app open and automatic rewarded interstitials; rewarded ads remain as opt-in buttons. Restore purchases on both platforms; verify server-side when online, trust local entitlement offline; verify-then-finish (snake-classic pattern).
- Debug builds always use Google's test IDs. Real IDs live in gitignored `lib/platform/ads/ad_ids.dart` generated from `ADMOB-NOTE.txt`; `ad_ids.example.dart` is committed.

## 8. Friends (client side)

- Every user has a short, unambiguous **friend code** (e.g. `JW-7K3P9Q`) from the backend.
- Add a friend by code, or share an invite link `https://jadewell.pranta.dev/f/<code>` (Android App Links / iOS Universal Links open the app on the add-friend sheet; falls back to the store page).
- Requests: send, accept, decline, remove. Friends leaderboard = today's daily for you + friends.
- Requires being online and a backend session; works for guests (guest accounts can have friends; linking keeps them).

## 9. Testing

| Suite | Runner | Covers |
|---|---|---|
| Engine | `dart test test_engine/` | rules, free-tile edge cases, PRNG golden values, dealer/solver agreement (5,000 seeds × layout), unsolvable fixtures, deadlock, shuffle solvability, undo of shuffle, stars, move log round-trip, daily seed goldens |
| Layer check | `flutter test test/tool` | checker passes on `lib/`, fails with exact violations on fixtures |
| Layouts | `dart run tool/validate_layouts.dart` + test | every layout valid, 500 seeds solvable |
| Data | `flutter test` with in-memory Drift | DAOs, migrations, sync outbox |
| Ads gate | unit | frequency cap, first-2-boards rule, never-after-abandon, reward-only-if-resolves |
| Widgets / goldens | `flutter test` | tile states, full 144 board light/dark/greyscale, key screens |
| Device | real Android phone + tablet each phase; iOS on the Mac later | |

Cross-language fixtures (`fixtures/deals/*.json`: seed, layoutId, generatorVersion → faces) are generated by the Dart engine and copied into the API repo; both test suites assert them.

## 10. Configuration and secrets

- `.env` (gitignored, shipped as an asset, public values only): `GOOGLE_WEB_CLIENT_ID`, `DEV_API_BACKEND_URL`, `PROD_API_BACKEND_URL`. `.env.example` committed.
- Firebase config files are gitignored (`flutterfire configure` regenerates them).
- `ADMOB-NOTE.txt`, `lib/platform/ads/ad_ids.dart`, `android/key.properties`, keystores: gitignored.

## 11. iOS handoff

`docs/IOS_HANDOFF.md` will list everything the Mac session must do: `flutterfire configure` for `GoogleService-Info.plist`, Swift Package Manager resolution, signing team, Sign in with Apple capability, push capability + APNs key upload to Firebase, Associated Domains (`applinks:jadewell.pranta.dev`), StoreKit product, ATT string and SKAdNetwork IDs, `GADApplicationIdentifier`, running goldens on iOS, and TestFlight upload.

## 12. Build order (Phases 4–6)

1. Engine + tests + `deal.dart` CLI (Phase 4)
2. Turtle generator + the other layouts + validator + index.json (Phase 5)
3. Theme, ClayDecoration, components, board, screens, motion, audio, analytics, auth (Phase 6)

Parallel agents from Phase 4: engine, layout authoring, theme/components, backend scaffolding, each in its own scope with the layering check as the contract.
