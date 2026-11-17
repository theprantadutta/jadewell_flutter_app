import 'package:flutter/widgets.dart';

import '../../../data/repositories/social_repository.dart';
import '../../components/components.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/skeleton/jw_skeleton.dart';
import '../../widgets/widgets.dart';
import '../settings/screen_chrome.dart';

/// Three small stars: earned ones in yellow (rewards), the rest faint.
class StarsRow extends StatelessWidget {
  const StarsRow({super.key, required this.stars, this.size = 13, this.max = 3, this.onFill});

  final int stars;
  final double size;
  final int max;

  /// Ink when drawn on a fill (the podium columns, the your-rank row).
  final Color? onFill;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < max; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 1),
            child: JwIcon(
              JwIcons.star,
              size: size,
              color: i < stars ? (onFill ?? JwFill.yellow.edge) : (onFill ?? jw.textMuted).withValues(alpha: 0.3),
            ),
          ),
      ],
    );
  }
}

/// Stars as a count for weekly totals (above 3): "★ 14".
class _StarsValue extends StatelessWidget {
  const _StarsValue({required this.stars, this.onFill});

  final int stars;
  final Color? onFill;
  static const size = 13.0;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    if (stars <= 3) return StarsRow(stars: stars, size: size, onFill: onFill);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        JwIcon(JwIcons.star, size: size + 1, color: onFill ?? JwFill.yellow.edge),
        const SizedBox(width: 3),
        Text('$stars', style: jw.text.numM.copyWith(fontSize: size + 2, color: onFill ?? jw.textMuted)),
      ],
    );
  }
}

String _entryLabel(AppLocalizations l, LeaderboardEntry e) =>
    l.leaderboardEntrySemantics(e.rank, e.displayName, e.stars, formatClock(e.timeMs));

Widget _avatar(BuildContext context, LeaderboardEntry e, double size, {JwFill? fill}) => JwAvatar(
      name: e.displayName,
      size: size,
      fill: fill ?? avatarFill(e.avatarColor, e.displayName),
    );

/// Podium column fill by rank (1 yellow, 2 sky, 3 coral).
JwFill podiumFill(int rank) => switch (rank) {
      1 => JwFill.yellow,
      2 => JwFill.sky,
      _ => JwFill.coral,
    };

/// Top three: avatars over raised blocks, 1st in the middle and tallest.
class Podium extends StatelessWidget {
  const Podium({super.key, required this.entries});

  /// Up to three, in rank order.
  final List<LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    final slots = <(LeaderboardEntry?, double, bool)>[
      (entries.length > 1 ? entries[1] : null, 118, false),
      (entries.isNotEmpty ? entries[0] : null, 150, true),
      (entries.length > 2 ? entries[2] : null, 100, false),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Expanded(child: _PodiumSlot(entry: slots[i].$1, height: slots[i].$2, first: slots[i].$3)),
          ],
        ],
      ),
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  const _PodiumSlot({required this.entry, required this.height, required this.first});

  final LeaderboardEntry? entry;
  final double height;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final e = entry;
    if (e == null) {
      return DecoratedBox(
        decoration: jw.clay(ClayLevel.sunken, radius: 22),
        child: SizedBox(height: height),
      );
    }
    final fill = podiumFill(e.rank);
    return Semantics(
      label: _entryLabel(l, e),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _avatar(context, e, first ? 54 : 44, fill: fill),
          const SizedBox(height: 8),
          Text(
            e.isMe ? l.leaderboardYou : e.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: jw.text.callout.copyWith(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          // A fill column; its 5 pt base edge paints below the box.
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: FillBox(
              fill: fill,
              radius: 22,
              glow: false,
              width: double.infinity,
              height: height,
              padding: const EdgeInsets.only(top: 14),
              child: Column(
                children: [
                  Text('${e.rank}', style: jw.text.numL.copyWith(fontSize: 28, height: 1.1, color: fill.on)),
                  const SizedBox(height: 4),
                  _StarsValue(stars: e.stars, onFill: fill.on),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(formatClock(e.timeMs), style: jw.text.numM.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: fill.on)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A ranked row: rank, avatar, name, stars and time in mono.
class LeaderboardRow extends StatelessWidget {
  const LeaderboardRow({super.key, required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final e = entry;
    return Semantics(
      label: _entryLabel(l, e),
      excludeSemantics: true,
      child: ColoredBox(
        color: e.isMe ? jw.accentSoft.withValues(alpha: 0.45) : JwBase.transparent,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text('${e.rank}', style: jw.text.numM.copyWith(fontSize: 16, color: jw.textMuted)),
                ),
                const SizedBox(width: 4),
                _avatar(context, e, 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    e.isMe ? l.leaderboardYou : e.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: jw.text.body.copyWith(fontSize: 16.5, fontWeight: e.isMe ? FontWeight.w600 : FontWeight.w400),
                  ),
                ),
                _StarsValue(stars: e.stars),
                const SizedBox(width: 12),
                Text(formatClock(e.timeMs), style: jw.text.numM.copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The pinned "You · Top 18% today" row: a purple fill row (radius 24).
class YouRow extends StatelessWidget {
  const YouRow({super.key, required this.me, required this.caption});

  final LeaderboardMe me;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final e = me.entry;
    const fill = JwFill.purple;
    final on = fill.on;
    return Semantics(
      label: '${_entryLabel(l, e)}. $caption',
      excludeSemantics: true,
      child: FillBox(
        fill: fill,
        radius: 24,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 36),
              child: Text('${e.rank}', style: jw.text.numM.copyWith(fontSize: 17, fontWeight: FontWeight.w700, color: on)),
            ),
            const SizedBox(width: 4),
            DecoratedBox(
              decoration: jw.clay(ClayLevel.chip, color: on),
              child: SizedBox.square(
                dimension: 40,
                child: Center(
                  child: Text(
                    l.leaderboardYou.characters.first.toUpperCase(),
                    style: jw.text.callout.copyWith(fontSize: 16, fontWeight: FontWeight.w700, color: fill.edge),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.leaderboardYou, style: jw.text.button.copyWith(fontSize: 16.5, color: on)),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: jw.text.callout.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: on),
                  ),
                ],
              ),
            ),
            _StarsValue(stars: e.stars, onFill: on),
            const SizedBox(width: 12),
            Text(formatClock(e.timeMs), style: jw.text.numM.copyWith(fontSize: 18, fontWeight: FontWeight.w700, color: on)),
          ],
        ),
      ),
    );
  }
}

/// Empty-state illustration (17b): three sunken podium blocks with a
/// yellow trophy badge resting on the tallest.
class EmptyPodium extends StatelessWidget {
  const EmptyPodium({super.key});

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    Widget block(double h) => DecoratedBox(
          decoration: jw.clay(ClayLevel.sunken, radius: 22),
          child: SizedBox(width: 56, height: h),
        );
    return SizedBox(
      height: 168,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          block(78),
          const SizedBox(width: 6),
          SizedBox(
            width: 56,
            height: 168,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                block(128),
                const Positioned(
                  top: 0,
                  child: IconBadge(icon: JwIcons.trophy, fill: JwFill.yellow, size: 52),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          block(60),
        ],
      ),
    );
  }
}

/// Placeholder while the first page loads: podium blocks and a few rows.
class LeaderboardSkeleton extends StatelessWidget {
  const LeaderboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 30, 32, 0),
        children: [
          const SizedBox(
            height: 200,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: JwSkeletonBox(height: 150, radius: 22)),
                SizedBox(width: 12),
                Expanded(child: JwSkeletonBox(height: 196, radius: 22)),
                SizedBox(width: 12),
                Expanded(child: JwSkeletonBox(height: 130, radius: 22)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < 5; i++) ...[
            const JwSkeletonBox(height: 44, radius: 16),
            const SizedBox(height: 10),
          ],
        ],
      );
}
