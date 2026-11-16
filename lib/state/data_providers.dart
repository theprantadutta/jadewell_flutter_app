import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/db/drift_repositories.dart';
import '../data/models/catalogue.dart';
import '../data/models/progress.dart';
import '../data/models/settings.dart';
import '../data/models/unlocks.dart';
import '../data/repositories/asset_catalogue_repository.dart';
import '../data/repositories/memory_repositories.dart';
import '../data/repositories/repositories.dart';
import '../data/sync/sync_engine.dart';
import 'app_providers.dart';
import 'session_controller.dart';

// ---- repositories (main.dart overrides the in-memory defaults with Drift) ----

final catalogueRepositoryProvider = Provider<CatalogueRepository>((ref) => AssetCatalogueRepository());

final _memoryProgress = Provider<MemoryProgressRepository>((ref) => MemoryProgressRepository());
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) => MemorySettingsRepository());
final progressRepositoryProvider = Provider<ProgressRepository>((ref) => ref.watch(_memoryProgress));
final statsRepositoryProvider = Provider<StatsRepository>((ref) => ref.watch(_memoryProgress));
final dailyRepositoryProvider = FutureProvider<DailyRepository>((ref) async =>
    MemoryDailyRepository(await ref.watch(catalogueProvider.future), ref.watch(_memoryProgress)));

// ---- Drift (main.dart points the repository providers above at these) ----

/// The on-device database, opened lazily on a background isolate.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final driftSettingsRepositoryProvider =
    Provider<SettingsRepository>((ref) => DriftSettingsRepository(ref.watch(databaseProvider)));
final driftProgressRepositoryProvider =
    Provider<ProgressRepository>((ref) => DriftProgressRepository(ref.watch(databaseProvider)));
final driftStatsRepositoryProvider =
    Provider<StatsRepository>((ref) => DriftStatsRepository(ref.watch(databaseProvider)));
final driftDailyRepositoryProvider = FutureProvider<DailyRepository>((ref) async =>
    DriftDailyRepository(ref.watch(databaseProvider), (await ref.watch(catalogueProvider.future)).dailyPool));

/// The outbox pusher. Started by [startBackgroundSync]; drains on app
/// pause/resume and whenever the backend session comes online.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final store = ref.watch(sessionStoreProvider);
  final engine = SyncEngine(
    db: ref.watch(databaseProvider),
    transport: ApiSyncTransport(ref.watch(apiClientProvider)),
    hasSession: () => store.token != null,
  )..start();
  final lifecycle = AppLifecycleListener(onPause: engine.drainNow, onResume: engine.drainNow);
  ref.listen(sessionProvider, (_, next) {
    if (next.value?.isOnline ?? false) engine.drainNow();
  });
  ref.onDispose(() {
    lifecycle.dispose();
    engine.dispose();
  });
  return engine;
});

/// Call once after the app's ProviderContainer exists. Never blocks.
void startBackgroundSync(ProviderContainer container) => container.read(syncEngineProvider);

// ---- read models for the UI ----

/// All layouts and chapters (assets; loads in a few ms).
final catalogueProvider = FutureProvider<Catalogue>((ref) => ref.watch(catalogueRepositoryProvider).load());

final settingsProvider = StreamNotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends StreamNotifier<AppSettings> {
  @override
  Stream<AppSettings> build() => ref.watch(settingsRepositoryProvider).watch();

  /// Current value, or defaults while loading.
  AppSettings get current => state.value ?? const AppSettings();

  Future<void> change(AppSettings Function(AppSettings) edit) async {
    final next = edit(current);
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).write(next);
  }
}

/// Layout id → progress.
final progressProvider =
    StreamProvider<Map<String, LayoutProgress>>((ref) => ref.watch(progressRepositoryProvider).watchAll());

final statsProvider = StreamProvider<PlayerStats>((ref) => ref.watch(statsRepositoryProvider).watch());

final dailyProvider = StreamProvider<DailyStatus>((ref) async* {
  final repo = await ref.watch(dailyRepositoryProvider.future);
  yield* repo.watchToday();
});

/// Lock state of a layout; null while catalogue/progress load.
final layoutAccessProvider = Provider.family<LayoutAccess?, String>((ref, id) {
  final c = ref.watch(catalogueProvider).value;
  final p = ref.watch(progressProvider).value;
  if (c == null || p == null) return null;
  return Unlocks.layout(c, id, p);
});

final chapterAccessProvider = Provider.family<ChapterAccess?, String>((ref, id) {
  final c = ref.watch(catalogueProvider).value;
  final p = ref.watch(progressProvider).value;
  if (c == null || p == null) return null;
  return Unlocks.chapter(c, id, p);
});
