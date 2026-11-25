import 'dart:async';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/settings.dart';
import '../../../engine/engine.dart';
import '../../../state/data_providers.dart';
import '../../../state/game/game_controller.dart';
import '../../../state/game/game_launch.dart';
import '../../../state/game/game_view_state.dart';
import '../../../state/platform_providers.dart';
import '../../board/board_view.dart';
import '../../board/tile/tile_face_spec.dart';
import '../../board/tile/tile_widget.dart';
import '../../components/components.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../router.dart';
import '../../theme/jw_background.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/widgets.dart';
import '../cleared/cleared_screen.dart' show kClearedHandoffMs;
import 'game_modals.dart';
import 'game_widgets.dart';

/// Game board (screens 03–09): top bar, counters, the board, the tool tray,
/// and the pause card, no-moves sheet, shuffle confirmation, hint toast and
/// rewarded offers.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.layoutId, this.daily = false});

  final String layoutId;

  /// Today's daily board (seed from the daily, ranked first clear).
  final bool daily;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  late final GameLaunch _launch = widget.daily ? const GameLaunch.daily() : GameLaunch.layout(widget.layoutId);
  late final GameController _controller;
  List<TileFaceSpec>? _faces;
  StreamSubscription<GameEvent>? _sub;
  bool _modalOpen = false;
  bool _leaving = false;
  bool _handoffReady = false;
  GameToast? _toast;
  Timer? _toastTimer;
  final List<Timer> _timers = [];

  NotifierProviderFamilyRef get _provider => gameControllerProvider(_launch);
  GameViewState get _state => ref.read(_provider);

  @override
  void initState() {
    super.initState();
    _controller = ref.read(_provider.notifier);
    _sub = _controller.events.listen(_onEvent);
    unawaited(
      TileFaceSpec.load().then((faces) {
        if (mounted) setState(() => _faces = faces);
      }),
    );
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _toastTimer?.cancel();
    for (final t in _timers) {
      t.cancel();
    }
    _controller.release();
    super.dispose();
  }

  void _after(Duration d, VoidCallback f) {
    late Timer t;
    t = Timer(d, () {
      _timers.remove(t);
      if (mounted) f();
    });
    _timers.add(t);
  }

  // --------------------------------------------------------------- events

  void _onEvent(GameEvent e) {
    switch (e) {
      case Deadlock():
        // Let the match exit play before the sheet rises.
        _after(const Duration(milliseconds: 650), () {
          final s = _state;
          if (s.deadlocked && !s.paused && !_modalOpen) unawaited(_showNoMoves());
        });
      case Cleared():
        final reduce = JwReduceMotion.of(context);
        // Last pair exit (800 ms) → t0; hand over to the cleared screen a
        // little into the beat sheet (it continues from the same t).
        final handoff = reduce
            ? const Duration(milliseconds: 350)
            : Duration(milliseconds: 800 + kClearedHandoffMs);
        _after(handoff, () {
          _handoffReady = true;
          _maybeShowCleared();
        });
      default:
        break;
    }
  }

  void _maybeShowCleared() {
    final result = _state.result;
    if (!_handoffReady || result == null || _leaving) return;
    _leaving = true;
    context.go(AppRoutes.cleared(result.layoutId));
  }

  void _showToast(String message, {String icon = JwIcons.info, JwFill fill = JwFill.sky}) {
    _toastTimer?.cancel();
    setState(() => _toast = (message: message, icon: icon, fill: fill));
    _toastTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  // -------------------------------------------------------------- actions

  Future<T?> _modal<T>(Widget Function(BuildContext) builder, {bool bottom = false, bool dismissible = true}) async {
    _modalOpen = true;
    try {
      return await showGameModal<T>(context, builder: builder, bottom: bottom, dismissible: dismissible);
    } finally {
      _modalOpen = false;
    }
  }

  bool _secondChanceChecked = false;

  /// Offers "Second chance" once, after the board-entry animation settles.
  void _maybeOfferSecondChance() {
    if (_secondChanceChecked) return;
    _secondChanceChecked = true;
    Future<void>.delayed(const Duration(milliseconds: 2200), () async {
      if (!mounted || _modalOpen || _leaving || !_controller.canOfferSecondChance) return;
      _controller.markSecondChanceOffered();
      final l = AppLocalizations.of(context);
      final granted = await _modal<bool>(
        (ctx) => RewardedIntroSheet(
          title: l.gameSecondChanceTitle,
          body: l.gameSecondChanceBody,
          icon: JwIcons.sparkle,
          watch: _controller.watchSecondChance,
        ),
        bottom: true,
      );
      if ((granted ?? false) && mounted) _showToast(l.gameSecondChanceGranted, icon: JwIcons.sparkle, fill: JwFill.yellow);
    });
  }

  Future<void> _showPause() async {
    final s = _state;
    if (s.phase != GamePhase.playing || _modalOpen || _leaving) return;
    _controller.pause(s.pauseReason ?? PauseReason.user);
    final l = AppLocalizations.of(context);
    final chapter = s.isDaily ? l.gameDailyChapter : s.chapterName;
    final action = await _modal<PauseAction>(
      (_) => PausedCard(
        time: formatClock(_controller.elapsedMs),
        meta: l.gamePausedMeta(s.layoutName, chapter, s.tilesLeft),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case PauseAction.restart:
        await _controller.restart();
      case PauseAction.settings:
        await context.push(AppRoutes.settings);
        if (mounted) await _showPause();
      case PauseAction.quit:
        await _quit();
      case PauseAction.resume || null:
        _controller.resume();
    }
  }

  Future<void> _onBack() async {
    if (_leaving || _modalOpen) return;
    final s = _state;
    if (s.phase != GamePhase.playing) {
      if (s.phase != GamePhase.cleared) await _quit();
      return;
    }
    _controller.pause();
    final leave = await _modal<bool>((_) => const QuitDialog());
    if (!mounted) return;
    if (leave ?? false) {
      await _quit();
    } else {
      _controller.resume();
    }
  }

  Future<void> _quit() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await _controller.quit();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  void _onHint() {
    switch (_controller.useHint()) {
      case HintAvailability.noMoves:
        unawaited(_showNoMoves());
      case HintAvailability.needsReward:
        final l = AppLocalizations.of(context);
        unawaited(_offerReward(l.gameRewardHintTitle, l.gameRewardHintBody, _controller.watchAdForHint, icon: JwIcons.hint));
      case HintAvailability.free || HintAvailability.none:
        break;
    }
  }

  Future<void> _onShuffle() async {
    final s = _state;
    if (s.phase != GamePhase.playing || s.paused) return;
    final l = AppLocalizations.of(context);
    switch (s.shuffleAvailability) {
      case ShuffleAvailability.deadlockFree:
        await _showNoMoves();
      case ShuffleAvailability.free:
        final ok = await _modal<bool>((_) => ShuffleConfirmDialog(tilesLeft: s.tilesLeft, freeLeft: s.freeShufflesLeft));
        if ((ok ?? false) && mounted && !_controller.shuffleWithCredit()) _showToast(l.gameShuffleFailed, icon: JwIcons.shuffle, fill: JwFill.pink);
      case ShuffleAvailability.needsReward:
        await _offerReward(
          l.gameRewardShuffleTitle,
          l.gameRewardShuffleBody,
          _controller.watchAdForShuffle,
          icon: JwIcons.shuffle,
          fill: JwFill.pink,
        );
      case ShuffleAvailability.none:
        break;
    }
  }

  Future<void> _offerReward(
    String title,
    String body,
    Future<bool> Function() watch, {
    String icon = JwIcons.video,
    JwFill fill = JwFill.yellow,
  }) async {
    final l = AppLocalizations.of(context);
    final granted = await _modal<bool>(
      (_) => RewardOfferSheet(title: title, body: body, watch: watch, icon: icon, fill: fill),
      bottom: true,
    );
    if (granted == false && mounted) _showToast(l.gameRewardUnavailable, icon: JwIcons.video, fill: JwFill.yellow);
  }

  Future<void> _showNoMoves() async {
    final s = _state;
    if (_modalOpen || s.phase != GamePhase.playing) return;
    final l = AppLocalizations.of(context);
    final action = await _modal<NoMovesAction>(
      (_) => NoMovesSheet(tilesLeft: s.tilesLeft, canUndo: s.canUndo),
      bottom: true,
    );
    if (!mounted) return;
    switch (action) {
      case NoMovesAction.shuffle:
        if (!_controller.shuffleFromDeadlock()) _showToast(l.gameShuffleFailed, icon: JwIcons.shuffle, fill: JwFill.pink);
      case NoMovesAction.undo:
        _controller.undo();
      case NoMovesAction.restart:
        await _controller.restart();
      case null:
        break;
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    ref.listen(_provider.select((s) => s.pauseReason), (prev, next) {
      if (next == PauseReason.background && !_modalOpen) unawaited(_showPause());
    });
    ref.listen(_provider.select((s) => s.result), (prev, next) {
      if (next != null) _maybeShowCleared();
    });
    // Once per screen (guarded); schedules the offer after entry settles.
    if (ref.watch(_provider.select((s) => s.phase == GamePhase.playing && s.resumed))) _maybeOfferSecondChance();
    final jw = context.jw;
    final phase = ref.watch(_provider.select((s) => s.phase));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_onBack());
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: jw.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Material(
          type: MaterialType.transparency,
          child: ColoredBox(
            color: jw.surface,
            child: JwBackground(
              blobs: PopBlobs.board,
              child: DefaultTextStyle(
                style: jw.text.body,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      _TopBar(
                        provider: _provider,
                        controller: _controller,
                        onBack: () => unawaited(_onBack()),
                        onPause: () => unawaited(_showPause()),
                      ),
                      const SizedBox(height: 8),
                      _CountersRow(provider: _provider, toast: _toast),
                      const SizedBox(height: 6),
                      Expanded(
                        child: phase == GamePhase.failed
                            ? _Failed(onBack: () => unawaited(_quit()))
                            : _BoardArea(
                                provider: _provider,
                                controller: _controller,
                                faces: _faces,
                              ),
                      ),
                      _Tray(
                        provider: _provider,
                        onHint: _onHint,
                        onUndo: _controller.undo,
                        onShuffle: () => unawaited(_onShuffle()),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef NotifierProviderFamilyRef = NotifierProvider<GameController, GameViewState>;

/// A transient message in the counters row with its leading badge.
typedef GameToast = ({String message, String icon, JwFill fill});

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.provider, required this.controller, required this.onBack, required this.onPause});

  final NotifierProviderFamilyRef provider;
  final GameController controller;
  final VoidCallback onBack;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final (name, chapter, daily, running, playing) = ref.watch(
      provider.select(
        (s) => (
          s.layoutName,
          s.chapterName,
          s.isDaily,
          s.phase == GamePhase.playing && !s.paused && s.busy == null,
          s.phase == GamePhase.playing,
        ),
      ),
    );
    final showTimer = ref.watch(settingsProvider.select((s) => s.value?.showTimer ?? true));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ConstrainedBox(
        // 46 tall; grows with large text instead of clipping the subtitle.
        constraints: const BoxConstraints(minHeight: 46),
        child: Row(
          children: [
            JwIconButton(icon: JwIcons.back, semanticLabel: l.navBack, onPressed: onBack),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jw.text.title.copyWith(fontSize: 23, height: 1.04)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      // Purple dot before "Chapter · Difficulty" (screen 03).
                      DecoratedBox(
                        decoration: BoxDecoration(color: JwFill.purple.mid, shape: BoxShape.circle),
                        child: const SizedBox.square(dimension: 8),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          daily ? l.gameDailyChapter : chapter,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: jw.text.callout.copyWith(fontSize: 15, height: 1.2, fontWeight: FontWeight.w500, color: jw.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (showTimer)
              GestureDetector(
                // Debug and profile builds only: long-press the timer to autoplay the
                // solution (QA for full boards and daily verification).
                onLongPress: !kReleaseMode && playing ? () => unawaited(controller.debugAutoplay()) : null,
                child: GameTimerPill(
                  elapsedMs: () => controller.elapsedMs,
                  running: running,
                  onTap: playing ? onPause : null,
                  semanticLabel: l.gamePauseSemantics,
                ),
              )
            else
              JwIconButton(icon: JwIcons.pause, semanticLabel: l.gameTimerHidden, color: jw.accent, onPressed: playing ? onPause : null),
          ],
        ),
      ),
    );
  }
}

class _CountersRow extends ConsumerWidget {
  const _CountersRow({required this.provider, required this.toast});

  final NotifierProviderFamilyRef provider;
  final GameToast? toast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final reduce = JwReduceMotion.of(context);
    final (tiles, pairs, hint, freeHints, combo, phase, paused, coaching) = ref.watch(
      provider.select((s) => (s.tilesLeft, s.pairsOpen, s.hint, s.freeHintsLeft, s.combo, s.phase, s.paused, s.coach != null)),
    );
    final Widget content;
    if (phase == GamePhase.loading || phase == GamePhase.failed) {
      content = const SizedBox(key: ValueKey('empty'), height: CounterChip.height);
    } else if (toast case final t?) {
      content = Padding(
        key: ValueKey('toast:${t.message}'),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: JwToast(message: t.message, icon: t.icon, fill: t.fill),
      );
    } else if (hint != null) {
      content = Padding(
        key: const ValueKey('hint'),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: JwToast(
          message: freeHints > 0 ? l.gameHintToast(freeHints) : l.gameHintToastRewarded,
          icon: JwIcons.hint,
          fill: JwFill.yellow,
        ),
      );
    } else if (coaching && !paused) {
      // First-move coach (starter board, first board ever): one line until
      // the first match; the pair it means glows on the board.
      content = Padding(
        key: const ValueKey('coach'),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: JwToast(message: l.gameCoachTip, icon: JwIcons.hint, fill: JwFill.mint),
      );
    } else {
      // Three chips (tiles, pairs, streak) can be wider than a phone: shrink
      // the row to fit inside the side margins instead of running off-screen.
      content = Padding(
        key: const ValueKey('chips'),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GameCounterChip(value: '$tiles', label: l.gameTilesLabel, icon: JwIcons.tile, fill: JwFill.mint),
              const SizedBox(width: 10),
              GameCounterChip(
                value: paused ? '–' : '$pairs',
                label: l.gamePairsOpenLabel(paused ? 0 : pairs),
                icon: JwIcons.pairs,
                fill: JwFill.pink,
              ),
              _ComboChip(combo: combo),
            ],
          ),
        ),
      );
    }
    return AnimatedOpacity(
      opacity: phase == GamePhase.cleared ? 0 : 1,
      duration: reduce ? Duration.zero : const Duration(milliseconds: 500),
      curve: JwMotion.standard,
      child: SizedBox(
        // The chip plus room for the toast's float shadow.
        height: 44,
        child: Center(
          child: AnimatedSwitcher(
            duration: reduce ? JwMotion.instant : JwMotion.quick,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// "×3 streak" chip (MOTION_SPEC §4): pops in at three quick matches
/// (450 ms springPop), grows 6 % per further match, fades out after 4 s idle.
class _ComboChip extends StatefulWidget {
  const _ComboChip({required this.combo});

  final int combo;

  @override
  State<_ComboChip> createState() => _ComboChipState();
}

class _ComboChipState extends State<_ComboChip> with TickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  Timer? _idle;
  int _shown = 0;

  bool _initialised = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialised) {
      _initialised = true;
      if (widget.combo >= 3) _show();
    }
  }

  @override
  void didUpdateWidget(_ComboChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.combo != oldWidget.combo) {
      if (widget.combo >= 3) {
        _show();
      } else if (_shown > 0) {
        unawaited(_fade.reverse());
      }
    }
  }

  void _show() {
    _shown = widget.combo;
    _fade.value = 1;
    if (JwReduceMotion.of(context)) {
      _pop.value = 1;
    } else {
      _pop.forward(from: 0);
    }
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 4), () {
      if (mounted) unawaited(_fade.reverse());
    });
  }

  @override
  void dispose() {
    _idle?.cancel();
    _pop.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([_pop, _fade]),
      builder: (context, _) {
        if (_fade.value == 0 || _shown < 3) return const SizedBox.shrink();
        // Grows a little per further match (MOTION_SPEC: 6 % steps), capped at
        // 1.12× so the scaled chip stays inside the counters row.
        final grow = 1 + (_shown - 3).clamp(0, 2) * 0.06;
        final pop = 0.4 + 0.6 * JwMotion.springPop.transform(_pop.value);
        return Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Opacity(
            opacity: _fade.value,
            child: Transform.translate(
              offset: Offset(0, -6 * (1 - _fade.value)),
              child: Transform.scale(
                scale: pop * grow * (0.9 + 0.1 * _fade.value),
                // Screen 03 shows the coral chip with the value only.
                child: GameCounterChip(
                  value: l.gameStreakValue(_shown),
                  icon: JwIcons.flame,
                  fill: JwFill.coral,
                  semanticLabel: '${l.gameStreakValue(_shown)} ${l.gameStreakLabel}',
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BoardArea extends ConsumerWidget {
  const _BoardArea({required this.provider, required this.controller, required this.faces});

  final NotifierProviderFamilyRef provider;
  final GameController controller;
  final List<TileFaceSpec>? faces;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (game, dealId, hint, paused) = ref.watch(provider.select((s) => (s.game, s.dealId, s.hint ?? s.coach, s.paused)));
    final tileSize = ref.watch(settingsProvider.select((s) => s.value?.tileSize ?? TileSizePreference.medium));
    if (game == null || faces == null) return const SizedBox.expand();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: BoardView(
        game: game,
        faces: faces!,
        events: controller.events,
        dealId: dealId,
        hint: hint,
        faceDown: paused,
        faceSize: switch (tileSize) {
          TileSizePreference.small => TileFaceSize.small,
          TileSizePreference.medium => TileFaceSize.medium,
          TileSizePreference.large => TileFaceSize.large,
        },
        onTileTap: controller.tap,
      ),
    );
  }
}

class _Tray extends ConsumerWidget {
  const _Tray({required this.provider, required this.onHint, required this.onUndo, required this.onShuffle});

  final NotifierProviderFamilyRef provider;
  final VoidCallback onHint;
  final VoidCallback onUndo;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    void haptic() => ref.read(hapticsProvider).selection();
    final (freeHints, canUndo, playing, hinting) = ref.watch(
      provider.select((s) => (s.freeHintsLeft, s.canUndo, s.phase == GamePhase.playing && !s.paused, s.hint != null)),
    );
    return JwTray(
      children: [
        FillKnob(
          icon: JwIcons.hint,
          label: l.gameToolHint,
          fill: JwFill.yellow,
          badge: freeHints > 0 ? freeHints : null,
          // Stays pressed while the suggested pair glows (screen 06).
          held: hinting,
          onPressed: playing ? onHint : null,
          onHaptic: haptic,
        ),
        FillKnob(
          icon: JwIcons.undo,
          label: l.gameToolUndo,
          fill: JwFill.sky,
          onPressed: playing && canUndo ? onUndo : null,
          onHaptic: haptic,
        ),
        FillKnob(
          icon: JwIcons.shuffle,
          label: l.gameToolShuffle,
          fill: JwFill.pink,
          onPressed: playing ? onShuffle : null,
          onHaptic: haptic,
        ),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.gameLoadFailed, textAlign: TextAlign.center, style: jw.text.h3),
            const SizedBox(height: 20),
            JwButton.secondary(label: l.gameBackToCollection, onPressed: onBack),
          ],
        ),
      ),
    );
  }
}
