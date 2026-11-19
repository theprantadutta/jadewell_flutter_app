import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/models/progress.dart';
import 'package:jadewell_flutter_app/platform/store_listing/store_listing_service.dart';
import 'package:jadewell_flutter_app/state/platform_providers.dart';
import 'package:jadewell_flutter_app/state/store_listing_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeStore implements StoreListingService {
  FakeStore(this.check, {this.flow = UpdateFlowResult.accepted});

  UpdateCheck check;
  UpdateFlowResult flow;
  final calls = <String>[];

  @override
  bool get supportsUpdates => true;
  @override
  bool get canOpenStoreListing => true;
  @override
  Future<UpdateCheck> checkForUpdate() async {
    calls.add('check');
    return check;
  }

  @override
  Future<UpdateFlowResult> startImmediateUpdate() async {
    calls.add('immediate');
    return flow;
  }

  @override
  Future<UpdateFlowResult> startFlexibleUpdate() async {
    calls.add('flexible');
    return flow;
  }

  @override
  Future<void> completeFlexibleUpdate() async => calls.add('complete');
  @override
  Future<void> requestReview() async => calls.add('review');
  @override
  Future<bool> openStoreListing() async {
    calls.add('listing');
    return true;
  }
}

const _available = UpdateCheck(state: UpdateState.available, immediateAllowed: true, flexibleAllowed: true);

void main() {
  group('AppUpdateController', () {
    ProviderContainer containerFor(FakeStore store) {
      final c = ProviderContainer(overrides: [storeListingProvider.overrideWithValue(store)]);
      addTearDown(c.dispose);
      return c;
    }

    test('a normal release downloads in the background, once per session', () async {
      final store = FakeStore(_available);
      final c = containerFor(store);
      final ctl = c.read(appUpdateProvider.notifier);
      await ctl.checkInBackground();
      expect(store.calls, ['check', 'flexible']);
      expect(c.read(appUpdateProvider), UpdateState.downloaded);
      // Resume: checks again, never prompts again, never installs by itself.
      store.check = _available;
      await ctl.checkInBackground();
      expect(store.calls, ['check', 'flexible', 'check']);
    });

    test('a priority 4+ release opens the full-screen update', () async {
      final store = FakeStore(const UpdateCheck(
        state: UpdateState.available,
        priority: 4,
        immediateAllowed: true,
        flexibleAllowed: true,
      ));
      await containerFor(store).read(appUpdateProvider.notifier).checkInBackground();
      expect(store.calls, ['check', 'immediate']);
    });

    test('a declined background download goes back to available', () async {
      final store = FakeStore(_available, flow: UpdateFlowResult.declined);
      final c = containerFor(store);
      await c.read(appUpdateProvider.notifier).checkInBackground();
      expect(c.read(appUpdateProvider), UpdateState.available);
    });

    test('Settings: up to date, unavailable, downloaded → restart, available → full screen', () async {
      final store = FakeStore(const UpdateCheck(state: UpdateState.upToDate));
      final ctl = containerFor(store).read(appUpdateProvider.notifier);
      expect(await ctl.checkFromSettings(), ManualUpdateResult.upToDate);
      store.check = UpdateCheck.unknown;
      expect(await ctl.checkFromSettings(), ManualUpdateResult.unavailable);
      store.check = const UpdateCheck(state: UpdateState.downloaded);
      expect(await ctl.checkFromSettings(), ManualUpdateResult.started);
      expect(store.calls.last, 'complete');
      store.check = _available;
      expect(await ctl.checkFromSettings(), ManualUpdateResult.started);
      expect(store.calls.last, 'immediate');
      store.flow = UpdateFlowResult.declined;
      expect(await ctl.checkFromSettings(), ManualUpdateResult.declined);
    });
  });

  group('ReviewPrompter', () {
    late SharedPreferences prefs;
    var now = DateTime(2026, 11, 19);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      now = DateTime(2026, 11, 19);
    });

    ReviewPrompter prompter(FakeStore store, {int cleared = 5}) => ReviewPrompter(
          store: store,
          prefs: () => prefs,
          stats: () async => PlayerStats(boardsCleared: cleared),
          clock: () => now,
        );

    test('asks after a good clear once enough boards are cleared, once per session', () async {
      final store = FakeStore(UpdateCheck.unknown);
      final p = prompter(store);
      expect(await p.maybeAskAfterClear(stars: 3), isTrue);
      expect(await p.maybeAskAfterClear(stars: 3), isFalse);
      expect(store.calls, ['review']);
    });

    test('never on a 1-star clear or before 3 clears', () async {
      final store = FakeStore(UpdateCheck.unknown);
      expect(await prompter(store).maybeAskAfterClear(stars: 1), isFalse);
      expect(await prompter(store, cleared: 2).maybeAskAfterClear(stars: 3), isFalse);
      expect(store.calls, isEmpty);
    });

    test('waits 60 days between asks and stops after 4', () async {
      final store = FakeStore(UpdateCheck.unknown);
      expect(await prompter(store).maybeAskAfterClear(stars: 2), isTrue);
      now = now.add(const Duration(days: 59));
      expect(await prompter(store).maybeAskAfterClear(stars: 2), isFalse);
      for (var i = 0; i < 3; i++) {
        now = now.add(const Duration(days: 61));
        expect(await prompter(store).maybeAskAfterClear(stars: 2), isTrue);
      }
      now = now.add(const Duration(days: 400));
      expect(await prompter(store).maybeAskAfterClear(stars: 3), isFalse);
      expect(store.calls.length, 4);
    });
  });
}
