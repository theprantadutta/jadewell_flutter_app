import 'package:flutter/foundation.dart';

/// What the game screen was opened for: a layout from the collection, or
/// today's daily board. Family key of `gameControllerProvider`.
@immutable
class GameLaunch {
  const GameLaunch({required this.layoutId, this.daily = false, this.seed});

  /// A collection layout.
  const GameLaunch.layout(this.layoutId, {this.seed}) : daily = false;

  /// Today's daily board (layout and seed come from `dailyProvider`).
  const GameLaunch.daily() : layoutId = '', daily = true, seed = null;

  /// Layout id; empty for the daily, which resolves it from `dailyProvider`.
  final String layoutId;
  final bool daily;

  /// Deal seed override (tests, replays). Null deals a random seed (or the
  /// daily seed).
  final int? seed;

  @override
  bool operator ==(Object other) =>
      other is GameLaunch && other.layoutId == layoutId && other.daily == daily && other.seed == seed;

  @override
  int get hashCode => Object.hash(layoutId, daily, seed);

  @override
  String toString() => daily ? 'GameLaunch.daily()' : 'GameLaunch($layoutId${seed == null ? '' : ', seed $seed'})';
}
