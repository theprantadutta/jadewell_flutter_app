import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../../data/api/api_result.dart';
import '../../data/api/purchases_api.dart';
import '../../data/repositories/entitlement_repository.dart';
import '../analytics/analytics_service.dart';
import 'pending_verifications.dart';
import 'purchase_service.dart';

/// What the backend's answer means for one receipt.
@visibleForTesting
enum VerifyOutcome {
  /// Confirmed: mark verified, then finish the store transaction.
  verified,

  /// Not now (offline, 404 while the endpoint isn't deployed, 5xx, no
  /// session, payment still clearing server-side): keep the local grant,
  /// queue the receipt, retry later.
  later,

  /// The store refunded it: revoke.
  refunded,

  /// Looked at and refused: revoke an unverified grant; on Android leave it
  /// unacknowledged so Play refunds it.
  invalid,
}

/// Remove ads on top of a [StoreAdapter] (flutter_inapp_purchase in the
/// app, a fake in tests). The flow, in OpenIAP's order:
///
///  1. listeners are attached, THEN the store connection is opened (StoreKit
///     replays unfinished transactions the moment it connects);
///  2. the product is fetched for its localized price — no product (not
///     created in the console yet) or no billing → "Not available yet";
///  3. a purchase is requested; the outcome arrives on the listeners;
///  4. a purchase the store reports PURCHASED is granted locally at once
///     (the player paid), then verified by our backend;
///  5. the store transaction is finished only after the backend verified
///     it — or, when the backend can't be reached / answers 404, at the
///     latest [acknowledgeDeadline] after the purchase, so Play's 3-day
///     auto-refund never hits a real purchase we merely failed to verify.
///     See docs/IAP.md for the trade-off.
///
/// PENDING purchases (cash, carrier billing, parental approval) are never
/// granted or finished; the store re-reports them as PURCHASED once paid.
class PurchaseServiceImpl implements PurchaseService {
  PurchaseServiceImpl({
    required this._store,
    required this._entitlements,
    required this._api,
    required this._pending,
    this._analytics = const NoOpAnalytics(),
    bool Function()? hasSession,
    String? Function()? accountId,
    DateTime Function()? clock,
    this.acknowledgeDeadline = const Duration(days: 2),
    this.storeTimeout = const Duration(seconds: 10),
    this.resumeCancelGrace = const Duration(seconds: 3),
  })  : _hasSession = hasSession ?? (() => true),
        _accountId = accountId ?? (() => null),
        _clock = clock ?? DateTime.now;

  final StoreAdapter _store;
  final EntitlementRepository _entitlements;
  final PurchasesApi _api;
  final PendingVerificationStore _pending;
  final AnalyticsService _analytics;
  final bool Function() _hasSession;
  final String? Function() _accountId;
  final DateTime Function() _clock;

  /// Force-acknowledge an unverifiable purchase this long after it was made
  /// (Play auto-refunds unacknowledged purchases after 3 days).
  final Duration acknowledgeDeadline;
  final Duration storeTimeout;

  /// After resume, how long to wait for a real purchase event before
  /// treating a still-open purchase as a silent cancel.
  final Duration resumeCancelGrace;

  static const _productId = ProductIds.removeAds;

  final _statusController = StreamController<StoreStatus>.broadcast();
  StoreStatus _status = const StoreLoading();
  StreamSubscription<StorePurchase>? _purchaseSub;
  StreamSubscription<StoreFailure>? _failureSub;

  bool _listening = false;
  bool _connected = false;
  String? _price;
  Future<void>? _loading;

  /// The purchase sheet is up and no terminal event has arrived yet.
  bool _purchasing = false;
  Timer? _resumeWatchdog;

  /// Receipts being verified right now (the purchase event and the resume
  /// reconcile both see a fresh purchase within the same second).
  final Set<String> _fulfilling = {};
  bool _reconciling = false;
  String? _lastUserId;
  bool _disposed = false;

  String get _source => _store.platform == 'ios' ? 'app_store' : 'play';

  void _log(String event, [Map<String, Object> params = const {}]) => unawaited(_analytics.log(event, params));

  // ---- status ----

  @override
  StoreStatus get current => _status;

  @override
  Stream<StoreStatus> get status => Stream.multi((c) {
        c.add(_status);
        final sub = _statusController.stream.listen(c.add, onError: c.addError);
        c.onCancel = sub.cancel;
      });

  void _emit(StoreStatus s) {
    if (_disposed) return;
    _status = s;
    _statusController.add(s);
  }

  /// The idle status for the store as it is now.
  StoreStatus _idle({bool owned = false, bool restored = false}) {
    if (owned) return StorePurchased(restored: restored, price: _price);
    if (!_connected) return const StoreUnavailable();
    final price = _price;
    return price == null ? const StoreProductMissing() : StoreReady(price);
  }

  Future<StoreStatus> _idleNow() async => _idle(owned: (await _entitlements.read()).removeAds);

  // ---- lifecycle ----

  @override
  Future<void> init() async {
    if (!_listening) {
      _listening = true;
      _purchaseSub = _store.purchases.listen(
        (p) => unawaited(_onPurchase(p)),
        onError: (Object e) => debugPrint('iap: purchase stream error: $e'),
      );
      _failureSub = _store.failures.listen(
        (f) => unawaited(_onFailure(f)),
        onError: (Object e) => debugPrint('iap: error stream error: $e'),
      );
    }
    await _loadStore();
    if (_connected) await reconcile();
  }

  /// Connects (if needed) and fetches the price. Coalesced.
  Future<void> _loadStore() => _loading ??= _loadStoreUnguarded().whenComplete(() => _loading = null);

  Future<void> _loadStoreUnguarded() async {
    if (!_connected) {
      try {
        _connected = await _store.connect().timeout(storeTimeout);
      } on Object catch (e) {
        debugPrint('iap: store connection failed: $e');
        _connected = false;
      }
    }
    if (_connected) {
      try {
        _price = await _store.fetchPrice(_productId).timeout(storeTimeout);
      } on Object catch (e) {
        debugPrint('iap: product fetch failed: $e');
        _price = null;
      }
      if (_price == null) debugPrint('iap: $_productId not found in the store (not created yet?)');
    }
    if (!_purchasing && !_busyStatus) _emit(await _idleNow());
  }

  bool get _busyStatus => _status is StoreVerifying || _status is StorePurchasing || _status is StorePending;

  @override
  Future<void> dispose() async {
    _disposed = true;
    _resumeWatchdog?.cancel();
    await _purchaseSub?.cancel();
    await _failureSub?.cancel();
    await _statusController.close();
    try {
      await _store.disconnect();
    } on Object {
      // nothing to do
    }
  }

  // ---- buy ----

  @override
  Future<void> buyRemoveAds() async {
    if (_purchasing) return;
    if ((await _entitlements.read()).removeAds) {
      _emit(_idle(owned: true));
      return;
    }
    if (_price == null) {
      // The store may have come up (or the product been created) since.
      await _loadStore();
      if (_price == null) return;
    }
    _log(AnalyticsEvents.iapStart);
    _purchasing = true;
    _emit(StorePurchasing(_price));
    try {
      await _store.requestPurchase(_productId, accountId: _accountId());
    } on StoreFailure catch (f) {
      await _onFailure(f);
    } on Object catch (e) {
      debugPrint('iap: requestPurchase threw: $e');
      await _onFailure(const StoreFailure(StoreErrorKind.other, code: 'request_failed'));
    }
  }

  // ---- store events ----

  Future<void> _onPurchase(StorePurchase p) async {
    if (p.productId != _productId) return;
    final interactive = _purchasing || _status is StorePending;
    _purchasing = false;
    _resumeWatchdog?.cancel();
    switch (p.state) {
      case StorePurchaseState.pending:
        // Not paid yet: nothing granted, nothing finished.
        if (!(await _entitlements.read()).removeAds) {
          if (_status is! StorePending) _log(AnalyticsEvents.iapPending);
          _emit(StorePending(_price));
        }
      case StorePurchaseState.purchased:
        await _fulfil(p, interactive: interactive);
      case StorePurchaseState.unknown:
        debugPrint('iap: purchase in an unknown state, ignored');
        if (interactive) _emit(await _idleNow());
    }
  }

  Future<void> _onFailure(StoreFailure f) async {
    if (f.productId != null && f.productId != _productId) return;
    // On iOS a refusal both throws from requestPurchase and arrives on the
    // error stream; only the first one finds _purchasing set.
    if (!_purchasing && f.kind != StoreErrorKind.alreadyOwned) return;
    _purchasing = false;
    _resumeWatchdog?.cancel();
    switch (f.kind) {
      case StoreErrorKind.cancelled:
        _log(AnalyticsEvents.iapCancel);
        _emit(await _idleNow());
      case StoreErrorKind.pending:
        _log(AnalyticsEvents.iapPending);
        _emit(StorePending(_price));
      case StoreErrorKind.alreadyOwned:
        // The store says they own it and we don't know: pick it up.
        await _restoreOwned(interactive: true);
        final owned = (await _entitlements.read()).removeAds;
        if (!owned) {
          _log(AnalyticsEvents.iapError, {'code': 'already_owned'});
          _emit(StoreError('already_owned', price: _price));
        }
      case StoreErrorKind.unavailable:
      case StoreErrorKind.other:
        _log(AnalyticsEvents.iapError, {'code': f.code});
        _emit(StoreError(f.code, price: _price));
    }
  }

  // ---- verify → grant → finish ----

  Future<void> _fulfil(StorePurchase p, {required bool interactive, bool restoring = false}) async {
    if (!_fulfilling.add(p.identity)) return;
    try {
      await _fulfilUnguarded(p, interactive: interactive, restoring: restoring);
    } on Object catch (e) {
      debugPrint('iap: fulfil failed: $e');
      if (interactive) _emit(await _idleNow());
    } finally {
      _fulfilling.remove(p.identity);
    }
  }

  Future<void> _fulfilUnguarded(StorePurchase p, {required bool interactive, required bool restoring}) async {
    final queue = await _pending.load();
    final queued = queue.where((e) => e.key == p.identity).firstOrNull;
    final current = await _entitlements.read();

    // Already verified and nothing outstanding: at most finish it.
    if (current.removeAds && current.isVerified && queued == null) {
      await _finish(p);
      if (interactive || restoring) _emit(_idle(owned: true, restored: !interactive));
      return;
    }

    // The store says paid: the player gets it now, verified or not.
    await _entitlements.grantRemoveAds(source: restoring ? 'restore' : _source);
    if (interactive) _emit(StoreVerifying(_price));

    final receipt = _receiptFor(p);
    final outcome = await _verify(receipt);
    switch (outcome) {
      case VerifyOutcome.verified:
        await _entitlements.markVerified(at: _clock());
        await _dequeue(p.identity);
        await _finish(p);
        if (interactive) _log(AnalyticsEvents.iapSuccess, {'verified': 1});
        _emit(_idle(owned: true, restored: !interactive));
      case VerifyOutcome.later:
        final entry = queued?.copyWith(attempts: queued.attempts + 1) ??
            PendingVerification(receipt: receipt, purchasedAt: p.purchasedAt ?? _clock(), attempts: 1);
        final acked = await _maybeForceAcknowledge(p, entry);
        await _enqueue(acked);
        if (interactive) _log(AnalyticsEvents.iapSuccess, {'verified': 0});
        _emit(_idle(owned: true, restored: !interactive));
      case VerifyOutcome.refunded:
      case VerifyOutcome.invalid:
        final latest = await _entitlements.read();
        if (outcome == VerifyOutcome.refunded || !latest.isVerified) {
          await _entitlements.revokeRemoveAds(source: 'server');
        }
        await _dequeue(p.identity);
        // iOS: finish so StoreKit stops replaying it. Android: leave it
        // unacknowledged so Play refunds it.
        if (_store.platform == 'ios') await _finish(p);
        final code = outcome == VerifyOutcome.refunded ? 'refunded' : 'invalid';
        if (interactive) {
          _log(AnalyticsEvents.iapError, {'code': code});
          _emit(StoreError(code, price: _price));
        } else {
          _emit(await _idleNow());
        }
    }
  }

  /// Acknowledges an Android purchase we still couldn't verify once it is
  /// [acknowledgeDeadline] old. iOS has no auto-refund, so its transaction
  /// stays unfinished (StoreKit replays it, which is the retry).
  Future<PendingVerification> _maybeForceAcknowledge(StorePurchase p, PendingVerification entry) async {
    if (_store.platform != 'android' || p.acknowledged || entry.acknowledged) {
      return p.acknowledged ? entry.copyWith(acknowledged: true) : entry;
    }
    if (_clock().difference(entry.purchasedAt) < acknowledgeDeadline) return entry;
    debugPrint('iap: acknowledging an unverified purchase before Play refunds it');
    final ok = await _finish(p);
    return ok ? entry.copyWith(acknowledged: true) : entry;
  }

  /// True when finished (or nothing to do).
  Future<bool> _finish(StorePurchase p) async {
    if (p.platform == 'android' && p.acknowledged) return true;
    try {
      await _store.finish(p);
      return true;
    } on Object catch (e) {
      // Not fatal: it comes back on the next reconcile.
      debugPrint('iap: finish failed: $e');
      return false;
    }
  }

  PurchaseReceipt _receiptFor(StorePurchase p) => p.platform == 'ios'
      ? PurchaseReceipt(
          platform: 'ios',
          productId: p.productId,
          transactionId: p.transactionId,
          signedTransaction: p.signedTransaction,
        )
      : PurchaseReceipt(platform: 'android', productId: p.productId, purchaseToken: p.purchaseToken);

  @visibleForTesting
  static VerifyOutcome classify(ApiResult<VerifyResponse> r) {
    if (r.isSuccess) {
      final v = r.value!;
      return switch (v.state) {
        ReceiptState.verified => v.valid ? VerifyOutcome.verified : VerifyOutcome.invalid,
        ReceiptState.pending => VerifyOutcome.later,
        ReceiptState.refunded => VerifyOutcome.refunded,
        ReceiptState.invalid => VerifyOutcome.invalid,
      };
    }
    // 404: the backend doesn't have the endpoint yet. Never a refusal.
    if (r.statusCode == 404) return VerifyOutcome.later;
    return switch (r.failure!) {
      ApiFailure.validation || ApiFailure.forbidden => VerifyOutcome.invalid,
      _ => VerifyOutcome.later,
    };
  }

  Future<VerifyOutcome> _verify(PurchaseReceipt receipt) async {
    if (!_hasSession()) return VerifyOutcome.later; // a 401 would only churn the session
    try {
      return classify(await _api.verify(receipt));
    } on Object catch (e) {
      debugPrint('iap: verify threw: $e');
      return VerifyOutcome.later;
    }
  }

  Future<void> _enqueue(PendingVerification entry) async {
    final queue = await _pending.load();
    await _pending.save([for (final e in queue) if (e.key != entry.key) e, entry]);
  }

  Future<void> _dequeue(String key) async {
    final queue = await _pending.load();
    if (queue.any((e) => e.key == key)) await _pending.save([for (final e in queue) if (e.key != key) e]);
  }

  /// Retries queued receipts the store didn't re-report (iOS finished, store
  /// offline). [skip]: keys already handled by this pass.
  Future<void> _retryPending({Set<String> skip = const {}}) async {
    for (final entry in await _pending.load()) {
      if (skip.contains(entry.key)) continue;
      final outcome = await _verify(entry.receipt);
      switch (outcome) {
        case VerifyOutcome.verified:
          await _entitlements.markVerified(at: _clock());
          await _dequeue(entry.key);
        case VerifyOutcome.later:
          await _enqueue(entry.copyWith(attempts: entry.attempts + 1));
        case VerifyOutcome.refunded:
        case VerifyOutcome.invalid:
          final latest = await _entitlements.read();
          if (outcome == VerifyOutcome.refunded || !latest.isVerified) {
            await _entitlements.revokeRemoveAds(source: 'server');
          }
          await _dequeue(entry.key);
      }
    }
  }

  // ---- restore / reconcile ----

  /// Runs every owned remove-ads purchase through [_fulfil]. Returns the keys seen.
  Future<Set<String>> _restoreOwned({required bool interactive}) async {
    final seen = <String>{};
    if (!_connected) return seen;
    final owned = await _store.ownedPurchases().timeout(storeTimeout);
    for (final p in owned) {
      if (p.productId != _productId || p.state != StorePurchaseState.purchased) continue;
      seen.add(p.identity);
      await _fulfil(p, interactive: false, restoring: interactive);
    }
    return seen;
  }

  @override
  Future<RestoreOutcome> restore() async {
    if (_purchasing) return RestoreOutcome.failed;
    if (!_connected || _price == null) await _loadStore();
    if (!_connected) {
      final owned = (await _entitlements.read()).removeAds;
      _log(AnalyticsEvents.iapRestore, {'result': owned ? 'restored' : 'unavailable'});
      return owned ? RestoreOutcome.restored : RestoreOutcome.unavailable;
    }
    try {
      await _store.syncWithStore().timeout(const Duration(seconds: 60));
    } on Object catch (e) {
      // A failed sync still leaves the store's local view to read.
      debugPrint('iap: store sync failed: $e');
    }
    try {
      final seen = await _restoreOwned(interactive: true);
      // Nothing on this store account: the backend may know the account
      // bought it elsewhere (e.g. on the other platform).
      if (seen.isEmpty && _hasSession()) {
        final r = await _api.restore(_store.platform, const []);
        if (r.isSuccess && r.value!) await _entitlements.mergeServer(removeAds: true, at: _clock());
      }
      final owned = (await _entitlements.read()).removeAds;
      _log(AnalyticsEvents.iapRestore, {'result': owned ? 'restored' : 'nothing'});
      _emit(_idle(owned: owned, restored: true));
      return owned ? RestoreOutcome.restored : RestoreOutcome.nothingToRestore;
    } on Object catch (e) {
      debugPrint('iap: restore failed: $e');
      _log(AnalyticsEvents.iapRestore, {'result': 'failed'});
      _log(AnalyticsEvents.iapError, {'code': 'restore_failed'});
      _emit(await _idleNow());
      return RestoreOutcome.failed;
    }
  }

  @override
  Future<void> reconcile() async {
    if (_disposed) return;
    if (_purchasing) {
      // Backing out of the sheet sometimes emits nothing. Give a real event
      // a moment to land, then drop the spinner.
      _resumeWatchdog?.cancel();
      _resumeWatchdog = Timer(resumeCancelGrace, () async {
        if (!_purchasing) return;
        _purchasing = false;
        _emit(await _idleNow());
      });
    }
    if (_reconciling) return;
    _reconciling = true;
    try {
      if (!_connected || _price == null) await _loadStore();
      var seen = <String>{};
      try {
        seen = await _restoreOwned(interactive: false);
      } on Object catch (e) {
        debugPrint('iap: reading owned purchases failed: $e');
      }
      await _retryPending(skip: seen);
      // A "Verifying…" left over from a purchase that died mid-flight.
      if (_status is StoreVerifying && _fulfilling.isEmpty) _emit(await _idleNow());
    } finally {
      _reconciling = false;
    }
  }

  @override
  Future<void> onSessionChanged(String? backendUserId) async {
    if (backendUserId == null || _disposed) return;
    if (backendUserId != _lastUserId) {
      _lastUserId = backendUserId;
      final r = await _api.entitlements();
      if (r.isSuccess) await _entitlements.mergeServer(removeAds: r.value!, at: _clock());
    }
    await reconcile();
  }
}
