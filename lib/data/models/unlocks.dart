import 'catalogue.dart';
import 'progress.dart';

/// Lock state of one layout, with the hint shown on a locked card.
class LayoutAccess {
  const LayoutAccess.open({this.isNew = false}) : locked = false, reason = null, remaining = 0;
  const LayoutAccess.locked(this.reason, this.remaining) : locked = true, isNew = false;

  final bool locked;

  /// Open but never played (card shows "New").
  final bool isNew;

  /// e.g. `LockReason.chapterClears` with [remaining] = 2 → "Clear 2 more Creatures".
  final LockReason? reason;
  final int remaining;
}

enum LockReason { chapterClears, chapterLocked }

/// Lock state of a whole chapter.
class ChapterAccess {
  const ChapterAccess({required this.locked, required this.remaining, required this.cleared, required this.total});
  final bool locked;

  /// Clears still needed to open it (meaning depends on the rule).
  final int remaining;
  final int cleared;
  final int total;
}

/// Pure unlock rules (data, not code: thresholds come from index.json).
/// A rewarded-ad unlock opens a single layout even inside a locked chapter.
abstract final class Unlocks {
  static int chapterClears(Catalogue c, String chapterId, Map<String, LayoutProgress> p) =>
      c.chapter(chapterId).layoutIds.where((id) => p[id]?.cleared ?? false).length;

  static int totalClears(Catalogue c, Map<String, LayoutProgress> p) =>
      c.chapterLayouts.where((l) => p[l.id]?.cleared ?? false).length;

  static ChapterAccess chapter(Catalogue c, String chapterId, Map<String, LayoutProgress> p) {
    final ch = c.chapter(chapterId);
    final cleared = chapterClears(c, chapterId, p);
    final remaining = switch (ch.unlock) {
      UnlockAlways() => 0,
      UnlockChapterClears(:final chapterId, :final count) => (count - chapterClears(c, chapterId, p)).clamp(0, count),
      UnlockTotalClears(:final count) => (count - totalClears(c, p)).clamp(0, count),
    };
    return ChapterAccess(locked: remaining > 0, remaining: remaining, cleared: cleared, total: ch.layoutIds.length);
  }

  static LayoutAccess layout(Catalogue c, String layoutId, Map<String, LayoutProgress> p) {
    final info = c.layout(layoutId);
    final prog = p[layoutId];
    if (info.isDaily) return const LayoutAccess.open();
    final isNew = prog == null || (prog.clears == 0 && prog.lastPlayedAt == null && !prog.hasSavedGame);
    if (prog?.adUnlocked ?? false) return LayoutAccess.open(isNew: isNew);

    final ch = chapter(c, info.chapterId, p);
    if (ch.locked) return LayoutAccess.locked(LockReason.chapterLocked, ch.remaining);
    final need = info.requiresChapterClears - ch.cleared;
    if (need > 0) return LayoutAccess.locked(LockReason.chapterClears, need);
    return LayoutAccess.open(isNew: isNew);
  }
}
