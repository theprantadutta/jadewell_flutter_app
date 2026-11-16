import 'dart:async';

/// Store product ids (both stores use the same id).
abstract final class ProductIds {
  static const prefix = 'com.pranta.jadewell.';
  static const removeAds = '${prefix}remove_ads';

  static const all = [removeAds];

  /// `com.pranta.jadewell.remove_ads` → `remove_ads` (analytics, logs).
  static String stripPrefix(String id) => id.startsWith(prefix) ? id.substring(prefix.length) : id;

  static String withPrefix(String id) => id.startsWith(prefix) ? id : '$prefix$id';
}

/// What the Store screen shows. Emitted by [PurchaseService.status].
sealed class StoreStatus {
  const StoreStatus();

  /// The localized price once the store returned the product.
  String? get price => null;
}

/// Billing is not available here (no Play Store, sideloaded build, simulator
/// without StoreKit config, or the connection failed). "Not available yet".
class StoreUnavailable extends StoreStatus {
  const StoreUnavailable();
}

/// The store answered but does not know the product (not created in the
/// console yet). Shown exactly like [StoreUnavailable].
class StoreProductMissing extends StoreStatus {
  const StoreProductMissing();
}

/// Connecting / fetching the product.
class StoreLoading extends StoreStatus {
  const StoreLoading();
}

/// Ready to buy.
class StoreReady extends StoreStatus {
  const StoreReady(this.price);
  @override
  final String price;
}

/// The store's purchase sheet is up.
class StorePurchasing extends StoreStatus {
  const StorePurchasing(this.price);
  @override
  final String? price;
}

/// The store confirmed payment; our backend is checking the receipt.
class StoreVerifying extends StoreStatus {
  const StoreVerifying(this.price);
  @override
  final String? price;
}

/// The store accepted the order but the payment has not cleared (cash,
/// carrier billing, parental approval). Nothing is granted until it does.
class StorePending extends StoreStatus {
  const StorePending(this.price);
  @override
  final String? price;
}

/// Owned. [restored] when it came from Restore rather than a new purchase.
class StorePurchased extends StoreStatus {
  const StorePurchased({this.restored = false, this.price});
  final bool restored;
  @override
  final String? price;
}

/// A purchase or restore failed. [code] is a short machine code (analytics).
class StoreError extends StoreStatus {
  const StoreError(this.code, {this.price});
  final String code;
  @override
  final String? price;
}

/// What a restore found.
enum RestoreOutcome { restored, nothingToRestore, unavailable, failed }

/// In-app purchases (Remove ads). Implementations: [UnavailablePurchaseService]
/// (default, tests) and `PurchaseServiceImpl` (flutter_inapp_purchase).
abstract interface class PurchaseService {
  /// Connects to the store and fetches the product. Never throws; never
  /// blocks start-up (call it unawaited).
  Future<void> init();

  /// The latest status; replays the current one to new listeners.
  Stream<StoreStatus> get status;
  StoreStatus get current;

  /// Opens the store sheet. The outcome arrives on [status].
  Future<void> buyRemoveAds();

  /// Restore purchases (iOS requires a visible button; Android too).
  Future<RestoreOutcome> restore();

  /// App resumed: re-read the store's owned purchases, finish anything left
  /// unfinished, retry pending verifications, clear a stuck "Verifying…".
  Future<void> reconcile();

  /// The backend session changed user (or came online): fetch the account's
  /// entitlements and merge them, then retry pending verifications.
  Future<void> onSessionChanged(String? backendUserId);

  Future<void> dispose();
}

/// No store at all: the Store screen shows "Not available yet".
class UnavailablePurchaseService implements PurchaseService {
  const UnavailablePurchaseService();

  @override
  Future<void> init() async {}

  @override
  Stream<StoreStatus> get status => Stream.value(const StoreUnavailable());

  @override
  StoreStatus get current => const StoreUnavailable();

  @override
  Future<void> buyRemoveAds() async {}

  @override
  Future<RestoreOutcome> restore() async => RestoreOutcome.unavailable;

  @override
  Future<void> reconcile() async {}

  @override
  Future<void> onSessionChanged(String? backendUserId) async {}

  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// Store adapter: the seam between the purchase logic and the billing plugin,
// so the whole flow is testable with a fake store.
// ---------------------------------------------------------------------------

enum StorePurchaseState { pending, purchased, unknown }

/// A purchase as the store reported it, plugin-neutral.
class StorePurchase {
  const StorePurchase({
    required this.productId,
    required this.state,
    required this.platform,
    this.purchaseToken,
    this.transactionId,
    this.signedTransaction,
    this.acknowledged = false,
    this.purchasedAt,
    this.native,
  });

  final String productId;
  final StorePurchaseState state;

  /// `android` or `ios`.
  final String platform;

  /// Android purchase token.
  final String? purchaseToken;

  /// iOS transaction id (Android: the order id, informational only).
  final String? transactionId;

  /// iOS signed transaction (JWS).
  final String? signedTransaction;

  /// Android: already acknowledged with Play.
  final bool acknowledged;

  /// When the store says it was bought (Play's 3-day acknowledge window
  /// starts here).
  final DateTime? purchasedAt;

  /// The plugin's own object, handed back to [StoreAdapter.finish].
  final Object? native;

  /// De-duplication key across replays.
  String get identity => purchaseToken ?? transactionId ?? signedTransaction ?? productId;
}

enum StoreErrorKind { cancelled, alreadyOwned, pending, unavailable, other }

class StoreFailure {
  const StoreFailure(this.kind, {this.code = 'unknown', this.productId});
  final StoreErrorKind kind;

  /// The store's error code name (analytics only; never shown).
  final String code;
  final String? productId;
}

abstract interface class StoreAdapter {
  /// `android` or `ios`.
  String get platform;

  /// Purchase updates (new purchases, cleared pending payments, replays).
  Stream<StorePurchase> get purchases;
  Stream<StoreFailure> get failures;

  /// True when billing is available.
  Future<bool> connect();

  /// The localized price, or null when the store doesn't know [productId].
  Future<String?> fetchPrice(String productId);

  /// Launches the store sheet. Throws [StoreFailure] on a synchronous refusal.
  Future<void> requestPurchase(String productId, {String? accountId});

  /// Acknowledge (Android) / finish (iOS). Throws on failure.
  Future<void> finish(StorePurchase purchase);

  /// Everything the store says this account owns (incl. unfinished).
  Future<List<StorePurchase>> ownedPurchases();

  /// Asks the store to sync with its servers (iOS may prompt for sign-in).
  Future<void> syncWithStore();

  Future<void> disconnect();
}
