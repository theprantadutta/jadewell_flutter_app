import '../../engine/engine.dart';

/// One playable layout plus its catalogue metadata.
class LayoutInfo {
  const LayoutInfo({
    required this.id,
    required this.name,
    required this.chapterId,
    required this.order,
    required this.difficulty,
    required this.parMs,
    required this.layout,
    this.requiresChapterClears = 0,
  });

  final String id;
  final String name;

  /// `classics`, `creatures`, `wonders`, or `daily` for the daily pool.
  final String chapterId;
  final int order;

  /// `easy` | `medium` | `hard`.
  final String difficulty;
  final int parMs;
  final Layout layout;

  /// Clears needed inside the chapter before this layout opens.
  final int requiresChapterClears;

  int get tileCount => layout.length;
  bool get isDaily => chapterId == 'daily';
}

/// How a chapter opens.
sealed class ChapterUnlock {
  const ChapterUnlock();

  static ChapterUnlock fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'always' => const UnlockAlways(),
        'chapterClears' => UnlockChapterClears(j['chapter'] as String, j['count'] as int),
        'totalClears' => UnlockTotalClears(j['count'] as int),
        final t => throw FormatException('unknown unlock type $t'),
      };
}

class UnlockAlways extends ChapterUnlock {
  const UnlockAlways();
}

class UnlockChapterClears extends ChapterUnlock {
  const UnlockChapterClears(this.chapterId, this.count);
  final String chapterId;
  final int count;
}

class UnlockTotalClears extends ChapterUnlock {
  const UnlockTotalClears(this.count);
  final int count;
}

class ChapterInfo {
  const ChapterInfo({required this.id, required this.name, required this.order, required this.unlock, required this.layoutIds});

  final String id;
  final String name;
  final int order;
  final ChapterUnlock unlock;

  /// In display order.
  final List<String> layoutIds;
}

/// Everything in `assets/layouts/` (loaded once, immutable).
class Catalogue {
  const Catalogue({required this.chapters, required this.layouts, required this.dailyPool});

  /// In display order.
  final List<ChapterInfo> chapters;
  final Map<String, LayoutInfo> layouts;
  final List<String> dailyPool;

  LayoutInfo layout(String id) => layouts[id] ?? (throw ArgumentError('unknown layout $id'));
  ChapterInfo chapter(String id) => chapters.firstWhere((c) => c.id == id);

  /// All non-daily layouts in display order.
  Iterable<LayoutInfo> get chapterLayouts sync* {
    for (final c in chapters) {
      for (final id in c.layoutIds) {
        yield layouts[id]!;
      }
    }
  }

  /// The layout after [id] in its chapter, then the first of the next chapter; null at the end.
  LayoutInfo? nextAfter(String id) {
    final all = chapterLayouts.toList();
    final i = all.indexWhere((l) => l.id == id);
    return (i >= 0 && i + 1 < all.length) ? all[i + 1] : null;
  }
}
