import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_engine.dart';

/// [AudioEngine] on flutter_soloud.
///
/// Lessons carried over from snake-classic's audio service:
///  * `SoLoud.instance` is resolved per call (a getter), so constructing this
///    class never loads the native library (tests, settings-only callers).
///  * Nothing streams from a file. `loadAsset` copies the asset to a temporary
///    file, and `LoadMode.disk` then re-reads that file on every play; Android
///    clears temp files under storage pressure and the next read aborted the
///    app in `SoLoud::DiskFile::read`. SFX are decoded into memory; music keeps
///    its compressed bytes in memory (`loadMem`, no temp file) and decodes as
///    it plays, which keeps a 2.5-minute track at ~1.7 MB instead of ~50 MB of
///    PCM.
///  * Every voice handle is validated before use: SoLoud recycles voices and
///    the setters hand the handle straight to native code.
class SoLoudAudioEngine implements AudioEngine {
  SoLoud get _soloud => SoLoud.instance;

  bool _sessionConfigured = false;

  @override
  Future<void> start() async {
    await _configureSession();
    await _soloud.init();
    // flutter_soloud 5 stops the output device after 500 ms of silence, so the
    // first tap after a quiet stretch would wait for the device to restart.
    // Keep it running while we are in the foreground; stop() releases it.
    _soloud.setAudioDeviceIdleTimeout(null);
  }

  /// Ambient, mixing with other apps: the player's own music keeps playing
  /// and nothing is ducked. iOS: `AVAudioSessionCategoryAmbient` +
  /// `mixWithOthers` (also honours the silent switch). Android: we never
  /// request audio focus, so other apps are not paused or ducked; the
  /// attributes describe game audio.
  Future<void> _configureSession() async {
    if (_sessionConfigured || kIsWeb) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.ambient,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.sonification,
          usage: AndroidAudioUsage.game,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ));
      // Activating an ambient, mix-with-others session on iOS interrupts
      // nobody. On Android setActive() would request audio focus (and pause or
      // duck the user's music), so it is deliberately skipped there.
      if (Platform.isIOS) await session.setActive(true);
      _sessionConfigured = true;
    } catch (e) {
      debugPrint('audio: session config failed: $e');
    }
  }

  @override
  Future<void> stop() => _soloud.deinitAsync();

  @override
  Future<Object> loadDecoded(String asset) async {
    final data = await rootBundle.load(asset);
    return _soloud.loadMem(asset, data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  @override
  Future<Object> loadStreamed(String asset) async {
    final data = await rootBundle.load(asset);
    // loadMem + LoadMode.disk = SoLoud WavStream over an in-memory copy of the
    // compressed bytes: no temp file is involved (see class doc).
    return _soloud.loadMem(
      asset,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      mode: LoadMode.disk,
    );
  }

  @override
  Future<void> dispose(Object source) => _soloud.disposeSource(source as AudioSource);

  @override
  Duration length(Object source) => _soloud.getLength(source as AudioSource);

  @override
  Object? play(Object source, {required double volume, bool looping = false}) {
    // play() returns a zeroed handle rather than throwing when the engine is
    // out of voices, so validate before handing it out.
    final handle = _soloud.play(source as AudioSource, volume: volume, looping: looping);
    return _soloud.getIsValidVoiceHandle(handle) ? handle : null;
  }

  @override
  bool isAlive(Object voice) => _soloud.isInitialized && _soloud.getIsValidVoiceHandle(voice as SoundHandle);

  @override
  void fadeTo(Object voice, double volume, Duration duration) {
    if (isAlive(voice)) _soloud.fadeVolume(voice as SoundHandle, volume, duration);
  }

  @override
  void stopVoice(Object voice, [Duration delay = Duration.zero]) {
    if (!isAlive(voice)) return;
    if (delay == Duration.zero) {
      _soloud.stop(voice as SoundHandle).ignore();
    } else {
      _soloud.scheduleStop(voice as SoundHandle, delay);
    }
  }
}
