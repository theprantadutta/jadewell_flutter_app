import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../engine/engine.dart';
import '../models/catalogue.dart';
import 'repositories.dart';

/// Loads `assets/layouts/index.json` and every layout it references.
class AssetCatalogueRepository implements CatalogueRepository {
  AssetCatalogueRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  Future<Catalogue>? _cache;

  @override
  Future<Catalogue> load() => _cache ??= _load();

  Future<Catalogue> _load() async {
    final index = jsonDecode(await _bundle.loadString('assets/layouts/index.json')) as Map<String, dynamic>;
    final chapters = <ChapterInfo>[];
    final layouts = <String, LayoutInfo>{};

    Future<LayoutInfo> loadLayout(String id, int requires) async {
      final data = LayoutData.parse(await _bundle.loadString('assets/layouts/$id.json'));
      return LayoutInfo(
        id: data.id,
        name: data.name,
        chapterId: data.chapter ?? 'daily',
        order: data.order ?? 0,
        difficulty: data.difficulty ?? 'medium',
        parMs: data.parMs ?? data.tiles.length * 2500,
        layout: data.build(),
        requiresChapterClears: requires,
      );
    }

    for (final ch in (index['chapters'] as List).cast<Map<String, dynamic>>()) {
      final ids = <String>[];
      for (final l in (ch['layouts'] as List).cast<Map<String, dynamic>>()) {
        final id = l['id'] as String;
        ids.add(id);
        layouts[id] = await loadLayout(id, (l['requiresChapterClears'] as int?) ?? 0);
      }
      chapters.add(ChapterInfo(
        id: ch['id'] as String,
        name: ch['name'] as String,
        order: ch['order'] as int,
        unlock: ChapterUnlock.fromJson(ch['unlock'] as Map<String, dynamic>),
        layoutIds: ids,
      ));
    }
    chapters.sort((a, b) => a.order.compareTo(b.order));
    final daily = (index['dailyPool'] as List).cast<String>();
    for (final id in daily) {
      layouts[id] ??= await loadLayout(id, 0);
    }
    return Catalogue(chapters: chapters, layouts: layouts, dailyPool: daily);
  }
}
