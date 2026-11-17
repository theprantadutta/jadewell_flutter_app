import 'package:flutter/widgets.dart';

import '../../../data/repositories/social_repository.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../widgets/skeleton/jw_skeleton.dart';
import '../../widgets/widgets.dart';
import '../settings/screen_chrome.dart';

/// Three small stars: earned ones in accent, the rest faint.
class StarsRow extends StatelessWidget {
  const StarsRow({super.key, required this.stars, this.size = 13, this.max = 3});

  final int stars;
  final double size;
  final int max;

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
              color: i < stars ? jw.accent : jw.textMuted.withValues(alpha: 0.3),
            ),
          ),
      ],
    );
  }
}

/// Stars as a count for weekly totals (above 3): "★ 14".
class _StarsValue extends StatelessWidget {
  const _StarsValue({required this.stars});

  final int stars;
  static const size = 13.0;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    if (stars <= 3) return StarsRow(stars: stars, size: size);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        JwIcon(JwIcons.star, size: size + 1, color: jw.accent),
        const SizedBox(width: 3),
        Text('$stars', style: jw.text.numM.copyWith(fontSize: size + 2, color: jw.textMuted)),
      ],
    );
  }
}

String _entryLabel(AppLocalizations l, LeaderboardEntry e) =>
    l.leaderboardEntrySemantics(e.rank, e.displayName, e.stars, formatClock(e.timeMs));

Widget _avatar(BuildContext context, LeaderboardEntry e, double size) => JwAvatar(
      name: e.displayName,
      size: size,
      color: avatarPastel(e.avatarColor, context.jw),
    );

/// Top three: avatars over raised blocks, 1st in the middle and tallest.
class Podium extends StatelessWidget {
  const Podium({super.key, required this.entries});

  /// Up to three, in rank order.
  final List<LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    final slots = <(LeaderboardEntry?, double, bool)>[
      (entries.length > 1 ? entries[1] : null, 118, false),
      (entries.isNotEmpty ? entries[0] : null, 146, true),
      (entries.length > 2 ? entries[2] : null, 100, false),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 12),
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
    return Semantics(
      label: _entryLabel(l, e),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _avatar(context, e, first ? 54 : 44),
          const SizedBox(height: 8),
          Text(
            e.isMe ? l.leaderboardYou : e.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: jw.text.callout.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: jw.clay(ClayLevel.raised, radius: 22),
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  children: [
                    Text(
                      '${e.rank}',
                      style: jw.text.h1.copyWith(fontSize: 30, color: first ? jw.accent : jw.textPrimary, height: 1.1),
                    ),
                    const SizedBox(height: 6),
                    _StarsValue(stars: e.stars),
                    const SizedBox(height: 4),
                    Text(formatClock(e.timeMs), style: jw.text.numM.copyWith(fontSize: 15, color: jw.textMuted)),
                  ],
                ),
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
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text('${e.rank}', style: jw.text.numM.copyWith(fontSize: 16, color: jw.textMuted)),
                ),
                const SizedBox(width: 4),
                _avatar(context, e, 32),
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
                Text(formatClock(e.timeMs), style: jw.text.numM.copyWith(fontSize: 17)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The pinned "You · Top 18% today" card.
class YouRow extends StatelessWidget {
  const YouRow({super.key, required this.me, required this.caption});

  final LeaderboardMe me;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final e = me.entry;
    return Semantics(
      label: '${_entryLabel(l, e)}. $caption',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: jw.clay(ClayLevel.raised, radius: 28),
        child: SizedBox(
          height: 66,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text('${e.rank}', style: jw.text.numM.copyWith(fontSize: 17, color: jw.accent)),
                ),
                DecoratedBox(
                  decoration: jw.clay(ClayLevel.chip, color: jw.accent),
                  child: SizedBox.square(
                    dimension: 40,
                    child: Center(
                      child: Text(
                        l.leaderboardYou.characters.first.toUpperCase(),
                        style: jw.text.callout.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: jw.onAccent),
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
                      Text(l.leaderboardYou, style: jw.text.callout.copyWith(fontSize: 16.5, fontWeight: FontWeight.w600)),
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: jw.text.callout.copyWith(fontSize: 14, color: jw.textMuted),
                      ),
                    ],
                  ),
                ),
                _StarsValue(stars: e.stars),
                const SizedBox(width: 12),
                Text(formatClock(e.timeMs), style: jw.text.numM.copyWith(fontSize: 17)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty-state illustration (17b): three sunken podium blocks with an
/// accent bead resting above the tallest.
class EmptyPodium extends StatelessWidget {
  const EmptyPodium({super.key});

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    Widget block(double h) => DecoratedBox(
          decoration: jw.clay(ClayLevel.sunken, radius: 22),
          child: SizedBox(width: 52, height: h),
        );
    return SizedBox(
      height: 146,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          block(70),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              JwBead(color: jw.accent, size: 36),
              const SizedBox(height: 8),
              block(100),
            ],
          ),
          const SizedBox(width: 6),
          block(54),
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
