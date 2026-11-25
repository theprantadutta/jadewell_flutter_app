# Analytics

Firebase Analytics (GA4 property `jadewell-c6647`, release builds only) behind
`AnalyticsService` (`lib/platform/analytics/`). Every event, param and user
property goes through `AnalyticsSanitizer`: valid names, no PII, values capped.
Debug/profile builds print what release would send (`analytics: ...` in logcat).

## Events

| Event | Params | When |
|---|---|---|
| `app_open` | | Splash, once per launch |
| `onboarding_step` | `step` | Each onboarding page shown |
| `onboarding_complete` | `step`, `skipped` | Finished or skipped |
| `layout_start` | `layout_id`, `daily`, `tiles`, `lifetime_clears`, `resumed` or `restart` | Board dealt, resumed or restarted |
| `board_cleared` | `layout_id`, `daily`, `tiles`, `lifetime_clears`, `time_ms`, `hints`, `undos`, `shuffles`, `stars` | Board cleared |
| `board_abandon` | `layout_id`, `daily`, `tiles`, `lifetime_clears`, `tiles_left`, `time_ms`, `trigger` (`quit`/`background`) | Left mid-board |
| `hint_used`, `shuffle_used` | `layout_id`, `kind` (free/rewarded) | |
| `undo_used`, `second_chance` | `layout_id` | |
| `deadlock_shown` | `layout_id`, `tiles_left` | |
| `daily_start`, `daily_complete` | `layout_id` (+ `time_ms`, `stars`) | Daily challenge |
| `stars_earned` | `layout_id`, `stars` | |
| `streak_repaired` | `restored_streak` | |
| `friend_added` | `via` | |
| `account_linked` | `provider` | |
| `settings_changed` | `setting` (name only, never the value) | |
| `iap_view` … `iap_error` | `code`, `verified`, `result` | Remove ads (docs/IAP.md) |
| `ad_gate` | `trigger`, `reason`, `daily` | Every ad decision (docs/ADS.md) |
| `ad_shown` | `format`, `placement`, `reason` | |
| `jw_ad_reward` | `placement`, `format` | |
| `ad_load_failed` | `format`, `code`, `message`, `attempt` | Each failed load, retries included |
| `ad_revenue` | `format`, `value_micros`, `currency`, `precision` | AdMob paid event |

`lifetime_clears` is the number of boards the player has cleared (counting this
one on `board_cleared`), so `lifetime_clears = 0` on `layout_start` /
`board_abandon` isolates players who have never finished a board.

## User properties

Set from `PlatformBridge` when the value changes: `account` (guest, google,
apple, other), `ads_removed` (0/1), `onboarding_done` (0/1), `theme`
(system/light/dark).

## GA4 setup (done 2026-11-25)

Custom definitions only collect from the day they are registered. When adding a
param that should be reportable, register it in GA4 Admin → Data display →
Custom definitions in the same change.

- **Event-scoped dimensions:** `layout_id`, `tiles`, `lifetime_clears`, `daily`,
  `resumed`, `restart`, `trigger`, `stars`, `kind`, `step`, `skipped`, `setting`,
  `result`, `provider`, `via`, `format`, `code`, `message`, `attempt`, `reason`,
  `placement`, `verified`, `restored_streak`.
- **User-scoped dimensions:** `account`, `ads_removed`, `onboarding_done`, `theme`.
- **Custom metrics:** `time_ms` (milliseconds), `tiles_left`, `hints`, `undos`,
  `shuffles`, `value_micros` (standard).
- **Key events:** `first_open` (default), `onboarding_complete`, `board_cleared`,
  `daily_complete`, `account_linked`. Star `iap_success` in Admin → Events once
  the first purchase has been logged (it can't be starred before it exists).

## What to look at

1. **First-board funnel** (Explore → Funnel): `first_open` → `onboarding_complete`
   → `layout_start` → `board_cleared` with `lifetime_clears = 1`. This is the
   number to move first.
2. **Where boards are left:** `board_abandon` by `layout_id`, `tiles`,
   `tiles_left` and `lifetime_clears`.
3. **Onboarding drop-off:** `onboarding_step` by `step`, and
   `onboarding_complete` by `skipped`.
4. **Retention:** Reports → Retention, and Explore → Cohort by first-session week.
5. **Ad health:** `ad_load_failed` by `format` × `code` × `message` (code 3 =
   no fill, which is normal for a new app; anything else is a setup problem) and
   by `attempt` (retries inflate the raw count).
6. **Revenue:** AdMob for money; `ad_revenue` × `format` here for per-user value.

Closed-testing data is noisy: Play pre-launch devices (`app_clear_data`, US/NL/SG
traffic) and tester-exchange installs inflate users and deflate engagement.
Compare by app version and country before drawing conclusions.
