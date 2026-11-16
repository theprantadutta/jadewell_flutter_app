import 'prng.dart';

/// The daily-board seed: FNV-1a 32 of `"YYYY-MM-DD|layoutId|generatorVersion"`.
///
/// The date is taken in UTC: a non-UTC [utcDate] is converted with
/// `toUtc()` first. Year is zero-padded to 4 digits, month and day to 2,
/// the generator version is plain decimal. Example: 2026-11-16, turtle, 1
/// hashes `"2026-11-16|turtle|1"`.
int dailySeed(DateTime utcDate, String layoutId, int generatorVersion) =>
    fnv1a32(dailySeedKey(utcDate, layoutId, generatorVersion));

/// The exact string hashed by [dailySeed].
String dailySeedKey(DateTime utcDate, String layoutId, int generatorVersion) {
  final d = utcDate.isUtc ? utcDate : utcDate.toUtc();
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day|$layoutId|$generatorVersion';
}

/// Days since 1970-01-01 (UTC) for [utcDate]'s calendar day.
int utcDayNumber(DateTime utcDate) {
  final d = utcDate.isUtc ? utcDate : utcDate.toUtc();
  return DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

/// Today's daily layout id. The pool is walked in cycles of `pool.length`
/// days; each cycle uses its own deterministic shuffle (xoshiro128** seeded
/// with `fnv1a32("daily-cycle|<cycle>")`), so no layout repeats within a
/// cycle and every player (and the server) picks the same one offline.
/// [pool] order matters: it is `index.json`'s `dailyPool` as written.
String dailyLayoutId(DateTime utcDate, List<String> pool) {
  if (pool.isEmpty) throw ArgumentError('empty daily pool');
  final day = utcDayNumber(utcDate);
  final cycle = day ~/ pool.length;
  final order = List<String>.of(pool);
  Xoshiro128(fnv1a32('daily-cycle|$cycle')).shuffle(order);
  return order[day % pool.length];
}
