import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/iap/purchase_service.dart';
import '../../../state/entitlement_providers.dart';

export '../../../platform/iap/purchase_service.dart' show RestoreOutcome;

/// What the Store screen shows.
enum StoreView {
  /// Connecting to the store / fetching the price.
  loading,

  /// No billing here, or the product doesn't exist in the store yet.
  notAvailable,
  ready,
  purchasing,
  verifying,

  /// Paid with a method that hasn't cleared (cash, carrier, approval).
  pending,
  purchased,

  /// The last purchase failed; Buy becomes "Try again".
  error,
}

class StoreState {
  const StoreState({required this.view, this.price, this.restoredOnly = false});

  final StoreView view;

  /// Localized price from the store (null when there is nothing to sell).
  final String? price;

  /// Purchased via Restore (no celebration).
  final bool restoredOnly;

  bool get adsRemoved => view == StoreView.purchased;
  bool get busy => view == StoreView.purchasing || view == StoreView.verifying || view == StoreView.loading;
}

final storeControllerProvider = NotifierProvider.autoDispose<StoreController, StoreState>(StoreController.new);

/// The Remove ads screen's view model: store status + local entitlement.
class StoreController extends Notifier<StoreState> {
  @override
  StoreState build() {
    final owned = ref.watch(entitlementProvider).removeAds;
    final status = ref.watch(storeStatusProvider).value ?? const StoreLoading();
    return derive(status, owned: owned);
  }

  /// Pure mapping (unit-tested): an in-flight purchase wins over the
  /// entitlement, the entitlement wins over everything else.
  static StoreState derive(StoreStatus status, {required bool owned}) {
    final price = status.price;
    switch (status) {
      case StorePurchasing():
        return StoreState(view: StoreView.purchasing, price: price);
      case StoreVerifying():
        return StoreState(view: StoreView.verifying, price: price);
      case StorePending() when !owned:
        return StoreState(view: StoreView.pending, price: price);
      default:
        break;
    }
    if (owned) {
      final restored = status is! StorePurchased || status.restored;
      return StoreState(view: StoreView.purchased, price: price, restoredOnly: restored);
    }
    return switch (status) {
      StoreLoading() => const StoreState(view: StoreView.loading),
      StoreUnavailable() || StoreProductMissing() => const StoreState(view: StoreView.notAvailable),
      StoreReady(:final price) => StoreState(view: StoreView.ready, price: price),
      StoreError(:final price) =>
        price == null ? const StoreState(view: StoreView.notAvailable) : StoreState(view: StoreView.error, price: price),
      // Purchased but no longer owned (revoked): back to selling if we can.
      _ => price == null ? const StoreState(view: StoreView.notAvailable) : StoreState(view: StoreView.ready, price: price),
    };
  }

  Future<void> purchaseRemoveAds() => ref.read(purchaseServiceProvider).buyRemoveAds();

  Future<RestoreOutcome> restore() => ref.read(purchaseServiceProvider).restore();
}
