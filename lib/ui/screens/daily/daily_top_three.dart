import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One row of today's top-3 preview on the daily screen.
class DailyTopEntry {
  const DailyTopEntry({required this.rank, required this.name, required this.timeMs});

  final int rank;
  final String name;
  final int timeMs;
}

/// Today's top three on the daily leaderboard.
///
/// TODO(leaderboard): replace with the state layer's daily leaderboard
/// provider (top 3 of today's board from the backend, cached). Until then it
/// is always empty and the daily screen shows "Be the first today".
final dailyTopThreeProvider = FutureProvider.autoDispose<List<DailyTopEntry>>((ref) async => const []);
