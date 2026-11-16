import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/platform_providers.dart';

/// Product id of the one non-consumable (both stores).
const kRemoveAdsProductId = 'com.pranta.jadewell.remove_ads';

enum StoreOutcome { purchased, restored, nothingToRestore, cancelled, failed, comingSoon }

class StoreState {
  const StoreState({this.busy = false, required this.adsRemoved});

  /// A purchase or restore is in flight.
  final bool busy;
  final bool adsRemoved;

  StoreState copyWith({bool? busy, bool? adsRemoved}) =>
      StoreState(busy: busy ?? this.busy, adsRemoved: adsRemoved ?? this.adsRemoved);
}

final storeControllerProvider = NotifierProvider.autoDispose<StoreController, StoreState>(StoreController.new);

/// Remove-ads purchase flow. IAP arrives in Phase 8 (`PurchaseService`,
/// verify-then-finish, server verification); until then both actions
/// report [StoreOutcome.comingSoon].
class StoreController extends Notifier<StoreState> {
  @override
  StoreState build() => StoreState(adsRemoved: ref.watch(adServiceProvider).adsRemoved);

  // TODO(Phase 8): buy kRemoveAdsProductId via PurchaseService, verify with
  // POST purchases/verify, then finish the transaction and set adsRemoved.
  Future<StoreOutcome> purchaseRemoveAds() async {
    if (state.adsRemoved) return StoreOutcome.purchased;
    return StoreOutcome.comingSoon;
  }

  // TODO(Phase 8): restorePurchases() on the store, then POST purchases/restore.
  Future<StoreOutcome> restore() async {
    if (state.adsRemoved) return StoreOutcome.restored;
    return StoreOutcome.comingSoon;
  }
}
