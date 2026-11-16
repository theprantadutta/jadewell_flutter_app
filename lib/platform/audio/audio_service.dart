/// Sound effects named after the interactions in MOTION_SPEC.md.
enum Sfx { tap, select, deselect, match, mismatch, blocked, shuffle, undo, hint, clear, star, unlock, toggle }

/// Music + SFX. The real implementation mixes with the user's own music by
/// default and suspends in the background. Both channels respect settings.
abstract interface class AudioService {
  Future<void> init();
  void play(Sfx sfx);

  /// Starts (or keeps) the background music loop.
  Future<void> startMusic();
  Future<void> stopMusic();

  /// From settings; takes effect immediately.
  void setMusicEnabled(bool enabled);
  void setSfxEnabled(bool enabled);

  /// App lifecycle: pause everything when backgrounded.
  void onBackground();
  void onForeground();
}

class NoOpAudio implements AudioService {
  const NoOpAudio();
  @override
  Future<void> init() async {}
  @override
  void play(Sfx sfx) {}
  @override
  Future<void> startMusic() async {}
  @override
  Future<void> stopMusic() async {}
  @override
  void setMusicEnabled(bool enabled) {}
  @override
  void setSfxEnabled(bool enabled) {}
  @override
  void onBackground() {}
  @override
  void onForeground() {}
}
