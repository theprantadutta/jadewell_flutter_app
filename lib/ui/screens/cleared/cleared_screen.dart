import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/catalogue.dart';
import '../../../data/models/progress.dart';
import '../../../data/models/unlocks.dart';
import '../../../platform/ads/ad_service.dart';
import '../../../platform/audio/audio_service.dart';
import '../../../state/data_providers.dart';
import '../../../state/game/game_controller.dart' show kHeadStartHints;
import '../../../state/game/game_providers.dart';
import '../../../state/game/game_view_state.dart';
import '../../../state/platform_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../router.dart';
import '../../theme/clay.dart';
import '../../theme/jw_background.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/widgets.dart';
import '../game/game_widgets.dart';

/// Beat-sheet time (MOTION_SPEC §3, t0 = last pair gone) at which the game
/// screen hands over to this screen; the timeline continues from here.
const kClearedHandoffMs = 500;

/// Beat times (ms after t0).
abstract final class ClearedBeats {
  static const medal = 800, title = 1050, time = 1250, best = 2500, stats = 2900, progress = 3400, actions = 3950;
  static const end = actions + 600;

  /// Taps after this skip to the final state.
  static const skipAfter = 1250;
}

/// Board cleared (screen 10) with the full beat sheet, plus three star beads
/// that drop in with the medal and the optional "Head start" offer.
class ClearedScreen extends ConsumerStatefulWidget {
  const ClearedScreen({super.key, required this.layoutId});

  final String layoutId;

  @override
  ConsumerState<ClearedScreen> createState() => _ClearedScreenState();
}

class _ClearedScreenState extends ConsumerState<ClearedScreen> with TickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: ClearedBeats.end - kClearedHandoffMs),
  );
  AnimationController? _fadeIn;
  ClearedResult? _result;
  bool _hapticDone = false;
  int _starsPopped = 0;
  bool _headStartChecked = false;
  String? _toast;

  double get _t => kClearedHandoffMs + _beat.value * (ClearedBeats.end - kClearedHandoffMs);

  @override
  void initState() {
    super.initState();
    final r = ref.read(lastClearedProvider);
    if (r == null || r.layoutId != widget.layoutId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.home);
      });
      return;
    }
    _result = r;
    _beat.addListener(_onBeat);
    _beat.addStatusListener((s) {
      if (s == AnimationStatus.completed) _after(const Duration(milliseconds: 400), _maybeOfferHeadStart);
    });
  }

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || _result == null) return;
    _started = true;
    if (JwReduceMotion.of(context)) {
      _fadeIn = AnimationController(vsync: this, duration: const Duration(milliseconds: 200))..forward();
      _beat.value = 1;
      _hapticDone = true;
      _starsPopped = 3;
      ref.read(hapticsProvider).success();
      _after(const Duration(milliseconds: 600), _maybeOfferHeadStart);
    } else {
      unawaited(_beat.forward());
    }
  }

  final List<Timer> _timers = [];

  void _after(Duration d, VoidCallback f) {
    late Timer t;
    t = Timer(d, () {
      _timers.remove(t);
      if (mounted) f();
    });
    _timers.add(t);
  }

  void _onBeat() {
    final t = _t;
    if (!_hapticDone && t >= ClearedBeats.medal) {
      _hapticDone = true;
      ref.read(hapticsProvider).success();
    }
    final stars = _result?.stars ?? 0;
    while (_starsPopped < stars && t >= _starStart(_starsPopped) + 120) {
      _starsPopped++;
      ref.read(audioProvider).play(Sfx.star);
    }
  }

  static double _starStart(int i) => ClearedBeats.medal + 250 + i * 120.0;

  void _skip() {
    if (_beat.isAnimating && _t >= ClearedBeats.skipAfter) _beat.value = 1;
  }

  Future<void> _maybeOfferHeadStart() async {
    if (_headStartChecked || !mounted) return;
    _headStartChecked = true;
    final ads = ref.read(adServiceProvider);
    // Never stack a rewarded interstitial on top of an interstitial.
    if (ads.adsRemoved || ref.read(headStartBonusProvider) > 0 || ref.read(clearInterstitialShownProvider)) return;
    final granted = await showGameModal<bool>(
      context,
      bottom: true,
      builder: (_) => _HeadStartSheet(
        watch: () async {
          final ok = await ads.showRewardedInterstitial(RewardedInterstitialPlacement.headStart);
          if (ok) ref.read(headStartBonusProvider.notifier).grant(kHeadStartHints);
          return ok;
        },
      ),
    );
    if ((granted ?? false) && mounted) {
      setState(() => _toast = AppLocalizations.of(context).clearedHeadStartGranted);
      _after(const Duration(milliseconds: 2600), () => setState(() => _toast = null));
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _beat.dispose();
    _fadeIn?.dispose();
    super.dispose();
  }

  double _p(num start, num duration) => ((_t - start) / duration).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final r = _result;
    if (r == null) return ColoredBox(color: jw.surface, child: const JwBackground());
    final catalogue = ref.watch(catalogueProvider).value;
    final progress = ref.watch(progressProvider).value;

    Widget content = AnimatedBuilder(
      animation: _beat,
      builder: (context, _) => _content(context, r, catalogue, progress),
    );
    if (_fadeIn != null) content = FadeTransition(opacity: _fadeIn!, child: content);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: jw.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Material(
        type: MaterialType.transparency,
        child: ColoredBox(
          color: jw.surface,
          child: JwBackground(
            child: DefaultTextStyle(
              style: jw.text.body,
              child: SafeArea(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => _skip(),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, ClearedResult r, Catalogue? catalogue, Map<String, LayoutProgress>? progress) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final chapterName = r.isDaily ? l.gameDailyChapter : r.chapterName;

    // Chapter / collection progress (live from the repository).
    int? chapterCleared, chapterTotal, totalCleared, totalLayouts;
    LayoutInfo? next;
    var nextOpen = false;
    if (catalogue != null && progress != null && !r.isDaily) {
      final ch = catalogue.chapters.where((c) => c.id == r.chapterId).firstOrNull;
      if (ch != null) {
        chapterCleared = Unlocks.chapterClears(catalogue, ch.id, progress);
        chapterTotal = ch.layoutIds.length;
      }
      totalCleared = Unlocks.totalClears(catalogue, progress);
      totalLayouts = catalogue.chapterLayouts.length;
      next = catalogue.nextAfter(r.layoutId);
      if (next != null) nextOpen = !Unlocks.layout(catalogue, next.id, progress).locked;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final k = (constraints.maxHeight / 790).clamp(0.72, 1.0);
        double gap(double v) => v * k;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                children: [
                  SizedBox(height: gap(16)),
                  _topBar(context, r, chapterName),
                  SizedBox(height: gap(30)),
                  _medalAndStars(context, r, k),
                  SizedBox(height: gap(28)),
                  _fadeUp(
                    _p(ClearedBeats.title, 600),
                    Column(
                      children: [
                        Text(l.clearedTitle(r.layoutName), textAlign: TextAlign.center, style: jw.text.h2.copyWith(fontSize: 30)),
                        const SizedBox(height: 6),
                        Text(
                          l.clearedMeta(chapterName, r.tileCount),
                          textAlign: TextAlign.center,
                          style: jw.text.callout.copyWith(fontSize: 15, fontWeight: FontWeight.w400, color: jw.textMuted),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: gap(22)),
                  _timePill(context, r, k),
                  SizedBox(height: gap(16)),
                  _bestChip(context, r),
                  SizedBox(height: gap(22)),
                  _stats(context, r),
                  if (chapterCleared != null && chapterTotal != null) ...[
                    SizedBox(height: gap(26)),
                    _chapterProgress(context, r, chapterName, chapterCleared, chapterTotal, totalCleared, totalLayouts),
                  ],
                  SizedBox(height: gap(26)),
                  _actions(context, r, next, nextOpen),
                  SizedBox(height: gap(16)),
                  AnimatedSwitcher(
                    duration: JwMotion.quick,
                    child: _toast == null
                        ? const SizedBox(height: 40)
                        : JwToast(key: ValueKey(_toast), message: _toast!, beadColor: jw.accent),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fadeUp(double p, Widget child, {double distance = 14}) {
    final c = JwMotion.easeOutSoft.transform(p);
    return IgnorePointer(
      ignoring: p < 0.5,
      child: Opacity(
        opacity: c.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, distance * (1 - c)), child: child),
      ),
    );
  }

  Widget _topBar(BuildContext context, ClearedResult r, String chapterName) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          JwIconButton(icon: JwIcons.back, semanticLabel: l.navBack, onPressed: () => context.go(AppRoutes.home)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.layoutName, maxLines: 1, overflow: TextOverflow.ellipsis, style: jw.text.title.copyWith(fontSize: 25, height: 1.04)),
                Text(
                  chapterName,
                  maxLines: 1,
                  style: jw.text.callout.copyWith(fontSize: 15, height: 1.2, fontWeight: FontWeight.w400, color: jw.textMuted),
                ),
              ],
            ),
          ),
          Semantics(
            label: l.clearedTimeSemantics(formatClock(r.timeMs)),
            excludeSemantics: true,
            child: DecoratedBox(
              decoration: jw.clay(ClayLevel.raised, radius: 23),
              child: SizedBox(
                height: 46,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      JwIcon(JwIcons.clock, size: 18, color: jw.accent),
                      const SizedBox(width: 12),
                      Text(formatClock(r.timeMs), style: jw.text.numM.copyWith(fontSize: 19)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _medalAndStars(BuildContext context, ClearedResult r, double k) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    // Medal: drops 200 pt with a landing squash, 900 ms springSoft.
    final p = _p(ClearedBeats.medal, 900);
    final drop = JwMotion.springSoft.transform(p);
    final land = p < 0.55 ? 0.0 : math.sin(((p - 0.55) / 0.45) * math.pi);
    final medalOpacity = (p * 8).clamp(0.0, 1.0);
    final bead = JwMotion.springPop.transform(_p(ClearedBeats.medal + 500, 500));
    final medalW = 110 * k, medalH = 130 * k;
    final medal = Opacity(
      opacity: medalOpacity,
      child: Transform.translate(
        offset: Offset(0, -200 * (1 - drop)),
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.diagonal3Values(1 + 0.05 * land, 1 - 0.07 * land, 1),
          child: SizedBox(
            width: medalW,
            height: medalH + 10,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: medalW,
                  height: medalH,
                  child: DecoratedBox(
                    decoration: ClayDecoration(
                      level: ClayLevel.flat,
                      colors: jw.colors,
                      color: jw.tileFace,
                      radius: 30 * k,
                      extraShadows: [
                        ClayShadow.inset(3, 3, 5, 0, jw.highlight),
                        ClayShadow.inset(-5, -6, 10, 0, jw.inner),
                        ClayShadow(0, 10 * k, 0, 0, jw.tileEdge),
                        ClayShadow(0, 26, 36, -12, jw.shadow),
                      ],
                    ),
                    child: Center(
                      child: Transform.scale(
                        scale: bead,
                        child: SizedBox.square(
                          dimension: 62 * k,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              JwBead(color: jw.accent, size: 62 * k),
                              JwIcon(JwIcons.check, size: 26 * k, color: jw.onAccent),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final stars = Semantics(
      label: l.clearedStarsSemantics(r.stars),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) SizedBox(width: 10 * k),
            _starBead(context, i < r.stars, _p(_starStart(i), 500), k, lifted: i == 1),
          ],
        ],
      ),
    );

    return SizedBox(
      height: medalH + 10 + 22 * k,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          medal,
          Positioned(bottom: 0, child: stars),
        ],
      ),
    );
  }

  Widget _starBead(BuildContext context, bool earned, double p, double k, {bool lifted = false}) {
    final jw = context.jw;
    final c = JwMotion.springPop.transform(p);
    final size = (lifted ? 40.0 : 34.0) * k;
    final Widget bead = earned
        ? Stack(
            alignment: Alignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: jw.shadow, blurRadius: 8, offset: const Offset(0, 4), spreadRadius: -2)],
                ),
                child: JwBead(color: jw.accent, size: size),
              ),
              JwIcon(JwIcons.star, size: size * 0.5, color: jw.onAccent),
            ],
          )
        : DecoratedBox(
            decoration: jw.clay(ClayLevel.sunken),
            child: SizedBox.square(
              dimension: size,
              child: Center(child: JwIcon(JwIcons.star, size: size * 0.46, color: jw.textMuted.withValues(alpha: 0.55))),
            ),
          );
    return Opacity(
      opacity: p.clamp(0.0, 1.0) == 0 ? 0 : (p * 4).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, (lifted ? -6 : 0) - 24 * (1 - c)),
        child: Transform.scale(scale: 0.3 + 0.7 * c, child: SizedBox.square(dimension: size, child: bead)),
      ),
    );
  }

  Widget _timePill(BuildContext context, ClearedResult r, double k) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final appear = JwMotion.easeOutSoft.transform(_p(ClearedBeats.time, 300));
    final count = Curves.easeOutCubic.transform(_p(ClearedBeats.time, 1100));
    final shown = formatClock((r.timeMs * count).round());
    return Semantics(
      label: l.clearedTimeSemantics(formatClock(r.timeMs)),
      excludeSemantics: true,
      child: Opacity(
        opacity: appear,
        child: Transform.scale(
          scale: 0.92 + 0.08 * appear,
          child: DecoratedBox(
            decoration: jw.clay(ClayLevel.raised, radius: 38 * k),
            child: SizedBox(
              height: 76 * k,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32 * k),
                child: Center(
                  widthFactor: 1,
                  child: Text(shown, style: jw.text.numXl.copyWith(fontSize: 56 * k, height: 1)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bestChip(BuildContext context, ClearedResult r) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final p = _p(ClearedBeats.best, 500);
    final c = JwMotion.springPop.transform(p);
    final improvement = r.improvementMs;
    final List<Widget> parts;
    var accent = true;
    if (improvement != null) {
      parts = [
        Text('${l.clearedNewBest} · ', style: jw.text.callout.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500)),
        Text(l.clearedFaster(formatClock(improvement)), style: jw.text.callout.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500)),
      ];
    } else if (r.firstClear || r.isNewBest) {
      parts = [Text(l.clearedFirstClear, style: jw.text.callout.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500))];
    } else if (r.previousBestMs != null) {
      accent = false;
      parts = [
        Text(
          l.clearedBest(formatClock(r.previousBestMs!)),
          style: jw.text.callout.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500, color: jw.textMuted),
        ),
      ];
    } else {
      return const SizedBox(height: 30);
    }
    return Opacity(
      opacity: (p * 3).clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.4 + 0.6 * c,
        child: DecoratedBox(
          decoration: accent ? jw.clay(ClayLevel.flat, color: jw.accentSoft, radius: 15) : jw.clay(ClayLevel.chip, radius: 15),
          child: SizedBox(
            height: 30,
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (accent) ...[JwBead(color: jw.accent, size: 17), const SizedBox(width: 8)] else const SizedBox(width: 6),
                  ...parts,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stats(BuildContext context, ClearedResult r) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final count = JwMotion.easeOutSoft.transform(_p(ClearedBeats.stats, 600));
    final values = [r.stats.tilesMatched, r.stats.longestStreak, r.stats.hintsUsed];
    final labels = [l.clearedTilesMatched, l.clearedLongestStreak, l.clearedHintsUsed(r.stats.hintsUsed)];
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _fadeUp(
              _p(ClearedBeats.stats + i * 80, 600),
              Semantics(
                label: '${values[i]} ${labels[i]}',
                excludeSemantics: true,
                child: DecoratedBox(
                  decoration: jw.clay(ClayLevel.raised, radius: 22),
                  child: SizedBox(
                    height: 70,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${(values[i] * count).round()}', style: jw.text.numL.copyWith(fontSize: 22)),
                        const SizedBox(height: 2),
                        Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: jw.text.callout.copyWith(fontWeight: FontWeight.w400, color: jw.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _chapterProgress(
    BuildContext context,
    ClearedResult r,
    String chapterName,
    int cleared,
    int total,
    int? totalCleared,
    int? totalLayouts,
  ) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final popped = _t >= ClearedBeats.progress;
    final filled = popped || !r.firstClear ? cleared : math.max(0, cleared - 1);
    final allBefore = popped || !r.firstClear || totalCleared == null ? totalCleared : math.max(0, totalCleared - 1);
    return _fadeUp(
      _p(ClearedBeats.stats + 160, 600),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(chapterName, style: jw.text.button.copyWith(fontSize: 16.5))),
              Text(l.clearedChapterCount(filled, total), style: jw.text.numM.copyWith(fontSize: 16, color: jw.textMuted)),
            ],
          ),
          const SizedBox(height: 10),
          JwSegmentedProgress(segments: total, filled: filled, semanticLabel: chapterName),
          if (allBefore != null && totalLayouts != null) ...[
            const SizedBox(height: 10),
            Text(
              l.clearedLayoutsCleared(allBefore, totalLayouts),
              style: jw.text.callout.copyWith(fontWeight: FontWeight.w400, color: jw.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, ClearedResult r, LayoutInfo? next, bool nextOpen) {
    final l = AppLocalizations.of(context);
    void haptic() => ref.read(hapticsProvider).light();
    final Widget primary;
    final List<Widget> secondary;
    if (r.isDaily) {
      primary = JwButton.primary(
        label: l.clearedLeaderboard,
        icon: JwIcons.trophy,
        expand: true,
        onHaptic: haptic,
        onPressed: () => context.go(AppRoutes.leaderboard),
      );
      secondary = [
        JwButton.secondary(label: l.clearedReplay, icon: JwIcons.replay, expand: true, onPressed: () => context.go(AppRoutes.dailyPlay)),
        JwButton.secondary(label: l.clearedHome, icon: JwIcons.grid, expand: true, onPressed: () => context.go(AppRoutes.home)),
      ];
    } else if (next != null && nextOpen) {
      primary = _NextButton(
        name: next.name,
        tiles: next.tileCount,
        onPressed: () {
          haptic();
          context.go(AppRoutes.game(next.id));
        },
      );
      secondary = [
        JwButton.secondary(label: l.clearedReplay, icon: JwIcons.replay, expand: true, onPressed: () => context.go(AppRoutes.game(r.layoutId))),
        JwButton.secondary(label: l.clearedCollection, icon: JwIcons.grid, expand: true, onPressed: () => context.go(AppRoutes.home)),
      ];
    } else {
      primary = JwButton.primary(
        label: l.clearedCollection,
        icon: JwIcons.grid,
        expand: true,
        onHaptic: haptic,
        onPressed: () => context.go(AppRoutes.home),
      );
      secondary = [
        JwButton.secondary(label: l.clearedReplay, icon: JwIcons.replay, expand: true, onPressed: () => context.go(AppRoutes.game(r.layoutId))),
      ];
    }
    return _fadeUp(
      _p(ClearedBeats.actions, 600),
      Column(
        children: [
          SizedBox(height: 58, child: primary),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < secondary.length; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(child: secondary[i]),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// "Next: Bridge · 78 tiles →" primary button.
class _NextButton extends StatelessWidget {
  const _NextButton({required this.name, required this.tiles, required this.onPressed});

  final String name;
  final int tiles;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final deco = jw.clay(ClayLevel.primary);
    final label = l.clearedNext(name);
    final meta = l.clearedNextTiles(tiles);
    return ClayPressable(
      decoration: deco,
      pressedDecoration: deco.copyWith(level: ClayLevel.pressed),
      onTap: onPressed,
      semanticLabel: '$label $meta',
      height: 58,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: jw.text.button.copyWith(color: jw.onAccent, fontSize: 17)),
          ),
          const SizedBox(width: 8),
          Text(meta, style: jw.text.callout.copyWith(color: jw.onAccent.withValues(alpha: 0.75), fontWeight: FontWeight.w400)),
          const SizedBox(width: 12),
          JwIcon(JwIcons.arrow, size: 19, color: jw.onAccent),
        ],
      ),
    );
  }
}

/// "Head start" rewarded-interstitial intro: the reward is stated, a 5 s
/// countdown starts the video, Skip opts out (docs/ARCHITECTURE.md §7).
class _HeadStartSheet extends StatefulWidget {
  const _HeadStartSheet({required this.watch});

  final Future<bool> Function() watch;

  @override
  State<_HeadStartSheet> createState() => _HeadStartSheetState();
}

class _HeadStartSheetState extends State<_HeadStartSheet> {
  static const _countdown = 5;
  int _left = _countdown;
  Timer? _timer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 1) {
        t.cancel();
        unawaited(_watch());
      } else {
        setState(() => _left--);
      }
    });
  }

  Future<void> _watch() async {
    if (_loading) return;
    _timer?.cancel();
    setState(() => _loading = true);
    final ok = await widget.watch();
    if (mounted) Navigator.of(context).pop(ok);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    return JwSheet(
      semanticLabel: l.clearedHeadStartTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              const GameIconWell(icon: JwIcons.hint, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.clearedHeadStartTitle, style: jw.text.h3.copyWith(fontSize: 20)),
                    const SizedBox(height: 4),
                    Text(l.clearedHeadStartBody, style: jw.text.callout.copyWith(fontWeight: FontWeight.w400, color: jw.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: JwButton.secondary(
                  label: l.clearedHeadStartSkip,
                  expand: true,
                  onPressed: _loading ? null : () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _loading
                    ? SizedBox(
                        height: 56,
                        child: Center(
                          child: SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: jw.accent),
                          ),
                        ),
                      )
                    : JwButton.primary(
                        label: '${l.clearedHeadStartWatch} · $_left',
                        icon: JwIcons.video,
                        expand: true,
                        semanticLabel: '${l.clearedHeadStartWatch}, ${l.clearedHeadStartCountdown(_left)}',
                        onPressed: _watch,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
