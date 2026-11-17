import 'package:flutter/widgets.dart';

import '../../board/tile/tile_face_spec.dart';
import '../../board/tile/tile_widget.dart';
import '../../components/components.dart';
import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
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

/// Every component of DESIGN_SYSTEM §11 in one column, in the order of
/// `design-system/sheets/components-elevation-*.png`, then the colour fills
/// of `colour-fills-*.png`. Stateful so the controls work in the gallery;
/// goldens render it as is.
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
        PrimaryButton(label: 'Primary', icon: JwIcons.play, expand: true, onPressed: () {}, onHaptic: h),
        const SizedBox(height: 16),
        FillBox(
          radius: JwRadius.pill,
          height: 56,
          pressed: 1,
          child: Center(child: Text('Primary · pressed', style: jw.text.button.copyWith(fontSize: 16.5, color: JwFill.purple.on))),
        ),
        const SizedBox(height: 16),
        JwButton.secondary(label: 'Secondary', icon: JwIcons.replay, expand: true, onPressed: () {}, onHaptic: h),
        const SizedBox(height: 14),
        DecoratedBox(
          decoration: jw.clay(ClayLevel.pressed),
          child: SizedBox(height: 56, child: Center(child: Text('Secondary · pressed', style: jw.text.button.copyWith(fontSize: 16)))),
        ),
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
        const GalleryEyebrow('Icon badges · 30–48 pt, radius ⅓'),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final f in JwFill.all) IconBadge(icon: JwIcons.star, fill: f)],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            for (final size in const [26.0, 30.0, 34.0, 40.0, 48.0, 64.0]) IconBadge(icon: JwIcons.shuffle, fill: JwFill.pink, size: size),
          ],
        ),
        const GalleryEyebrow('Fill card (hero / plate)'),
        HeroCard(
          confetti: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Daily · Sun 15 Nov', style: jw.text.callout.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: JwFill.purple.on)),
              const SizedBox(height: 2),
              Text('Lotus', style: jw.text.h1.copyWith(color: JwFill.purple.on)),
              const SizedBox(height: 10),
              PrimaryButton(label: 'Play', fill: JwFill.yellow, height: 40, onPressed: () {}, onHaptic: h),
            ],
          ),
        ),
        const GalleryEyebrow('Counter chips (cchip)'),
        Wrap(
          spacing: 10,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const CounterChip(icon: JwIcons.tile, value: '86', label: 'tiles', fill: JwFill.mint),
            const CounterChip(icon: JwIcons.pairs, value: '6', label: 'pairs', fill: JwFill.pink),
            const CounterChip(icon: JwIcons.flame, value: '×6', fill: JwFill.coral),
            JwTimerPill(time: '4:12', onTap: () {}, onHaptic: h),
            const JwChip(value: '2', label: 'free left'),
            const JwChip.accent(value: '×4', label: 'streak'),
          ],
        ),
        const GalleryEyebrow('Progress'),
        GestureDetector(
          onTap: () => setState(() => _progress = _progress > 0.9 ? 0.15 : _progress + 0.2),
          child: JwProgressTrack(value: _progress, semanticLabel: 'Chapter progress'),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => setState(() => _segments = (_segments + 1) % 5),
          child: JwSegmentedProgress(segments: 4, filled: _segments, semanticLabel: 'Daily streak'),
        ),
        const GalleryEyebrow('Toggles · segmented'),
        Row(
          children: [
            JwToggle(value: _sound, onChanged: (v) => setState(() => _sound = v), onHaptic: h, semanticLabel: 'Sound'),
            const SizedBox(width: 18),
            JwToggle(value: _toggleOff, onChanged: (v) => setState(() => _toggleOff = v), onHaptic: h, semanticLabel: 'Example'),
          ],
        ),
        const SizedBox(height: 10),
        JwSegmented<String>(
          segments: const {'light': 'Light', 'dark': 'Dark', 'system': 'System'},
          selected: _theme,
          onChanged: (v) => setState(() => _theme = v),
          onHaptic: h,
        ),
        const GalleryEyebrow('Tool tray · coloured knobs'),
        JwTray(
          margin: EdgeInsets.zero,
          children: [
            FillKnob(
              icon: JwIcons.hint,
              label: 'Hint',
              fill: JwFill.yellow,
              badge: _hints,
              onPressed: () => setState(() => _hints = _hints == 0 ? 3 : _hints - 1),
              onHaptic: h,
            ),
            FillKnob(icon: JwIcons.undo, label: 'Undo', fill: JwFill.sky, onPressed: () {}, onHaptic: h),
            FillKnob(icon: JwIcons.shuffle, label: 'Shuffle', fill: JwFill.pink, onPressed: () {}, onHaptic: h),
          ],
        ),
        const GalleryEyebrow('Layout card'),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: JwLayoutCard.tiles(
                name: 'Fortress',
                meta: '128 tiles · Hard',
                tiles: tiles,
                plateFill: JwFill.pink,
                height: 196,
                onTap: () {},
                onHaptic: h,
                stateRow: Row(
                  children: [
                    const IconBadge(icon: JwIcons.check, fill: JwFill.mint, size: 22),
                    const SizedBox(width: 6),
                    Text('Best 6:24', style: jw.text.numM.copyWith(fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Flexible(
              child: JwLayoutCard.tiles(
                name: 'Dragon',
                meta: '144 tiles · Expert',
                tiles: tiles,
                locked: true,
                height: 196,
                stateRow: Row(children: [JwIcon(JwIcons.lock, size: 16, color: jw.textMuted), const SizedBox(width: 4), Text('Clear 3 more', style: jw.text.caption)]),
              ),
            ),
          ],
        ),
        const GalleryEyebrow('List group · coloured badges'),
        JwListGroup(
          children: [
            JwListRow(
              icon: JwIcons.sound,
              badgeFill: JwFill.pink,
              title: 'Sound',
              trailing: JwToggle(value: _sound, onChanged: (v) => setState(() => _sound = v), onHaptic: h, semanticLabel: 'Sound'),
            ),
            JwListRow(icon: JwIcons.shield, badgeFill: JwFill.sky, title: 'Privacy', chevron: true, onTap: () {}, onHaptic: h),
            JwListRow(icon: JwIcons.text, badgeFill: JwFill.mint, title: 'Tile face size', value: 'Large', chevron: true, onTap: () {}, onHaptic: h),
            JwListRow(icon: JwIcons.bag, badgeFill: JwFill.yellow, title: 'Remove ads', value: r'$1.99', monoValue: true, chevron: true, onTap: () {}, onHaptic: h),
            JwListRow(icon: JwIcons.trash, title: 'Reset progress', destructive: true, onTap: () {}, onHaptic: h),
          ],
        ),
        const GalleryEyebrow('Modal'),
        JwDialog(
          title: 'Shuffle the board?',
          actions: [
            JwButton.secondary(label: 'Cancel', small: true, expand: true, onPressed: () {}, onHaptic: h),
            JwButton.primary(label: 'Shuffle', small: true, expand: true, onPressed: () {}, onHaptic: h),
          ],
          leading: const IconBadge(icon: JwIcons.shuffle, fill: JwFill.pink, size: 68),
        ),
        const GalleryEyebrow('Sheet · toast · avatars'),
        JwSheet(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: IconBadge(icon: JwIcons.pause, fill: JwFill.yellow, size: 64)),
              const SizedBox(height: 12),
              Text('Paused', style: jw.text.h3, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('4:12', style: jw.text.numXl, textAlign: TextAlign.center),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Wrap(
          spacing: 10,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            JwToast(message: 'This pair is ready · 2 hints left', icon: JwIcons.hint, fill: JwFill.yellow),
            JwToast(message: 'Daily streak saved'),
            JwAvatar(name: 'Mei'),
            JwAvatar(name: 'Pranta'),
            JwAvatar(name: 'Ola'),
            JwAvatar(name: 'Sam'),
          ],
        ),
        const GalleryEyebrow('Elevation levels'),
        const GalleryElevationRow(),
        const GalleryEyebrow('Colour fills'),
        const GalleryFillsSheet(),
        const GalleryEyebrow('Pop background'),
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: const SizedBox(height: 220, child: PopBackground(blobs: PopBlobs.corners)),
        ),
      ],
    );
  }
}

/// e0 sunken / e1 chip / e2 raised / e3 floating / pressed / fill swatches.
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
    };
    Widget swatch(String label, Widget box) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [box, const SizedBox(height: 10), Text(label, style: jw.text.caption)],
    );
    return Wrap(
      spacing: 18,
      runSpacing: 18,
      children: [
        for (final e in levels.entries)
          swatch(e.key, DecoratedBox(decoration: jw.clay(e.value, radius: 22), child: const SizedBox(width: 96, height: 70))),
        swatch('fill · f-purple', const FillBox(radius: 22, width: 96, height: 70)),
      ],
    );
  }
}

/// The six fills as on `colour-fills-*.png`: a fill card with its name and
/// on-fill sample, two badges and large text in the fill colour.
class GalleryFillsSheet extends StatelessWidget {
  const GalleryFillsSheet({super.key});

  static const _names = ['Purple', 'Mint', 'Yellow', 'Pink', 'Sky', 'Coral'];

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Wrap(
      spacing: 14,
      runSpacing: 18,
      children: [
        for (var i = 0; i < JwFill.all.length; i++)
          SizedBox(
            width: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FillBox(
                  fill: JwFill.all[i],
                  radius: 26,
                  height: 120,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_names[i], style: jw.text.h3.copyWith(color: JwFill.all[i].on)),
                      const Spacer(),
                      Text('Aa · on-fill', style: jw.text.callout.copyWith(fontWeight: FontWeight.w600, color: JwFill.all[i].on)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    IconBadge(icon: JwIcons.star, fill: JwFill.all[i], size: 34),
                    const SizedBox(width: 10),
                    IconBadge(icon: JwIcons.hint, fill: JwFill.all[i], size: 46),
                    const SizedBox(width: 12),
                    Text('Aa', style: jw.text.h2.copyWith(color: i == 0 ? jw.purpleText : JwFill.all[i].mid)),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One tile per visual state: playable, blocked, selected, hinted, blocker,
/// face-down (`tile-states-anatomy-*.png`).
class GalleryTileRow extends StatelessWidget {
  const GalleryTileRow({super.key, required this.face, this.scale = 1.6});

  final TileFaceSpec face;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Wrap(
      spacing: 14,
      runSpacing: 10,
      children: [
        for (final s in TileVisualState.values)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 12 * scale, bottom: 8 * scale),
                child: TileWidget(face: face, state: s, scale: scale, reduceMotion: true),
              ),
              Text(s.name, style: jw.text.caption),
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
