import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_inapp_purchase/flutter_inapp_purchase.dart';

import 'purchase_service.dart';

/// [StoreAdapter] on flutter_inapp_purchase (OpenIAP): Play Billing on
/// Android, StoreKit 2 on iOS.
class OpenIapStoreAdapter implements StoreAdapter {
  OpenIapStoreAdapter() : _iap = FlutterInappPurchase.instance;

  final FlutterInappPurchase _iap;

  @override
  String get platform => Platform.isIOS ? 'ios' : 'android';

  @override
  Stream<StorePurchase> get purchases => _iap.purchaseUpdatedListener.map(_map);

  @override
  Stream<StoreFailure> get failures => _iap.purchaseErrorListener.map(_failure);

  @override
  Future<bool> connect() async {
    try {
      return await _iap.initConnection();
    } on PurchaseError {
      // Billing unavailable (no Play Store, unsupported device): not an error.
      return false;
    }
  }

  @override
  Future<String?> fetchPrice(String productId) async {
    final products = await _iap.fetchProducts<Product>(skus: [productId], type: ProductQueryType.InApp);
    for (final p in products) {
      if (p.id == productId && p.displayPrice.isNotEmpty) return p.displayPrice;
      debugPrint('iap: store returned an unusable product (id: ${p.id}, price: "${p.displayPrice}")');
    }
    return null;
  }

  @override
  Future<void> requestPurchase(String productId, {String? accountId}) async {
    try {
      await _iap.requestPurchase(
        RequestPurchaseProps.inApp((
          apple: RequestPurchaseIosProps(sku: productId, appAccountToken: _isUuid(accountId) ? accountId : null),
          google: RequestPurchaseAndroidProps(skus: [productId], obfuscatedAccountId: accountId),
        )),
      );
    } on PurchaseError catch (e) {
      throw _failure(e);
    }
  }

  @override
  Future<void> finish(StorePurchase purchase) async {
    final native = purchase.native;
    if (native is! Purchase) throw StateError('not a store purchase');
    await _iap.finishTransaction(purchase: native, isConsumable: false);
  }

  @override
  Future<List<StorePurchase>> ownedPurchases() async =>
      [for (final p in await _iap.getAvailablePurchases()) _map(p)];

  @override
  Future<void> syncWithStore() => _iap.restorePurchases();

  @override
  Future<void> disconnect() async {
    await _iap.endConnection();
  }

  static StorePurchase _map(Purchase p) {
    final state = switch (p.purchaseState) {
      PurchaseState.Purchased => StorePurchaseState.purchased,
      PurchaseState.Pending => StorePurchaseState.pending,
      PurchaseState.Unknown => StorePurchaseState.unknown,
    };
    final at = p.transactionDate > 0 ? DateTime.fromMillisecondsSinceEpoch(p.transactionDate.toInt()) : null;
    return switch (p) {
      PurchaseIOS() => StorePurchase(
          productId: p.productId,
          state: state,
          platform: 'ios',
          transactionId: p.transactionId,
          // OpenIAP puts the StoreKit 2 JWS on the unified purchaseToken.
          signedTransaction: p.purchaseToken,
          purchasedAt: at,
          native: p,
        ),
      PurchaseAndroid() => StorePurchase(
          productId: p.productId,
          state: state,
          platform: 'android',
          purchaseToken: p.purchaseToken,
          transactionId: p.transactionId,
          acknowledged: p.isAcknowledgedAndroid ?? false,
          purchasedAt: at,
          native: p,
        ),
    };
  }

  static StoreFailure _failure(PurchaseError e) {
    final kind = switch (e.code) {
      ErrorCode.UserCancelled => StoreErrorKind.cancelled,
      ErrorCode.AlreadyOwned => StoreErrorKind.alreadyOwned,
      ErrorCode.Pending || ErrorCode.DeferredPayment => StoreErrorKind.pending,
      ErrorCode.IapNotAvailable ||
      ErrorCode.BillingUnavailable ||
      ErrorCode.ServiceDisconnected ||
      ErrorCode.NotPrepared ||
      ErrorCode.InitConnection =>
        StoreErrorKind.unavailable,
      _ => StoreErrorKind.other,
    };
    return StoreFailure(kind, code: _snake(e.code?.name ?? 'unknown'), productId: e.productId);
  }

  /// `UserCancelled` → `user_cancelled` (analytics codes).
  static String _snake(String s) =>
      s.replaceAllMapped(RegExp(r'(?<=[a-z0-9])([A-Z])'), (m) => '_${m[1]}').toLowerCase();

  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  /// StoreKit silently drops an appAccountToken that is not a UUID.
  static bool _isUuid(String? v) => v != null && _uuid.hasMatch(v);
}
