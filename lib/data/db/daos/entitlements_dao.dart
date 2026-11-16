import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'entitlements_dao.g.dart';

/// Remove-ads entitlement (local trust when offline). Used by the IAP layer.
@DriftAccessor(tables: [EntitlementsTable])
class EntitlementsDao extends DatabaseAccessor<AppDatabase> with _$EntitlementsDaoMixin {
  EntitlementsDao(super.attachedDatabase);

  Stream<bool> watchRemoveAds() =>
      select(entitlementsTable).watchSingleOrNull().map((r) => r?.removeAds ?? false);

  Future<EntitlementsRow?> read() => select(entitlementsTable).getSingleOrNull();

  Future<void> setRemoveAds(bool value, {required String source, DateTime? verifiedAt}) =>
      into(entitlementsTable).insertOnConflictUpdate(
        EntitlementsTableCompanion.insert(
          id: const Value(0),
          removeAds: Value(value),
          source: Value(source),
          verifiedAt: Value(verifiedAt),
        ),
      );
}
