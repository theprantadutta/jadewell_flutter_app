import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/catalogue.dart';
import '../../../data/models/progress.dart';
import '../../../data/models/unlocks.dart';
import '../../../state/data_providers.dart';
import '../../../state/platform_providers.dart';
import '../../components/components.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../router.dart';
import '../../theme/clay.dart';
import '../../theme/jw_background.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/jw_logo_tile.dart';
import '../../widgets/skeleton/jw_skeleton.dart';
import '../../widgets/widgets.dart';
import '../daily/countdown.dart';
import 'layout_card_parts.dart';
import 'layout_labels.dart';
import 'unlock_sheet.dart';

/// Layout select: header with the star chip, daily hero, collection cards
/// and chapters (screen 11); the first-run "start here" variant (17a);
/// skeleton (18).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final catalogue = ref.watch(catalogueProvider).value;
    final progress = ref.watch(progressProvider).value;
    final loading = catalogue == null || progress == null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: jw.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: JwBackground(
          blobs: HomeScreen.blobs,
          child: SafeArea(
            bottom: false,
            child: JwContentWidth(
              maxWidth: 720,
              child: LayoutBuilder(
                builder: (context, box) {
                  final columns = _columnsFor(box.maxWidth);
                  return JwSkeletonSwitcher(
                    loading: loading,
                    skeleton: JwSkeletonHome(columns: columns, semanticLabel: l.commonLoading),
                    builder: (context) => _HomeContent(catalogue: catalogue!, progress: progress!, columns: columns),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Screen 11 blobs: big purple top-right, pink and mint peeking in at the
  /// sides of the collection.
  static const blobs = [
    PopBlob(JwFill.purple, Offset(0.96, 0.03), 0.2),
    PopBlob(JwFill.pink, Offset(-0.02, 0.43), 0.06),
    PopBlob(JwFill.mint, Offset(1.01, 0.72), 0.06),
  ];

  static int _columnsFor(double width) => ((width - 32 + 14) / (172 + 14)).floor().clamp(2, 3);
}

/// Badge fill and icon of a chapter, by chapter index (Classics purple grid,
/// Creatures mint sparkle, Wonders yellow trophy, then pink / sky / coral).
(JwFill, String) chapterStyle(int index) => switch (index % 6) {
      0 => (JwFill.purple, JwIcons.grid),
      1 => (JwFill.mint, JwIcons.sparkle),
      2 => (JwFill.yellow, JwIcons.trophy),
      3 => (JwFill.pink, JwIcons.heart),
      4 => (JwFill.sky, JwIcons.star),
      _ => (JwFill.coral, JwIcons.flame),
    };

class _HomeContent extends ConsumerStatefulWidget {
  const _HomeContent({required this.catalogue, required this.progress, required this.columns});

  final Catalogue catalogue;
  final Map<String, LayoutProgress> progress;
  final int columns;

  @override
  ConsumerState<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<_HomeContent> {
  final _scroll = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {};

  GlobalKey _keyFor(String chapterId) => _sectionKeys[chapterId] ??= GlobalKey(debugLabel: 'chapter-$chapterId');

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls the chapter section into view (it may not be built yet when it
  /// is far below: jump towards the end first, then align).
  Future<void> _scrollToChapter(String chapterId) async {
    final reduce = JwReduceMotion.of(context);
    final duration = reduce ? const Duration(milliseconds: 1) : JwMotion.gentle;
    var ctx = _keyFor(chapterId).currentContext;
    if (ctx == null && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      ctx = _keyFor(chapterId).currentContext;
    }
    if (ctx == null || !ctx.mounted) return;
    await Scrollable.ensureVisible(ctx, duration: duration, curve: JwMotion.easeOutSoft, alignment: 0.02);
  }

  @override
  Widget build(BuildContext context) {
    final catalogue = widget.catalogue;
    final progress = widget.progress;
    final layouts = catalogue.chapterLayouts.toList();
    final firstRun = progress.values.every((p) => !p.cleared && !p.hasSavedGame && p.lastPlayedAt == null);
    final earned = layouts.fold<int>(0, (a, i) => a + (progress[i.id]?.bestStars ?? 0));
    final plateIndex = {for (var i = 0; i < layouts.length; i++) layouts[i].id: i};

    // The active chapter: the first unlocked one still to finish.
    final chapters = catalogue.chapters;
    final access = [for (final ch in chapters) Unlocks.chapter(catalogue, ch.id, progress)];
    var active = access.indexWhere((a) => !a.locked && a.cleared < a.total);
    if (active < 0) active = 0;

    var slot = 0;
    Widget fade(Widget child) => JwFadeUp(index: slot++, child: child);

    return CustomScrollView(
      controller: _scroll,
      // Keep the chapter sections built so the collection cards can scroll
      // to them; cards paint from cached textures, so this stays cheap.
      scrollCacheExtent: const ScrollCacheExtent.pixels(1600),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
          sliver: SliverList.list(
            children: [
              fade(_HomeHeader(firstRun: firstRun, earned: earned, total: layouts.length * 3)),
              const SizedBox(height: 22),
              fade(firstRun ? _StartHereCard(info: layouts.first) : const _DailyHeroCard()),
              const SizedBox(height: 30),
              fade(
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Semantics(
                    header: true,
                    child: Text(AppLocalizations.of(context).homeExploreCollections, style: context.jw.text.h3.copyWith(fontSize: 21)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              fade(
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < chapters.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(
                        child: _ChapterCard(
                          chapter: chapters[i],
                          access: access[i],
                          index: i,
                          active: i == active,
                          onTap: () => unawaited(_scrollToChapter(chapters[i].id)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              for (var i = 0; i < chapters.length; i++) ...[
                const SizedBox(height: 30),
                fade(
                  KeyedSubtree(
                    key: _keyFor(chapters[i].id),
                    child: _ChapterSection(
                      catalogue: catalogue,
                      chapter: chapters[i],
                      index: i,
                      progress: progress,
                      columns: widget.columns,
                      plateIndex: plateIndex,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- header

/// Logo tile, greeting + title, the star chip and the Statistics / Settings
/// buttons (owner decision: both stay in the header).
class _HomeHeader extends ConsumerWidget {
  const _HomeHeader({required this.firstRun, required this.earned, required this.total});

  final bool firstRun;
  final int earned;
  final int total;

  static String greeting(AppLocalizations l, DateTime now) => now.hour < 12
      ? l.homeGreetingMorning
      : (now.hour < 18 ? l.homeGreetingAfternoon : l.homeGreetingEvening);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final haptics = ref.read(hapticsProvider);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(top: 6), child: JwLogoTile()),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                firstRun ? l.homeWelcome : greeting(l, DateTime.now()),
                style: jw.text.body.copyWith(fontSize: 15, color: jw.textMuted, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Semantics(
                header: true,
                child: Text(
                  firstRun ? l.homeFirstRunTitle : l.homeReadyTitle,
                  style: jw.text.h2.copyWith(fontSize: 25, height: 1.12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            CounterChip(
              icon: JwIcons.star,
              fill: JwFill.yellow,
              value: '$earned/$total',
              semanticLabel: l.homeStarsEarned(earned, total),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                JwIconButton(
                  icon: JwIcons.chart,
                  semanticLabel: l.homeStatistics,
                  size: 42,
                  iconSize: 19,
                  onHaptic: haptics.selection,
                  onPressed: () => context.push(AppRoutes.stats),
                ),
                const SizedBox(width: 10),
                JwIconButton(
                  icon: JwIcons.gear,
                  semanticLabel: l.homeSettings,
                  size: 42,
                  iconSize: 19,
                  onHaptic: haptics.selection,
                  onPressed: () => context.push(AppRoutes.settings),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- hero cards

class _DailyHeroCard extends ConsumerWidget {
  const _DailyHeroCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final daily = ref.watch(dailyProvider).value;
    final catalogue = ref.watch(catalogueProvider).value;
    final info = daily == null ? null : catalogue?.layouts[daily.layoutId];
    if (daily == null || info == null) {
      return const JwSkeletonScope(child: JwSkeletonBox(height: 172, radius: 30));
    }
    final date = DateTime.parse(daily.date);
    final dateLabel = DateFormat('EEE d MMM', l.localeName).format(date);
    final on = JwFill.purple.on;
    final jw = context.jw;
    void open() => context.push(AppRoutes.daily);
    return HeroCard(
      radius: 30,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
      onTap: open,
      onHaptic: ref.read(hapticsProvider).selection,
      semanticLabel: '${l.homeDailyEyebrow(dateLabel)}, ${info.name}, ${LayoutLabels.meta(l, info)}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 136),
        // The art sits top-right; the Play row runs under it, as in screen 11.
        child: Stack(
          children: [
            Positioned(right: -4, top: 0, child: const TwinTilesArt()),
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 104),
                    child: Text(
                      l.homeDailyEyebrow(dateLabel),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: jw.text.callout.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: on),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 104),
                    child: Text(
                      info.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: jw.text.h1.copyWith(fontSize: 30, height: 1.15, color: on),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 96),
                    child: DailyCountdown(
                    builder: (context, left) => Semantics(
                      label: l.homeDailyEndsIn(formatCountdown(left)),
                      excludeSemantics: true,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${l.homeDailyTilesEndsIn(info.tileCount)} ',
                              style: jw.text.callout.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: on),
                            ),
                            RollingText(
                              formatCountdown(left),
                              style: jw.text.numM.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: on),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 14,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PrimaryButton(
                        label: l.homePlay,
                        icon: JwIcons.play,
                        height: 46,
                        fill: JwFill.yellow,
                        onHaptic: ref.read(hapticsProvider).light,
                        onPressed: open,
                      ),
                      if (daily.streak > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            JwIcon(JwIcons.flame, size: 17, color: on),
                            const SizedBox(width: 6),
                            Text(
                              l.homeDailyStreak(daily.streak),
                              style: jw.text.callout.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: on),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The daily hero's art: two tilted white tiles (plum and circle faces)
/// with a small yellow sphere. Static; painted once behind a boundary.
class TwinTilesArt extends StatelessWidget {
  const TwinTilesArt({super.key, this.scale = 1});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final s = scale;
    Widget tile(Widget face) => DecoratedBox(
          decoration: jw.clay(
            ClayLevel.flat,
            color: jw.tileEdge,
            radius: 12 * s,
            extraShadows: [ClayShadow(0, 6 * s, 12 * s, 0, JwFill.purple.edge.withValues(alpha: 0.45))],
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: 5 * s),
            child: DecoratedBox(
              decoration: jw.clay(ClayLevel.flat, color: jw.tileFace, radius: 11 * s),
              child: SizedBox(width: 48 * s, height: 58 * s, child: Center(child: face)),
            ),
          ),
        );
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          width: 112 * s,
          height: 112 * s,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 2 * s,
                top: 0,
                child: SizedBox.square(dimension: 24 * s, child: CustomPaint(painter: _SpherePainter(JwFill.yellow))),
              ),
              Positioned(
                left: 6 * s,
                top: 26 * s,
                child: Transform.rotate(
                  angle: -0.16,
                  child: tile(Text('梅', style: jw.text.glyph.copyWith(fontSize: 26 * s, color: JwFaceInks.flowers))),
                ),
              ),
              Positioned(
                left: 50 * s,
                top: 18 * s,
                child: Transform.rotate(
                  angle: 0.1,
                  child: tile(SizedBox.square(dimension: 28 * s, child: CustomPaint(painter: _CirclePainter()))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpherePainter extends CustomPainter {
  _SpherePainter(this.fill);
  final JwFill fill;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 0.95,
          colors: [JwFaceInks.lighten(fill.top, 0.55), fill.mid, fill.edge],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_SpherePainter old) => old.fill != fill;
}

/// One-circle tile face: green ring with a red centre.
class _CirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas
      ..drawCircle(c, r, Paint()..color = JwFaceInks.circleGreen)
      ..drawCircle(c, r * 0.66, Paint()..color = JwFaceInks.lighten(JwFaceInks.circleGreen, 0.82))
      ..drawCircle(c, r * 0.42, Paint()..color = JwFaceInks.circleRed);
  }

  @override
  bool shouldRepaint(_CirclePainter old) => false;
}

/// First run (17a): a yellow hero pointing at the first layout.
class _StartHereCard extends ConsumerWidget {
  const _StartHereCard({required this.info});

  final LayoutInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    const fill = JwFill.yellow;
    void open() => context.push(AppRoutes.game(info.id));
    return HeroCard(
      fill: fill,
      radius: 30,
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      onTap: open,
      onHaptic: ref.read(hapticsProvider).selection,
      semanticLabel: '${l.homeStartHere}, ${info.name}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 136),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.homeStartHere.toUpperCase(), style: jw.text.eyebrow.copyWith(color: fill.on, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text(info.name, style: jw.text.h1.copyWith(fontSize: 30, height: 1.15, color: fill.on)),
                  const SizedBox(height: 2),
                  Text(
                    l.homeFirstBoardMeta(info.tileCount),
                    style: jw.text.callout.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: fill.on),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: l.homePlayFirstBoard,
                    icon: JwIcons.play,
                    height: 46,
                    onHaptic: ref.read(hapticsProvider).light,
                    onPressed: open,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(width: 104, height: 110, child: JwSilhouette(tiles: LayoutLabels.tiles(info))),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------- collection cards

/// "Explore collections" card (§11 chapter card): 84 tall, radius 22; the
/// active chapter is a purple fill, the others raised with their badge.
class _ChapterCard extends ConsumerWidget {
  const _ChapterCard({required this.chapter, required this.access, required this.index, required this.active, required this.onTap});

  final ChapterInfo chapter;
  final ChapterAccess access;
  final int index;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final (fill, icon) = chapterStyle(index);
    final fg = active ? JwFill.purple.on : jw.textPrimary;
    final scaler = MediaQuery.textScalerOf(context);
    final height = 84 + (scaler.scale(15) - 15) * 2;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (active)
            DecoratedBox(
              decoration: jw.clay(ClayLevel.flat, color: JwFill.purple.on.withValues(alpha: 0.2), radius: 10),
              child: SizedBox.square(
                dimension: 28,
                child: Center(child: JwIcon(icon, size: 16, color: JwFill.purple.on, strokeWidth: JwIcon.badgeStroke)),
              ),
            )
          else
            Transform.translate(offset: const Offset(0, -1.5), child: IconBadge(icon: icon, fill: fill, size: 28)),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(chapter.name, style: jw.text.button.copyWith(fontSize: 15, color: fg)),
                const SizedBox(width: 8),
                Text(
                  '${access.cleared}/${access.total}',
                  style: jw.text.numM.copyWith(fontSize: 13.5, fontWeight: FontWeight.w500, color: active ? fg : jw.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final label = '${chapter.name}, ${l.homeChapterProgress(access.cleared, access.total)}';
    final haptic = ref.read(hapticsProvider).selection;
    if (active) {
      return FillPressable(
        fill: JwFill.purple,
        radius: 22,
        width: double.infinity,
        height: height,
        onTap: onTap,
        onHaptic: haptic,
        semanticLabel: label,
        child: content,
      );
    }
    final deco = jw.clay(ClayLevel.raised, radius: 22);
    return ClayPressable(
      decoration: deco,
      pressedDecoration: deco.copyWith(level: ClayLevel.pressed),
      pressedScale: 0.97,
      width: double.infinity,
      height: height,
      onTap: onTap,
      onHaptic: haptic,
      semanticLabel: label,
      child: content,
    );
  }
}

// ------------------------------------------------------------------ chapters

class _ChapterSection extends ConsumerWidget {
  const _ChapterSection({
    required this.catalogue,
    required this.chapter,
    required this.index,
    required this.progress,
    required this.columns,
    required this.plateIndex,
  });

  final Catalogue catalogue;
  final ChapterInfo chapter;
  final int index;
  final Map<String, LayoutProgress> progress;
  final int columns;
  final Map<String, int> plateIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final access = Unlocks.chapter(catalogue, chapter.id, progress);
    final layouts = [for (final id in chapter.layoutIds) catalogue.layout(id)];
    final anyAdUnlocked = layouts.any((i) => progress[i.id]?.adUnlocked ?? false);
    final collapsed = access.locked && chapter.unlock is UnlockTotalClears && !anyAdUnlocked;
    final (fill, icon) = chapterStyle(index);

    if (collapsed) {
      return _LockedChapterRow(
        chapter: chapter,
        layouts: layouts,
        fill: fill,
        icon: icon,
        caption: _lockedChapterCaption(l, chapter, layouts.length, access.remaining),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 6),
          child: Row(
            children: [
              Transform.translate(offset: const Offset(0, -1.5), child: IconBadge(icon: icon, fill: fill, size: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(header: true, child: Text(chapter.name, style: jw.text.h3.copyWith(fontSize: 22))),
              ),
              Semantics(
                label: l.homeChapterProgress(access.cleared, access.total),
                excludeSemantics: true,
                child: Text(
                  '${access.cleared} / ${access.total}',
                  style: jw.text.numM.copyWith(fontSize: 15, fontWeight: FontWeight.w500, color: jw.textMuted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _CardGrid(
          columns: columns,
          children: [
            for (final info in layouts)
              _LayoutCard(
                info: info,
                plate: JwFills.plate(plateIndex[info.id] ?? 0),
                progress: progress[info.id],
                access: Unlocks.layout(catalogue, info.id, progress),
                lockLabel: (a) => _layoutLockLabel(l, catalogue, chapter, info, a, progress),
              ),
          ],
        ),
      ],
    );
  }
}

String _chapterLockLabel(AppLocalizations l, Catalogue c, ChapterInfo ch, int remaining) => switch (ch.unlock) {
      UnlockTotalClears(:final count) => l.homeUnlocksAtClears(count),
      UnlockChapterClears(:final chapterId) => () {
          final name = c.chapter(chapterId).name;
          return l.homeLockedChapterClears(remaining, LayoutLabels.singular(name), name);
        }(),
      UnlockAlways() => '',
    };

/// "4 layouts · unlocks at 8 clears" under a collapsed chapter.
String _lockedChapterCaption(AppLocalizations l, ChapterInfo ch, int count, int remaining) => switch (ch.unlock) {
      UnlockTotalClears(count: final clears) => '${l.homeChapterLayouts(count)} · ${l.homeChapterUnlocksAt(clears)}',
      _ => l.homeChapterLayouts(count),
    };

String _layoutLockLabel(
  AppLocalizations l,
  Catalogue c,
  ChapterInfo ch,
  LayoutInfo info,
  LayoutAccess a,
  Map<String, LayoutProgress> progress,
) {
  if (a.reason == LockReason.chapterLocked) return _chapterLockLabel(l, c, ch, a.remaining);
  final clearedHere = Unlocks.chapterClears(c, ch.id, progress);
  if (clearedHere == 0 && a.remaining == 1) return l.homeLockedClearFirst(c.layout(ch.layoutIds.first).name);
  return l.homeLockedClearMore(a.remaining, LayoutLabels.singular(ch.name), ch.name);
}

/// Layout cards in [columns] columns, 14 pt gaps. Each row is as tall as its
/// tallest card's content (at least the spec's 196 pt), so a card never
/// clips its state row at any text scale or column count.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  static const double gap = 14;
  static const double minCardHeight = 196;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += columns) {
      final cells = <Widget>[];
      for (var c = 0; c < columns; c++) {
        if (c > 0) cells.add(const SizedBox(width: gap));
        final i = start + c;
        cells.add(
          Expanded(
            child: i < children.length
                ? ConstrainedBox(constraints: const BoxConstraints(minHeight: minCardHeight), child: children[i])
                : const SizedBox.shrink(),
          ),
        );
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
      rows.add(IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

class _LayoutCard extends ConsumerWidget {
  const _LayoutCard({required this.info, required this.plate, required this.progress, required this.access, required this.lockLabel});

  final LayoutInfo info;
  final JwFill plate;
  final LayoutProgress? progress;
  final LayoutAccess access;
  final String Function(LayoutAccess) lockLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final haptics = ref.read(hapticsProvider);
    final p = progress;
    final meta = LayoutLabels.meta(l, info);
    final caption = jw.text.callout.copyWith(fontSize: 14);

    Widget? state;
    String stateLabel = '';
    if (access.locked) {
      final label = lockLabel(access);
      stateLabel = '${l.homeLocked}, $label';
      state = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: JwIcon(JwIcons.lock, size: 15, color: jw.textMuted),
          ),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: caption.copyWith(fontWeight: FontWeight.w500, color: jw.textMuted, height: 1.15),
            ),
          ),
        ],
      );
    } else if (p != null && p.hasSavedGame && (p.savedFraction ?? 0) <= 0) {
      // Saved after a hint/shuffle but no pair matched yet: a 0% bar reads
      // as broken, so just say it's under way.
      stateLabel = l.homeInProgress;
      state = SizedBox(
        height: 22,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(l.homeInProgress, style: caption.copyWith(fontWeight: FontWeight.w600, color: jw.purpleText)),
        ),
      );
    } else if (p != null && p.hasSavedGame) {
      // At least 1% once anything is matched (1 pair of 144 rounds to 1%).
      final pct = '${((p.savedFraction ?? 0) * 100).ceil().clamp(1, 99)}%';
      stateLabel = '${l.homeResume} $pct';
      state = SizedBox(
        height: 22,
        child: Row(
          children: [
            Expanded(child: MiniTrack(value: p.savedFraction ?? 0, width: double.infinity)),
            const SizedBox(width: 10),
            Text(pct, style: jw.text.numM.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: jw.purpleText)),
          ],
        ),
      );
    } else if (p != null && p.cleared) {
      final best = p.bestTimeMs == null ? '' : formatClock(p.bestTimeMs!);
      stateLabel = '${l.homeBest} $best, ${l.homeStarsSemantics(p.bestStars)}';
      state = SizedBox(
        height: 22,
        child: Row(
          children: [
            Transform.translate(
              offset: const Offset(0, -1.5),
              child: const IconBadge(icon: JwIcons.check, fill: JwFill.mint, size: 22),
            ),
            const SizedBox(width: 7),
            Text(l.homeBest, style: caption.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 5),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(best, maxLines: 1, style: jw.text.numM.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 4),
            StarRow(earned: p.bestStars, size: 11, gap: 1),
          ],
        ),
      );
    } else if (access.isNew) {
      stateLabel = l.homeNew;
      state = SizedBox(height: 22, child: Align(alignment: Alignment.centerLeft, child: NewPill(label: l.homeNew)));
    }

    return JwLayoutCard.tiles(
      key: ValueKey('layout-card-${info.id}'),
      name: info.name,
      tiles: LayoutLabels.tiles(info),
      meta: access.locked ? null : meta,
      stateRow: state,
      locked: access.locked,
      plateFill: plate,
      width: double.infinity,
      // Sized by its content; the grid gives every card in a row the
      // tallest card's height.
      height: null,
      semanticLabel: [info.name, meta, if (stateLabel.isNotEmpty) stateLabel].join(', '),
      onHaptic: haptics.selection,
      onTap: access.locked
          ? () => showUnlockLayoutSheet(context, ref, info)
          : () => context.push(AppRoutes.game(info.id)),
    );
  }
}

/// A chapter that unlocks by total clears, folded into one sunken row
/// (Wonders): its badge, name, "4 layouts · unlocks at 8 clears" and a
/// lock. Tapping offers to unlock its first layout with a video.
class _LockedChapterRow extends ConsumerWidget {
  const _LockedChapterRow({
    required this.chapter,
    required this.layouts,
    required this.fill,
    required this.icon,
    required this.caption,
  });

  final ChapterInfo chapter;
  final List<LayoutInfo> layouts;
  final JwFill fill;
  final String icon;
  final String caption;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final first = layouts.first;
    final deco = jw.clay(ClayLevel.sunken, radius: 26);
    return ClayPressable(
      key: ValueKey('locked-chapter-${chapter.id}'),
      decoration: deco,
      pressedDecoration: deco,
      pressedScale: 0.98,
      onHaptic: ref.read(hapticsProvider).selection,
      onTap: () => showUnlockLayoutSheet(context, ref, first),
      semanticLabel: '${chapter.name}, ${l.homeLocked}, $caption',
      padding: const EdgeInsets.fromLTRB(16, 16, 20, 16),
      child: Row(
        children: [
          Transform.translate(offset: const Offset(0, -1.5), child: IconBadge(icon: icon, fill: fill, size: 48)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(header: true, child: Text(chapter.name, style: jw.text.button.copyWith(fontSize: 17))),
                const SizedBox(height: 2),
                Text(caption, style: jw.text.callout.copyWith(fontSize: 14, fontWeight: FontWeight.w400, color: jw.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          JwIcon(JwIcons.lock, size: 20, color: jw.textMuted),
        ],
      ),
    );
  }
}
