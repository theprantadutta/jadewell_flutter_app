import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/catalogue.dart';
import '../../../data/models/progress.dart';
import '../../../state/data_providers.dart';
import '../../../state/platform_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../router.dart';
import '../../theme/clay.dart';
import '../../theme/jw_background.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/empty_state/jw_empty_state.dart';
import '../../widgets/skeleton/jw_skeleton.dart';
import '../../widgets/widgets.dart';
import '../home/layout_labels.dart';

/// Statistics (screens 14, 17c).
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key, this.clock = DateTime.now});

  /// For tests: "today" for the 7-day chart labels.
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final stats = ref.watch(statsProvider).value;
    final catalogue = ref.watch(catalogueProvider).value;
    final progress = ref.watch(progressProvider).value;
    final haptics = ref.read(hapticsProvider);

    Widget body;
    if (stats == null) {
      body = const JwSkeletonScope(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 22, 16, 0),
          child: Column(
            children: [
              Row(children: [Expanded(child: JwSkeletonBox(height: 104)), SizedBox(width: 14), Expanded(child: JwSkeletonBox(height: 104))]),
              SizedBox(height: 14),
              Row(children: [Expanded(child: JwSkeletonBox(height: 104)), SizedBox(width: 14), Expanded(child: JwSkeletonBox(height: 104))]),
              SizedBox(height: 14),
              JwSkeletonBox(height: 184, radius: 30),
            ],
          ),
        ),
      );
    } else if (stats.isEmpty) {
      final first = catalogue?.chapterLayouts.firstOrNull;
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 32),
        children: [
          _StatGrid(stats: stats, empty: true),
          const SizedBox(height: 64),
          JwFadeUp(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: JwEmptyState(
                illustration: const JwEmptyBars(),
                title: l.statsEmptyTitle,
                body: l.statsEmptyBody,
                actionLabel: l.statsEmptyAction,
                actionIcon: JwIcons.play,
                onHaptic: haptics.light,
                onAction: first == null ? null : () => context.push(AppRoutes.game(first.id)),
              ),
            ),
          ),
        ],
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 32),
        children: [
          JwFadeUp(child: _StatGrid(stats: stats)),
          const SizedBox(height: 14),
          JwFadeUp(index: 1, child: _WeekChart(days: stats.last7Days, today: clock())),
          if (catalogue != null && progress != null) ..._bestTimes(context, catalogue, progress),
        ],
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: jw.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: JwBackground(
          child: SafeArea(
            bottom: false,
            child: JwContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      children: [
                        JwIconButton(
                          icon: JwIcons.back,
                          semanticLabel: l.navBack,
                          onHaptic: haptics.selection,
                          onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
                        ),
                        const SizedBox(width: 22),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(header: true, child: Text(l.statsTitle, style: jw.text.h1.copyWith(fontSize: 30, height: 1.1))),
                              Text(l.statsAllTime, style: jw.text.body.copyWith(fontSize: 16, color: jw.textMuted, height: 1.3)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _bestTimes(BuildContext context, Catalogue catalogue, Map<String, LayoutProgress> progress) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final rows = [
      for (final p in progress.values)
        if (p.bestTimeMs != null && catalogue.layouts[p.layoutId] != null && !catalogue.layouts[p.layoutId]!.isDaily)
          (info: catalogue.layouts[p.layoutId]!, ms: p.bestTimeMs!),
    ]..sort((a, b) => a.ms.compareTo(b.ms));
    if (rows.isEmpty) return const [];
    return [
      const SizedBox(height: 30),
      JwFadeUp(
        index: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Semantics(header: true, child: Text(l.statsBestTimes, style: jw.text.h3.copyWith(fontSize: 22))),
        ),
      ),
      const SizedBox(height: 14),
      JwFadeUp(
        index: 3,
        child: JwListGroup(
          children: [
            for (final r in rows)
              Semantics(
                label: '${r.info.name}, ${formatClock(r.ms)}',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: jw.clay(ClayLevel.sunken, radius: 14),
                        child: SizedBox.square(
                          dimension: 40,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: JwSilhouette(tiles: LayoutLabels.tiles(r.info)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Text(r.info.name, style: jw.text.body.copyWith(fontSize: 16.5))),
                      Text(formatClock(r.ms), style: jw.text.numM.copyWith(fontSize: 16.5)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats, this.empty = false});

  final PlayerStats stats;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final n = NumberFormat.decimalPattern(l.localeName);
    final cards = [
      _StatCard(icon: JwIcons.grid, value: n.format(stats.gamesPlayed), label: l.statsGamesPlayed, empty: empty),
      _StatCard(icon: JwIcons.check, value: n.format(stats.boardsCleared), label: l.statsBoardsCleared, empty: empty),
      _StatCard(icon: JwIcons.tile, value: n.format(stats.tilesMatched), label: l.statsTilesMatched, empty: empty),
      _StatCard(
        icon: JwIcons.flame,
        value: n.format(stats.currentStreak),
        label: stats.bestStreak > 0 ? l.statsDayStreakBest(stats.bestStreak) : l.statsDayStreak,
        empty: empty,
      ),
    ];
    return Column(
      children: [
        Row(children: [Expanded(child: cards[0]), const SizedBox(width: 14), Expanded(child: cards[1])]),
        const SizedBox(height: 14),
        Row(children: [Expanded(child: cards[2]), const SizedBox(width: 14), Expanded(child: cards[3])]),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.value, required this.label, this.empty = false});

  final String icon;
  final String value;
  final String label;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Semantics(
      label: '$value $label',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: jw.clay(empty ? ClayLevel.sunken : ClayLevel.raised, radius: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 22, child: empty ? null : JwIcon(icon, size: 20, color: jw.accent)),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: jw.text.numL.copyWith(fontSize: 26, color: empty ? jw.textMuted : jw.textPrimary),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: jw.text.callout.copyWith(fontSize: 14.5, fontWeight: FontWeight.w400, color: jw.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.days, required this.today});

  /// Oldest first; last = today.
  final List<int> days;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final narrow = DateFormat('EEEEE', l.localeName);
    final full = DateFormat('EEEE', l.localeName);
    final values = days.length >= 7 ? days.sublist(days.length - 7) : [...List.filled(7 - days.length, 0), ...days];
    final total = values.fold(0, (a, b) => a + b);
    final peak = math.max(1, values.reduce(math.max));
    return DecoratedBox(
      decoration: jw.clay(ClayLevel.raised, radius: 30),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Semantics(header: true, child: Text(l.statsLast7Days, style: jw.text.h3.copyWith(fontSize: 18)))),
                Text(l.statsGamesCount(total), style: jw.text.callout.copyWith(fontWeight: FontWeight.w400, color: jw.textMuted)),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 112,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(
                      child: Semantics(
                        label: '${full.format(today.subtract(Duration(days: 6 - i)))}, ${l.statsGamesCount(values[i])}',
                        excludeSemantics: true,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: values[i] / peak),
                          duration: JwReduceMotion.of(context) ? Duration.zero : const Duration(milliseconds: 1000),
                          curve: JwMotion.easeOutSoft,
                          builder: (context, t, _) => DecoratedBox(
                            decoration: i == 6
                                ? jw.clay(ClayLevel.chip, color: jw.accent, radius: 16)
                                : jw.clay(ClayLevel.sunken, radius: 16),
                            child: SizedBox(height: 26 + 86 * t, width: double.infinity),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      narrow.format(today.subtract(Duration(days: 6 - i))),
                      textAlign: TextAlign.center,
                      style: jw.text.callout.copyWith(fontWeight: FontWeight.w400, color: jw.textMuted),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
