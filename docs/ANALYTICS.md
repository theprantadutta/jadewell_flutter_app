# Analytics

Firebase Analytics (GA4 property `jadewell-c6647`, release builds only) behind
`AnalyticsService` (`lib/platform/analytics/`). Every event, param and user
property goes through `AnalyticsSanitizer`: valid names, no PII, values capped.
Debug/profile builds print what release would send (`analytics: ...` in logcat).

## Events

| Event | Params | When |
|---|---|---|
| `app_open` | | Splash, once per launch |
| `onboarding_step` | `step` | Legacy (app ≤ 1.0.6): each onboarding page shown. No longer sent |
| `onboarding_complete` | `flow`, `step`, `skipped` | First run done (see "First run" below) |
| `coach_complete` | `layout_id`, `time_ms` | First match on the starter board under the first-move coach |
| `how_to_play_open` | `source` (`settings`) | Settings → How to play opened (the old onboarding pages) |
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

## First run (play first, after 1.0.6)

A new player (`onboarding_done` unset) goes from the splash straight into the
starter board (`layout_id = sprout`, 40 tiles, index.json `starter`). No intro
pages: the board coaches the first move (the first matching free pair glows and
a "Tap two matching free tiles" tip shows until the first match). The old
onboarding pages are Settings → How to play.

- `onboarding_complete` is logged when the splash hands over to the starter
  board, and `onboarding_done` is set then, so leaving the board unfinished
  never brings the intro back. Params: `flow = play_first`, `skipped = false`,
  `step = 0` (no intro pages were shown). Older versions sent `step` 1–3 and
  `skipped` true/false without `flow`; filter on `flow` to separate them.
- `coach_complete` marks the first match (`time_ms` = board time to it). It is
  logged at most once per board and only on the starter board for a player with
  `lifetime_clears = 0`.
- The starter board's `layout_start`, `board_cleared` and `board_abandon` carry
  `layout_id = sprout` and `tiles = 40` like any board.

**To register in GA4** (event-scoped dimensions; the lead does this): `flow`,
`source`. `time_ms` on `coach_complete` is already a registered metric.

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
   → `layout_start` → `coach_complete` → `board_cleared` with
   `lifetime_clears = 1`. This is the number to move first. From the release after 1.0.6 the first
   board is the 40-tile starter (`layout_id = sprout`).
2. **Where boards are left:** `board_abandon` by `layout_id`, `tiles`,
   `tiles_left` and `lifetime_clears`.
3. **Onboarding drop-off:** up to 1.0.6, `onboarding_step` by `step` and
   `onboarding_complete` by `skipped`; after that there are no intro pages, so
   look at `coach_complete` vs `board_abandon` on `sprout` instead, and
   `how_to_play_open` for who wants the rules.
4. **Retention:** Reports → Retention, and Explore → Cohort by first-session week.
5. **Ad health:** `ad_load_failed` by `format` × `code` × `message` (code 3 =
   no fill, which is normal for a new app; anything else is a setup problem) and
   by `attempt` (retries inflate the raw count).
6. **Revenue:** AdMob for money; `ad_revenue` × `format` here for per-user value.

Closed-testing data is noisy: Play pre-launch devices (`app_clear_data`, US/NL/SG
traffic) and tester-exchange installs inflate users and deflate engagement.
Compare by app version and country before drawing conclusions.

## Daily reminder (local notifications)

**How the permission is asked** (Apple's guidance: ask in context, explain the
value in Jadewell's own UI first, and keep the one-shot OS dialog for an
explicit yes). The primer sheet "Never miss a daily board" lists three benefits
and offers "Turn on reminders" / "Not now"; only "Turn on reminders" shows the
OS dialog, so "Not now" leaves it unused for later.

- **Home, by itself:** never on the cleared screen. It opens on Home ~900 ms
  after Home appears, only while Home is the current route (nothing pushed or
  open on top), once the player has cleared at least one board (the Sprout
  warm-up counts), with the setting on and the OS permission missing, at most
  once per app session, and never in a session where the in-app review was
  requested. Ask 1 comes on the first Home visit after the first clear. After
  "Not now" there is at most one more ask (ask 2), no sooner than 3 days later
  AND after 3 more clears. After that, a yes, or an OS refusal, Home never asks
  again. Rules: `ReminderPromptPolicy` (`lib/state/reminder_policy.dart`);
  history in SharedPreferences (`reminder.asks`, `reminder.lastAskMs`,
  `reminder.clearsAtAsk`, `reminder.accepted`, `reminder.osDenied`; the old
  cleared-screen ask's `reminder.decided` migrates to one answer given).
- **Settings → Daily reminder:** switching it on while the OS permission is
  missing opens the same primer; "Not now" leaves it off (and counts as an
  answer for the Home rules). Once the OS has said no, the switch skips the
  primer, asks the OS directly and, if it is still blocked, shows a toast
  pointing to the phone's settings.

| Event | Params | When |
|---|---|---|
| `reminder_prompt` | `result` (`accepted` / `declined` / `os_denied`), `source` (`home` / `settings`), `attempt` (int, which answer this is: 1 or 2 from Home; Settings can go higher) | The player answered the reminder primer on Home or in Settings (`declined` = Not now or dismissed; `os_denied` = Turn on reminders, then the OS dialog said no or is blocked), or switched Settings → Daily reminder on after an earlier OS refusal (no primer then). Earlier builds (cleared-screen ask) logged `source: cleared` without `attempt` |
| `reminder_scheduled` | `hours_ahead` (int, hours until the day-1 reminder), `variant` (`streak` / `daily`) | The app went to the background and reminders were (re)scheduled. Fires on every background, so use it for counts per user, not per session |
| `reminder_open` | `day` (1–3, which reminder of the chain), `variant` (`streak` / `daily` / `comeback`) | The app was launched or brought back by tapping a reminder (`notification_open` is reserved by Firebase) |

Settings → Daily reminder also logs the existing `settings_changed` with `setting: daily_reminder`.

**To register in GA4** (Admin → Custom definitions, event-scoped custom dimensions; the lead does this):

- `result` (dimension)
- `source` (dimension)
- `attempt` (dimension; already registered for `ad_load_failed`, same meaning "try number")
- `variant` (dimension)
- `day` (dimension)
- `hours_ahead` (custom metric, unit: standard)

Skip any that are already registered for another event: GA4 custom definitions are per parameter name, not per event.

Mark `reminder_open` as a key event if reminder-driven sessions should show up in the acquisition reports.
