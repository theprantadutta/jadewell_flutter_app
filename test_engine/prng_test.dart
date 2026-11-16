import 'dart:convert';
import 'dart:io';

import 'package:jadewell_flutter_app/engine/engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

// Golden values computed independently (Python reference implementation with
// arbitrary-precision ints masked to 32 bits), not by this engine.
void main() {
  group('mul32 / rotl32', () {
    test('wraps like unsigned 32-bit', () {
      expect(mul32(0xFFFFFFFF, 0xFFFFFFFF), 1);
      expect(mul32(0x80000000, 2), 0);
      expect(mul32(0x12345678, 0x9ABCDEF0), (0x12345678 * 0x9ABCDEF0) & 0xFFFFFFFF);
      expect(mul32(123456789, 987654321), (123456789 * 987654321) & 0xFFFFFFFF);
      expect(rotl32(0x80000001, 1), 0x00000003);
      expect(rotl32(0x12345678, 8), 0x34567812);
    });
  });

  group('xoshiro128** seeded by splitmix32', () {
    const goldens = {
      0: [3809008728, 1133695204, 53579671, 2891528803, 139681546, 2203266335],
      1: [2442144158, 3238099751, 3819917871, 2104621829, 2021136066, 4223536128],
      42: [2837322924, 544945897, 479756282, 3500138142, 339756180, 113173290],
      0xFFFFFFFF: [835879718, 1921286648, 2356205009, 1885780724, 980451116, 1053911718],
    };
    goldens.forEach((seed, expected) {
      test('seed $seed', () {
        final rng = Xoshiro128(seed);
        expect([for (var i = 0; i < expected.length; i++) rng.nextUint32()], expected);
      });
    });

    test('nextInt is unbiased rejection sampling (goldens)', () {
      final rng = Xoshiro128(42);
      final ns = [1, 2, 3, 10, 144, 1000, 0x80000001, 0x100000000];
      expect([for (final n in ns) rng.nextInt(n)], [0, 1, 2, 2, 132, 290, 65323186, 1112262688]);
    });

    test('nextInt range and rejects bad n', () {
      final rng = Xoshiro128(7);
      for (var i = 0; i < 2000; i++) {
        final v = rng.nextInt(13);
        expect(v, inInclusiveRange(0, 12));
      }
      expect(() => rng.nextInt(0), throwsRangeError);
      expect(() => rng.nextInt(0x100000001), throwsRangeError);
    });

    test('roughly uniform', () {
      final rng = Xoshiro128(99);
      final counts = List.filled(6, 0);
      for (var i = 0; i < 60000; i++) {
        counts[rng.nextInt(6)]++;
      }
      for (final c in counts) {
        expect(c, inInclusiveRange(9500, 10500));
      }
    });

    test('all-zero state is replaced', () {
      final rng = Xoshiro128.fromState(0, 0, 0, 0);
      expect(rng.state, [1, 0, 0, 0]);
    });

    test('shuffle is Fisher-Yates from the top', () {
      final list = [0, 1, 2, 3, 4];
      Xoshiro128(5).shuffle(list);
      final rng = Xoshiro128(5);
      final expected = [0, 1, 2, 3, 4];
      for (var i = 4; i > 0; i--) {
        final j = rng.nextInt(i + 1);
        final t = expected[i];
        expected[i] = expected[j];
        expected[j] = t;
      }
      expect(list, expected);
    });
  });

  group('FNV-1a 32', () {
    test('reference vectors', () {
      expect(fnv1a32(''), 0x811C9DC5);
      expect(fnv1a32('a'), 0xE40C292C);
      expect(fnv1a32('foobar'), 0xBF9CF968);
    });
    test('hashes UTF-8 bytes', () {
      expect(fnv1a32('é'), isNot(fnv1a32('e')));
    });
  });

  group('seed derivation', () {
    test('goldens', () {
      expect(deriveSeed(42, 1), 939911724);
      expect(deriveSeed(42, 2), 3948730756);
      expect(deriveSeed(0, 1), 2462723854);
      expect(shuffleSeed(42, 0), 429742635);
      expect(attemptSeed(42, 0), 42);
      expect(attemptSeed(42, 3), deriveSeed(42, 3));
    });
  });

  group('daily seed', () {
    test('key format and golden', () {
      final d = DateTime.utc(2026, 11, 16);
      expect(dailySeedKey(d, 'turtle', 1), '2026-11-16|turtle|1');
      expect(dailySeed(d, 'turtle', 1), 3850022033);
    });
    test('uses the UTC date of the instant', () {
      final late = DateTime.utc(2026, 1, 5, 23, 59, 59);
      expect(dailySeedKey(late, 'x', 1), '2026-01-05|x|1');
      final local = DateTime.utc(2026, 3, 1, 12).toLocal();
      expect(dailySeedKey(local, 'x', 1), '2026-03-01|x|1');
    });
    test('changes with each input', () {
      final d = DateTime.utc(2026, 11, 16);
      final base = dailySeed(d, 'turtle', 1);
      expect(dailySeed(DateTime.utc(2026, 11, 17), 'turtle', 1), isNot(base));
      expect(dailySeed(d, 'dragon', 1), isNot(base));
      expect(dailySeed(d, 'turtle', 2), isNot(base));
    });
  });

  group('fixtures/deals/prng.json', () {
    test('matches the engine', () {
      final json = jsonDecode(File('$repoRoot/fixtures/deals/prng.json').readAsStringSync()) as Map<String, Object?>;
      for (final e in (json['xoshiro128ss'] as List<Object?>).cast<Map<String, Object?>>()) {
        final rng = Xoshiro128(e['seed'] as int);
        final out = (e['outputs'] as List<Object?>).cast<int>();
        expect([for (var i = 0; i < out.length; i++) rng.nextUint32()], out, reason: 'seed ${e['seed']}');
      }
      for (final e in (json['nextInt'] as List<Object?>).cast<Map<String, Object?>>()) {
        final rng = Xoshiro128(e['seed'] as int);
        final ns = (e['n'] as List<Object?>).cast<int>();
        expect([for (final n in ns) rng.nextInt(n)], (e['outputs'] as List<Object?>).cast<int>());
      }
      for (final e in (json['fnv1a32'] as List<Object?>).cast<Map<String, Object?>>()) {
        expect(fnv1a32(e['input'] as String), e['hash']);
      }
      for (final e in (json['dailySeed'] as List<Object?>).cast<Map<String, Object?>>()) {
        final d = DateTime.parse('${e['date']}T00:00:00Z');
        expect(dailySeedKey(d, e['layoutId'] as String, e['generatorVersion'] as int), e['key']);
        expect(dailySeed(d, e['layoutId'] as String, e['generatorVersion'] as int), e['seed']);
      }
      for (final e in (json['shuffleSeed'] as List<Object?>).cast<Map<String, Object?>>()) {
        expect(shuffleSeed(e['dealSeed'] as int, e['index'] as int), e['subSeed']);
      }
      for (final e in (json['attemptSeed'] as List<Object?>).cast<Map<String, Object?>>()) {
        expect(attemptSeed(e['seed'] as int, e['attempt'] as int), e['attemptSeed']);
      }
    });
  });
}
