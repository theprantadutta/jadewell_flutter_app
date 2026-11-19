import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/jw_theme.dart';

/// The 43 icons in `assets/icons/` (24 pt grid, 2 pt round stroke).
abstract final class JwIcons {
  static const arrow = 'arrow', back = 'back', bag = 'bag', cal = 'cal';
  static const chart = 'chart', check = 'check', chev = 'chev', clock = 'clock';
  static const door = 'door', download = 'download', eye = 'eye', fire = 'fire', flame = 'flame';
  static const gauge = 'gauge', gear = 'gear', grid = 'grid', heart = 'heart', hint = 'hint';
  static const info = 'info', lock = 'lock', mail = 'mail', moon = 'moon', motion = 'motion';
  static const pairs = 'pairs', pause = 'pause', play = 'play', replay = 'replay';
  static const restore = 'restore', shield = 'shield', shuffle = 'shuffle';
  static const sound = 'sound', sparkle = 'sparkle', star = 'star', sun = 'sun';
  static const text = 'text', tile = 'tile', trash = 'trash', trophy = 'trophy';
  static const undo = 'undo', user = 'user', vib = 'vib', video = 'video', x = 'x';

  static const all = [
    arrow, back, bag, cal, chart, check, chev, clock, door, download, eye, fire, //
    flame, gauge, gear, grid, heart, hint, info, lock, mail, moon, motion, pairs, pause, play,
    replay, restore, shield, shuffle, sound, sparkle, star, sun, text, tile,
    trash, trophy, undo, user, vib, video, x,
  ];
}

/// Renders `assets/icons/<name>.svg` with `currentColor` mapped to [color]
/// (defaults to the ambient [IconTheme] colour, then `textPrimary`).
///
/// [strokeWidth] (in 24-grid units) overrides the drawn 2 pt stroke: icons
/// inside fill badges use 2.4 (DESIGN_SYSTEM §12).
class JwIcon extends StatelessWidget {
  const JwIcon(this.name, {super.key, this.size = 22, this.color, this.semanticLabel, this.strokeWidth});

  final String name;
  final double size;
  final Color? color;
  final String? semanticLabel;
  final double? strokeWidth;

  /// Stroke width of icons inside fill badges.
  static const double badgeStroke = 2.4;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? JwTheme.of(context).textPrimary;
    final theme = SvgTheme(currentColor: c);
    final path = 'assets/icons/$name.svg';
    final stroke = strokeWidth;
    return SvgPicture(
      stroke == null || stroke == 2 ? SvgAssetLoader(path, theme: theme) : _StrokeSvgLoader(path, stroke, theme: theme),
      width: size,
      height: size,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}

/// An icon asset with its `stroke-width="2"` replaced.
class _StrokeSvgLoader extends SvgAssetLoader {
  const _StrokeSvgLoader(super.assetName, this.strokeWidth, {super.theme});

  final double strokeWidth;

  @override
  String provideSvg(ByteData? message) =>
      super.provideSvg(message).replaceAll('stroke-width="2"', 'stroke-width="$strokeWidth"');

  @override
  SvgCacheKey cacheKey(BuildContext? context) =>
      SvgCacheKey(theme: getTheme(context), colorMapper: colorMapper, keyData: (assetName, strokeWidth));

  @override
  int get hashCode => Object.hash(super.hashCode, strokeWidth);

  @override
  bool operator ==(Object other) => other is _StrokeSvgLoader && other.strokeWidth == strokeWidth && super == other;
}
