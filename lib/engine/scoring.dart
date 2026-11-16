/// Stars for a cleared board (docs/ARCHITECTURE.md §2).
///
///  * 3 stars: time ≤ par **and** hints ≤ 1 **and** no rewarded shuffles;
///  * 2 stars: time ≤ 1.5 × par **or** hints ≤ 3;
///  * 1 star otherwise.
///
/// Undo never costs stars, and neither do free shuffles (the per-board free
/// credits or the deadlock shuffle): only shuffles paid with a rewarded ad
/// count as [rewardedShuffles]. `1.5 × par` is evaluated exactly in integers
/// as `2 × time ≤ 3 × par`.
int starsFor({required int timeMs, required int parMs, required int hintsUsed, required int rewardedShuffles}) {
  if (timeMs <= parMs && hintsUsed <= 1 && rewardedShuffles == 0) return 3;
  if (2 * timeMs <= 3 * parMs || hintsUsed <= 3) return 2;
  return 1;
}
