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
import '../../../state/store_listing_controller.dart';
import '../../components/components.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../router.dart';
import '../../theme/clay.dart';
import '../../theme/jw_background.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/widgets.dart';
import '../game/game_modals.dart';
import '../game/game_widgets.dart';
import '../home/layout_labels.dart' show JwContentWidth;

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

/// Board cleared (screen 10) with the full beat sheet: the purple hero
/// scales in with a confetti burst and the medal, our 1–3 stars pop in under
/// the title, then time, best, stats, chapter progress and actions; then the
/// optional "Head start" offer.
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
    // A good clear may ask for a review (rare: ReviewPolicy). Never right
    // after an interstitial, and the head-start offer waits for another board.
    if (!ref.read(clearInterstitialShownProvider) &&
        await ref.read(reviewPrompterProvider).maybeAskAfterClear(stars: _result?.stars ?? 0)) {
      return;
    }
    if (!mounted) return;
    // Never stack a rewarded interstitial on top of an interstitial.
    if (ads.adsRemoved || ref.read(headStartBonusProvider) > 0 || ref.read(clearInterstitialShownProvider)) return;
    final granted = await showGameModal<bool>(
      context,
      bottom: true,
      builder: (ctx) => RewardedIntroSheet(
        title: AppLocalizations.of(ctx).clearedHeadStartTitle,
        body: AppLocalizations.of(ctx).clearedHeadStartBody,
        icon: JwIcons.hint,
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
                  child: Stack(
                    children: [
                      Positioned.fill(child: content),
                      // Top, so it never covers the actions.
                      Positioned(
                        left: 16,
                        right: 16,
                        top: 8,
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: JwMotion.quick,
                            child: _toast == null
                                ? const SizedBox.shrink()
                                : JwToast(key: ValueKey(_toast), message: _toast!, icon: JwIcons.hint, fill: JwFill.yellow),
                          ),
                        ),
                      ),
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

  Widget _content(BuildContext context, ClearedResult r, Catalogue? catalogue, Map<String, LayoutProgress>? progress) {
    final l = AppLocalizations.of(context);
    final chapterName = r.isDaily ? l.gameDailyChapter : r.chapterName;

    // Chapter progress (live from the repository).
    int? chapterCleared, chapterTotal;
    LayoutInfo? next;
    var nextOpen = false;
    if (catalogue != null && progress != null && !r.isDaily) {
      final ch = catalogue.chapters.where((c) => c.id == r.chapterId).firstOrNull;
      if (ch != null) {
        chapterCleared = Unlocks.chapterClears(catalogue, ch.id, progress);
        chapterTotal = ch.layoutIds.length;
      }
      // "Next" = the next open layout in collection order that isn't cleared
      // yet (skipping locked ones), else any open one; never this board.
      final all = catalogue.chapterLayouts.toList();
      final at = all.indexWhere((l) => l.id == r.layoutId);
      LayoutInfo? pick({required bool uncleared}) {
        for (var k = 1; k < all.length; k++) {
          final cand = all[(at + k) % all.length];
          if (Unlocks.layout(catalogue, cand.id, progress).locked) continue;
          if (uncleared && (progress[cand.id]?.cleared ?? false)) continue;
          return cand;
        }
        return null;
      }

      next = at < 0 ? null : (pick(uncleared: true) ?? pick(uncleared: false));
      nextOpen = next != null;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Screen 10 is ~825 pt tall at k = 1: ~375 pt of text and buttons
        // that never scale and ~450 pt of gaps, medal, stars and pill that do.
        // Shorter screens shrink the scalable part (to 0.7×); every block
        // still sizes to its content, and the page scrolls when even that
        // isn't enough (large text).
        // Tablets have room to spare: let the scalable part grow (to 1.3×)
        // so the page fills the screen instead of ending two-thirds down.
        final tablet = constraints.maxWidth >= 600;
        final k = ((constraints.maxHeight - 375) / 450).clamp(0.7, tablet ? 1.3 : 1.0);
        double v(double x) => x * k;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: JwContentWidth(
                maxWidth: 680,
                child: Column(
                  children: [
                    SizedBox(height: v(16)),
                    _topBar(context, r, chapterName),
                    SizedBox(height: v(14)),
                    _heroAndTime(context, r, k),
                    SizedBox(height: v(12)),
                    _bestChip(context, r, k),
                    SizedBox(height: v(16)),
                    _stats(context, r, k),
                    if (chapterCleared != null && chapterTotal != null) ...[
                      SizedBox(height: v(16)),
                      _chapterProgress(context, r, chapterName, chapterCleared, chapterTotal, k),
                    ],
                    SizedBox(height: v(20)),
                    _actions(context, r, next, nextOpen, k),
                    // Clear of the gesture bar (SafeArea adds the inset).
                    const SizedBox(height: 16),
                  ],
                ),
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 46),
      child: Row(
        children: [
          JwIconButton(icon: JwIcons.back, semanticLabel: l.navBack, onPressed: () => context.go(AppRoutes.home)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.layoutName, maxLines: 1, overflow: TextOverflow.ellipsis, style: jw.text.title.copyWith(fontSize: 23, height: 1.04)),
                const SizedBox(height: 3),
                Text(
                  chapterName,
                  maxLines: 1,
                  style: jw.text.callout.copyWith(fontSize: 15, height: 1.2, fontWeight: FontWeight.w500, color: jw.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The purple hero (medal, title, stars, meta, confetti) with the time
  /// pill overlapping its bottom edge.
  Widget _heroAndTime(BuildContext context, ClearedResult r, double k) {
    final pillH = 70 * k, overlap = 30 * k;
    // Hero scales in from 0.94 (400 ms springSoft) at the medal beat.
    final hp = _p(ClearedBeats.medal, 400);
    final hs = 0.94 + 0.06 * JwMotion.springSoft.transform(hp);
    final hero = Opacity(
      opacity: (hp * 3).clamp(0.0, 1.0),
      child: Transform.scale(
        scale: hs,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            HeroCard(
              radius: 32,
              width: double.infinity,
              // Room at the bottom for the half of the time pill that overlaps.
              padding: EdgeInsets.fromLTRB(16, 24 * k, 16, overlap + 12 * k),
              child: _heroContent(context, r, k),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: _ConfettiBurst(progress: _p(ClearedBeats.medal, 900), originY: (24 + 60) * k),
              ),
            ),
          ],
        ),
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        // The hero plus the part of the pill hanging below it (and its edge).
        Padding(padding: EdgeInsets.only(bottom: pillH - overlap + 4), child: hero),
        Positioned(bottom: 4, child: _timePill(context, r, k)),
      ],
    );
  }

  Widget _heroContent(BuildContext context, ClearedResult r, double k) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final on = JwFill.purple.on;
    final title = _p(ClearedBeats.title, 600);
    return Column(
      children: [
        _medal(context, k),
        SizedBox(height: 14 * k),
        _fadeUp(
          title,
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              l.clearedBoardTitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: jw.text.h1.copyWith(fontSize: 30, height: 1.1, color: on),
            ),
          ),
        ),
        SizedBox(height: 6 * k),
        Semantics(
          label: l.clearedStarsSemantics(r.stars),
          excludeSemantics: true,
          child: SizedBox(
            height: 40 * k,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) SizedBox(width: 8 * k),
                  _star(i < r.stars, _p(_starStart(i), 500), k, lifted: i == 1),
                ],
              ],
            ),
          ),
        ),
        SizedBox(height: 4 * k),
        _fadeUp(
          title,
          Text(
            l.clearedMeta(r.layoutName, r.tileCount),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // Secondary text on purple: ≥ 13.5 pt semibold, full opacity.
            style: jw.text.callout.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: on),
          ),
        ),
      ],
    );
  }

  /// The white medal holding a mint check: drops 200 pt with a landing
  /// squash (900 ms springSoft); the check pops 500 ms later.
  Widget _medal(BuildContext context, double k) {
    final jw = context.jw;
    final p = _p(ClearedBeats.medal, 900);
    final drop = JwMotion.springSoft.transform(p);
    final land = p < 0.55 ? 0.0 : math.sin(((p - 0.55) / 0.45) * math.pi);
    final check = JwMotion.springPop.transform(_p(ClearedBeats.medal + 500, 500));
    final w = 96 * k, h = 112 * k, edge = 7 * k;
    return Opacity(
      opacity: (p * 8).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, -200 * (1 - drop)),
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.diagonal3Values(1 + 0.05 * land, 1 - 0.07 * land, 1),
          child: Padding(
            padding: EdgeInsets.only(bottom: edge),
            child: DecoratedBox(
              decoration: ClayDecoration(
                level: ClayLevel.flat,
                colors: jw.colors,
                color: jw.tileFace,
                radius: 28 * k,
                extraShadows: [
                  ClayShadow.inset(3, 3, 5, 0, jw.highlight),
                  ClayShadow.inset(-5, -6, 10, 0, jw.inner),
                  ClayShadow(0, edge, 0, 0, JwTheme.light.tileEdge),
                  ClayShadow(0, 22, 30, -12, jw.shadow),
                ],
              ),
              child: SizedBox(
                width: w,
                height: h,
                child: Center(
                  child: Transform.scale(
                    scale: check,
                    child: FillBox(
                      fill: JwFill.mint,
                      radius: 28 * k,
                      edge: 4,
                      glow: false,
                      width: 56 * k,
                      height: 56 * k,
                      child: Center(
                        child: JwIcon(JwIcons.check, size: 28 * k, color: JwFill.mint.on, strokeWidth: JwIcon.badgeStroke),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A star on the hero: yellow fill when earned, a translucent white
  /// outline when not; pops in (500 ms springPop, 120 ms stagger).
  Widget _star(bool earned, double p, double k, {bool lifted = false}) {
    final c = JwMotion.springPop.transform(p);
    final size = (lifted ? 38.0 : 32.0) * k;
    return Opacity(
      opacity: p == 0 ? 0 : (p * 4).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, (lifted ? -4 * k : 0) - 18 * (1 - c)),
        child: Transform.scale(
          scale: 0.3 + 0.7 * c,
          child: RepaintBoundary(
            child: CustomPaint(size: Size.square(size), painter: earned ? const ClearedStarPainter.earned() : const ClearedStarPainter.empty()),
          ),
        ),
      ),
    );
  }

  Widget _timePill(BuildContext context, ClearedResult r, double k) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final appear = JwMotion.easeOutSoft.transform(_p(ClearedBeats.time, 300));
    final count = Curves.easeOutCubic.transform(_p(ClearedBeats.time, 1100));
    final shown = formatClock((r.timeMs * count).round());
    final h = 70 * k, badge = 50 * k;
    return Semantics(
      label: l.clearedTimeSemantics(formatClock(r.timeMs)),
      excludeSemantics: true,
      child: Opacity(
        opacity: appear,
        child: Transform.scale(
          scale: 0.92 + 0.08 * appear,
          child: DecoratedBox(
            decoration: jw.clay(ClayLevel.floating, radius: h / 2),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: h),
              child: Padding(
                padding: EdgeInsets.only(left: 10 * k, right: 30 * k, top: 4, bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -2),
                      child: FillBox(
                        fill: JwFill.yellow,
                        radius: badge / 2,
                        edge: 4,
                        glow: false,
                        width: badge,
                        height: badge,
                        child: Center(
                          child: JwIcon(JwIcons.clock, size: badge * 0.52, color: JwFill.yellow.on, strokeWidth: JwIcon.badgeStroke),
                        ),
                      ),
                    ),
                    SizedBox(width: 16 * k),
                    Text(shown, style: jw.text.numXl.copyWith(fontSize: 46 * k, height: 1)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bestChip(BuildContext context, ClearedResult r, double k) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final p = _p(ClearedBeats.best, 500);
    final c = JwMotion.springPop.transform(p);
    final improvement = r.improvementMs;
    const h = 34.0;
    final String text;
    var accent = true;
    if (improvement != null && improvement >= 1000) {
      text = '${l.clearedNewBest} · ${l.clearedFaster(formatClock(improvement))}';
    } else if (improvement != null) {
      // Beat the old best by under a second: "0:00 faster" reads as a tie.
      text = l.clearedNewBest;
    } else if (r.firstClear || r.isNewBest) {
      text = l.clearedFirstClear;
    } else if (r.previousBestMs != null) {
      accent = false;
      text = l.clearedBest(formatClock(r.previousBestMs!));
    } else {
      return const SizedBox(height: h + 3);
    }
    final fg = accent ? JwFill.coral.on : jw.textMuted;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(size: const Size.square(17), painter: ClearedStarPainter.solid(fg)),
        const SizedBox(width: 9),
        Flexible(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: jw.text.callout.copyWith(fontSize: 15, fontWeight: FontWeight.w700, color: fg)),
        ),
      ],
    );
    final chip = accent
        ? FillBox(
            fill: JwFill.coral,
            radius: h / 2,
            edge: 3,
            glow: false,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            child: row,
          )
        : DecoratedBox(
            decoration: jw.clay(ClayLevel.chip, radius: h / 2),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7), child: row),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Opacity(
        opacity: (p * 3).clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.4 + 0.6 * c, child: chip),
      ),
    );
  }

  Widget _stats(BuildContext context, ClearedResult r, double k) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final count = JwMotion.easeOutSoft.transform(_p(ClearedBeats.stats, 600));
    final values = [r.stats.tilesMatched, r.stats.longestStreak, r.stats.hintsUsed];
    final labels = [l.clearedTilesMatched, l.clearedLongestStreak, l.clearedHintsUsed(r.stats.hintsUsed)];
    const icons = [JwIcons.tile, JwIcons.flame, JwIcons.hint];
    const fills = [JwFill.mint, JwFill.pink, JwFill.sky];
    // Cards size to their content; IntrinsicHeight keeps the three equal.
    return IntrinsicHeight(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  decoration: jw.clay(ClayLevel.raised, radius: 24),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12, 11 * k, 8, 10 * k),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconBadge(icon: icons[i], fill: fills[i]),
                        SizedBox(height: 7 * k),
                        Text('${(values[i] * count).round()}', maxLines: 1, style: jw.text.numL.copyWith(height: 1.05)),
                        Text(
                          labels[i],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: jw.text.callout.copyWith(fontSize: 13.5, fontWeight: FontWeight.w500, color: jw.textMuted),
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
      ),
    );
  }

  Widget _chapterProgress(BuildContext context, ClearedResult r, String chapterName, int cleared, int total, double k) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final popped = _t >= ClearedBeats.progress;
    final filled = popped || !r.firstClear ? cleared : math.max(0, cleared - 1);
    return _fadeUp(
      _p(ClearedBeats.stats + 160, 600),
      DecoratedBox(
        decoration: jw.clay(ClayLevel.raised, radius: 26),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14 * k, 18, 14 * k),
          child: Row(
            children: [
              const IconBadge(icon: JwIcons.grid, fill: JwFill.purple, size: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(chapterName, maxLines: 1, overflow: TextOverflow.ellipsis, style: jw.text.button.copyWith(fontSize: 16.5))),
                        Text(
                          l.clearedChapterCount(filled, total),
                          style: jw.text.numM.copyWith(fontSize: 16, fontWeight: FontWeight.w700, color: jw.purpleText),
                        ),
                      ],
                    ),
                    SizedBox(height: 8 * k),
                    JwSegmentedProgress(segments: total, filled: filled, semanticLabel: chapterName),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, ClearedResult r, LayoutInfo? next, bool nextOpen, double k) {
    final l = AppLocalizations.of(context);
    void haptic() => ref.read(hapticsProvider).light();
    final primaryH = (60 * k).clamp(54.0, 60.0);
    final Widget primary;
    final List<Widget> secondary;
    if (r.isDaily) {
      primary = PrimaryButton(
        label: l.clearedLeaderboard,
        icon: JwIcons.trophy,
        height: primaryH,
        expand: true,
        onHaptic: haptic,
        onPressed: () => context.go(AppRoutes.leaderboard),
      );
      secondary = [
        JwButton.secondary(label: l.clearedReplay, icon: JwIcons.replay, expand: true, onPressed: () => context.go(AppRoutes.dailyPlay)),
        JwButton.secondary(label: l.clearedHome, icon: JwIcons.grid, expand: true, onPressed: () => context.go(AppRoutes.home)),
      ];
    } else if (next != null && nextOpen) {
      final label = l.clearedNext(next.name);
      primary = PrimaryButton(
        label: label,
        trailingIcon: JwIcons.arrow,
        height: primaryH,
        expand: true,
        semanticLabel: '$label ${l.clearedNextTiles(next.tileCount)}',
        onHaptic: haptic,
        onPressed: () => context.go(AppRoutes.game(next.id)),
      );
      secondary = [
        JwButton.secondary(label: l.clearedReplay, icon: JwIcons.replay, expand: true, onPressed: () => context.go(AppRoutes.game(r.layoutId))),
        JwButton.secondary(label: l.clearedCollection, icon: JwIcons.grid, expand: true, onPressed: () => context.go(AppRoutes.home)),
      ];
    } else {
      primary = PrimaryButton(
        label: l.clearedCollection,
        icon: JwIcons.grid,
        height: primaryH,
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
          primary,
          SizedBox(height: 10 * k),
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

/// Confetti burst on the cleared hero (MOTION_SPEC cleared beat sheet):
/// small clay pieces in the six fills fly out from the medal and settle at
/// fixed spots. Each piece is its own [RepaintBoundary]; frames only move
/// them with transforms (no per-frame painting or blur).
class _ConfettiBurst extends StatelessWidget {
  const _ConfettiBurst({required this.progress, required this.originY});

  /// 0 → 1 over the burst.
  final double progress;

  /// Burst origin: horizontally centred, [originY] pt from the top (the
  /// medal's centre).
  final double originY;

  // x, y (fractions of the hero), width, height (pt), rotation (rad), fill.
  // None sit over the medal or the text column (x 0.15–0.85 below the
  // medal).
  static const _pieces = [
    (0.13, 0.17, 14.0, 18.0, 0.30, JwFill.yellow),
    (0.385, 0.065, 8.0, 12.0, 0.0, JwFill.mint),
    (0.665, 0.055, 10.0, 14.0, 0.50, JwFill.yellow),
    (0.865, 0.135, 12.0, 17.0, -0.60, JwFill.pink),
    (0.08, 0.40, 8.0, 12.0, 0.0, JwFill.purple),
    (0.925, 0.35, 15.0, 10.0, -0.45, JwFill.coral),
    // Kept to the edges beside the title, stars and meta line.
    (0.06, 0.66, 10.0, 14.0, 0.80, JwFill.mint),
    (0.94, 0.62, 12.0, 17.0, 0.20, JwFill.sky),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = c.biggest;
        final o = Offset(size.width / 2, originY);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < _pieces.length; i++) _piece(i, size, o),
          ],
        );
      },
    );
  }

  Widget _piece(int i, Size size, Offset o) {
    final (x, y, w, h, rot, fill) = _pieces[i];
    // A small stagger so the pieces don't move as one.
    final p = ((progress - i * 0.025) / 0.8).clamp(0.0, 1.0);
    final c = JwMotion.springSoft.transform(p);
    final end = Offset(x * size.width, y * size.height);
    final at = Offset.lerp(o, end, c)!;
    return Positioned(
      left: 0,
      top: 0,
      child: Opacity(
        opacity: (p * 5).clamp(0.0, 1.0),
        child: Transform(
          transform: Matrix4.identity()
            ..translateByDouble(at.dx - w / 2, at.dy - h / 2, 0, 1)
            ..translateByDouble(w / 2, h / 2, 0, 1)
            ..rotateZ(rot + (1 - c) * 2.4)
            ..scaleByDouble(0.4 + 0.6 * c, 0.4 + 0.6 * c, 1, 1)
            ..translateByDouble(-w / 2, -h / 2, 0, 1),
          child: RepaintBoundary(
            child: CustomPaint(size: Size(w, h + 2), painter: _ConfettiPiecePainter(fill)),
          ),
        ),
      ),
    );
  }
}

/// One confetti piece: a rounded clay rect (fill gradient over a 2 pt edge).
class _ConfettiPiecePainter extends CustomPainter {
  const _ConfettiPiecePainter(this.fill);

  final JwFill fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height - 2);
    final r = Radius.circular(math.min(rect.width, rect.height) * 0.38);
    canvas
      ..drawRRect(RRect.fromRectAndRadius(rect.shift(const Offset(0, 2)), r), Paint()..color = fill.edge)
      ..drawRRect(RRect.fromRectAndRadius(rect, r), Paint()..shader = JwFills.gradient(fill).createShader(rect));
  }

  @override
  bool shouldRepaint(_ConfettiPiecePainter old) => !identical(old.fill, fill);
}

/// A rounded five-point star: [ClearedStarPainter.earned] is a yellow clay
/// star (gradient over a 2.5 pt edge), [ClearedStarPainter.empty] a
/// translucent white outline for the purple hero, and
/// [ClearedStarPainter.solid] a flat glyph (the "New best" chip).
class ClearedStarPainter extends CustomPainter {
  const ClearedStarPainter.earned() : _mode = 0, _color = null;
  const ClearedStarPainter.empty() : _mode = 1, _color = null;
  const ClearedStarPainter.solid(Color color) : _mode = 2, _color = color;

  final int _mode;
  final Color? _color;

  static Path _star(Size size, double inset) {
    final c = Offset(size.width / 2, size.height * 0.53);
    final outer = size.shortestSide / 2 - inset;
    final inner = outer * 0.5;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? outer : inner;
      final pt = c + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final white = JwFill.purple.on;
    switch (_mode) {
      case 0:
        final s = size.shortestSide;
        final round = s * 0.09;
        final path = _star(Size(size.width, size.height - s * 0.07), round);
        final edge = Paint()
          ..color = JwFill.yellow.edge
          ..strokeWidth = round * 2
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.fill;
        final shifted = path.shift(Offset(0, s * 0.07));
        canvas
          ..drawPath(shifted, edge)
          ..drawPath(shifted, Paint.from(edge)..style = PaintingStyle.stroke);
        final face = Paint()
          ..shader = JwFills.gradient(JwFill.yellow).createShader(Offset.zero & size)
          ..strokeWidth = round * 2
          ..strokeJoin = StrokeJoin.round;
        canvas
          ..drawPath(path, face..style = PaintingStyle.fill)
          ..drawPath(path, face..style = PaintingStyle.stroke);
      case 1:
        final s = size.shortestSide;
        final path = _star(size, s * 0.09);
        canvas
          ..drawPath(path, Paint()..color = white.withValues(alpha: 0.14))
          ..drawPath(
            path,
            Paint()
              ..color = white.withValues(alpha: 0.55)
              ..style = PaintingStyle.stroke
              ..strokeWidth = s * 0.07
              ..strokeJoin = StrokeJoin.round,
          );
      default:
        final s = size.shortestSide;
        final round = s * 0.08;
        final path = _star(size, round);
        final paint = Paint()
          ..color = _color!
          ..strokeWidth = round * 2
          ..strokeJoin = StrokeJoin.round;
        canvas
          ..drawPath(path, paint..style = PaintingStyle.fill)
          ..drawPath(path, paint..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(ClearedStarPainter old) => old._mode != _mode || old._color != _color;
}

/// "Head start" rewarded-interstitial intro: the reward is stated, a 5 s
/// countdown starts the video, Skip opts out (docs/ARCHITECTURE.md §7).
