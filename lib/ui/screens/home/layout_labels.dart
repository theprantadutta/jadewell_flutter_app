import 'package:flutter/widgets.dart';

import '../../../data/models/catalogue.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/jw_silhouette.dart';

/// Shared presentation helpers for layouts (home, daily, statistics).
abstract final class LayoutLabels {
  static final Expando<List<SilhouetteTile>> _tiles = Expando('silhouette');

  /// Silhouette cells for [info] (cached per layout).
  static List<SilhouetteTile> tiles(LayoutInfo info) =>
      _tiles[info.layout] ??= List.unmodifiable([for (final p in info.layout.positions) SilhouetteTile(p.x, p.y, p.z)]);

  static String difficulty(AppLocalizations l, String d) => switch (d) {
        'easy' => l.difficultyEasy,
        'hard' => l.difficultyHard,
        _ => l.difficultyMedium,
      };

  /// "120 tiles · Easy".
  static String meta(AppLocalizations l, LayoutInfo info) =>
      l.tilesAndDifficulty(info.tileCount, difficulty(l, info.difficulty));

  /// Singular of a chapter name for "Clear 1 more Creature" (English data names).
  static String singular(String chapterName) =>
      chapterName.endsWith('s') ? chapterName.substring(0, chapterName.length - 1) : chapterName;
}

/// m:ss under an hour, else h:mm:ss (best times, daily clear time).
String formatClock(int ms) {
  final total = (ms / 1000).floor();
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// Content column for tablets: centred, at most [maxWidth] wide (no-op on phones).
class JwContentWidth extends StatelessWidget {
  const JwContentWidth({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}
