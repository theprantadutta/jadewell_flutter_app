/// Deterministic 32-bit PRNG and hashing for deals.
///
/// Everything here works on unsigned 32-bit values held in Dart `int`s and
/// masks explicitly after every operation that can exceed 32 bits. Products
/// are formed from 16-bit halves ([mul32]) so no intermediate exceeds 2^53:
/// results are identical on the Dart VM, AOT and dart2js / dart2wasm.
/// See docs/ENGINE.md §PRNG for the reference description.
library;

import 'dart:convert';

/// Mask for 32-bit unsigned arithmetic.
const int kMask32 = 0xFFFFFFFF;

/// Golden-ratio increment used by splitmix32 and seed derivation.
const int kGolden32 = 0x9E3779B9;

/// (a × b) mod 2^32 for unsigned 32-bit a, b (C#: `unchecked(a * b)` on uint).
int mul32(int a, int b) {
  final al = a & 0xFFFF, ah = (a >>> 16) & 0xFFFF;
  final bl = b & 0xFFFF, bh = (b >>> 16) & 0xFFFF;
  final cross = ((ah * bl + al * bh) & 0xFFFF) << 16;
  return (al * bl + cross) & kMask32;
}

/// (a + b) mod 2^32.
int add32(int a, int b) => (a + b) & kMask32;

/// Rotate a 32-bit value left by [k] (0 < k < 32).
int rotl32(int x, int k) => ((x << k) | (x >>> (32 - k))) & kMask32;

/// splitmix32 output function (the "mix" applied to an already-advanced state).
int mix32(int z) {
  z &= kMask32;
  z = mul32(z ^ (z >>> 16), 0x85EBCA6B);
  z = mul32(z ^ (z >>> 13), 0xC2B2AE35);
  return (z ^ (z >>> 16)) & kMask32;
}

/// splitmix32 generator, used only to expand a 32-bit seed into xoshiro state.
final class SplitMix32 {
  SplitMix32(int seed) : _state = seed & kMask32;

  int _state;

  /// state += 0x9E3779B9; return mix32(state).
  int next() {
    _state = add32(_state, kGolden32);
    return mix32(_state);
  }
}

/// xoshiro128** (Blackman & Vigna) over 32-bit words.
final class Xoshiro128 {
  /// Seeds the four state words with four successive [SplitMix32] outputs
  /// of [seed]. If all four were zero (impossible in practice) s0 becomes 1.
  factory Xoshiro128(int seed) {
    final sm = SplitMix32(seed);
    final s0 = sm.next(), s1 = sm.next(), s2 = sm.next(), s3 = sm.next();
    return Xoshiro128.fromState(s0, s1, s2, s3);
  }

  Xoshiro128.fromState(int s0, int s1, int s2, int s3)
    : _s0 = s0 & kMask32,
      _s1 = s1 & kMask32,
      _s2 = s2 & kMask32,
      _s3 = s3 & kMask32 {
    if (_s0 == 0 && _s1 == 0 && _s2 == 0 && _s3 == 0) _s0 = 1;
  }

  int _s0, _s1, _s2, _s3;

  /// Current state words (s0, s1, s2, s3).
  List<int> get state => [_s0, _s1, _s2, _s3];

  /// Next unsigned 32-bit output.
  int nextUint32() {
    final result = mul32(rotl32(mul32(_s1, 5), 7), 9);
    final t = (_s1 << 9) & kMask32;
    _s2 ^= _s0;
    _s3 ^= _s1;
    _s1 ^= _s2;
    _s0 ^= _s3;
    _s2 ^= t;
    _s3 = rotl32(_s3, 11);
    return result;
  }

  /// Uniform integer in [0, n) for 1 ≤ n ≤ 2^32, without modulo bias:
  /// draws r until r < 2^32 − (2^32 mod n), then returns r mod n.
  int nextInt(int n) {
    if (n <= 0 || n > 0x100000000) {
      throw RangeError.range(n, 1, 0x100000000, 'n');
    }
    final limit = 0x100000000 - (0x100000000 % n);
    while (true) {
      final r = nextUint32();
      if (r < limit) return r % n;
    }
  }

  /// In-place Fisher–Yates: for i = len−1 down to 1, swap(i, nextInt(i+1)).
  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }
}

/// FNV-1a 32-bit hash of [s]'s UTF-8 bytes
/// (offset basis 0x811C9DC5, prime 0x01000193).
int fnv1a32(String s) {
  var h = 0x811C9DC5;
  for (final b in utf8.encode(s)) {
    h = mul32(h ^ b, 0x01000193);
  }
  return h;
}

/// Derives a new 32-bit seed: mix32((seed + index × 0x9E3779B9) mod 2^32).
int deriveSeed(int seed, int index) => mix32(add32(seed & kMask32, mul32(index & kMask32, kGolden32)));
