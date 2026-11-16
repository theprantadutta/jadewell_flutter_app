import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../board/tile/tile_face_painter.dart';
import '../../board/tile/tile_face_spec.dart';
import '../../board/tile/tile_widget.dart';
import '../../theme/jw_background.dart';
import '../../theme/jw_fonts.dart';
import '../../theme/jw_theme.dart';
import '../../widgets/widgets.dart';
import 'gallery_sheets.dart';

/// Developer gallery: every component and all 42 faces in every tile state,
/// with light/dark and reduce-motion switches. Temporary home until the
/// router lands.
class DevGalleryScreen extends StatefulWidget {
  const DevGalleryScreen({super.key});

  @override
  State<DevGalleryScreen> createState() => _DevGalleryScreenState();
}

class _DevGalleryScreenState extends State<DevGalleryScreen> {
  Brightness? _brightness;
  bool _reduceMotion = false;
  List<TileFaceSpec>? _faces;
  List<SilhouetteTile>? _fortress;
  int _tapped = -1;

  @override
  void initState() {
    super.initState();
    registerFontLicenses();
    _load();
  }

  Future<void> _load() async {
    final faces = await TileFaceSpec.load();
    List<SilhouetteTile>? fortress;
    try {
      final raw = await rootBundle.loadString('assets/layouts/fortress.json');
      final j = jsonDecode(raw) as Map<String, Object?>;
      fortress = [
        for (final t in (j['tiles']! as List<Object?>).cast<Map<String, Object?>>()) SilhouetteTile.fromJson(t),
      ];
    } on Object {
      fortress = null;
    }
    if (!mounted) return;
    setState(() {
      _faces = faces;
      _fortress = fortress;
    });
  }

  void _haptic() => HapticFeedback.selectionClick();

  @override
  Widget build(BuildContext context) {
    final brightness = _brightness ?? MediaQuery.platformBrightnessOf(context);
    final dark = brightness == Brightness.dark;
    return Theme(
      data: buildJwThemeData(brightness),
      child: JwReduceMotion(
        enabled: _reduceMotion,
        child: Builder(
          builder: (context) {
            final jw = context.jw;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
              child: ColoredBox(
                color: jw.surface,
                child: JwBackground(
                  child: DefaultTextStyle(
                    style: jw.text.body,
                    child: SafeArea(
                      bottom: false,
                      child: CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                            sliver: SliverList.list(
                              children: [
                                Text('Jadewell', style: jw.text.h1),
                                Text('Dev gallery · Soft 3D Clay', style: jw.text.body.copyWith(color: jw.textMuted)),
                                const SizedBox(height: 14),
                                JwListGroup(
                                  children: [
                                    JwListRow(
                                      icon: JwIcons.moon,
                                      title: 'Dark theme',
                                      trailing: JwToggle(
                                        value: dark,
                                        onHaptic: _haptic,
                                        semanticLabel: 'Dark theme',
                                        onChanged: (v) =>
                                            setState(() => _brightness = v ? Brightness.dark : Brightness.light),
                                      ),
                                    ),
                                    JwListRow(
                                      icon: JwIcons.motion,
                                      title: 'Reduce motion',
                                      trailing: JwToggle(
                                        value: _reduceMotion,
                                        onHaptic: _haptic,
                                        semanticLabel: 'Reduce motion',
                                        onChanged: (v) => setState(() => _reduceMotion = v),
                                      ),
                                    ),
                                  ],
                                ),
                                GalleryComponentsSheet(silhouette: _fortress, onHaptic: _haptic),
                                const GalleryEyebrow('Icons'),
                                Wrap(
                                  spacing: 14,
                                  runSpacing: 14,
                                  children: [
                                    for (final n in JwIcons.all)
                                      Tooltip(
                                        message: n,
                                        child: JwIcon(n, size: 24, color: jw.textPrimary),
                                      ),
                                  ],
                                ),
                                if (_faces != null) ..._tiles(context, _faces!),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _tiles(BuildContext context, List<TileFaceSpec> faces) {
    final jw = context.jw;
    return [
      const GalleryEyebrow('Tap a tile'),
      Wrap(
        spacing: 2,
        runSpacing: 6,
        children: [
          for (final i in [0, 4, 13, 22, 27, 31, 33, 35, 39])
            GestureDetector(
              onTap: () {
                _haptic();
                setState(() => _tapped = _tapped == i ? -1 : i);
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: TileWidget(
                  face: faces[i],
                  scale: 1.25,
                  state: _tapped == i ? TileVisualState.selected : TileVisualState.playable,
                ),
              ),
            ),
        ],
      ),
      const GalleryEyebrow('Tile faces'),
      GalleryTileFacesSheet(faces: faces, bigScale: 1.25),
      const GalleryEyebrow('Tile states'),
      Text('Hinted bobs unless motion is reduced.', style: jw.text.caption),
      GalleryTileStatesSheet(faces: faces),
      const GalleryEyebrow('Tile states · greyscale'),
      ColorFiltered(
        colorFilter: const ColorFilter.matrix(kGreyscaleMatrix),
        child: GalleryTileStatesSheet(faces: faces, faceIds: const [0, 4, 10, 15, 22, 27, 31, 33, 35]),
      ),
    ];
  }
}
