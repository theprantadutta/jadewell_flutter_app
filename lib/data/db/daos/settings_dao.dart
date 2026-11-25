import 'package:drift/drift.dart';

import '../../models/settings.dart';
import '../app_database.dart';
import '../tables.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [SettingsTable])
class SettingsDao extends DatabaseAccessor<AppDatabase> with _$SettingsDaoMixin {
  SettingsDao(super.attachedDatabase);

  Stream<AppSettings> watch() =>
      select(settingsTable).watchSingleOrNull().map((r) => r == null ? const AppSettings() : _toModel(r));

  Future<AppSettings> read() async {
    final r = await select(settingsTable).getSingleOrNull();
    return r == null ? const AppSettings() : _toModel(r);
  }

  Future<void> write(AppSettings s) => into(settingsTable).insertOnConflictUpdate(
        SettingsTableCompanion.insert(
          id: const Value(0),
          theme: Value(s.theme),
          music: Value(s.music),
          soundEffects: Value(s.soundEffects),
          haptics: Value(s.haptics),
          showTimer: Value(s.showTimer),
          tileSize: Value(s.tileSize),
          reduceMotion: Value(s.reduceMotion),
          highRefreshRate: Value(s.highRefreshRate),
          dailyReminder: Value(s.dailyReminder),
          onboardingDone: Value(s.onboardingDone),
        ),
      );

  static AppSettings _toModel(SettingsRow r) => AppSettings(
        theme: r.theme,
        music: r.music,
        soundEffects: r.soundEffects,
        haptics: r.haptics,
        showTimer: r.showTimer,
        tileSize: r.tileSize,
        reduceMotion: r.reduceMotion,
        highRefreshRate: r.highRefreshRate,
        dailyReminder: r.dailyReminder,
        onboardingDone: r.onboardingDone,
      );
}
