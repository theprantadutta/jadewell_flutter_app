import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/social_repository.dart';
import '../../../state/social_providers.dart';

/// One row of today's top-3 preview on the daily screen.
class DailyTopEntry {
  const DailyTopEntry({required this.rank, required this.name, required this.timeMs, this.stars = 0});

  final int rank;
  final String name;
  final int timeMs;
  final int stars;
}

/// Today's top three, from the (cached, kept-alive) daily leaderboard tab.
/// Empty while offline or before anyone has a verified result.
final dailyTopThreeProvider = FutureProvider.autoDispose<List<DailyTopEntry>>((ref) async {
  final view = await ref.watch(leaderboardProvider(LeaderboardKind.daily).future);
  final entries = view.page?.entries ?? const [];
  return [
    for (final e in entries.take(3))
      DailyTopEntry(rank: e.rank, name: e.displayName, timeMs: e.timeMs, stars: e.stars),
  ];
});
