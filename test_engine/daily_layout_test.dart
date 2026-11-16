import 'package:jadewell_flutter_app/engine/engine.dart';
import 'package:test/test.dart';

void main() {
  const pool = ['lotus', 'lantern', 'fan', 'bonsai', 'koi', 'gate', 'moon', 'bell'];

  test('no repeats within a cycle and every layout appears once per cycle', () {
    for (var cycle = 0; cycle < 50; cycle++) {
      final start = DateTime.utc(1970).add(Duration(days: (2500 + cycle) * pool.length));
      final ids = [for (var i = 0; i < pool.length; i++) dailyLayoutId(start.add(Duration(days: i)), pool)];
      expect(ids.toSet(), pool.toSet());
    }
  });

  test('deterministic and independent of the time of day', () {
    final a = dailyLayoutId(DateTime.utc(2026, 11, 16, 0, 1), pool);
    final b = dailyLayoutId(DateTime.utc(2026, 11, 16, 23, 59), pool);
    expect(a, b);
    expect(utcDayNumber(DateTime.utc(1970, 1, 2)), 1);
  });

  test('golden values (shared with the C# port)', () {
    final got = [for (var d = 0; d < 10; d++) dailyLayoutId(DateTime.utc(2026, 11, 16).add(Duration(days: d)), pool)];
    expect(got, ['koi', 'moon', 'lotus', 'bell', 'bonsai', 'moon', 'gate', 'lantern', 'lotus', 'fan']);
  });
}
