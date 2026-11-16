import 'dart:math' as math;

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
import '../../l10n/generated/app_localizations.dart';
import '../../router.dart';
import '../../theme/clay.dart';
import '../../theme/jw_background.dart';
import '../../theme/jw_theme.dart';
import '../../widgets/skeleton/jw_skeleton.dart';
import '../../widgets/widgets.dart';
import '../daily/countdown.dart';
import 'layout_card_parts.dart';
import 'layout_labels.dart';
import 'unlock_sheet.dart';

/// Layout select: progress, daily card, chapters with cards (screen 11);
/// the first-run "collection is waiting" variant (17a); skeleton (18).
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
          child: SafeArea(
            bottom: false,
            child: JwContentWidth(
              maxWidth: 720,
              child: LayoutBuilder(
                builder: (context, box) {
                  final columns = _columnsFor(box.maxWidth);
                  return JwSkeletonSwitcher(
                    loading: loading,
                    skeleton: JwSkeletonHome(title: l.appName, columns: columns, semanticLabel: l.commonLoading),
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

  static int _columnsFor(double width) => ((width - 32 + 14) / (172 + 14)).floor().clamp(2, 3);
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent({required this.catalogue, required this.progress, required this.columns});

  final Catalogue catalogue;
  final Map<String, LayoutProgress> progress;
  final int columns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final haptics = ref.read(hapticsProvider);
    final total = catalogue.chapterLayouts.length;
    final cleared = Unlocks.totalClears(catalogue, progress);
    final firstRun = progress.values.every((p) => !p.cleared && !p.hasSavedGame && p.lastPlayedAt == null);
    final first = catalogue.chapterLayouts.first;

    var slot = 0;
    Widget fade(Widget child) => JwFadeUp(index: slot++, child: child);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          sliver: SliverList.list(
            children: [
              fade(
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Semantics(header: true, child: Text(l.appName, style: jw.text.h1.copyWith(fontSize: 34))),
                            const SizedBox(height: 6),
                            Text(
                              firstRun ? l.homeCollectionWaiting : l.homeLayoutsCleared(cleared, total),
                              style: jw.text.body.copyWith(fontSize: 16, color: jw.textMuted),
                            ),
                          ],
                        ),
                      ),
                      JwIconButton(
                        icon: JwIcons.chart,
                        semanticLabel: l.homeStatistics,
                        size: 48,
                        onHaptic: haptics.selection,
                        onPressed: () => context.push(AppRoutes.stats),
                      ),
                      const SizedBox(width: 14),
                      JwIconButton(
                        icon: JwIcons.gear,
                        semanticLabel: l.homeSettings,
                        size: 48,
                        onHaptic: haptics.selection,
                        onPressed: () => context.push(AppRoutes.settings),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              fade(
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: JwProgressTrack(
                    value: total == 0 ? 0 : math.max(cleared / total, firstRun ? 0.03 : 0),
                    semanticLabel: l.homeLayoutsCleared(cleared, total),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              fade(firstRun ? _StartHereCard(info: first) : const _DailyHeroCard()),
              for (final ch in catalogue.chapters) ...[
                const SizedBox(height: 30),
                fade(_ChapterSection(catalogue: catalogue, chapter: ch, progress: progress, columns: columns)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- hero cards

class _HeroShell extends StatelessWidget {
  const _HeroShell({required this.plate, required this.child, this.onTap, this.semanticLabel});

  final Widget plate;
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final deco = jw.clay(ClayLevel.raised, radius: 30);
    return ClayPressable(
      decoration: deco,
      pressedDecoration: deco.copyWith(level: ClayLevel.pressed),
      pressedScale: 0.985,
      onTap: onTap,
      isButton: onTap != null,
      semanticLabel: semanticLabel,
      dimWhenDisabled: false,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          DecoratedBox(
            decoration: jw.clay(ClayLevel.sunken, radius: 26),
            child: SizedBox.square(
              dimension: 122,
              child: Padding(padding: const EdgeInsets.all(14), child: plate),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _DailyHeroCard extends ConsumerWidget {
  const _DailyHeroCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final daily = ref.watch(dailyProvider).value;
    final catalogue = ref.watch(catalogueProvider).value;
    final info = daily == null ? null : catalogue?.layouts[daily.layoutId];
    if (daily == null || info == null) {
      return const JwSkeletonScope(child: JwSkeletonBox(height: 154, radius: 30));
    }
    final date = DateTime.parse(daily.date);
    final dateLabel = DateFormat('EEE d MMM', l.localeName).format(date);
    void open() => context.push(AppRoutes.daily);
    return _HeroShell(
      plate: JwSilhouette(tiles: LayoutLabels.tiles(info)),
      onTap: open,
      semanticLabel: '${l.homeDailyToday(dateLabel)}, ${info.name}, ${LayoutLabels.meta(l, info)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SoftPill(
            label: l.homeDailyToday(dateLabel),
            height: 28,
            style: jw.text.callout.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Text(info.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jw.text.h2.copyWith(fontSize: 27)),
          const SizedBox(height: 2),
          Text(LayoutLabels.meta(l, info), style: jw.text.caption.copyWith(fontSize: 14, fontWeight: FontWeight.w400)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DailyCountdown(
                  builder: (context, left) => Semantics(
                    label: l.homeDailyEndsIn(formatCountdown(left)),
                    excludeSemantics: true,
                    // Shrinks on narrow cards instead of overflowing into Play.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: RollingText(
                        formatCountdown(left),
                        style: jw.text.numM.copyWith(fontSize: 17, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              JwButton.primary(
                label: l.homePlay,
                icon: JwIcons.play,
                small: true,
                onHaptic: ref.read(hapticsProvider).light,
                onPressed: open,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StartHereCard extends ConsumerWidget {
  const _StartHereCard({required this.info});

  final LayoutInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    void open() => context.push(AppRoutes.game(info.id));
    return _HeroShell(
      plate: JwSilhouette(tiles: LayoutLabels.tiles(info)),
      onTap: open,
      semanticLabel: '${l.homeStartHere}, ${info.name}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.homeStartHere.toUpperCase(), style: jw.text.eyebrow.copyWith(color: jw.accent, fontSize: 13)),
          const SizedBox(height: 8),
          Text(info.name, style: jw.text.h3.copyWith(fontSize: 22)),
          const SizedBox(height: 2),
          Text(l.homeFirstBoardMeta(info.tileCount), style: jw.text.caption.copyWith(fontSize: 14, fontWeight: FontWeight.w400)),
          const SizedBox(height: 12),
          JwButton.primary(
            label: l.homePlayFirstBoard,
            icon: JwIcons.play,
            small: true,
            onHaptic: ref.read(hapticsProvider).light,
            onPressed: open,
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ chapters

class _ChapterSection extends ConsumerWidget {
  const _ChapterSection({required this.catalogue, required this.chapter, required this.progress, required this.columns});

  final Catalogue catalogue;
  final ChapterInfo chapter;
  final Map<String, LayoutProgress> progress;
  final int columns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final access = Unlocks.chapter(catalogue, chapter.id, progress);
    final layouts = [for (final id in chapter.layoutIds) catalogue.layout(id)];
    final anyAdUnlocked = layouts.any((i) => progress[i.id]?.adUnlocked ?? false);
    final collapsed = access.locked && chapter.unlock is UnlockTotalClears && !anyAdUnlocked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Expanded(
                child: Semantics(header: true, child: Text(chapter.name, style: jw.text.h3.copyWith(fontSize: 23))),
              ),
              Semantics(
                label: l.homeChapterProgress(access.cleared, access.total),
                excludeSemantics: true,
                child: Text(
                  '${access.cleared} / ${access.total}',
                  style: jw.text.numM.copyWith(fontSize: 16, fontWeight: FontWeight.w500, color: jw.textMuted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (collapsed)
          _LockedChapterRow(layouts: layouts, label: _chapterLockLabel(l, catalogue, chapter, access.remaining))
        else
          _CardGrid(
            columns: columns,
            children: [
              for (final info in layouts)
                _LayoutCard(
                  info: info,
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

class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 14.0;
        final w = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final c in children) SizedBox(width: w, child: c)],
        );
      },
    );
  }
}

class _LayoutCard extends ConsumerWidget {
  const _LayoutCard({required this.info, required this.progress, required this.access, required this.lockLabel});

  final LayoutInfo info;
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
    final caption = jw.text.callout.copyWith(fontSize: 14.5);

    Widget? state;
    String stateLabel = '';
    if (access.locked) {
      final label = lockLabel(access);
      stateLabel = '${l.homeLocked}, $label';
      state = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 8),
            child: JwIcon(JwIcons.lock, size: 16, color: jw.textMuted),
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
    } else if (p != null && p.hasSavedGame) {
      final pct = '${((p.savedFraction ?? 0) * 100).round()}%';
      stateLabel = '${l.homeResume} $pct';
      state = Row(
        children: [
          Text(l.homeResume, style: caption.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Expanded(child: Align(alignment: Alignment.centerLeft, child: MiniTrack(value: p.savedFraction ?? 0))),
          const SizedBox(width: 8),
          Text(pct, style: jw.text.numM.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500)),
        ],
      );
    } else if (p != null && p.cleared) {
      final best = p.bestTimeMs == null ? '' : formatClock(p.bestTimeMs!);
      stateLabel = '${l.homeBest} $best, ${l.homeStarsSemantics(p.bestStars)}';
      state = Row(
        children: [
          const CheckDisc(size: 20),
          const SizedBox(width: 6),
          Text(l.homeBest, style: caption.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(width: 5),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(best, maxLines: 1, style: jw.text.numM.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(width: 4),
          StarRow(earned: p.bestStars, size: 10, gap: 1),
        ],
      );
    } else if (access.isNew) {
      stateLabel = l.homeNew;
      state = SoftPill(label: l.homeNew, expand: true, height: 24, style: caption.copyWith(fontWeight: FontWeight.w600, fontSize: 14));
    }

    // Cards are 190 tall in the spec; the two-line lock hint needs 16 pt more.
    final scaler = MediaQuery.textScalerOf(context);
    final height = 206 + (scaler.scale(16) - 16) * 4;

    return JwLayoutCard.tiles(
      key: ValueKey('layout-card-${info.id}'),
      name: info.name,
      tiles: LayoutLabels.tiles(info),
      meta: meta,
      stateRow: state,
      locked: access.locked,
      width: double.infinity,
      height: height,
      semanticLabel: [info.name, meta, if (stateLabel.isNotEmpty) stateLabel].join(', '),
      onHaptic: haptics.selection,
      onTap: access.locked
          ? () => showUnlockLayoutSheet(context, ref, info)
          : () => context.push(AppRoutes.game(info.id)),
    );
  }
}

class _LockedChapterRow extends ConsumerWidget {
  const _LockedChapterRow({required this.layouts, required this.label});

  final List<LayoutInfo> layouts;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: jw.clay(ClayLevel.sunken, radius: 30),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  for (final info in layouts)
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: '${info.name}, ${l.homeLocked}, $label',
                        excludeSemantics: true,
                        onTap: () => showUnlockLayoutSheet(context, ref, info),
                        child: GestureDetector(
                          key: ValueKey('locked-silhouette-${info.id}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            ref.read(hapticsProvider).selection();
                            showUnlockLayoutSheet(context, ref, info);
                          },
                          child: SizedBox(
                            height: 64,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: JwSilhouette(tiles: LayoutLabels.tiles(info), locked: true),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            JwIcon(JwIcons.lock, size: 16, color: jw.textMuted),
            const SizedBox(width: 10),
            Flexible(
              flex: 2,
              child: Text(
                label,
                textAlign: TextAlign.right,
                style: jw.text.callout.copyWith(fontSize: 14.5, color: jw.textMuted, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
