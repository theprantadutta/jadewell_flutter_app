import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio_engine.dart';
import 'audio_service.dart';

/// Music + SFX on an [AudioEngine] (SoLoud in the app, a fake in tests).
///
/// * **One serial queue** for everything that touches the engine's lifetime
///   or loads assets: start, suspend, resume, music start/crossfade/stop. A
///   quick background/foreground flip can never start the engine while it is
///   still being torn down, nor load into an engine that is going away.
/// * **SFX** are preloaded, decoded in memory, at [init] and played
///   synchronously from [play] (no queue, no await: lowest latency).
/// * **Music** rotates through [musicTracks] with a gentle crossfade. Each
///   track also loops on its own, so a late timer only means one more loop.
/// * **Flags** apply instantly: disabling music fades it out now; disabling
///   SFX drops the next [play].
/// * **Background**: the engine is released entirely (snake-classic: a SoLoud
///   mixer left running behind a destroyed activity crashed the app later)
///   and brought back on foreground.
class AudioServiceImpl implements AudioService {
  AudioServiceImpl(
    this._engine, {
    this.musicTracks = defaultMusicTracks,
    this.musicVolume = 0.32,
    this.crossfade = const Duration(seconds: 4),
  });

  final AudioEngine _engine;
  final List<String> musicTracks;

  /// Music sits well under the SFX so cues stay audible.
  final double musicVolume;
  final Duration crossfade;

  static const List<String> defaultMusicTracks = [
    'assets/audio/music/hot_spring_town.ogg',
    'assets/audio/music/notebook_lofi.ogg',
    'assets/audio/music/chill_lofi.ogg',
  ];

  static String sfxAsset(Sfx sfx) => 'assets/audio/sfx/${sfx.name}.wav';

  /// Per-cue gain on top of the normalised assets (MOTION_SPEC: soft, nothing
  /// jumps out; frequent UI ticks quieter than rewards).
  static const Map<Sfx, double> sfxVolume = {
    Sfx.tap: 0.55,
    Sfx.toggle: 0.55,
    Sfx.select: 0.8,
    Sfx.deselect: 0.7,
    Sfx.match: 0.85,
    Sfx.mismatch: 0.75,
    Sfx.blocked: 0.7,
    Sfx.shuffle: 0.8,
    Sfx.undo: 0.7,
    Sfx.hint: 0.8,
    Sfx.clear: 0.9,
    Sfx.star: 0.85,
    Sfx.unlock: 0.85,
  };

  /// The same cue fired again within this window is dropped (a double tap
  /// would otherwise stack two identical voices into one louder click).
  static const Duration _sameCueGap = Duration(milliseconds: 35);

  bool _sfxEnabled = true;
  bool _musicEnabled = true;

  /// [init] has been called (the app wants the engine).
  bool _wanted = false;

  /// Engine up and SFX loaded; [play] works.
  bool _ready = false;

  /// App is in the background.
  bool _background = false;

  /// [startMusic] called and not stopped since.
  bool _musicWanted = false;

  final Map<Sfx, Object> _sfx = {};
  final Map<Sfx, DateTime> _lastPlayed = {};

  int _trackIndex = 0;
  Object? _musicSource;
  Object? _musicVoice;
  Timer? _rotation;

  /// Bumped whenever the engine goes away, so work that awaited across a
  /// suspend drops what it loaded instead of using a dead engine's source.
  int _generation = 0;

  Future<void> _ops = Future.value();

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _ops.then((_) => op());
    // One failed step must never wedge every later one.
    _ops = next.catchError((Object e, StackTrace s) {
      debugPrint('audio: $e');
    });
    return _ops;
  }

  // ---- state, for tests and logs ----
  @visibleForTesting
  bool get isReady => _ready;
  @visibleForTesting
  bool get isMusicPlaying => _musicVoice != null && _engine.isAlive(_musicVoice!);
  @visibleForTesting
  int get currentTrack => _trackIndex;

  /// Resolves when every queued engine operation has run.
  @visibleForTesting
  Future<void> get idle => _ops;

  @override
  Future<void> init() {
    _wanted = true;
    return _enqueue(_start);
  }

  Future<void> _start() async {
    if (_ready || _background || !_wanted) return;
    final generation = _generation;
    final sw = Stopwatch()..start();
    await _engine.start();
    for (final sfx in Sfx.values) {
      try {
        final source = await _engine.loadDecoded(sfxAsset(sfx));
        if (generation != _generation) return;
        _sfx[sfx] = source;
      } catch (e) {
        debugPrint('audio: failed to load ${sfx.name}: $e');
      }
    }
    _ready = true;
    debugPrint('audio: engine ready, ${_sfx.length}/${Sfx.values.length} sfx in ${sw.elapsedMilliseconds} ms');
    if (_musicWanted && _musicEnabled) await _startTrack(fadeIn: const Duration(seconds: 2));
  }

  Future<void> _suspend() async {
    if (!_ready) return;
    _generation++;
    _ready = false; // gate play() before anything reaches the engine
    _rotation?.cancel();
    _rotation = null;
    _sfx.clear();
    _musicVoice = null;
    _musicSource = null;
    try {
      await _engine.stop();
    } catch (e) {
      debugPrint('audio: suspend failed: $e');
    }
    debugPrint('audio: suspended');
  }

  @override
  void play(Sfx sfx) {
    if (!_ready || !_sfxEnabled) return;
    final source = _sfx[sfx];
    if (source == null) return;
    final now = DateTime.now();
    final last = _lastPlayed[sfx];
    if (last != null && now.difference(last) < _sameCueGap) return;
    _lastPlayed[sfx] = now;
    try {
      _engine.play(source, volume: sfxVolume[sfx] ?? 0.8);
    } catch (e) {
      debugPrint('audio: play ${sfx.name} failed: $e');
    }
  }

  @override
  Future<void> startMusic() {
    _musicWanted = true;
    return _enqueue(() async {
      if (_ready && _musicEnabled && !isMusicPlaying) await _startTrack(fadeIn: const Duration(seconds: 2));
    });
  }

  @override
  Future<void> stopMusic() {
    _musicWanted = false;
    return _enqueue(() => _fadeOutMusic(const Duration(milliseconds: 600)));
  }

  @override
  void setMusicEnabled(bool enabled) {
    if (_musicEnabled == enabled) return;
    _musicEnabled = enabled;
    if (enabled) {
      if (_musicWanted) unawaited(startMusic());
    } else {
      // Fade the live voice right away rather than behind queued work.
      _rotation?.cancel();
      _rotation = null;
      final voice = _musicVoice;
      if (voice != null) {
        _engine.fadeTo(voice, 0, const Duration(milliseconds: 400));
        _engine.stopVoice(voice, const Duration(milliseconds: 420));
        _musicVoice = null;
      }
      // Free the track once the fade is over (disposing stops its voices).
      unawaited(_enqueue(() async {
        await Future<void>.delayed(const Duration(milliseconds: 450));
        await _disposeMusicSource();
      }));
    }
  }

  @override
  void setSfxEnabled(bool enabled) => _sfxEnabled = enabled;

  @override
  void onBackground() {
    if (_background) return;
    _background = true;
    unawaited(_enqueue(_suspend));
  }

  @override
  void onForeground() {
    if (!_background) return;
    _background = false;
    unawaited(_enqueue(_start));
  }

  // ---- music ----

  /// Loads and starts [_trackIndex], crossfading from whatever is playing.
  Future<void> _startTrack({required Duration fadeIn}) async {
    if (musicTracks.isEmpty) return;
    final generation = _generation;
    final Object source;
    try {
      source = await _engine.loadStreamed(musicTracks[_trackIndex]);
    } catch (e) {
      debugPrint('audio: music ${musicTracks[_trackIndex]} unavailable: $e');
      return;
    }
    if (generation != _generation) return; // engine went away while loading
    if (!_ready || !_musicWanted || !_musicEnabled) {
      await _engine.dispose(source);
      return;
    }
    final voice = _engine.play(source, volume: 0, looping: true);
    if (voice == null) {
      await _engine.dispose(source);
      return;
    }
    _engine.fadeTo(voice, musicVolume, fadeIn);

    final oldVoice = _musicVoice;
    final oldSource = _musicSource;
    _musicVoice = voice;
    _musicSource = source;
    if (oldVoice != null) {
      _engine.fadeTo(oldVoice, 0, fadeIn);
      _engine.stopVoice(oldVoice, fadeIn);
    }
    if (oldSource != null) {
      // Dispose after the old voice has faded out, on the queue.
      Timer(fadeIn + const Duration(milliseconds: 300), () {
        unawaited(_enqueue(() async {
          if (generation == _generation) await _engine.dispose(oldSource);
        }));
      });
    }
    debugPrint('audio: music track ${_trackIndex + 1}/${musicTracks.length} playing');
    _scheduleRotation(_engine.length(source));
  }

  void _scheduleRotation(Duration trackLength) {
    _rotation?.cancel();
    _rotation = null;
    if (musicTracks.length < 2) return; // a single track simply loops
    var wait = trackLength - crossfade;
    if (wait < const Duration(seconds: 5)) wait = trackLength;
    _rotation = Timer(wait, () {
      _rotation = null;
      unawaited(_enqueue(() async {
        if (!_ready || !_musicWanted || !_musicEnabled) return;
        _trackIndex = (_trackIndex + 1) % musicTracks.length;
        await _startTrack(fadeIn: crossfade);
      }));
    });
  }

  Future<void> _fadeOutMusic(Duration duration) async {
    _rotation?.cancel();
    _rotation = null;
    final voice = _musicVoice;
    _musicVoice = null;
    if (voice != null) {
      _engine.fadeTo(voice, 0, duration);
      _engine.stopVoice(voice, duration);
      await Future<void>.delayed(duration);
    }
    await _disposeMusicSource();
  }

  Future<void> _disposeMusicSource() async {
    if (_musicVoice != null) return; // music restarted meanwhile
    final source = _musicSource;
    _musicSource = null;
    if (source != null && _ready) await _engine.dispose(source);
  }
}
