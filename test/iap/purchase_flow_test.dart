import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/api/api_result.dart';
import 'package:jadewell_flutter_app/data/api/install_identity.dart';
import 'package:jadewell_flutter_app/data/api/purchases_api.dart';
import 'package:jadewell_flutter_app/data/repositories/entitlement_repository.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_service.dart';
import 'package:jadewell_flutter_app/platform/iap/pending_verifications.dart';
import 'package:jadewell_flutter_app/platform/iap/purchase_service.dart';
import 'package:jadewell_flutter_app/platform/iap/purchase_service_impl.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InstallIdentity identity;
  setUpAll(() async => identity = await testIdentity());

  final t0 = DateTime.utc(2026, 11, 16, 9);
  late DateTime now;
  late FakeStore store;
  late FakeBackend backend;
  late MemoryEntitlementRepository entitlements;
  late MemoryPendingVerificationStore pending;
  late RecordingAnalytics analytics;
  late bool hasSession;
  late List<StoreStatus> statuses;

  PurchaseServiceImpl build({String platform = 'android'}) {
    store = FakeStore(platform: platform);
    final service = PurchaseServiceImpl(
      store: store,
      entitlements: entitlements,
      api: purchasesApi(backend, identity),
      pending: pending,
      analytics: analytics,
      hasSession: () => hasSession,
      clock: () => now,
      resumeCancelGrace: const Duration(milliseconds: 20),
    );
    service.status.listen(statuses.add);
    addTearDown(service.dispose);
    return service;
  }

  setUp(() {
    now = t0;
    backend = FakeBackend();
    entitlements = MemoryEntitlementRepository();
    pending = MemoryPendingVerificationStore();
    analytics = RecordingAnalytics();
    hasSession = true;
    statuses = [];
  });

  Future<void> settle() => pumpEventQueue(times: 50);

  group('store availability', () {
    test('ready with the localized price from the store', () async {
      final s = build();
      store.price = '1,99 €';
      await s.init();
      expect(s.current, isA<StoreReady>().having((r) => r.price, 'price', '1,99 €'));
    });

    test('product not in the store yet → productMissing, buying does nothing', () async {
      final s = build();
      store.price = null;
      await s.init();
      expect(s.current, isA<StoreProductMissing>());
      await s.buyRemoveAds();
      expect(store.requested, isEmpty);
      expect(analytics.names, isNot(contains(AnalyticsEvents.iapStart)));
    });

    test('no billing → unavailable; a connect that throws is unavailable too', () async {
      var s = build();
      store.connects = false;
      await s.init();
      expect(s.current, isA<StoreUnavailable>());

      s = build();
      store.connectError = Exception('billing service unavailable');
      await s.init();
      expect(s.current, isA<StoreUnavailable>());
      expect(await s.restore(), RestoreOutcome.unavailable);
    });

    test('a product created later is picked up on resume', () async {
      final s = build();
      store.price = null;
      await s.init();
      expect(s.current, isA<StoreProductMissing>());
      store.price = r'$1.99';
      await s.reconcile();
      expect(s.current, isA<StoreReady>());
    });
  });

  group('purchase', () {
    test('success: purchasing → verifying → purchased; verified, then finished', () async {
      final s = build();
      backend.verifyReturns('verified');
      await s.init();
      await s.buyRemoveAds();
      expect(s.current, isA<StorePurchasing>());

      store.emit(androidPurchase(at: t0));
      await settle();

      expect(statuses.whereType<StoreVerifying>(), isNotEmpty);
      expect(s.current, isA<StorePurchased>().having((p) => p.restored, 'restored', false));
      final e = await entitlements.read();
      expect(e.removeAds, isTrue);
      expect(e.verifiedAt, now);
      expect(store.finished, ['tok-1']);
      expect(pending.entries, isEmpty);
      expect(backend.lastBody('/purchases/verify'), {
        'platform': 'android',
        'product_id': 'com.pranta.jadewell.remove_ads',
        'purchase_token': 'tok-1',
        'transaction_id': null,
        'signed_transaction': null,
      });
      expect(analytics.names, containsAllInOrder([AnalyticsEvents.iapStart, AnalyticsEvents.iapSuccess]));
    });

    test('iOS sends the transaction id and signed transaction', () async {
      final s = build(platform: 'ios');
      backend.verifyReturns('verified');
      await s.init();
      await s.buyRemoveAds();
      store.emit(iosPurchase());
      await settle();
      expect(backend.lastBody('/purchases/verify'), {
        'platform': 'ios',
        'product_id': 'com.pranta.jadewell.remove_ads',
        'purchase_token': null,
        'transaction_id': '2000001',
        'signed_transaction': 'jws.2000001',
      });
      expect(store.finished, ['2000001']);
    });

    test('404 (backend not deployed): granted locally, verify later, acknowledged by the 2-day deadline', () async {
      final s = build(); // no /purchases/verify route → 404
      await s.init();
      await s.buyRemoveAds();
      final purchase = androidPurchase(at: t0);
      store.emit(purchase);
      await settle();

      expect(s.current, isA<StorePurchased>());
      expect((await entitlements.read()).removeAds, isTrue);
      expect((await entitlements.read()).isVerified, isFalse);
      expect(store.finished, isEmpty, reason: 'not acknowledged before verification');
      expect(pending.entries.single.key, 'tok-1');
      expect(pending.entries.single.purchasedAt, t0);

      // A day later, still 404: still unacknowledged, still granted.
      store.owned = [purchase];
      now = t0.add(const Duration(days: 1));
      await s.reconcile();
      expect(store.finished, isEmpty);
      expect((await entitlements.read()).removeAds, isTrue);

      // Two days after the purchase: acknowledge so Play doesn't refund it.
      now = t0.add(const Duration(days: 2, minutes: 1));
      await s.reconcile();
      expect(store.finished, ['tok-1']);
      expect(pending.entries.single.acknowledged, isTrue);
      expect(pending.entries.single.attempts, greaterThanOrEqualTo(3));

      // The backend ships: next resume verifies and clears the queue.
      backend.verifyReturns('verified');
      store.owned = [androidPurchase(at: t0, acknowledged: true)];
      await s.reconcile();
      expect((await entitlements.read()).isVerified, isTrue);
      expect(pending.entries, isEmpty);
      expect(store.finished, ['tok-1'], reason: 'already acknowledged, not again');
    });

    test('offline / no session counts as later, without a request', () async {
      final s = build();
      hasSession = false;
      await s.init();
      await s.buyRemoveAds();
      store.emit(androidPurchase(at: t0));
      await settle();
      expect(backend.count('/purchases/verify'), 0);
      expect((await entitlements.read()).removeAds, isTrue);
      expect(pending.entries, hasLength(1));

      // Session comes online: the queue drains.
      hasSession = true;
      backend.verifyReturns('verified');
      backend.routes['/purchases/entitlements'] = (200, {'entitlements': {'remove_ads': false}});
      await s.onSessionChanged('user-1');
      expect(pending.entries, isEmpty);
      expect((await entitlements.read()).isVerified, isTrue);
    });

    test('pending payment: shown, nothing granted or finished until PURCHASED', () async {
      final s = build();
      backend.verifyReturns('verified');
      await s.init();
      await s.buyRemoveAds();
      store.emit(androidPurchase(state: StorePurchaseState.pending));
      await settle();

      expect(s.current, isA<StorePending>());
      expect((await entitlements.read()).removeAds, isFalse);
      expect(store.finished, isEmpty);
      expect(analytics.names, contains(AnalyticsEvents.iapPending));

      store.emit(androidPurchase());
      await settle();
      expect((await entitlements.read()).removeAds, isTrue);
      expect(s.current, isA<StorePurchased>().having((p) => p.restored, 'restored', false));
    });

    test('cancel is silent: back to ready, nothing granted', () async {
      final s = build();
      await s.init();
      store.onRequest = (_) => throw const StoreFailure(StoreErrorKind.cancelled, code: 'user_cancelled');
      await s.buyRemoveAds();
      await settle();
      expect(s.current, isA<StoreReady>());
      expect(statuses.whereType<StoreError>(), isEmpty);
      expect((await entitlements.read()).removeAds, isFalse);
      expect(analytics.names, contains(AnalyticsEvents.iapCancel));

      // The same cancel arriving on the error stream too is ignored.
      store.fail(const StoreFailure(StoreErrorKind.cancelled));
      await settle();
      expect(analytics.names.where((n) => n == AnalyticsEvents.iapCancel), hasLength(1));
    });

    test('a store error shows error with retry and logs the code only', () async {
      final s = build();
      await s.init();
      await s.buyRemoveAds();
      store.fail(const StoreFailure(StoreErrorKind.other, code: 'network_error'));
      await settle();
      expect(s.current, isA<StoreError>().having((e) => e.price, 'price', r'$1.99'));
      expect(analytics.events.last.$1, AnalyticsEvents.iapError);
      expect(analytics.events.last.$2, {'code': 'network_error'});
    });

    test('already owned is treated as a restore', () async {
      final s = build();
      backend.verifyReturns('verified');
      await s.init();
      store.owned = [androidPurchase(acknowledged: true)];
      store.onRequest = (_) => throw const StoreFailure(StoreErrorKind.alreadyOwned, code: 'already_owned');
      await s.buyRemoveAds();
      await settle();
      expect((await entitlements.read()).removeAds, isTrue);
      expect(s.current, isA<StorePurchased>().having((p) => p.restored, 'restored', true));
      expect(statuses.whereType<StoreError>(), isEmpty);
    });

    test('invalid receipt: revoked, left unacknowledged on Android (Play refunds it)', () async {
      final s = build();
      backend.routes['/purchases/verify'] = (422, {'error': 'invalid purchase token'});
      await s.init();
      await s.buyRemoveAds();
      store.emit(androidPurchase());
      await settle();
      expect((await entitlements.read()).removeAds, isFalse);
      expect(store.finished, isEmpty);
      expect(pending.entries, isEmpty);
      expect(s.current, isA<StoreError>().having((e) => e.code, 'code', 'invalid'));
    });

    test('invalid receipt on iOS is finished so StoreKit stops replaying it', () async {
      final s = build(platform: 'ios');
      backend.verifyReturns('invalid', removeAds: false);
      await s.init();
      await s.buyRemoveAds();
      store.emit(iosPurchase());
      await settle();
      expect((await entitlements.read()).removeAds, isFalse);
      expect(store.finished, ['2000001']);
    });

    test('refunded revokes even a verified entitlement', () async {
      final s = build();
      await entitlements.markVerified(at: t0);
      await pending.save([PendingVerification(receipt: const PurchaseReceipt(platform: 'android', productId: ProductIds.removeAds, purchaseToken: 'tok-1'), purchasedAt: t0)]);
      backend.verifyReturns('refunded', removeAds: false);
      await s.init();
      expect((await entitlements.read()).removeAds, isFalse);
      expect(pending.entries, isEmpty);
    });

    test('resume with no store event clears a stuck purchasing spinner', () async {
      final s = build();
      await s.init();
      await s.buyRemoveAds();
      expect(s.current, isA<StorePurchasing>());
      await s.reconcile();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(s.current, isA<StoreReady>());
    });
  });

  group('restore and sign-in', () {
    test('restore with nothing owned asks the backend, then says nothing to restore', () async {
      final s = build();
      backend.routes['/purchases/restore'] = (200, {'entitlements': {'remove_ads': false}});
      await s.init();
      expect(await s.restore(), RestoreOutcome.nothingToRestore);
      expect(store.syncs, 1);
      expect(backend.lastBody('/purchases/restore'), {'platform': 'android', 'purchases': <Object>[]});
      expect(analytics.names, contains(AnalyticsEvents.iapRestore));
    });

    test('restore finds the store purchase, verifies and finishes it', () async {
      final s = build();
      backend.verifyReturns('verified');
      await s.init();
      store.owned = [androidPurchase()];
      expect(await s.restore(), RestoreOutcome.restored);
      expect((await entitlements.read()).isVerified, isTrue);
      expect((await entitlements.read()).source, 'server');
      expect(store.finished, ['tok-1']);
      expect(s.current, isA<StorePurchased>().having((p) => p.restored, 'restored', true));
    });

    test('restore on a new platform comes from the account', () async {
      final s = build(platform: 'ios');
      backend.routes['/purchases/restore'] = (200, {'entitlements': {'remove_ads': true}});
      await s.init();
      expect(await s.restore(), RestoreOutcome.restored);
    });

    test('signing in merges the account entitlements; 404 changes nothing', () async {
      final s = build();
      await s.init();
      await s.onSessionChanged('user-1'); // 404
      expect((await entitlements.read()).removeAds, isFalse);

      backend.routes['/purchases/entitlements'] = (200, {'entitlements': {'remove_ads': true}});
      await s.onSessionChanged('user-2');
      expect((await entitlements.read()).removeAds, isTrue);
      expect((await entitlements.read()).isVerified, isTrue);

      // Same user again: no second fetch.
      final before = backend.count('/purchases/entitlements');
      await s.onSessionChanged('user-2');
      expect(backend.count('/purchases/entitlements'), before);
    });

    test('a replayed, verified, acknowledged purchase costs no request', () async {
      final s = build();
      await entitlements.markVerified(at: t0);
      await s.init();
      store.owned = [androidPurchase(acknowledged: true)];
      await s.reconcile();
      expect(backend.count('/purchases/verify'), 0);
      expect(store.finished, isEmpty);
    });
  });

  group('classify', () {
    ApiResult<VerifyResponse> failed(ApiFailure f, int code) => ApiResult.failed(f, statusCode: code);

    test('404 and transient failures are later, 4xx refusals invalid', () {
      expect(PurchaseServiceImpl.classify(failed(ApiFailure.validation, 404)), VerifyOutcome.later);
      expect(PurchaseServiceImpl.classify(failed(ApiFailure.serverUnavailable, 503)), VerifyOutcome.later);
      expect(PurchaseServiceImpl.classify(failed(ApiFailure.offlineOrTransport, 0)), VerifyOutcome.later);
      expect(PurchaseServiceImpl.classify(failed(ApiFailure.unauthorized, 401)), VerifyOutcome.later);
      expect(PurchaseServiceImpl.classify(failed(ApiFailure.badResponse, 200)), VerifyOutcome.later);
      expect(PurchaseServiceImpl.classify(failed(ApiFailure.validation, 422)), VerifyOutcome.invalid);
      expect(PurchaseServiceImpl.classify(failed(ApiFailure.forbidden, 403)), VerifyOutcome.invalid);
    });

    test('server states', () {
      ApiResult<VerifyResponse> ok(String state) =>
          ApiResult.success(VerifyResponse.fromJson({'valid': state == 'verified', 'state': state}));
      expect(PurchaseServiceImpl.classify(ok('verified')), VerifyOutcome.verified);
      expect(PurchaseServiceImpl.classify(ok('pending')), VerifyOutcome.later);
      expect(PurchaseServiceImpl.classify(ok('refunded')), VerifyOutcome.refunded);
      expect(PurchaseServiceImpl.classify(ok('invalid')), VerifyOutcome.invalid);
    });
  });
}
