import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/api/purchases_api.dart';

/// A store-confirmed purchase our backend has not verified yet (offline,
/// 404 while the endpoint isn't deployed, no session). Retried on resume and
/// whenever the backend session comes online.
class PendingVerification {
  const PendingVerification({
    required this.receipt,
    required this.purchasedAt,
    this.attempts = 0,
    this.acknowledged = false,
  });

  factory PendingVerification.fromJson(Map<String, dynamic> j) => PendingVerification(
        receipt: PurchaseReceipt.fromJson(j['receipt'] as Map<String, dynamic>),
        purchasedAt: DateTime.parse(j['purchased_at'] as String),
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        acknowledged: j['acknowledged'] as bool? ?? false,
      );

  final PurchaseReceipt receipt;

  /// When the store says it was bought: Play's 3-day acknowledge window
  /// starts here, so the force-acknowledge deadline counts from it too.
  final DateTime purchasedAt;
  final int attempts;

  /// Already acknowledged/finished with the store despite no verification.
  final bool acknowledged;

  String get key => receipt.key;

  PendingVerification copyWith({int? attempts, bool? acknowledged}) => PendingVerification(
        receipt: receipt,
        purchasedAt: purchasedAt,
        attempts: attempts ?? this.attempts,
        acknowledged: acknowledged ?? this.acknowledged,
      );

  Map<String, dynamic> toJson() => {
        'receipt': receipt.toJson(),
        'purchased_at': purchasedAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'acknowledged': acknowledged,
      };
}

/// Where the verify-later queue lives. Device-only, so SharedPreferences
/// (ARCHITECTURE §3); purchases never go through the sync outbox.
abstract interface class PendingVerificationStore {
  Future<List<PendingVerification>> load();
  Future<void> save(List<PendingVerification> entries);
}

class MemoryPendingVerificationStore implements PendingVerificationStore {
  List<PendingVerification> entries = [];

  @override
  Future<List<PendingVerification>> load() async => List.of(entries);

  @override
  Future<void> save(List<PendingVerification> entries) async => this.entries = List.of(entries);
}

class PrefsPendingVerificationStore implements PendingVerificationStore {
  PrefsPendingVerificationStore(this._prefs);

  static const key = 'iap_pending_verifications';
  final SharedPreferences _prefs;

  @override
  Future<List<PendingVerification>> load() async {
    final raw = _prefs.getStringList(key) ?? const [];
    final out = <PendingVerification>[];
    for (final s in raw) {
      try {
        out.add(PendingVerification.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } on Object {
        // Unparseable: it could never be sent, so drop it.
      }
    }
    return out;
  }

  @override
  Future<void> save(List<PendingVerification> entries) =>
      _prefs.setStringList(key, [for (final e in entries) jsonEncode(e.toJson())]);
}
