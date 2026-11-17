import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/progress.dart';
import '../../../state/data_providers.dart';
import '../../../state/platform_providers.dart';
import '../../components/components.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../router.dart';
import '../../theme/clay.dart';
import '../../theme/jw_background.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/skeleton/jw_skeleton.dart';
import '../../widgets/widgets.dart';
import '../home/layout_card_parts.dart';
import '../home/layout_labels.dart';
import '../settings/screen_chrome.dart' show kMetaBlobs;
import 'countdown.dart';
import 'daily_top_three.dart';
import 'streak_repair_card.dart';

/// Daily challenge (screen 12): today's board, countdown, streak week and
/// the top-3 preview.
class DailyScreen extends ConsumerWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final daily = ref.watch(dailyProvider).value;
    final catalogue = ref.watch(catalogueProvider).value;
    final info = daily == null ? null : catalogue?.layouts[daily.layoutId];
    final haptics = ref.read(hapticsProvider);
    final date = daily == null ? null : DateTime.parse(daily.date);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: jw.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: JwBackground(
          blobs: kMetaBlobs,
          child: SafeArea(
            child: JwContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _TopBar(
                      title: l.dailyTitle,
                      subtitle: date == null ? '' : DateFormat('EEEE d MMMM', l.localeName).format(date),
                      trailing: JwIconButton(
                        icon: JwIcons.trophy,
                        semanticLabel: l.dailyLeaderboard,
                        onHaptic: haptics.selection,
                        onPressed: () => context.push(AppRoutes.leaderboard),
                      ),
                    ),
                  ),
                  Expanded(
                    child: daily == null || info == null
                        ? const JwSkeletonScope(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                              child: Column(
                                children: [
                                  JwSkeletonBox(height: 400, radius: 34),
                                  SizedBox(height: 24),
                                  JwSkeletonBox(height: 90, radius: 24),
                                ],
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 22, 16, 24),
                            children: [
                              JwFadeUp(child: _BoardCard(daily: daily, name: info.name, meta: l.dailyMeta(info.tileCount, LayoutLabels.difficulty(l, info.difficulty)), tiles: LayoutLabels.tiles(info))),
                              const SizedBox(height: 28),
                              JwFadeUp(index: 1, child: _StreakWeek(daily: daily)),
                              const StreakRepairCard(),
                              const SizedBox(height: 24),
                              const JwFadeUp(index: 2, child: _TopThree()),
                            ],
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                    child: daily != null && daily.clearedToday
                        ? JwButton.secondary(
                            label: l.dailyPlayAgain,
                            icon: JwIcons.replay,
                            expand: true,
                            onHaptic: haptics.light,
                            onPressed: () => context.push(AppRoutes.dailyPlay),
                          )
                        : PrimaryButton(
                            label: l.dailyPlay,
                            icon: JwIcons.play,
                            height: 62,
                            expand: true,
                            onHaptic: haptics.light,
                            onPressed: daily == null ? null : () => context.push(AppRoutes.dailyPlay),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Back button, title + subtitle, optional trailing action.
class _TopBar extends ConsumerWidget {
  const _TopBar({required this.title, required this.subtitle, this.trailing});

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        JwIconButton(
          icon: JwIcons.back,
          semanticLabel: l.navBack,
          onHaptic: ref.read(hapticsProvider).selection,
          onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(title, style: jw.text.h1.copyWith(fontSize: 28, height: 1.15))),
              if (subtitle.isNotEmpty)
                Text(subtitle, style: jw.text.body.copyWith(fontSize: 16, color: jw.textMuted, height: 1.3)),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// The purple daily hero (screen 12): the silhouette on a translucent
/// plate with confetti, name, meta and the countdown in white.
class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.daily, required this.name, required this.meta, required this.tiles});

  final DailyStatus daily;
  final String name;
  final String meta;
  final List<SilhouetteTile> tiles;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final on = JwFill.purple.on;
    final body = jw.text.callout.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: on);
    return HeroCard(
      radius: 34,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: on.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(26)),
            child: CustomPaint(
              painter: ConfettiPainter(count: 6, seed: 2, exclude: JwFill.purple),
              child: SizedBox(
                height: 196,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 22),
                  child: JwSilhouette(tiles: tiles, semanticLabel: name),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: jw.text.h1.copyWith(fontSize: 30, height: 1.1, color: on)),
                const SizedBox(height: 6),
                Text(meta, style: body),
                if (daily.clearedToday) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Transform.translate(offset: const Offset(0, -1.5), child: const CheckDisc(size: 26)),
                      const SizedBox(width: 10),
                      Flexible(child: Text(l.dailyClearedIn(formatClock(daily.firstClearMs!)), style: body)),
                      const SizedBox(width: 10),
                      StarRow(
                        earned: daily.firstClearStars ?? 0,
                        size: 15,
                        semanticLabel: l.homeStarsSemantics(daily.firstClearStars ?? 0),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                DailyCountdown(
                  builder: (context, left) => Semantics(
                    label: '${l.dailyEndsIn} ${formatCountdown(left)}',
                    excludeSemantics: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        JwIcon(JwIcons.clock, size: 19, color: on),
                        const SizedBox(width: 8),
                        Text(l.dailyEndsIn, style: body.copyWith(fontSize: 15.5)),
                        const SizedBox(width: 12),
                        RollingText(formatCountdown(left), style: jw.text.numM.copyWith(fontSize: 21, fontWeight: FontWeight.w700, color: on)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakWeek extends StatelessWidget {
  const _StreakWeek({required this.daily});

  final DailyStatus daily;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final today = DateTime.parse(daily.date);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final narrow = DateFormat('EEEEE', l.localeName);
    final full = DateFormat('EEEE', l.localeName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, right: 6),
          child: Row(
            children: [
              Transform.translate(
                offset: const Offset(0, -1.5),
                child: const IconBadge(icon: JwIcons.flame, fill: JwFill.coral, size: 32),
              ),
              const SizedBox(width: 12),
              Expanded(child: Semantics(header: true, child: Text(l.dailyStreak, style: jw.text.h3.copyWith(fontSize: 20)))),
              // Coral is allowed as text at >= 18 pt bold (DESIGN_SYSTEM §3).
              Text('${daily.streak}', style: jw.text.numM.copyWith(fontSize: 19, fontWeight: FontWeight.w700, color: JwFill.coral.edge)),
              const SizedBox(width: 6),
              Text(l.dailyStreakDays(daily.streak), style: jw.text.body.copyWith(fontSize: 16, color: jw.textMuted)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 7; i++)
              Builder(
                builder: (context) {
                  final day = monday.add(Duration(days: i));
                  final done = i < daily.weekDone.length && daily.weekDone[i];
                  final isToday = i == today.weekday - 1;
                  final label = done
                      ? l.dailyDayDone(full.format(day))
                      : (isToday ? l.dailyDayToday(full.format(day)) : full.format(day));
                  return Semantics(
                    label: label,
                    excludeSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        children: [
                          _DayBead(done: done, today: isToday, day: day.day),
                          const SizedBox(height: 10),
                          Text(narrow.format(day), style: jw.text.callout.copyWith(fontSize: 15, color: jw.textMuted, fontWeight: FontWeight.w400)),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// A streak day dot: mint check when done, a raised dot with the date for
/// today, a sunken dot otherwise.
class _DayBead extends StatelessWidget {
  const _DayBead({required this.done, required this.today, required this.day});

  final bool done;
  final bool today;
  final int day;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    const size = 38.0;
    final Widget dot;
    if (done) {
      dot = const CheckDisc(size: size, round: true);
    } else {
      dot = DecoratedBox(
        decoration: today ? jw.clay(ClayLevel.chip, gradient: jw.knobGradient) : jw.clay(ClayLevel.sunken),
        child: SizedBox.square(
          dimension: size,
          child: today
              ? Center(child: Text('$day', style: jw.text.numM.copyWith(fontSize: 14.5, fontWeight: FontWeight.w700, color: jw.purpleText)))
              : null,
        ),
      );
    }
    // Room for the mint dot's 3 pt base edge.
    return SizedBox(width: size, height: size + 3, child: Align(alignment: Alignment.topCenter, child: dot));
  }
}

/// Trophy badge fill for a podium rank (1 yellow, 2 sky, 3 coral).
JwFill rankFill(int rank) => switch (rank) {
      1 => JwFill.yellow,
      2 => JwFill.sky,
      _ => JwFill.coral,
    };

class _TopThree extends ConsumerWidget {
  const _TopThree();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final rows = ref.watch(dailyTopThreeProvider).value ?? const <DailyTopEntry>[];
    if (rows.isEmpty) {
      return JwListGroup(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                const JwIconWell(icon: JwIcons.trophy, size: 40, fill: JwFill.yellow),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.dailyBeFirst, style: jw.text.body.copyWith(fontSize: 16.5, fontWeight: FontWeight.w600)),
                      Text(l.dailyBeFirstBody, style: jw.text.caption.copyWith(fontSize: 14, fontWeight: FontWeight.w400)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return JwListGroup(
      children: [
        for (final r in rows.take(3))
          Semantics(
            label: '${r.rank}, ${r.name}, ${formatClock(r.timeMs)}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Transform.translate(
                    offset: const Offset(0, -1.5),
                    child: IconBadge(icon: JwIcons.trophy, fill: rankFill(r.rank), size: 30),
                  ),
                  const SizedBox(width: 12),
                  JwAvatar(name: r.name, fill: rankFill(r.rank)),
                  const SizedBox(width: 14),
                  Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jw.text.body.copyWith(fontSize: 17))),
                  Text(formatClock(r.timeMs), style: jw.text.numM.copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
