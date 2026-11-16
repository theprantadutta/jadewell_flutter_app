import 'dart:async';

import '../db/app_database.dart';
import '../db/daos/entitlements_dao.dart';

/// What the player owns. The local row is the truth the app acts on: it is
/// granted the moment the store confirms a purchase, stamped [verifiedAt]
/// once our backend confirms it, and revoked only on a server verdict
/// (refund / invalid). Offline, the local value is trusted as is.
class Entitlement {
  const Entitlement({this.removeAds = false, this.source, this.verifiedAt});

  static const none = Entitlement();

  final bool removeAds;

  /// Who last wrote it: `play`, `app_store`, `restore`, `server`.
  final String? source;

  /// When the backend last confirmed it; null = store-confirmed only.
  final DateTime? verifiedAt;

  bool get isVerified => verifiedAt != null;

  @override
  bool operator ==(Object other) =>
      other is Entitlement && other.removeAds == removeAds && other.source == source && other.verifiedAt == verifiedAt;

  @override
  int get hashCode => Object.hash(removeAds, source, verifiedAt);

  @override
  String toString() => 'Entitlement(removeAds: $removeAds, source: $source, verifiedAt: $verifiedAt)';
}

abstract interface class EntitlementRepository {
  Stream<Entitlement> watch();
  Future<Entitlement> read();

  /// The store confirmed a purchase (or restore). Keeps an existing
  /// [Entitlement.verifiedAt].
  Future<void> grantRemoveAds({required String source});

  /// The backend confirmed it.
  Future<void> markVerified({required DateTime at, String source = 'server'});

  /// The backend reported a refund, or refused the receipt.
  Future<void> revokeRemoveAds({required String source});

  /// Merges an authoritative server answer (`GET purchases/entitlements`,
  /// `POST purchases/restore`). True → granted and verified. False → revoked
  /// only if the local grant was itself server-verified; a store-confirmed
  /// grant still waiting for verification is kept (it verifies later).
  Future<void> mergeServer({required bool removeAds, required DateTime at});
}

/// Shared merge rule for both implementations.
Future<void> _merge(EntitlementRepository repo, {required bool removeAds, required DateTime at}) async {
  if (removeAds) {
    await repo.markVerified(at: at);
    return;
  }
  final current = await repo.read();
  if (current.removeAds && current.isVerified) await repo.revokeRemoveAds(source: 'server');
}

/// Drift-backed (the `entitlements` table via [EntitlementsDao]).
class DriftEntitlementRepository implements EntitlementRepository {
  DriftEntitlementRepository(AppDatabase db) : _dao = db.entitlementsDao;

  final EntitlementsDao _dao;

  static Entitlement _fromRow(EntitlementsRow? r) =>
      r == null ? Entitlement.none : Entitlement(removeAds: r.removeAds, source: r.source, verifiedAt: r.verifiedAt);

  @override
  Stream<Entitlement> watch() => _dao.select(_dao.entitlementsTable).watchSingleOrNull().map(_fromRow).distinct();

  @override
  Future<Entitlement> read() async => _fromRow(await _dao.read());

  @override
  Future<void> grantRemoveAds({required String source}) async {
    final current = await read();
    await _dao.setRemoveAds(true, source: source, verifiedAt: current.removeAds ? current.verifiedAt : null);
  }

  @override
  Future<void> markVerified({required DateTime at, String source = 'server'}) =>
      _dao.setRemoveAds(true, source: source, verifiedAt: at);

  @override
  Future<void> revokeRemoveAds({required String source}) => _dao.setRemoveAds(false, source: source);

  @override
  Future<void> mergeServer({required bool removeAds, required DateTime at}) =>
      _merge(this, removeAds: removeAds, at: at);
}

/// In-memory (tests, previews).
class MemoryEntitlementRepository implements EntitlementRepository {
  MemoryEntitlementRepository([Entitlement initial = Entitlement.none]) : _value = initial;

  Entitlement _value;
  final _changes = StreamController<Entitlement>.broadcast();

  void _set(Entitlement e) {
    _value = e;
    _changes.add(e);
  }

  @override
  Stream<Entitlement> watch() async* {
    yield _value;
    yield* _changes.stream;
  }

  @override
  Future<Entitlement> read() async => _value;

  @override
  Future<void> grantRemoveAds({required String source}) async =>
      _set(Entitlement(removeAds: true, source: source, verifiedAt: _value.removeAds ? _value.verifiedAt : null));

  @override
  Future<void> markVerified({required DateTime at, String source = 'server'}) async =>
      _set(Entitlement(removeAds: true, source: source, verifiedAt: at));

  @override
  Future<void> revokeRemoveAds({required String source}) async => _set(Entitlement(source: source));

  @override
  Future<void> mergeServer({required bool removeAds, required DateTime at}) =>
      _merge(this, removeAds: removeAds, at: at);
}
