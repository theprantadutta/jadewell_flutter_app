import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jadewell_flutter_app/data/api/api_client.dart';
import 'package:jadewell_flutter_app/data/api/install_identity.dart';
import 'package:jadewell_flutter_app/data/api/purchases_api.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_service.dart';
import 'package:jadewell_flutter_app/platform/iap/purchase_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A scriptable store.
class FakeStore implements StoreAdapter {
  FakeStore({this.platform = 'android', this.connects = true, this.price = r'$1.99'});

  @override
  final String platform;
  bool connects;
  Object? connectError;
  String? price;
  List<StorePurchase> owned = [];

  /// What requestPurchase does (default: nothing; the test emits events).
  FutureOr<void> Function(String productId)? onRequest;

  final requested = <String>[];
  final finished = <String>[];
  int syncs = 0;
  int connectCalls = 0;

  final _purchases = StreamController<StorePurchase>.broadcast();
  final _failures = StreamController<StoreFailure>.broadcast();

  void emit(StorePurchase p) => _purchases.add(p);
  void fail(StoreFailure f) => _failures.add(f);

  @override
  Stream<StorePurchase> get purchases => _purchases.stream;

  @override
  Stream<StoreFailure> get failures => _failures.stream;

  @override
  Future<bool> connect() async {
    connectCalls++;
    if (connectError != null) throw connectError!;
    return connects;
  }

  @override
  Future<String?> fetchPrice(String productId) async => price;

  @override
  Future<void> requestPurchase(String productId, {String? accountId}) async {
    requested.add(productId);
    await onRequest?.call(productId);
  }

  @override
  Future<void> finish(StorePurchase purchase) async => finished.add(purchase.identity);

  @override
  Future<List<StorePurchase>> ownedPurchases() async => List.of(owned);

  @override
  Future<void> syncWithStore() async => syncs++;

  @override
  Future<void> disconnect() async {}
}

StorePurchase androidPurchase({
  String token = 'tok-1',
  StorePurchaseState state = StorePurchaseState.purchased,
  bool acknowledged = false,
  DateTime? at,
}) =>
    StorePurchase(
      productId: ProductIds.removeAds,
      state: state,
      platform: 'android',
      purchaseToken: token,
      transactionId: 'GPA.1',
      acknowledged: acknowledged,
      purchasedAt: at,
    );

StorePurchase iosPurchase({String tx = '2000001', DateTime? at}) => StorePurchase(
      productId: ProductIds.removeAds,
      state: StorePurchaseState.purchased,
      platform: 'ios',
      transactionId: tx,
      signedTransaction: 'jws.$tx',
      purchasedAt: at,
    );

/// The backend: path → (status, body). Records every request.
class FakeBackend {
  final Map<String, (int, Object?)> routes = {};
  final List<(String, String, Map<String, dynamic>?)> requests = [];

  int count(String path) => requests.where((r) => r.$2 == path).length;
  Map<String, dynamic>? lastBody(String path) => requests.lastWhere((r) => r.$2 == path).$3;

  http.Client get client => MockClient((req) async {
        final path = req.url.path.replaceFirst('/api/v1', '');
        requests.add((req.method, path, req.body.isEmpty ? null : jsonDecode(req.body) as Map<String, dynamic>));
        final (status, body) = routes[path] ?? (404, {'error': 'not found'});
        return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
      });

  void verifyReturns(String state, {bool removeAds = true, int status = 200}) => routes['/purchases/verify'] = (
        status,
        {
          'valid': state == 'verified',
          'product_id': ProductIds.removeAds,
          'state': state,
          'entitlements': {'remove_ads': removeAds},
        }
      );
}

Future<InstallIdentity> testIdentity() async {
  SharedPreferences.setMockInitialValues({});
  PackageInfo.setMockInitialValues(
    appName: 'Jadewell',
    packageName: 'com.pranta.jadewell',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  return InstallIdentity.load();
}

PurchasesApi purchasesApi(FakeBackend backend, InstallIdentity identity) => PurchasesApi(
      ApiClient(
        baseUrl: 'https://api.test/api/v1',
        identity: identity,
        tokenProvider: () => 'jwt',
        httpClient: backend.client,
      ),
    );

class RecordingAnalytics implements AnalyticsService {
  final events = <(String, Map<String, Object>)>[];
  List<String> get names => [for (final e in events) e.$1];

  @override
  Future<void> log(String event, [Map<String, Object> params = const {}]) async => events.add((event, params));

  @override
  Future<void> screen(String name) async {}
}

/// A [PurchaseService] whose status the test drives.
class FakePurchaseService implements PurchaseService {
  FakePurchaseService([this._current = const StoreReady(r'$1.99')]);

  StoreStatus _current;
  final _changes = StreamController<StoreStatus>.broadcast();
  RestoreOutcome restoreResult = RestoreOutcome.nothingToRestore;
  int buys = 0;
  int restores = 0;

  void set(StoreStatus s) {
    _current = s;
    _changes.add(s);
  }

  @override
  StoreStatus get current => _current;

  @override
  Stream<StoreStatus> get status => Stream.multi((c) {
        c.add(_current);
        final sub = _changes.stream.listen(c.add);
        c.onCancel = sub.cancel;
      });

  @override
  Future<void> init() async {}

  @override
  Future<void> buyRemoveAds() async => buys++;

  @override
  Future<RestoreOutcome> restore() async {
    restores++;
    return restoreResult;
  }

  @override
  Future<void> reconcile() async {}

  @override
  Future<void> onSessionChanged(String? backendUserId) async {}

  @override
  Future<void> dispose() async {}
}
