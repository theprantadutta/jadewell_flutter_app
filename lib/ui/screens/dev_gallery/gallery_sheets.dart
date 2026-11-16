import 'package:flutter/widgets.dart';

import '../../board/tile/tile_face_spec.dart';
import '../../board/tile/tile_widget.dart';
import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../widgets/widgets.dart';

/// Section heading in eyebrow style.
class GalleryEyebrow extends StatelessWidget {
  const GalleryEyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 12),
    child: Text(text.toUpperCase(), style: context.jw.text.eyebrow),
  );
}

/// A small fallback silhouette (used when no layout asset is available).
final List<SilhouetteTile> kDemoSilhouette = [
  for (var x = 0; x < 20; x += 2) ...[SilhouetteTile(x, 0, 0), SilhouetteTile(x, 14, 0)],
  for (var y = 2; y < 14; y += 2) ...[SilhouetteTile(0, y, 0), SilhouetteTile(18, y, 0)],
  for (var x = 4; x < 16; x += 2) ...[SilhouetteTile(x, 4, 0), SilhouetteTile(x, 10, 0)],
  for (var y = 6; y < 10; y += 2) ...[SilhouetteTile(4, y, 0), SilhouetteTile(14, y, 0)],
  for (var x = 6; x < 14; x += 2) SilhouetteTile(x, 7, 1),
];

/// Every component of DESIGN_SYSTEM §11 in one column. Stateful so the
/// controls work in the gallery; goldens render it as is.
class GalleryComponentsSheet extends StatefulWidget {
  const GalleryComponentsSheet({super.key, this.silhouette, this.onHaptic});

  final List<SilhouetteTile>? silhouette;
  final VoidCallback? onHaptic;

  @override
  State<GalleryComponentsSheet> createState() => _GalleryComponentsSheetState();
}

class _GalleryComponentsSheetState extends State<GalleryComponentsSheet> {
  bool _sound = true;
  bool _toggleOff = false;
  String _theme = 'system';
  int _hints = 3;
  double _progress = 0.62;
  int _segments = 3;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final h = widget.onHaptic;
    final tiles = widget.silhouette ?? kDemoSilhouette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GalleryEyebrow('Buttons'),
        JwButton.primary(label: 'Primary', icon: JwIcons.play, expand: true, onPressed: () {}, onHaptic: h),
        const SizedBox(height: 14),
        JwButton.secondary(label: 'Secondary', icon: JwIcons.replay, expand: true, onPressed: () {}, onHaptic: h),
        const SizedBox(height: 6),
        JwButton.tertiary(label: 'Tertiary', onPressed: () {}, onHaptic: h),
        const SizedBox(height: 6),
        Row(
          children: [
            JwButton.primary(label: 'Small', small: true, onPressed: () {}, onHaptic: h),
            const SizedBox(width: 14),
            JwButton.secondary(label: 'Small', small: true, onPressed: () {}, onHaptic: h),
            const SizedBox(width: 14),
            JwIconButton(icon: JwIcons.back, semanticLabel: 'Back', onPressed: () {}, onHaptic: h),
            const SizedBox(width: 14),
            JwIconButton(icon: JwIcons.gear, semanticLabel: 'Settings', onPressed: () {}, onHaptic: h),
          ],
        ),
        const GalleryEyebrow('Chips · counters'),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const JwChip(value: '86', label: 'tiles'),
            const JwChip(value: '6', label: 'pairs open'),
            const JwChip.accent(value: '×4', label: 'streak'),
            JwTimerPill(time: '4:12', onTap: () {}, onHaptic: h),
          ],
        ),
        const GalleryEyebrow('Progress'),
        GestureDetector(
          onTap: () => setState(() => _progress = _progress > 0.9 ? 0.15 : _progress + 0.2),
          child: JwProgressTrack(value: _progress, semanticLabel: 'Chapter progress'),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => setState(() => _segments = (_segments + 1) % 5),
          child: JwSegmentedProgress(segments: 4, filled: _segments, semanticLabel: 'Daily streak'),
        ),
        const GalleryEyebrow('Toggles · segmented'),
        Row(
          children: [
            JwToggle(value: _sound, onChanged: (v) => setState(() => _sound = v), onHaptic: h, semanticLabel: 'Sound'),
            const SizedBox(width: 18),
            JwToggle(
              value: _toggleOff,
              onChanged: (v) => setState(() => _toggleOff = v),
              onHaptic: h,
              semanticLabel: 'Example',
            ),
          ],
        ),
        const SizedBox(height: 10),
        JwSegmented<String>(
          segments: const {'light': 'Light', 'dark': 'Dark', 'system': 'System'},
          selected: _theme,
          onChanged: (v) => setState(() => _theme = v),
          onHaptic: h,
        ),
        const GalleryEyebrow('Tool knobs · tray'),
        JwTray(
          margin: EdgeInsets.zero,
          children: [
            JwToolKnob(
              icon: JwIcons.hint,
              label: 'Hint',
              accentIcon: true,
              badge: _hints,
              onPressed: () => setState(() => _hints = _hints == 0 ? 3 : _hints - 1),
              onHaptic: h,
            ),
            JwToolKnob(icon: JwIcons.undo, label: 'Undo', onPressed: () {}, onHaptic: h),
            JwToolKnob(icon: JwIcons.shuffle, label: 'Shuffle', onPressed: () {}, onHaptic: h),
          ],
        ),
        const GalleryEyebrow('Cards'),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: JwLayoutCard.tiles(
                name: 'Fortress',
                meta: '128 tiles · Hard',
                tiles: tiles,
                onTap: () {},
                onHaptic: h,
                stateRow: Row(children: [JwIcon(JwIcons.star, size: 16, color: jw.accent), const SizedBox(width: 4), Text('Best 6:24', style: jw.text.numM.copyWith(fontSize: 13))]),
              ),
            ),
            const SizedBox(width: 14),
            Flexible(
              child: JwLayoutCard.tiles(
                name: 'Dragon',
                meta: '144 tiles · Expert',
                tiles: tiles,
                locked: true,
                stateRow: Row(children: [JwIcon(JwIcons.lock, size: 16, color: jw.textMuted), const SizedBox(width: 4), Text('Clear 3 more', style: jw.text.caption)]),
              ),
            ),
          ],
        ),
        const GalleryEyebrow('List group'),
        JwListGroup(
          children: [
            JwListRow(
              icon: JwIcons.sound,
              title: 'Sound',
              trailing: JwToggle(value: _sound, onChanged: (v) => setState(() => _sound = v), onHaptic: h, semanticLabel: 'Sound'),
            ),
            JwListRow(icon: JwIcons.text, title: 'Tile face size', value: 'Large', chevron: true, onTap: () {}, onHaptic: h),
            JwListRow(icon: JwIcons.bag, title: 'Remove ads', value: r'$1.99', monoValue: true, chevron: true, onTap: () {}, onHaptic: h),
            JwListRow(icon: JwIcons.shield, title: 'Privacy', chevron: true, onTap: () {}, onHaptic: h),
            JwListRow(icon: JwIcons.trash, title: 'Reset progress', destructive: true, onTap: () {}, onHaptic: h),
          ],
        ),
        const GalleryEyebrow('Modal'),
        JwDialog(
          title: 'Shuffle the board?',
          body: 'Body copy sits in textMuted.',
          actions: [
            JwButton.secondary(label: 'Cancel', small: true, expand: true, onPressed: () {}, onHaptic: h),
            JwButton.primary(label: 'Shuffle', small: true, expand: true, onPressed: () {}, onHaptic: h),
          ],
        ),
        const GalleryEyebrow('Sheet · toast · avatars'),
        JwSheet(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Paused', style: jw.text.h3, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('4:12', style: jw.text.numXl, textAlign: TextAlign.center),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const JwToast(message: 'Daily streak saved'),
            const Spacer(),
            const JwAvatar(name: 'Mei'),
            const SizedBox(width: 10),
            const JwAvatar(name: 'Pranta'),
            const SizedBox(width: 10),
            const JwAvatar(name: 'Ola'),
          ],
        ),
        const GalleryEyebrow('Elevation levels'),
        const GalleryElevationRow(),
      ],
    );
  }
}

/// e0 / e1 / e2 / e3 / pressed / primary swatches.
class GalleryElevationRow extends StatelessWidget {
  const GalleryElevationRow({super.key});

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    const levels = {
      'e0 · sunken': ClayLevel.sunken,
      'e1 · chip': ClayLevel.chip,
      'e2 · raised': ClayLevel.raised,
      'e3 · floating': ClayLevel.floating,
      'pressed': ClayLevel.pressed,
      'primary': ClayLevel.primary,
    };
    return Wrap(
      spacing: 18,
      runSpacing: 18,
      children: [
        for (final e in levels.entries)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: jw.clay(e.value, radius: 22),
                child: const SizedBox(width: 96, height: 70),
              ),
              const SizedBox(height: 8),
              Text(e.key, style: jw.text.caption),
            ],
          ),
      ],
    );
  }
}

/// All 42 faces as playable tiles, at 2.5× and at real size.
class GalleryTileFacesSheet extends StatelessWidget {
  const GalleryTileFacesSheet({super.key, required this.faces, this.bigScale = 2.0});

  final List<TileFaceSpec> faces;
  final double bigScale;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    const rows = <String, List<int>>{
      'Circles': [0, 9],
      'Bamboo': [9, 18],
      'Characters': [18, 27],
      'Winds': [27, 31],
      'Dragons': [31, 34],
      'Flowers': [34, 38],
      'Seasons': [38, 42],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(r.key, style: jw.text.h3.copyWith(fontSize: 16)),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 14,
            children: [
              for (var i = r.value[0]; i < r.value[1]; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 10),
                  child: TileWidget(face: faces[i], scale: bigScale),
                ),
            ],
          ),
          Wrap(
            spacing: 2,
            children: [
              for (var i = r.value[0]; i < r.value[1]; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: TileWidget(face: faces[i]),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Every face in every [TileVisualState] (one row per state), plus a
/// playable/blocked pair at the S/M/L face sizes.
class GalleryTileStatesSheet extends StatelessWidget {
  const GalleryTileStatesSheet({super.key, required this.faces, this.faceIds, this.scale = 1});

  final List<TileFaceSpec> faces;

  /// Restrict to these faces (all 42 when null).
  final List<int>? faceIds;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final ids = faceIds ?? [for (var i = 0; i < faces.length; i++) i];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in TileVisualState.values) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text(s.name, style: jw.text.callout.copyWith(color: jw.textMuted)),
          ),
          Wrap(
            spacing: 4 * scale,
            runSpacing: 12 * scale,
            children: [
              for (final i in ids)
                Padding(
                  padding: EdgeInsets.only(top: 8 * scale, bottom: 6 * scale),
                  child: TileWidget(face: faces[i], state: s, scale: scale, reduceMotion: true),
                ),
            ],
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text('face size S · M · L', style: jw.text.callout.copyWith(color: jw.textMuted)),
        ),
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            for (final size in TileFaceSize.values) ...[
              TileWidget(face: faces[4], faceSize: size, scale: scale),
              TileWidget(face: faces[4], faceSize: size, scale: scale, state: TileVisualState.blocked),
            ],
          ],
        ),
      ],
    );
  }
}
