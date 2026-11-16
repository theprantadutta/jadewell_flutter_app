# In-app purchases (Remove ads)

One non-consumable product on both stores:

| | |
|---|---|
| Product id | `com.pranta.jadewell.remove_ads` (same on Google Play and the App Store) |
| Type | Non-consumable (Play: one-time product; App Store: Non-Consumable) |
| Price | $1.99 (store-localized; the app always shows the store's own price string) |
| Effect | Interstitials, app open and automatic rewarded interstitials stop. Opt-in rewarded ads (extra hint/shuffle, unlock, streak repair) stay available. |

**Status (Nov 2026): the code is complete; the product does not exist in either store yet.** Until it does, the Store screen shows a calm "Not available yet — check back soon" card, Settings still shows the Remove ads row (without a price), and nothing else changes. The day the product is created and active, the price appears and purchases work with no app change.

## Code map

| File | Role |
|---|---|
| `lib/platform/iap/purchase_service.dart` | `PurchaseService` interface, `StoreStatus` (sealed: unavailable / productMissing / loading / ready(price) / purchasing / verifying / pending / purchased / error(code)), `ProductIds`, the `StoreAdapter` seam, `UnavailablePurchaseService` (default) |
| `lib/platform/iap/purchase_service_impl.dart` | The flow (below). Plugin-free, tested with a fake store |
| `lib/platform/iap/openiap_store_adapter_impl.dart` | `StoreAdapter` on `flutter_inapp_purchase` 11.4 (OpenIAP: Play Billing 9.1 / StoreKit 2) |
| `lib/platform/iap/pending_verifications.dart` | Verify-later queue (SharedPreferences, device-only) |
| `lib/data/api/purchases_api.dart` | `POST /purchases/verify`, `POST /purchases/restore`, `GET /purchases/entitlements` |
| `lib/data/repositories/entitlement_repository.dart` | Drift `entitlements` row (via `EntitlementsDao`) + in-memory twin |
| `lib/state/entitlement_providers.dart` | `entitlementProvider` (sync `Entitlement.removeAds`), `storeStatusProvider`, `removeAdsPriceProvider`, `startPurchases()` |
| `lib/ui/screens/store/` | Store screen + `StoreController` (status + entitlement → `StoreView`) |

`main.dart` overrides `purchaseServiceProvider` / `entitlementRepositoryProvider` and calls `startPurchases(container)`, which: connects to the store in the background, reconciles on every resume, merges server entitlements whenever the backend session is online for a (new) user, and feeds `entitlementProvider.removeAds` into `AdService.setAdsRemoved` (fires immediately with the stored value on start).

Package: `flutter_inapp_purchase` (same family as snake-classic, now on 11.x). The low-level API (`initConnection` / `fetchProducts` / `requestPurchase` / `purchaseUpdatedListener` / `finishTransaction` / `getAvailablePurchases` / `restorePurchases`) is used rather than 11.x's `createPurchaseFlow`, because our acknowledge policy (below) needs control over *when* a purchase is finished. Note: it pins `platform` < 3.2.0, so `platform` resolves to 3.1.6.

## The flow

1. **Listeners first, then `initConnection`.** StoreKit replays unfinished transactions the moment the connection opens.
2. **Fetch the product.** No billing (no Play Store, sideloaded build, simulator without StoreKit config, connection error) → `StoreUnavailable`. Store answers but has no such product (Play returns an unfetched placeholder with an empty price; seen on the device in Nov 2026) → `StoreProductMissing`. Both render "Not available yet". A product created later is picked up on the next resume (`reconcile()` re-fetches while there is no price).
3. **Buy** → `StorePurchasing` (spinner). The result arrives on the listeners:
   - **PURCHASED** → granted locally at once (the player paid; the Drift row is the local truth), `StoreVerifying`, then `POST /purchases/verify`.
   - **PENDING** (cash, carrier billing, parental approval) → "Payment pending". Nothing granted, nothing finished. Play re-reports it as PURCHASED when it clears; the listener or the next resume reconcile picks it up.
   - **User cancelled** → silently back to Ready (`iap_cancel`).
   - **Already owned** → treated as a restore (owned purchases are read and run through verification).
   - **Other errors** → error state with "Try again" (`iap_error` with the store's code only).
4. **Verification verdict** (`PurchaseServiceImpl.classify`):

| Backend answer | Meaning | Local entitlement | Store transaction |
|---|---|---|---|
| 200 `state: verified` | Confirmed | granted, `verifiedAt` set | finished (acknowledged) |
| 200 `state: pending`, **404**, 5xx, timeout, offline, 401, unparsable, no session yet | Verify later | stays granted | see acknowledge policy |
| 200 `state: refunded` | Refunded | revoked | iOS finished; Android left alone |
| 200 `state: invalid`, other 4xx (400/403/409/422) | Refused | revoked if never verified | iOS finished (stops replays); Android left **unacknowledged** so Play refunds it |

5. **Restore** (header button, visible on both platforms; Apple requires it): `restorePurchases()` sync, then every owned purchase goes through the same verification. If the store account owns nothing, `POST /purchases/restore` with an empty list asks the backend whether this *account* owns it (e.g. bought on the other platform).
6. **Resume** (`reconcile()`): reloads the store if it had no price, walks owned purchases (finishes anything verified but unfinished, verifies anything new or still queued), retries queued receipts the store no longer reports, and clears a stuck "Purchasing…" spinner 3 s after resume if the store sent no event (backing out of the Play sheet sometimes emits nothing).
7. **Sign-in / user change** (`onSessionChanged`): `GET /purchases/entitlements` → merge: `true` → granted + verified; `false` → revokes only a grant that was itself server-verified (refund/revocation). A store grant still awaiting verification is kept — offline/unverified local truth is trusted until the server says otherwise about that receipt.

Purchases never go through the sync outbox; they are verified directly.

## Acknowledge policy (Android) and why

Play auto-refunds a purchase that is not acknowledged within **3 days**. snake-classic acknowledges only after the backend verified the purchase, so an unverifiable purchase is refunded — correct when the backend is always up. Jadewell must also work while the purchases endpoint is not deployed (404) or the device is offline, and a $1.99 non-consumable refunded under a paying player is the worst outcome. So:

- **Backend reachable** → acknowledge **only after** it returns `verified`. A refusal (`invalid` / 4xx) is never acknowledged, so Play refunds it — the safe end for a bad receipt.
- **Backend 404 / unreachable / no session** → the purchase stays granted locally and its receipt is queued. Verification is retried on every resume and whenever the session comes online. If it is still unverified **2 days after the purchase time the store reports**, the purchase is acknowledged anyway (one day of margin before Play's deadline). Verification keeps being retried afterwards; a later `refunded`/`invalid` verdict still revokes the entitlement.
- **Trade-off:** acknowledging unverified means a forged/abused receipt could stick if our backend stays unreachable for two days. Play's own signature on the purchase (only Play can deliver a PURCHASED purchase to the listener) and the later server re-check keep that risk small for $1.99; the alternative (letting Play refund real purchases while our server is down) is worse.
- **Residual risk:** the deadline is enforced when the app runs (start or resume). A player who buys while the backend is down and doesn't open the app between day 2 and day 3 would be auto-refunded by Play (and keeps no entitlement once the server/queue sees the refund). Acceptable; deploy the endpoint before the product goes live and this never happens.
- **iOS** has no auto-refund: an unverified transaction stays unfinished, and StoreKit replaying it on every launch *is* the retry.

## Backend contract (implemented by the backend; the client is built to exactly this)

All Bearer JWT (the app's backend session).

```
POST /api/v1/purchases/verify
{"platform":"android"|"ios","product_id":"com.pranta.jadewell.remove_ads",
 "purchase_token":"<android purchaseToken>"|null,
 "transaction_id":"<ios transactionId>"|null,
 "signed_transaction":"<ios JWS>"|null}
→ 200 {"valid":true,"product_id":"…","state":"verified"|"pending"|"refunded"|"invalid","entitlements":{"remove_ads":true}}
→ 4xx {"error":"…"} when invalid

POST /api/v1/purchases/restore   {"platform":"…","purchases":[<same item shape>]}  → {"entitlements":{"remove_ads":bool}}
GET  /api/v1/purchases/entitlements                                              → {"entitlements":{"remove_ads":bool}}
```

A 404 from any of these (backend not deployed yet) is "try later", never a failure.

## Analytics

`iap_view` (Store screen opened), `iap_start` (sheet launched), `iap_success` (`verified`: 1/0), `iap_cancel`, `iap_pending`, `iap_restore` (`result`: restored / nothing / unavailable / failed), `iap_error` (`code` only, e.g. `network_error`, `invalid`, `refunded`, `already_owned`, `restore_failed`). No tokens, ids or prices are logged.

## Remaining console steps

### Google Play Console

Production access is **not** required to create the product: in-app products can be created once any app bundle containing Play Billing has been uploaded to *any* track (internal testing is enough). Steps:

1. **Payments profile**: Setup → Payments profile (merchant account) must exist and be verified, or the Monetize section stays locked.
2. **Upload a release AAB** (built from this code; Play Billing adds `com.android.vending.BILLING` automatically) to **Testing → Internal testing** and roll it out.
3. **Monetize with Play → Products → One-time products → Create**:
   - Product ID `com.pranta.jadewell.remove_ads` (cannot be changed or reused later)
   - Name "Remove ads", description "Removes ads between boards. Rewarded videos stay optional."
   - Purchase option: **Buy**, non-consumable (one-time); price **USD 1.99**, "Set prices" → update local prices from the USD price
   - **Activate** the product.
4. **License testers**: Settings → License testing → add the tester Gmail accounts (test purchases are free and auto-refund).
5. **Backend verification access** (for `POST /purchases/verify` on the server):
   - Google Cloud project linked to the Play developer account; enable **Google Play Android Developer API**
   - Create a service account + JSON key; in Play Console → Users and permissions → invite the service-account e-mail with **View financial data** and **Manage orders and subscriptions** for Jadewell
   - Give the JSON key to the backend (its secret store, never this repo). New service accounts can take up to ~24 h before the API accepts them.
   - Optional: Monetization setup → **Real-time developer notifications** → Pub/Sub topic pointing at the backend, so refunds/voided purchases revoke without waiting for the app.
6. **Test**: install from the internal-testing opt-in link on a device signed in with a license tester (a sideloaded debug build signed with another key may load the product but is not a reliable purchase test). Buy → "Verifying…" → celebration; check the order in Order management; Restore after reinstall; refund the test order and confirm the server reports `refunded`.

### App Store Connect

1. **Agreements, Tax and Banking**: the **Paid Apps** agreement must be active (bank + tax forms), or products never load.
2. **App → Monetization → In-App Purchases → +**: type **Non-Consumable**, reference name "Remove ads", Product ID `com.pranta.jadewell.remove_ads`.
3. **Price schedule**: USD **1.99** price point (all territories auto-equalized).
4. **App Store localization** (English): display name "Remove ads", description "Removes ads between boards. Rewarded videos stay optional."
5. **Review information**: a screenshot of the Store screen and a note ("Remove ads, one-time; Restore is in the top-right of the Remove ads screen, Settings → Remove ads").
6. Status must reach **Ready to Submit**; the first IAP is submitted **with an app version** (add it under the version's "In-App Purchases and Subscriptions" section before submitting the build).
7. **Backend verification**: Users and Access → Integrations → **In-App Purchase** key: create a key (`.p8`), note Key ID and Issuer ID → backend secret store (App Store Server API, used to verify `signed_transaction` / look up `transaction_id`). Optional: App Information → **App Store Server Notifications V2** URL → backend, for refunds/revocations.
8. **Sandbox testers**: Users and Access → Sandbox → add testers; on the device sign in under Settings → App Store → Sandbox Account.
9. Xcode side (on the Mac): see `docs/IOS_HANDOFF.md` (In-App Purchase capability; optional StoreKit configuration file for simulator testing).

## Tests

`test/iap/`: entitlement repository (memory + Drift: grant / verify / revoke / offline trust / server merge), purchase flow against a fake store and a fake HTTP backend (success → verify → finish; 404 → granted locally, verify later, acknowledge at the 2-day deadline, then verified when the backend ships; no session; pending; cancel; error; already owned → restore; invalid on Android vs iOS; refunded; restore; sign-in merge; stuck spinner on resume; product missing / unavailable / appearing later), and Store screen widget states.
