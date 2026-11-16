import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/db/app_database.dart';
import 'package:jadewell_flutter_app/data/repositories/entitlement_repository.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 16, 12);

  void contract(String name, EntitlementRepository Function() create, {Future<void> Function()? dispose}) {
    group(name, () {
      late EntitlementRepository repo;
      setUp(() => repo = create());
      if (dispose != null) tearDown(dispose);

      test('starts with nothing', () async {
        expect((await repo.read()).removeAds, isFalse);
      });

      test('grant → verify → revoke', () async {
        await repo.grantRemoveAds(source: 'play');
        var e = await repo.read();
        expect(e.removeAds, isTrue);
        expect(e.isVerified, isFalse);
        expect(e.source, 'play');

        await repo.markVerified(at: t0);
        e = await repo.read();
        expect(e.removeAds, isTrue);
        expect(e.verifiedAt!.toUtc(), t0);

        // A replayed store grant keeps the verification.
        await repo.grantRemoveAds(source: 'restore');
        expect((await repo.read()).verifiedAt!.toUtc(), t0);

        await repo.revokeRemoveAds(source: 'server');
        e = await repo.read();
        expect(e.removeAds, isFalse);
        expect(e.verifiedAt, isNull);
      });

      test('server merge: true grants and verifies', () async {
        await repo.mergeServer(removeAds: true, at: t0);
        final e = await repo.read();
        expect(e.removeAds, isTrue);
        expect(e.verifiedAt!.toUtc(), t0);
      });

      test('server merge: false revokes a verified grant (refund)', () async {
        await repo.markVerified(at: t0);
        await repo.mergeServer(removeAds: false, at: t0);
        expect((await repo.read()).removeAds, isFalse);
      });

      test('offline trust: false never revokes a store grant awaiting verification', () async {
        await repo.grantRemoveAds(source: 'play');
        await repo.mergeServer(removeAds: false, at: t0);
        expect((await repo.read()).removeAds, isTrue);
      });

      test('watch emits changes', () async {
        final seen = <bool>[];
        final sub = repo.watch().listen((e) => seen.add(e.removeAds));
        await pumpEventQueue();
        await repo.grantRemoveAds(source: 'play');
        await pumpEventQueue();
        await repo.revokeRemoveAds(source: 'server');
        await pumpEventQueue();
        await sub.cancel();
        expect(seen.first, isFalse);
        expect(seen, containsAllInOrder([false, true, false]));
      });
    });
  }

  contract('memory', MemoryEntitlementRepository.new);

  late AppDatabase db;
  contract(
    'drift',
    () {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      return DriftEntitlementRepository(db);
    },
    dispose: () => db.close(),
  );
}
