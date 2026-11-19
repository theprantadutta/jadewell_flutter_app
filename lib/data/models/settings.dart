enum ThemePreference { light, dark, system }

/// S 0.9× · M 1× · L 1.12× of the tile footprint (DESIGN_SYSTEM §3).
enum TileSizePreference { small, medium, large }

class AppSettings {
  const AppSettings({
    this.theme = ThemePreference.system,
    this.music = true,
    this.soundEffects = true,
    this.haptics = true,
    this.showTimer = true,
    this.tileSize = TileSizePreference.medium,
    this.reduceMotion = false,
    this.highRefreshRate = false,
    this.onboardingDone = false,
  });

  final ThemePreference theme;
  final bool music;
  final bool soundEffects;
  final bool haptics;
  final bool showTimer;
  final TileSizePreference tileSize;

  /// In-app switch; the OS flag also applies (either one reduces motion).
  final bool reduceMotion;

  /// Ask the display for its fastest rate (90/120 Hz) instead of the OS
  /// default. Off by default: Jadewell is built for 60 Hz and faster costs
  /// battery, so it is the player's choice (docs/PERFORMANCE.md).
  final bool highRefreshRate;
  final bool onboardingDone;

  AppSettings copyWith({
    ThemePreference? theme,
    bool? music,
    bool? soundEffects,
    bool? haptics,
    bool? showTimer,
    TileSizePreference? tileSize,
    bool? reduceMotion,
    bool? highRefreshRate,
    bool? onboardingDone,
  }) =>
      AppSettings(
        theme: theme ?? this.theme,
        music: music ?? this.music,
        soundEffects: soundEffects ?? this.soundEffects,
        haptics: haptics ?? this.haptics,
        showTimer: showTimer ?? this.showTimer,
        tileSize: tileSize ?? this.tileSize,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        highRefreshRate: highRefreshRate ?? this.highRefreshRate,
        onboardingDone: onboardingDone ?? this.onboardingDone,
      );
}
