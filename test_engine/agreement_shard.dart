// Dealer ↔ solver agreement, the core of "every board is solvable"
// (brief §5.4, Appendix B): for every bundled layout and 5,000 seeds in each
// dealer mode, the forward solver (which never sees the construction order)
// must confirm the deal within its verification budget. Unsolvable or
// budget-exceeded verdicts fail the suite.
//
// Run with ENGINE_STATS=1 to print max solver nodes / time per layout.
// Split into shards (agreement_<k>_test.dart) so `dart test` runs them in
// parallel.

import 'dart:io';

import 'package:jadewell_flutter_app/engine/engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const int kAgreementSeeds = 5000;
const int kShards = 4;

void runAgreementShard(int shard) {
  final files = bundledLayoutFiles();
  for (var i = shard; i < files.length; i += kShards) {
    final file = files[i];
    final name = file.uri.pathSegments.last.replaceAll('.json', '');
    for (final (mode, options) in [('unbiased', DealerOptions.unbiased), ('production', DealerOptions.production)]) {
      test('$name: $kAgreementSeeds seeds, $mode dealer', () {
        final layout = Layout.parse(file.readAsStringSync());
        var maxNodes = 0, maxSeed = 0, maxUs = 0, maxAttempt = 0;
        final sw = Stopwatch()..start();
        for (var k = 0; k < kAgreementSeeds; k++) {
          // Unbiased: seeds 0…4999. Production: spread over the 32-bit range.
          final seed = mode == 'unbiased' ? k : deriveSeed(0x5EED0000 + i, k);
          final d = deal(layout, seed, options: options);
          expect(isValidSolution(layout, d.faces, d.solution), isTrue, reason: '$name seed $seed construction');
          final t0 = sw.elapsedMicroseconds;
          final r = solve(layout, d.faces);
          final us = sw.elapsedMicroseconds - t0;
          if (r is! SolveSolvable) fail('$name seed $seed ($mode): dealer and solver disagree: $r');
          expect(isValidSolution(layout, d.faces, r.solution), isTrue, reason: '$name seed $seed solver solution');
          if (r.nodes > maxNodes) {
            maxNodes = r.nodes;
            maxSeed = seed;
          }
          if (us > maxUs) maxUs = us;
          if (d.attempt > maxAttempt) maxAttempt = d.attempt;
        }
        final summary =
            'agreement $name ($mode): $kAgreementSeeds/$kAgreementSeeds solvable, '
            'max nodes $maxNodes (seed $maxSeed) of budget $kVerifyBudget, '
            'max solve ${(maxUs / 1000).toStringAsFixed(1)} ms, max attempt $maxAttempt, '
            'total ${sw.elapsedMilliseconds} ms';
        // Set ENGINE_STATS=1 to print the per-layout numbers.
        if (Platform.environment['ENGINE_STATS'] == '1') stdout.writeln(summary);
      }, timeout: const Timeout(Duration(minutes: 5)));
    }
  }
}
