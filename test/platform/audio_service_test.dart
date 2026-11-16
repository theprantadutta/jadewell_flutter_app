import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/platform/audio/audio_engine.dart';
import 'package:jadewell_flutter_app/platform/audio/audio_service.dart';
import 'package:jadewell_flutter_app/platform/audio/audio_service_impl.dart';

class FakeVoice {
  FakeVoice(this.source, this.volume, this.looping);
  final String source;
  double volume;
  final bool looping;
  bool alive = true;
}

/// Records what the service asks of the engine. Loads can be held open with
/// [gate] to test the queue.
/// Engine misuse seen by [FakeEngine]. Recorded rather than expect()ed: the
/// service swallows engine errors, and flutter_test's guarded expect() would
/// clash with a pending pump. Checked after every test.
final _violations = <String>[];

void _check(bool ok, String what) {
  if (!ok) {
    _violations.add(what);
    throw StateError('FakeEngine: $what');
  }
}

class FakeEngine implements AudioEngine {
  final log = <String>[];
  final voices = <FakeVoice>[];
  final disposed = <String>[];
  bool running = false;
  Completer<void>? gate;
  Duration trackLength = const Duration(seconds: 60);

  @override
  Future<void> start() async {
    log.add('start');
    running = true;
  }

  @override
  Future<void> stop() async {
    log.add('stop');
    _check(running, 'stop without start');
    running = false;
    for (final v in voices) {
      v.alive = false;
    }
  }

  @override
  Future<Object> loadDecoded(String asset) async {
    _check(running, 'load into a stopped engine');
    return asset;
  }

  @override
  Future<Object> loadStreamed(String asset) async {
    log.add('loadStreamed ${asset.split('/').last}');
    await gate?.future;
    return asset;
  }

  @override
  Future<void> dispose(Object source) async => disposed.add((source as String).split('/').last);

  @override
  Duration length(Object source) => trackLength;

  @override
  Object? play(Object source, {required double volume, bool looping = false}) {
    _check(running, 'play on a stopped engine');
    final v = FakeVoice((source as String).split('/').last, volume, looping);
    voices.add(v);
    return v;
  }

  @override
  bool isAlive(Object voice) => (voice as FakeVoice).alive;

  @override
  void fadeTo(Object voice, double volume, Duration duration) => (voice as FakeVoice).volume = volume;

  @override
  void stopVoice(Object voice, [Duration delay = Duration.zero]) => (voice as FakeVoice).alive = false;

  List<FakeVoice> get sfxVoices => voices.where((v) => v.source.endsWith('.wav')).toList();
  List<FakeVoice> get musicVoices => voices.where((v) => v.source.endsWith('.ogg')).toList();
  List<FakeVoice> get liveMusic => musicVoices.where((v) => v.alive).toList();
}

void main() {
  late FakeEngine engine;
  late AudioServiceImpl audio;

  tearDown(() {
    expect(_violations, isEmpty);
    _violations.clear();
  });

  setUp(() {
    engine = FakeEngine();
    audio = AudioServiceImpl(engine,
        musicTracks: const ['m/a.ogg', 'm/b.ogg', 'm/c.ogg'], crossfade: const Duration(seconds: 4));
  });

  test('SFX are silent until init, then play from the preloaded set', () async {
    audio.play(Sfx.select);
    expect(engine.voices, isEmpty);
    await audio.init();
    expect(audio.isReady, isTrue);
    audio.play(Sfx.select);
    expect(engine.sfxVoices.single.source, 'select.wav');
    expect(engine.sfxVoices.single.volume, AudioServiceImpl.sfxVolume[Sfx.select]);
  });

  test('every Sfx has an asset and a volume', () {
    for (final s in Sfx.values) {
      expect(AudioServiceImpl.sfxAsset(s), 'assets/audio/sfx/${s.name}.wav');
      expect(AudioServiceImpl.sfxVolume[s], isNotNull, reason: s.name);
    }
  });

  test('sfx flag applies instantly', () async {
    await audio.init();
    audio
      ..setSfxEnabled(false)
      ..play(Sfx.match);
    expect(engine.sfxVoices, isEmpty);
    audio
      ..setSfxEnabled(true)
      ..play(Sfx.match);
    expect(engine.sfxVoices, hasLength(1));
  });

  test('the same cue fired twice at once plays once', () async {
    await audio.init();
    audio
      ..play(Sfx.tap)
      ..play(Sfx.tap)
      ..play(Sfx.toggle);
    expect(engine.sfxVoices.map((v) => v.source), ['tap.wav', 'toggle.wav']);
  });

  test('music requested before init starts once the engine is ready, quieter than SFX', () async {
    unawaited(audio.startMusic());
    await audio.init();
    await audio.idle;
    final m = engine.liveMusic.single;
    expect(m.source, 'a.ogg');
    expect(m.looping, isTrue);
    expect(m.volume, audio.musicVolume);
    expect(audio.musicVolume, lessThan(AudioServiceImpl.sfxVolume.values.reduce((a, b) => a < b ? a : b)));
  });

  test('music disabled: startMusic stays silent; enabling starts it; disabling stops it now', () async {
    audio.setMusicEnabled(false);
    await audio.init();
    await audio.startMusic();
    expect(engine.musicVoices, isEmpty);

    audio.setMusicEnabled(true);
    await audio.idle;
    expect(engine.liveMusic, hasLength(1));

    audio.setMusicEnabled(false);
    expect(engine.liveMusic, isEmpty, reason: 'fades out immediately, not after queued work');
    await audio.idle;
    expect(engine.disposed, contains('a.ogg'));
  });

  test('startMusic twice does not stack voices', () async {
    await audio.init();
    unawaited(audio.startMusic());
    await audio.startMusic();
    expect(engine.musicVoices, hasLength(1));
  });

  test('stopMusic fades out and frees the track', () async {
    await audio.init();
    await audio.startMusic();
    await audio.stopMusic();
    expect(engine.liveMusic, isEmpty);
    expect(engine.disposed, ['a.ogg']);
  });

  test('background releases the engine; foreground restarts it and the music', () async {
    await audio.init();
    await audio.startMusic();
    audio.onBackground();
    await audio.idle;
    expect(engine.running, isFalse);
    expect(audio.isReady, isFalse);
    audio.play(Sfx.tap);
    expect(engine.sfxVoices, isEmpty, reason: 'no play while suspended');

    audio.onForeground();
    await audio.idle;
    expect(engine.running, isTrue);
    expect(engine.liveMusic, hasLength(1));
    expect(engine.log.where((l) => l == 'start'), hasLength(2));
  });

  test('quick background/foreground flips are serialised', () async {
    await audio.init();
    for (var i = 0; i < 5; i++) {
      audio
        ..onBackground()
        ..onForeground();
    }
    await audio.idle;
    // FakeEngine asserts start/stop alternate and nothing loads into a stopped engine.
    expect(engine.running, isTrue);
    expect(audio.isReady, isTrue);
  });

  test('backgrounded before init: the engine starts only on foreground', () async {
    audio.onBackground();
    await audio.init();
    expect(engine.log, isEmpty);
    audio.onForeground();
    await audio.idle;
    expect(engine.log, ['start']);
  });

  test('a track that finishes loading after a suspend is dropped, not played', () async {
    await audio.init();
    engine.gate = Completer<void>();
    unawaited(audio.startMusic());
    await Future<void>.delayed(Duration.zero);
    audio.onBackground(); // queued behind the pending load
    engine.gate!.complete();
    await audio.idle;
    expect(engine.running, isFalse);
    expect(engine.liveMusic, isEmpty);
  });

  testWidgets('tracks rotate with a crossfade before each ends', (tester) async {
    // Everything in FakeEngine completes synchronously, so the fake clock
    // drives the queue, the rotation timer and the fades.
    // The service is built inside the fake zone so its queue runs there.
    engine.trackLength = const Duration(seconds: 30);
    audio = AudioServiceImpl(engine,
        musicTracks: const ['m/a.ogg', 'm/b.ogg', 'm/c.ogg'], crossfade: const Duration(seconds: 4));
    unawaited(audio.init());
    unawaited(audio.startMusic());
    await tester.pump();
    expect(engine.liveMusic.single.source, 'a.ogg');

    await tester.pump(const Duration(seconds: 26)); // 30 s - 4 s crossfade
    await tester.pump();
    expect(audio.currentTrack, 1);
    expect(engine.liveMusic.single.source, 'b.ogg');
    expect(engine.musicVoices.first.volume, 0, reason: 'old track faded out');

    await tester.pump(const Duration(seconds: 5));
    expect(engine.disposed, contains('a.ogg'));

    unawaited(audio.stopMusic());
    await tester.pump(const Duration(seconds: 1));
    expect(engine.liveMusic, isEmpty);
  });
}
