import 'api_client.dart';
import 'api_result.dart';

/// One store purchase as the backend needs to see it. Android sends the Play
/// purchase token; iOS sends the StoreKit 2 transaction id and its signed
/// transaction (JWS). Field names are the wire names, and also the keys of
/// the persisted verify-later queue.
class PurchaseReceipt {
  const PurchaseReceipt({
    required this.platform,
    required this.productId,
    this.purchaseToken,
    this.transactionId,
    this.signedTransaction,
  });

  factory PurchaseReceipt.fromJson(Map<String, dynamic> j) => PurchaseReceipt(
        platform: j['platform'] as String,
        productId: j['product_id'] as String,
        purchaseToken: j['purchase_token'] as String?,
        transactionId: j['transaction_id'] as String?,
        signedTransaction: j['signed_transaction'] as String?,
      );

  /// `android` or `ios`.
  final String platform;
  final String productId;

  /// Android only.
  final String? purchaseToken;

  /// iOS only.
  final String? transactionId;

  /// iOS only: the JWS the backend verifies against Apple's certificates.
  final String? signedTransaction;

  /// Stable key for de-duplicating the same purchase across replays.
  String get key => purchaseToken ?? transactionId ?? signedTransaction ?? productId;

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'product_id': productId,
        'purchase_token': purchaseToken,
        'transaction_id': transactionId,
        'signed_transaction': signedTransaction,
      };
}

/// The backend's verdict on one receipt.
enum ReceiptState { verified, pending, refunded, invalid }

class VerifyResponse {
  const VerifyResponse({required this.valid, required this.state, this.removeAds});

  factory VerifyResponse.fromJson(Map<String, dynamic> j) {
    final ent = j['entitlements'];
    return VerifyResponse(
      valid: j['valid'] as bool? ?? false,
      state: ReceiptState.values.asNameMap()[j['state'] as String? ?? ''] ??
          ((j['valid'] as bool? ?? false) ? ReceiptState.verified : ReceiptState.invalid),
      removeAds: ent is Map ? ent['remove_ads'] as bool? : null,
    );
  }

  final bool valid;
  final ReceiptState state;

  /// The account's remove-ads entitlement after this verify, when sent.
  final bool? removeAds;
}

/// `/purchases/*` (backend contract in docs/IAP.md). Every call returns an
/// [ApiResult]; the purchase service decides what a failure means (a 404
/// while the backend lacks the endpoint is "verify later", never a refusal).
class PurchasesApi {
  PurchasesApi(this._client);

  final ApiClient _client;

  Future<ApiResult<VerifyResponse>> verify(PurchaseReceipt receipt) async =>
      _parse(await _client.post('/purchases/verify', body: receipt.toJson()), VerifyResponse.fromJson);

  /// Remove-ads entitlement after the server re-checked [receipts].
  Future<ApiResult<bool>> restore(String platform, List<PurchaseReceipt> receipts) async => _parse(
        await _client.post('/purchases/restore', body: {
          'platform': platform,
          'purchases': [for (final r in receipts) r.toJson()],
        }),
        _removeAds,
      );

  /// The signed-in account's entitlements (e.g. after signing in on a new device).
  Future<ApiResult<bool>> entitlements() async => _parse(await _client.get('/purchases/entitlements'), _removeAds);

  static bool _removeAds(Map<String, dynamic> j) =>
      (j['entitlements'] as Map<String, dynamic>)['remove_ads'] as bool;

  static ApiResult<T> _parse<T>(ApiResult<Map<String, dynamic>> raw, T Function(Map<String, dynamic>) parse) {
    if (!raw.isSuccess) return ApiResult.failed(raw.failure!, statusCode: raw.statusCode, message: raw.message);
    try {
      return ApiResult.success(parse(raw.value!), statusCode: raw.statusCode);
    } on Object {
      return ApiResult.failed(ApiFailure.badResponse, statusCode: raw.statusCode);
    }
  }
}
