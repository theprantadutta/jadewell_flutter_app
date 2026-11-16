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
