# Analytics

Firebase Analytics behind `AnalyticsService` (`lib/platform/analytics/`). Release builds send to Firebase; debug and profile builds print the sanitized event (`DebugPrintAnalytics`). Every event goes through `AnalyticsSanitizer` (valid names, no reserved names or prefixes, no PII keys, strings capped at 100 chars, bools as 0/1). Event names live in `AnalyticsEvents`. Ad events are documented in `docs/ADS.md`.

## Daily reminder (local notifications)

| Event | Params | When |
|---|---|---|
| `reminder_prompt` | `result` (`accepted` / `declined` / `os_denied`), `source` (`cleared` / `settings`) | The player answered the "Want a daily reminder?" sheet on the cleared screen (`declined` = Not now or dismissed; `os_denied` = Yes, then the OS dialog said no or is blocked), or switched Settings → Daily reminder on while the OS permission was missing |
| `reminder_scheduled` | `hours_ahead` (int, hours until the day-1 reminder), `message` (`streak` / `daily`) | The app went to the background and reminders were (re)scheduled. Fires on every background, so use it for counts per user, not per session |
| `reminder_open` | `day` (1–3, which reminder of the chain), `message` (`streak` / `daily` / `comeback`) | The app was launched or brought back by tapping a reminder (`notification_open` is reserved by Firebase) |

Settings → Daily reminder also logs the existing `settings_changed` with `setting: daily_reminder`.

**To register in GA4** (Admin → Custom definitions, event-scoped custom dimensions; the lead does this):

- `result` (dimension)
- `source` (dimension)
- `message` (dimension)
- `day` (dimension)
- `hours_ahead` (custom metric, unit: standard)

Skip any that are already registered for another event: GA4 custom definitions are per parameter name, not per event.

Mark `reminder_open` as a key event if reminder-driven sessions should show up in the acquisition reports.
