# Jadewell engine (`lib/engine`)

Pure Dart: no Flutter, no packages, no `dart:io`, no `dart:math` `Random`. Tested with `dart test test_engine`.
This document is the porting reference for the C# server: everything marked **(bit-exact)** must be reproduced
exactly, or boards, daily seeds and move-log replays will differ. `fixtures/deals/*.json` holds golden values for all of
it (see [Fixtures](#fixtures)).

| File | Contents |
|---|---|
| `tiles.dart` | 42 faces, match keys, 144-tile multiset, canonical face pairs |
| `layout.dart` | layout JSON, canonical order, validation, neighbour lists, free rule |
| `tile_set.dart` | immutable position bitset (32-bit words) |
| `prng.dart` | 32-bit helpers, splitmix32, xoshiro128\*\*, FNV-1a, seed derivation |
| `daily.dart` | daily seed |
| `dealer.dart` | reverse-construction dealer, sub-board dealer (shuffle), `kGeneratorVersion = 1` |
| `solver.dart` | independent forward solver (verification and hints) |
| `game_state.dart`, `commands.dart`, `events.dart` | immutable state, pure commands, UI events |
| `scoring.dart` | stars |
| `move_log.dart` | move-log entries, binary format, replay |
| `engine.dart` | barrel export |

## 1. Tiles (bit-exact)

Face ids are those of `design/design-system/tile-faces.json`:

| ids | faces | match key |
|---|---|---|
| 0–8 | circles 1–9 | = id |
| 9–17 | bamboo 1–9 | = id |
| 18–26 | characters 1–9 | = id |
| 27–30 | winds E, S, W, N | = id |
| 31–33 | dragons red, green, white | = id |
| 34–37 | flowers plum, orchid, chrysanthemum, bamboo | 34 (`FL`) |
| 38–41 | seasons spring, summer, autumn, winter | 35 (`SE`) |

Two tiles match iff their match keys are equal. A full set is 4 copies of faces 0–33 and 1 copy of faces 34–41
(144 tiles). CLI codes: `C1…C9`, `B1…B9`, `K1…K9`, `WE WS WW WN`, `DR DG DW`, `F1…F4`, `S1…S4`.

**Face pairs.** `facePairs(multiset)`: sort the face ids ascending and pair consecutive entries
`(f[0],f[1]), (f[2],f[3]), …`. Faces of one match key have contiguous ids, so this works whenever every match key
occurs an even number of times. For the full set this is the **canonical pair list** (72 pairs):

```
(0,0),(0,0),(1,1),(1,1),…,(33,33),(33,33),(34,35),(36,37),(38,39),(40,41)
```

## 2. Layouts (bit-exact)

JSON: `{ "id", "name", "version"=1, "difficulty"?, "chapter"?, "order"?, "parMs"?, "tiles": [{"x","y","z"}…] }`,
extra keys ignored. `x`, `y` are half-tile units (a tile covers `[x, x+2) × [y, y+2)`), `z` is the layer.

**Canonical order.** Positions sorted ascending by `(z, y, x)`. A **position index** is the index in that order.
Faces, solutions, fixtures and move logs all use position indices. (Files may list tiles in any order; the
generated `turtle.json` is already canonical.)

**Validation** (errors): tile count even and 2…144; no negative coordinate; no two tiles on the same layer overlap
(`|dx| < 2 && |dy| < 2`, duplicates included); every tile on `z > 0` overlaps at least one tile on `z − 1`.
*Warning* (not an error): a tile on `z ≥ p.z + 2` overhangs `p` while nothing on `p.z + 1` covers `p`.

**Neighbours** of position `i` at `(x, y, z)`, each list ascending by index:

- `coveredBy(i)`: tiles on `z + 1` with `|dx| < 2 && |dy| < 2`;
- `covers(i)`: tiles on `z − 1` with `|dx| < 2 && |dy| < 2`;
- `leftOf(i)`: tiles on `z` with `dx == −2 && |dy| < 2`;
- `rightOf(i)`: tiles on `z` with `dx == +2 && |dy| < 2`.

**Free rule** w.r.t. a set `R` of remaining positions: `i` is free iff no member of `coveredBy(i)` is in `R`, and not
(some member of `leftOf(i)` is in `R` and some member of `rightOf(i)` is in `R`). Only layer `z + 1` counts as cover.

**Upright turtle.** `tool/gen_turtle.dart` builds `assets/layouts/turtle.json` from brief Appendix A (classic
`(col, row, layer)` → `newCol = row`, `newRow = col + 1`, `x = 2·newCol`, `y = 2·newRow`): 144 tiles, 8×15, layers
87/36/16/4/1, cap at `(7, 13, 4)` (index 143), end tiles at `(7, 0, 0)`, `(7, 26, 0)`, `(7, 28, 0)`. A test fails if
the file and the generator disagree.

## 3. PRNG and hashes (bit-exact)

All values are unsigned 32-bit. In C# use `uint` and `unchecked` arithmetic; `mul32(a, b)` is `a * b`,
`>>>` is `>>` on `uint`.

```
mul32(a, b)   = (a × b) mod 2^32
add32(a, b)   = (a + b) mod 2^32
rotl32(x, k)  = (x << k | x >>> (32 − k)) mod 2^32

mix32(z):                      // splitmix32 output function (murmur3 fmix32 constants)
  z = mul32(z ^ (z >>> 16), 0x85EBCA6B)
  z = mul32(z ^ (z >>> 13), 0xC2B2AE35)
  return z ^ (z >>> 16)

SplitMix32(seed): state = seed
  next(): state = add32(state, 0x9E3779B9); return mix32(state)

Xoshiro128(seed):               // xoshiro128** 1.1 (Blackman & Vigna)
  sm = SplitMix32(seed); s0 = sm.next(); s1 = sm.next(); s2 = sm.next(); s3 = sm.next()
  if s0 == s1 == s2 == s3 == 0: s0 = 1          // cannot happen in practice
  nextUint32():
    result = mul32(rotl32(mul32(s1, 5), 7), 9)
    t = s1 << 9                                   // mod 2^32
    s2 ^= s0; s3 ^= s1; s1 ^= s2; s0 ^= s3; s2 ^= t; s3 = rotl32(s3, 11)
    return result
  nextInt(n), 1 ≤ n ≤ 2^32:                       // unbiased rejection sampling
    limit = 2^32 − (2^32 mod n)                   // compute in 64-bit
    loop: r = nextUint32(); if r < limit: return r mod n
  shuffle(list):                                  // Fisher–Yates from the top
    for i = len−1 down to 1: j = nextInt(i + 1); swap(list[i], list[j])

fnv1a32(s):  h = 0x811C9DC5; for each UTF-8 byte b of s: h = mul32(h ^ b, 0x01000193); return h

deriveSeed(seed, index) = mix32(add32(seed, mul32(index, 0x9E3779B9)))
attemptSeed(seed, a)    = a == 0 ? seed : deriveSeed(seed, a)
shuffleSeed(dealSeed, k) = deriveSeed(dealSeed ^ 0x53485546, k + 1)      // 0x53485546 = "SHUF", k = 0-based shuffle index
dailySeed(dateUtc, layoutId, gv) = fnv1a32("YYYY-MM-DD|layoutId|gv")   // e.g. "2026-11-16|turtle|1" → 3850022033
```

`dailySeed` takes the UTC calendar date (year 4 digits, month and day 2 digits, zero-padded; `gv` plain decimal).
The Dart code avoids 64-bit overflow (products from 16-bit halves) so the VM, AOT and dart2js agree; this was checked
by compiling a 300-deal checksum program with `dart compile js` and running it under Node (identical output).

## 4. Dealer (bit-exact)

`kGeneratorVersion = 1`. Changing anything in this section, §1–§3, or the production options requires a new
generator version (daily seeds include it, so dailies never change under an app update).

**Options** (part of the deal definition):

| option | production (app, daily, server) | tests |
|---|---|---|
| `spreadCandidates` | **2** (slight spread bias) | 1 (unbiased), unless a test is about the bias |
| `maxDeadEnds` | 32 | 32 |
| `maxAttempts` | 64 | 64 |

Production uses a slight bias (best of 2 draws) because it measurably spreads pairs apart (mean squared pair distance
on the turtle 120 vs 94 half-units², +27%) at no cost to dealing speed, while keeping deals varied; stronger bias makes pairs
predictably far apart.

**`deal(layout, seed)`**, with `n` = number of positions:

```
for attempt in 0 … maxAttempts−1:
    rng = Xoshiro128(attemptSeed(seed, attempt))
    order = construct(all positions, rng)          // may fail → next attempt
    if order failed: continue
    pairs = copy of the 72 canonical pairs
    rng.shuffle(pairs)                             // always all 72, even when n < 144
    pairs = first n/2 entries
    faces = array of n, all −1
    for k in 0 … n/2−1: (a, b) = order[k]; (fa, fb) = pairs[k]; faces[a] = fa; faces[b] = fb
    return (faces, order, attempt)
throw DealException                                // the layout admits no full removal order
```

**`construct(start, rng)`** (simulated removal, brief §5.4; the same `rng` continues into the pair shuffle):

```
remaining = start; steps = []; deadEnds = 0
while remaining not empty:
    free = positions in remaining that are free w.r.t. remaining, ascending by index
    if |free| < 2:                                  // dead end: no RNG draw here
        deadEnds += 1
        if deadEnds > maxDeadEnds or steps is empty: fail
        undo = min(deadEnds, |steps|)               // escalating backtrack
        repeat undo times: (a, b) = steps.pop(); remaining += {a, b}
        continue
    i = rng.nextInt(|free|); a = free[i]
    rest = free without index i (still ascending)
    draws = min(spreadCandidates, |rest|)
    b = −1; best = −1
    repeat draws times:
        c = rest[rng.nextInt(|rest|)]                // with replacement
        s = spreadScore(pos[a], pos[c])
        if s > best: best = s; b = c                 // strictly greater: first draw wins ties
    steps.push((a, b)); remaining −= {a, b}
return steps
```

`spreadScore(p, q)`: `dx = q.x − p.x`, `dy = q.y − p.y`; `0` if `|dx| < 2 && |dy| < 2`, else `dx² + dy²`.

Both tiles of every pair come from the free set of the same intermediate board, so `order` played front to back is a
legal solution: every deal is solvable by construction. `isValidSolution` replays it as a cheap proof; the forward
solver (§5) confirms independently.

This section was checked by porting it to Python from the text alone (not the Dart code): the port reproduces every
deal and shuffle in `fixtures/deals/turtle.json`.

**`dealSubBoard(layout, remaining, faces, subSeed)`** (shuffle): identical loop with `start = remaining` and
`seed = subSeed`, except the pair list is `facePairs(faces of the remaining tiles)` (sorted then paired, §1),
shuffled whole with the same `rng` after construction. Positions outside `remaining` keep their faces. Returns
nothing when every attempt fails (the remaining positions admit no full removal order, e.g. two stacked tiles); the
game then rejects the shuffle with `shuffleImpossible`.

## 5. Solver (not bit-exact)

`solve(layout, faces, {remaining, budget})` → `SolveSolvable(solution) | SolveUnsolvable | SolveUnknown`. It sees
only positions and faces. The server can use any correct solver; only its verdicts matter. Design:

- DFS over matching free pairs; memo of *failed* remaining-sets (exact 32-bit-word bitsets in an open-addressing table).
- **Safe moves:** when all remaining tiles of a key are free (2 or 4), remove them without branching.
- **Symmetry:** 3 free of 4 → branch over the 3 pairings; 2 free → one move.
- **Pruning (sound):** (1) a tile none of whose same-key partners can ever be free together with it (each partner is
  transitively above or below it through `coveredBy`) → dead; (2) *relaxed clearance*: let every tile leave alone as
  soon as it is free, except keys with exactly 2 remaining, which leave together when both are free; removal is
  monotone, so the greedy fixpoint is the most that can ever be cleared, and leftovers prove the state dead.
- **Ordering:** pairs whose tiles cover (×3) or side-touch the most remaining tiles first.
- **Restarts:** Luby schedule (256 × 1, 1, 2, 1, 1, 2, 4, …) with randomised move scores from run 1 on (jitter range
  12 + 2·run, seeded with the run number). A run that finishes within its limit is exhaustive, so `SolveUnsolvable`
  is a proof; the memo of proven failures carries over.
- **Budget** counts nodes across runs: `kVerifyBudget = 200000` for deals and shuffles, `kHintBudget = 20000` for hints.
  Exceeding it gives `SolveUnknown`; tests treat that as failure.

Measured (`ENGINE_STATS=1 dart test test_engine`): 20 bundled layouts × 5,000 seeds × 2 dealer modes, all solvable;
max 70,719 nodes / ~0.3 s (pyramid, temple, unbiased); turtle max 1,601 (unbiased) / 5,184 (production) nodes.
An extra 100,000-seed turtle run per mode: all solvable, max 21,823 nodes.

## 6. Game rules

`GameState` is immutable; commands return `(GameState, List<GameEvent>)` and return the *same instance* when they do
nothing. The engine never reads a clock: commands take `elapsedMs` (clamped so it never decreases).

- **New game:** `GameState.newGame(layout, seed, options = production)` deals and verifies with the solver
  (`verifiedBySolver`). Counters: `freeHintsLeft = 3`, `freeShufflesLeft = 2`.
- **Select** (MOTION_SPEC §2): free A → `Selected(A)`; A again → `Deselected(A)`; matching free B → `Matched(A, B,
  freed)`; non-matching free B → `Mismatch(A, B)`, `Selected(B)`; blocked tile → `Blocked(tile, blockers)` (covering
  tiles, plus both side neighbours if side-blocked), selection unchanged. Removed / out-of-range taps: nothing.
- After every match, undo and shuffle: board empty → `Cleared(stats)`; else no matching free pair → `Deadlock`.
- **Undo:** unlimited, free; pops a match (restores tiles; `Undone(entry, reblocked)`) or a shuffle (restores the
  previous faces). Spent credits are not refunded. Drops the selection.
- **Shuffle** `shuffle(free:, rewarded:)`: `free` = the deadlock shuffle (only while deadlocked, costs nothing);
  `rewarded` = paid by a rewarded ad (counts in `rewardedShuffles`, costs the 3rd star); neither = uses a free credit
  or is rejected (`noShuffleCredits`). The k-th shuffle of the game (0-based, never decremented by undo) uses
  `subSeed = shuffleSeed(dealSeed, k)` and `dealSubBoard`, then the solver verifies.
- **Hint:** on deadlock returns `[Deadlock]` and consumes nothing (the UI offers the shuffle, never an ad). Otherwise
  uses a free credit (or `rewarded: true`), and shows the first move of a solver solution within `kHintBudget`, else
  the first available pair. `findHint` / `hintAvailability` / `shuffleAvailability` are side-effect-free queries.
- **Grants:** `grantHint` / `grantShuffle` add free credits (head start, second chance); shuffles from these cost no stars.
- **Streak:** consecutive matches; a mismatch or undo resets it. `tilesMatched` = tiles currently removed.
- `toJson` / `fromJson` snapshot the state for Resume.

## 7. Stars (bit-exact)

```
3 if time ≤ par and hintsUsed ≤ 1 and rewardedShuffles == 0
2 if 2·time ≤ 3·par or hintsUsed ≤ 3
1 otherwise
```

`time` = elapsed ms of the clearing match; `par` = `parMs` from the layout metadata (turtle: 360000). Undo, free
credits and the deadlock shuffle never cost stars. No par → no stars.

## 8. Move log (bit-exact)

Text form: base64url (RFC 4648 §5, alphabet `A–Z a–z 0–9 - _`) **without padding**; decoders accept padding.
Bytes:

```
u8 version = 1
then entries until the end of the data:
  0x00  match             varint a, varint b, varint dt
  0x01  shuffle (credit)  u32le subSeed, varint dt
  0x02  shuffle (rewarded) u32le subSeed, varint dt
  0x03  shuffle (deadlock) u32le subSeed, varint dt
  0x04  hint (credit)
  0x05  hint (rewarded)
  0x06  undo
```

- `varint`: unsigned LEB128, 7 bits per byte, least-significant group first, high bit set on every byte but the
  last; at most 5 bytes, value ≤ 2^32 − 1.
- `u32le`: 4 bytes little-endian.
- `dt`: elapsed ms of this entry minus that of the previous *match or shuffle* entry (the first is relative to 0).
  Hints and undos carry no time. Elapsed values are absolute board-clock ms; they never decrease.
- `a`, `b`: position indices (canonical order).

Example: `match(3, 140, 1500 ms), hint(credit), shuffle(credit, 0xDEADBEEF, 2000 ms), undo` →
bytes `01 00 03 8c01 dc0b 04 01 efbeadde f403 06` → `AQADjAHcCwQB776t3vQDBg`.

**Replay** `replay(layout, seed, gv, log) → ReplayResult {legal, cleared, error, errorIndex, finalTimeMs, stars}`:

1. `gv` must be 1; the log must decode; deal with production options.
2. For each entry, in order (nothing may follow the clearing match):
   - **match:** `a ≠ b`, both remaining, both free, keys equal; remove both.
   - **shuffle:** `subSeed == shuffleSeed(seed, k)` for the k-th shuffle entry (0-based, undone ones included);
     `deadlock` kind requires a deadlock; apply `dealSubBoard` (must succeed). Credits are not checked (bonus credits
     are granted outside the log), but the kind is kept: `rewarded` shuffles count against the 3rd star.
   - **hint:** a matching free pair must exist; counts in `hintsUsed`.
   - **undo:** history must be non-empty; pop the last match or shuffle.
3. `cleared` iff the board is empty; `finalTimeMs` = elapsed of the clearing match; `stars` per §7.

## 9. Fixtures

Generated by `dart run tool/deal.dart --fixtures` (`--check` fails if stale); the Dart tests assert all of them.

- `fixtures/deals/prng.json`: splitmix32, xoshiro128\*\* outputs, `nextInt` sequences, FNV-1a, `deriveSeed`,
  `attemptSeed`, `shuffleSeed`, daily seeds with their key strings.
- `fixtures/deals/turtle.json`: canonical `positions`; `deals` = 25 seeds with production options
  (`{layoutId, layoutVersion, generatorVersion, spreadCandidates, seed, attempt, faces[], solution[[a,b]…]}`);
  `unbiasedDeals` = 5 seeds with `spreadCandidates = 1`; `shuffles` = `{seed, removed[], subSeed, facesBefore[],
  facesAfter[]}` after playing the first k construction pairs.
- `fixtures/deals/move_logs.json`: a full game log (hints, undo, shuffles) with its expected replay result and raw
  bytes, plus the example above.

## 10. Tools and tests

```
dart run tool/deal.dart --layout turtle --seed 42      # ASCII board per layer, solution, solver verdict, timings
dart run tool/deal.dart --layout turtle --daily 2026-11-16
dart run tool/gen_turtle.dart [--check]
dart test test_engine                                  # ≈ 45 s; agreement shards run in parallel
ENGINE_STATS=1 dart test test_engine/agreement_0_test.dart   # print per-layout solver numbers
dart run coverage:test_with_coverage --out coverage/engine -- test_engine
```

The dealer↔solver agreement test (`agreement_<k>_test.dart`) covers every `assets/layouts/*.json` except
`index.json`, 5,000 seeds each in both dealer modes; any unsolvable or budget-exceeded verdict fails the suite.

## Daily layout choice

`dailyLayoutId(utcDate, pool)` (`lib/engine/daily.dart`), where `pool` is `index.json`'s `dailyPool` in file order:

1. `day = floor(utcMidnight(utcDate).millisecondsSinceEpoch / 86_400_000)` (days since 1970-01-01 UTC).
2. `cycle = day ~/ pool.length`.
3. `order = copy of pool`, shuffled with `Xoshiro128(fnv1a32("daily-cycle|<cycle>")).shuffle(order)` (same top-down Fisher–Yates as §2).
4. Result: `order[day % pool.length]`.

The seed is then `dailySeed(utcDate, layoutId, generatorVersion)`. Golden values for the pool `lotus, lantern, fan, bonsai, koi, gate, moon, bell`, 2026-11-16 onward: `koi, moon, lotus, bell, bonsai, moon, gate, lantern, lotus, fan` (test `test_engine/daily_layout_test.dart`).
