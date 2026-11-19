import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/db/app_database.dart';
import 'package:jadewell_flutter_app/data/models/settings.dart';

void main() {
  test('schema 1 → 2 keeps the saved settings and adds High refresh rate (off)', () async {
    // The settings table exactly as schema 1 (1.0.0–1.0.5) created it, with a
    // player's saved choices in it.
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
      raw.execute('''
        CREATE TABLE settings (
          id INTEGER NOT NULL DEFAULT 0,
          theme TEXT NOT NULL DEFAULT 'system',
          music INTEGER NOT NULL DEFAULT 1 CHECK (music IN (0, 1)),
          sound_effects INTEGER NOT NULL DEFAULT 1 CHECK (sound_effects IN (0, 1)),
          haptics INTEGER NOT NULL DEFAULT 1 CHECK (haptics IN (0, 1)),
          show_timer INTEGER NOT NULL DEFAULT 1 CHECK (show_timer IN (0, 1)),
          tile_size TEXT NOT NULL DEFAULT 'medium',
          reduce_motion INTEGER NOT NULL DEFAULT 0 CHECK (reduce_motion IN (0, 1)),
          onboarding_done INTEGER NOT NULL DEFAULT 0 CHECK (onboarding_done IN (0, 1)),
          PRIMARY KEY (id)
        )''');
      raw.execute("INSERT INTO settings (id, theme, music, tile_size, onboarding_done) VALUES (0, 'dark', 0, 'large', 1)");
      raw.userVersion = 1;
    }));
    addTearDown(db.close);

    final s = await db.settingsDao.read();
    expect(s.theme, ThemePreference.dark);
    expect(s.music, isFalse);
    expect(s.tileSize, TileSizePreference.large);
    expect(s.onboardingDone, isTrue);
    expect(s.highRefreshRate, isFalse);

    await db.settingsDao.write(s.copyWith(highRefreshRate: true));
    expect((await db.settingsDao.read()).highRefreshRate, isTrue);
    expect(db.schemaVersion, 2);
  });
}
