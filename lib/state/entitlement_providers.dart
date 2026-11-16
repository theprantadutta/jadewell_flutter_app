import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/purchases_api.dart';
import '../data/repositories/entitlement_repository.dart';
import '../platform/iap/purchase_service.dart';
import 'app_providers.dart';
import 'data_providers.dart';
import 'platform_providers.dart';
import 'session_controller.dart';

export '../data/repositories/entitlement_repository.dart' show Entitlement;

// ---- wiring (main.dart overrides the defaults) ----

/// In-memory by default (tests); main.dart points it at
/// [driftEntitlementRepositoryProvider].
final entitlementRepositoryProvider = Provider<EntitlementRepository>((ref) => MemoryEntitlementRepository());

final driftEntitlementRepositoryProvider =
    Provider<EntitlementRepository>((ref) => DriftEntitlementRepository(ref.watch(databaseProvider)));

final purchasesApiProvider = Provider<PurchasesApi>((ref) => PurchasesApi(ref.watch(apiClientProvider)));

/// No store by default ("Not available yet"); main.dart overrides it with
/// `PurchaseServiceImpl`.
final purchaseServiceProvider = Provider<PurchaseService>((ref) => const UnavailablePurchaseService());

// ---- read models ----

/// What the player owns, synchronously (`Entitlement.none` until the local
/// row has loaded, a few ms after start). The ad service follows
/// `removeAds` through [startPurchases]; anything else can `ref.watch` it.
final entitlementProvider = NotifierProvider<EntitlementController, Entitlement>(EntitlementController.new);

class EntitlementController extends Notifier<Entitlement> {
  @override
  Entitlement build() {
    final sub = ref.watch(entitlementRepositoryProvider).watch().listen((e) => state = e);
    ref.onDispose(sub.cancel);
    return Entitlement.none;
  }
}

/// The Store's status (price, purchasing, verifying, …).
final storeStatusProvider = StreamProvider<StoreStatus>((ref) => ref.watch(purchaseServiceProvider).status);

/// The localized Remove ads price, or null while the store has none to sell.
final removeAdsPriceProvider = Provider<String?>((ref) => ref.watch(storeStatusProvider).value?.price);

// ---- start-up ----

/// Call once from main.dart after the container exists. Never blocks:
///
/// * connects to the store and reconciles owned purchases (background);
/// * reconciles again on every resume (pending payments that cleared,
///   unfinished transactions, a stuck "Verifying…");
/// * whenever the backend session is online for a (new) user, merges that
///   account's server entitlements and retries pending verifications;
/// * feeds `entitlementProvider.removeAds` into the ad service.
void startPurchases(ProviderContainer container) {
  final service = container.read(purchaseServiceProvider);
  unawaited(service.init());

  AppLifecycleListener(onResume: () => unawaited(service.reconcile()));

  container.listen<AsyncValue<BackendSession>>(sessionProvider, (_, next) {
    final s = next.value;
    if (s != null && s.isOnline) unawaited(service.onSessionChanged(s.user!.id));
  });

  container.listen<Entitlement>(
    entitlementProvider,
    (_, e) => container.read(adServiceProvider).setAdsRemoved(e.removeAds),
    fireImmediately: true,
  );
}
