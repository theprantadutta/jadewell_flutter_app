/// The small slice of an audio engine that [AudioServiceImpl] needs.
///
/// It exists so the service's queueing, flags and lifecycle logic can be
/// unit-tested without the native engine: `SoLoudAudioEngine` is the real one,
/// tests use a fake. Sources and voices are opaque to the service.
abstract interface class AudioEngine {
  /// Configures the platform audio session and starts the engine.
  Future<void> start();

  /// Releases the engine. Every source and voice dies with it.
  Future<void> stop();

  /// Loads a short asset fully decoded into memory (low latency, for SFX).
  Future<Object> loadDecoded(String asset);

  /// Loads an asset's compressed bytes into memory and decodes while playing
  /// (for long music tracks). Never streams from a file on disk.
  Future<Object> loadStreamed(String asset);

  Future<void> dispose(Object source);

  Duration length(Object source);

  /// Starts a voice, or returns null if the engine could not create one.
  Object? play(Object source, {required double volume, bool looping = false});

  bool isAlive(Object voice);
  void fadeTo(Object voice, double volume, Duration duration);

  /// Stops [voice] after [delay] (zero: now).
  void stopVoice(Object voice, [Duration delay = Duration.zero]);
}
