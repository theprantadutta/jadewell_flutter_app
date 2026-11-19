import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data' show Int8List;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink, ProviderListenable;

import '../../data/models/catalogue.dart';
import '../../data/models/progress.dart';
import '../../data/repositories/repositories.dart';
import '../../engine/commands.dart' as cmd;
import '../../engine/engine.dart';
import '../../platform/ads/ad_service.dart';
import '../../platform/analytics/analytics_service.dart';
import '../../platform/audio/audio_service.dart';
import '../../platform/haptics/haptic_service.dart';
import '../app_providers.dart';
import '../data_providers.dart';
import '../platform_providers.dart';
import 'game_clock.dart';
import 'game_launch.dart';
import 'game_providers.dart';
import 'game_view_state.dart';

/// One board's controller (docs/ARCHITECTURE.md §4): loads or resumes the
/// board, owns the clock, applies engine commands, persists, records the
/// result and fires analytics, audio and haptics. Kept alive for the board's
/// lifetime; the screen calls [release] when the board is left.
final gameControllerProvider = NotifierProvider.autoDispose.family<GameController, GameViewState, GameLaunch>(
  GameController.new,
);

/// How long a hint stays up (MOTION_SPEC §3).
const kHintDuration = Duration(milliseconds: 2100);

/// Matches at most this far apart build a combo (MOTION_SPEC §4).
const kComboWindowMs = 4000;

/// Delay between a move and the debounced save.
const kSaveDebounce = Duration(milliseconds: 400);

/// Head-start reward size (docs/ARCHITECTURE.md §7).
const kHeadStartHints = 2;

/// Minimum time between "Second chance" offers for the same layout.
const kSecondChanceCooldown = Duration(hours: 12);

class GameController extends Notifier<GameViewState> {
  GameController(this.launch);

  final GameLaunch launch;

  late GameClock _clock;
  late ProgressRepository _repo;
  late AnalyticsService _analytics;
  late AudioService _audio;
  late HapticService _haptics;
  late AdService _ads;
  KeepAliveLink? _keepAlive;
  AppLifecycleListener? _lifecycle;
  final StreamController<GameEvent> _events = StreamController.broadcast(sync: true);
  Timer? _saveTimer;
  Timer? _hintTimer;
  bool _background = false;
  bool _inactive = false;
  bool _dirty = false;
  int? _dailySeed;
  int _lastMatchMs = -kComboWindowMs * 2;

  /// Last published state (readable while disposing).
  GameViewState? _latest;

  /// Engine events of this board, for the board's animations. Delivered
  /// synchronously, right after the state they belong to is published.
  Stream<GameEvent> get events => _events.stream;

  /// Board clock in ms (the timer pill polls this; it only changes while running).
  int get elapsedMs => _clock.elapsedMs;
  bool get clockRunning => _clock.isRunning;

  @override
  bool updateShouldNotify(GameViewState previous, GameViewState next) {
    _latest = next;
    return !identical(previous, next);
  }

  @override
  GameViewState build() {
    _clock = ref.read(gameClockFactoryProvider)();
    _repo = ref.read(progressRepositoryProvider);
    _analytics = ref.read(analyticsProvider);
    _audio = ref.read(audioProvider);
    _haptics = ref.read(hapticsProvider);
    _ads = ref.read(adServiceProvider);
    _keepAlive = ref.keepAlive();
    _lifecycle = AppLifecycleListener(onStateChange: handleLifecycle);
    ref.onDispose(_dispose);
    Future.microtask(_load);
    return GameViewState(launch: launch);
  }

  // ---------------------------------------------------------------- loading

  Future<void> _load() async {
    try {
      final catalogue = await _readFuture(catalogueProvider.future);
      final LayoutInfo info;
      String? dailyDate;
      var dailyCleared = false;
      if (launch.daily) {
        final daily = await _readFuture(dailyProvider.future);
        info = catalogue.layout(daily.layoutId);
        dailyDate = daily.date;
        _dailySeed = daily.seed;
        dailyCleared = daily.clearedToday;
      } else {
        info = catalogue.layout(launch.layoutId);
      }
      final chapterName = catalogue.chapters.where((c) => c.id == info.chapterId).firstOrNull?.name ?? '';

      GameState? game;
      var elapsed = 0;
      if (launch.seed == null && !(launch.daily && dailyCleared)) {
        final saved = await _repo.loadSavedGame(info.id);
        if (saved != null) {
          try {
            final g = GameState.fromJson(info.layout, saved.stateJson);
            if (!g.isCleared && (!launch.daily || g.seed == _dailySeed)) {
              game = g;
              elapsed = saved.elapsedMs;
            }
          } on FormatException catch (e) {
            debugPrint('game: discarding saved board for ${info.id}: $e');
          }
        }
      }
      final resumed = game != null;
      game ??= await ref.read(gameDealerProvider)(info.layout, _newSeed(), info.parMs);
      if (!ref.mounted) return;

      final bonus = ref.read(headStartBonusProvider.notifier).take();
      if (bonus > 0) game = cmd.grantHint(game, count: bonus).$1;

      _clock.reset(elapsed);
      state = state.copyWith(
        phase: GamePhase.playing,
        info: info,
        chapterName: chapterName,
        game: game,
        dealId: 1,
        resumed: resumed,
        dailyDate: dailyDate,
      );
      _log(AnalyticsEvents.layoutStart, {'layout_id': info.id, 'daily': launch.daily ? 1 : 0, 'resumed': resumed ? 1 : 0});
      if (launch.daily) _log(AnalyticsEvents.dailyStart, {'layout_id': info.id});
      _syncClock();
      _ads.onBoardStarted(); // a late interstitial for the previous clear must not land on this board
      if (game.isDeadlocked) _emit(const [Deadlock()], source: _Source.system);
    } catch (e, st) {
      debugPrint('game: failed to load $launch: $e\n$st');
      if (!ref.mounted) return;
      state = state.copyWith(phase: GamePhase.failed, error: e);
    }
  }

  /// Awaits a provider's future while listening to it, so a stream provider
  /// is not paused for lack of listeners (Riverpod 3).
  Future<T> _readFuture<T>(ProviderListenable<Future<T>> future) async {
    final sub = ref.listen(future, (_, _) {});
    try {
      return await sub.read();
    } finally {
      sub.close();
    }
  }

  int _newSeed() => launch.seed ?? (launch.daily ? _dailySeed! : ref.read(gameSeedSourceProvider)());

  // ------------------------------------------------------------- commands

  bool get _canPlay => state.phase == GamePhase.playing && !state.paused && state.busy == null && state.game != null;

  /// A tap on board position [pos]. Any tap clears a showing hint.
  void tap(int pos) {
    if (!_canPlay) return;
    final (next, events) = cmd.select(state.game!, pos, elapsedMs: _clock.elapsedMs);
    _apply(next, events, source: _Source.tap, clearHint: true);
  }

  /// Hint button. Shows a free hint when one is left; otherwise returns what
  /// the screen should offer instead ([HintAvailability.noMoves]: the free
  /// shuffle, never an ad; [HintAvailability.needsReward]: the video offer).
  HintAvailability useHint() {
    if (!_canPlay) return HintAvailability.none;
    final availability = state.hintAvailability;
    if (availability == HintAvailability.free) _applyHint(rewarded: false);
    return availability;
  }

  /// Plays a rewarded video for a hint. Only when a matching pair exists
  /// (otherwise the reward could not resolve); the hint is granted only if
  /// the ad reports the reward. Returns whether a hint was shown.
  Future<bool> watchAdForHint() async {
    if (!_canPlay || state.hintAvailability != HintAvailability.needsReward) return false;
    final rewarded = await _playRewarded(RewardBusy.hint, RewardedPlacement.hint);
    if (!rewarded || !ref.mounted || state.game == null || state.game!.availableMoves.isEmpty) return false;
    state = state.copyWith(game: cmd.grantHint(state.game!).$1);
    _applyHint(rewarded: true);
    return true;
  }

  void _applyHint({required bool rewarded}) {
    final (next, events) = cmd.hint(state.game!);
    _apply(next, events, source: _Source.system);
    final shown = events.whereType<HintShown>().firstOrNull;
    if (shown != null) {
      _log(AnalyticsEvents.hintUsed, {'layout_id': state.info!.id, 'kind': rewarded ? 'rewarded' : 'free'});
    }
  }

  void undo() {
    if (!_canPlay) return;
    final (next, events) = cmd.undo(state.game!);
    if (identical(next, state.game)) return;
    _lastMatchMs = -kComboWindowMs * 2;
    _apply(next, events, source: _Source.system, clearHint: true, combo: 0);
    _log(AnalyticsEvents.undoUsed, {'layout_id': state.info!.id});
  }

  /// Uses a free shuffle credit (after the confirm dialog). False when none
  /// is left or the board admits no shuffle.
  bool shuffleWithCredit() => _shuffle(free: false, rewarded: false);

  /// The always-free shuffle from the "No moves" sheet.
  bool shuffleFromDeadlock() => _shuffle(free: true, rewarded: false);

  /// Plays a rewarded video for a shuffle (after the free ones are spent).
  Future<bool> watchAdForShuffle() async {
    if (!_canPlay || state.shuffleAvailability != ShuffleAvailability.needsReward) return false;
    final rewarded = await _playRewarded(RewardBusy.shuffle, RewardedPlacement.shuffle);
    if (!rewarded || !ref.mounted) return false;
    return _shuffle(free: false, rewarded: true);
  }

  bool _shuffle({required bool free, required bool rewarded}) {
    if (!_canPlay) return false;
    final (next, events) = cmd.shuffle(state.game!, free: free, rewarded: rewarded, elapsedMs: _clock.elapsedMs);
    if (identical(next, state.game)) {
      _emit(events, source: _Source.system);
      return false;
    }
    _apply(next, events, source: _Source.system, clearHint: true);
    final kind = free ? 'deadlock' : (rewarded ? 'rewarded' : 'free');
    _log(AnalyticsEvents.shuffleUsed, {'layout_id': state.info!.id, 'kind': kind});
    return true;
  }

  // ------------------------------------------------- autoplay (QA, demo mode)

  bool _autoplaying = false;

  /// DEBUG AND PROFILE BUILDS ONLY (never release): plays the board to the
  /// end through the normal [tap] path (real move log, timing, animations,
  /// audio and haptics), so a full board can be checked on a device and its
  /// frame rate measured (docs/PERFORMANCE.md).
  ///
  /// The solver runs on a background isolate, once per board and again only
  /// after a shuffle, so the autoplay itself never costs a UI frame. With
  /// [extras], it also uses a hint every 7th pair, undoes and replays every
  /// 11th pair and shuffles once a third of the way in, so those animations
  /// are measured too.
  Future<void> demoPlay({
    Duration perTap = const Duration(milliseconds: 260),
    bool extras = true,
  }) async {
    if (kReleaseMode || _autoplaying) return;
    _autoplaying = true;
    try {
      var plan = await _solveInBackground();
      var played = 0;
      var shuffled = false;
      while (plan != null && plan.isNotEmpty) {
        if (!await _waitPlayable()) return;
        final total = state.game!.remaining.length ~/ 2 + played;
        if (extras && !shuffled && played >= total ~/ 3 && state.shuffleAvailability == ShuffleAvailability.free) {
          shuffled = true;
          if (shuffleWithCredit()) {
            await Future<void>.delayed(perTap * 4); // shuffle animation
            plan = await _solveInBackground();
            continue;
          }
        }
        final (a, b) = plan.removeAt(0);
        if (extras && played > 0 && played % 7 == 0 && state.hintAvailability == HintAvailability.free) {
          useHint();
          await Future<void>.delayed(perTap * 3); // hint glow
          if (!await _waitPlayable()) return;
        }
        final g = state.game!;
        if (g.selected != null) tap(g.selected!); // clear a stray selection
        tap(a);
        await Future<void>.delayed(perTap);
        if (!await _waitPlayable()) return;
        tap(b);
        played++;
        await Future<void>.delayed(perTap * 2);
        if (extras && played % 11 == 0 && state.game!.remaining.length > 0 && _canPlay) {
          undo(); // the pair comes back; play it again
          await Future<void>.delayed(perTap * 2);
          if (!await _waitPlayable()) return;
          tap(a);
          await Future<void>.delayed(perTap);
          if (!await _waitPlayable()) return;
          tap(b);
          await Future<void>.delayed(perTap * 2);
        }
      }
    } finally {
      _autoplaying = false;
    }
  }

  /// Back-compat name for the long-press-the-timer QA autoplay.
  Future<void> debugAutoplay() => demoPlay(extras: false, perTap: const Duration(milliseconds: 220));

  /// Waits (up to 5 s) for a board that takes taps, e.g. after a modal.
  Future<bool> _waitPlayable() async {
    for (var i = 0; i < 50; i++) {
      if (!ref.mounted) return false;
      if (_canPlay) return true;
      if (state.phase != GamePhase.playing) return false;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  Future<List<(int, int)>?> _solveInBackground() async {
    final g = state.game;
    if (g == null) return null;
    final layout = g.layout, faces = Int8List.fromList(g.faces), remaining = g.remaining;
    final r = await Isolate.run(() => solve(layout, faces, remaining: remaining));
    if (r is! SolveSolvable || r.solution.isEmpty) {
      debugPrint('game: autoplay stopped ($r)');
      return null;
    }
    return [...r.solution];
  }

  // ------------------------------------------------------ second chance

  /// "Second chance" (docs/ARCHITECTURE.md §7): offered when the player comes
  /// back to a saved board and has already spent free hints or shuffles. At
  /// most once per layout per [kSecondChanceCooldown]; never with Remove ads.
  bool get canOfferSecondChance {
    final s = state;
    final g = s.game;
    if (!_canPlay || g == null || !s.resumed || _ads.adsRemoved) return false;
    if (g.freeHintsLeft > 0 && g.freeShufflesLeft > 0) return false;
    final last = ref.read(sharedPreferencesProvider).getInt(_secondChanceKey);
    return last == null || DateTime.now().millisecondsSinceEpoch - last >= kSecondChanceCooldown.inMilliseconds;
  }

  String get _secondChanceKey => 'second_chance_at_${state.info?.id}';

  /// Records that the offer was shown (whether or not the player watched).
  void markSecondChanceOffered() =>
      unawaited(ref.read(sharedPreferencesProvider).setInt(_secondChanceKey, DateTime.now().millisecondsSinceEpoch));

  /// Plays the rewarded interstitial; grants +1 hint and +1 shuffle only if
  /// the ad paid out.
  Future<bool> watchSecondChance() async {
    if (!_canPlay) return false;
    state = state.copyWith(busy: () => RewardBusy.secondChance);
    _syncClock();
    var rewarded = false;
    try {
      rewarded = await _ads.showRewardedInterstitial(RewardedInterstitialPlacement.secondChance);
    } catch (e) {
      debugPrint('game: second chance ad failed: $e');
    }
    if (!ref.mounted) return false;
    state = state.copyWith(busy: () => null);
    _syncClock();
    if (!rewarded || state.game == null) return false;
    final withHint = cmd.grantHint(state.game!).$1;
    state = state.copyWith(game: cmd.grantShuffle(withHint).$1);
    _log(AnalyticsEvents.secondChance, {'layout_id': state.info!.id});
    return true;
  }

  Future<bool> _playRewarded(RewardBusy busy, RewardedPlacement placement) async {
    state = state.copyWith(busy: () => busy);
    _syncClock();
    var rewarded = false;
    try {
      rewarded = await _ads.showRewarded(placement);
    } catch (e) {
      debugPrint('game: rewarded ad failed: $e');
    }
    if (!ref.mounted) return false;
    state = state.copyWith(busy: () => null);
    _syncClock();
    return rewarded;
  }

  /// Deals a fresh board (the daily re-deals the same seed). Spent credits
  /// reset with the board.
  Future<void> restart() async {
    final info = state.info;
    if (info == null || state.phase == GamePhase.loading) return;
    _saveTimer?.cancel();
    _clearHintTimer();
    _dirty = false;
    final game = await ref.read(gameDealerProvider)(info.layout, _newSeed(), info.parMs);
    if (!ref.mounted) return;
    unawaited(_guard(_repo.clearSavedGame(info.id)));
    _clock.reset();
    _lastMatchMs = -kComboWindowMs * 2;
    state = state.copyWith(
      phase: GamePhase.playing,
      game: game,
      dealId: state.dealId + 1,
      pauseReason: () => null,
      hint: () => null,
      combo: 0,
      resumed: false,
    );
    _log(AnalyticsEvents.layoutStart, {'layout_id': info.id, 'daily': launch.daily ? 1 : 0, 'restart': 1});
    _syncClock();
  }

  // ----------------------------------------------------------- pause, exit

  void pause([PauseReason reason = PauseReason.user]) {
    if (state.phase != GamePhase.playing || state.paused) return;
    state = state.copyWith(pauseReason: () => reason, hint: () => null);
    _clearHintTimer();
    _syncClock();
    unawaited(_flushSave());
  }

  void resume() {
    if (!state.paused) return;
    state = state.copyWith(pauseReason: () => null);
    _syncClock();
  }

  /// Leaves the board: saves it for Resume, fires `board_abandon`, and
  /// releases the controller.
  Future<void> quit() async {
    if (state.phase == GamePhase.playing) {
      _logAbandon('quit');
      await _flushSave();
    }
    release();
  }

  /// Releases the keep-alive link so the controller disposes once the screen
  /// stops listening.
  void release() {
    _keepAlive?.close();
    _keepAlive = null;
  }

  /// App lifecycle (wired to an [AppLifecycleListener]; public for tests).
  void handleLifecycle(AppLifecycleState lifecycle) {
    switch (lifecycle) {
      case AppLifecycleState.resumed:
        _background = false;
        _inactive = false;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _inactive = true;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _inactive = true;
        // A full-screen rewarded ad also backgrounds the activity: not an abandon.
        if (!_background && state.busy == null) {
          _background = true;
          if (state.phase == GamePhase.playing && state.game != null) {
            _logAbandon('background');
            if (!state.paused) state = state.copyWith(pauseReason: () => PauseReason.background, hint: () => null);
            _clearHintTimer();
            unawaited(_flushSave());
          }
        }
    }
    if (ref.mounted) _syncClock();
  }

  void _logAbandon(String trigger) {
    final s = state;
    _log(AnalyticsEvents.boardAbandon, {
      'layout_id': s.info?.id ?? launch.layoutId,
      'daily': launch.daily ? 1 : 0,
      'tiles_left': s.tilesLeft,
      'time_ms': _clock.elapsedMs,
      'trigger': trigger,
    });
  }

  void _syncClock() {
    final s = state;
    final run = s.phase == GamePhase.playing && !s.paused && s.busy == null && !_background && !_inactive;
    if (run && !_clock.isRunning) {
      _clock.start();
    } else if (!run && _clock.isRunning) {
      _clock.stop();
    }
  }

  // ----------------------------------------------------- applying changes

  void _apply(GameState next, List<GameEvent> events, {required _Source source, bool clearHint = false, int? combo}) {
    final prev = state.game;
    var nextCombo = combo ?? state.combo;
    (int, int)? hintPair = clearHint ? null : state.hint;
    for (final e in events) {
      if (e is Matched) {
        final now = next.lastElapsedMs;
        nextCombo = now - _lastMatchMs <= kComboWindowMs ? nextCombo + 1 : 1;
        _lastMatchMs = now;
      } else if (e is HintShown) {
        hintPair = (e.a, e.b);
      }
    }
    if (clearHint && state.hint != null) _clearHintTimer();
    if (hintPair != null && hintPair != state.hint) _startHintTimer();
    state = state.copyWith(game: next, combo: nextCombo, hint: () => hintPair);
    _emit(events, source: source, combo: nextCombo);
    if (!identical(prev, next)) {
      _dirty = true;
      _scheduleSave();
    }
    final cleared = events.whereType<Cleared>().firstOrNull;
    if (cleared != null) unawaited(_onCleared(cleared.stats));
  }

  void _emit(List<GameEvent> events, {required _Source source, int combo = 0}) {
    final mismatch = events.any((e) => e is Mismatch);
    for (final e in events) {
      if (!_events.isClosed) _events.add(e);
      switch (e) {
        case Selected():
          if (!mismatch) _haptics.light();
          _audio.play(Sfx.select);
        case Deselected():
          if (source == _Source.tap) _audio.play(Sfx.deselect);
        case Matched():
          combo >= 5 ? _haptics.heavy() : _haptics.medium();
          _audio.play(Sfx.match);
        case Mismatch():
          _haptics.light();
          _audio.play(Sfx.mismatch);
        case Blocked():
          _haptics.selectionError();
          _audio.play(Sfx.blocked);
        case Shuffled():
          _audio.play(Sfx.shuffle);
        case Undone():
          _audio.play(Sfx.undo);
        case HintShown():
          _audio.play(Sfx.hint);
        case Deadlock():
          _log(AnalyticsEvents.deadlockShown, {'layout_id': state.info?.id ?? launch.layoutId, 'tiles_left': state.tilesLeft});
        case Cleared():
          _audio.play(Sfx.clear);
        case Rejected():
          break;
      }
    }
  }

  void _startHintTimer() {
    _hintTimer?.cancel();
    _hintTimer = Timer(kHintDuration, () {
      if (ref.mounted && state.hint != null) state = state.copyWith(hint: () => null);
    });
  }

  void _clearHintTimer() {
    _hintTimer?.cancel();
    _hintTimer = null;
  }

  // ------------------------------------------------------------- clearing

  Future<void> _onCleared(ClearStats stats) async {
    _saveTimer?.cancel();
    _dirty = false;
    _clearHintTimer();
    final s = state;
    final info = s.info!;
    final game = s.game!;
    state = s.copyWith(phase: GamePhase.cleared, hint: () => null);
    _syncClock();
    final stars = starsFor(
      timeMs: stats.elapsedMs,
      parMs: info.parMs,
      hintsUsed: stats.hintsUsed,
      rewardedShuffles: stats.rewardedShuffles,
    );
    final result = GameResult(
      layoutId: info.id,
      seed: game.seed,
      generatorVersion: game.generatorVersion,
      outcome: GameOutcome.cleared,
      timeMs: stats.elapsedMs,
      stars: stars,
      hintsUsed: stats.hintsUsed,
      undos: stats.undos,
      shufflesUsed: stats.shufflesUsed,
      tilesMatched: stats.tilesMatched,
      longestStreak: stats.longestStreak,
      playedAt: DateTime.now(),
      dailyDate: launch.daily ? s.dailyDate : null,
      moveLog: launch.daily ? encodeMoveLog(game.moveLog) : null,
    );
    RecordOutcome? outcome;
    try {
      outcome = await _repo.recordResult(result);
    } catch (e, st) {
      debugPrint('game: recordResult failed: $e\n$st');
    }
    final cleared = ClearedResult(
      layoutId: info.id,
      layoutName: info.name,
      chapterId: info.chapterId,
      chapterName: s.chapterName,
      tileCount: info.tileCount,
      isDaily: launch.daily,
      stats: stats,
      stars: stars,
      isNewBest: outcome?.isNewBest ?? false,
      previousBestMs: outcome?.previousBestMs,
      firstClear: (outcome?.progress.clears ?? 0) == 1,
      dailyDate: s.dailyDate,
    );
    if (!ref.mounted) return;
    ref.read(lastClearedProvider.notifier).set(cleared);
    state = state.copyWith(result: cleared);
    _log(AnalyticsEvents.boardCleared, {
      'layout_id': info.id,
      'daily': launch.daily ? 1 : 0,
      'time_ms': stats.elapsedMs,
      'hints': stats.hintsUsed,
      'undos': stats.undos,
      'shuffles': stats.shufflesUsed,
      'stars': stars,
    });
    _log(AnalyticsEvents.starsEarned, {'layout_id': info.id, 'stars': stars});
    if (launch.daily) _log(AnalyticsEvents.dailyComplete, {'layout_id': info.id, 'time_ms': stats.elapsedMs, 'stars': stars});
    ref.read(clearInterstitialShownProvider.notifier).set(false);
    unawaited(_guard(_ads.onBoardCleared(isDaily: launch.daily).then((shown) {
      if (ref.mounted) ref.read(clearInterstitialShownProvider.notifier).set(shown);
    })));
  }

  // ---------------------------------------------------------- persistence

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(kSaveDebounce, () => unawaited(_flushSave()));
  }

  /// Saves the board now (moves made and not cleared).
  Future<void> _flushSave() async {
    _saveTimer?.cancel();
    final s = state;
    final game = s.game;
    final info = s.info;
    if (game == null || info == null || s.phase != GamePhase.playing || game.moveLog.isEmpty) return;
    _dirty = false;
    await _guard(
      _repo.saveGame(
        info.id,
        stateJson: game.toJson(),
        elapsedMs: _clock.elapsedMs,
        fractionCleared: game.tilesMatched / game.layout.length,
      ),
    );
  }

  Future<void> _guard(Future<void> f) async {
    try {
      await f;
    } catch (e, st) {
      debugPrint('game: storage call failed: $e\n$st');
    }
  }

  void _log(String event, Map<String, Object> params) => unawaited(_guard(_analytics.log(event, params)));

  void _dispose() {
    final pending = _dirty || (_saveTimer?.isActive ?? false);
    _saveTimer?.cancel();
    _clearHintTimer();
    _lifecycle?.dispose();
    _clock.stop();
    final s = _latest;
    final game = s?.game;
    if (s != null && pending && game != null && s.info != null && s.phase == GamePhase.playing && game.moveLog.isNotEmpty) {
      unawaited(
        _guard(
          _repo.saveGame(
            s.info!.id,
            stateJson: game.toJson(),
            elapsedMs: _clock.elapsedMs,
            fractionCleared: game.tilesMatched / game.layout.length,
          ),
        ),
      );
    }
    unawaited(_events.close());
  }
}

/// What triggered a batch of events (audio differs for taps vs. side effects).
enum _Source { tap, system }
