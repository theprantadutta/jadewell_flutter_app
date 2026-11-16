import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The 40 icons in `assets/icons/` (24 pt grid, 2 pt round stroke).
abstract final class JwIcons {
  static const arrow = 'arrow', back = 'back', bag = 'bag', cal = 'cal';
  static const chart = 'chart', check = 'check', chev = 'chev', clock = 'clock';
  static const door = 'door', eye = 'eye', fire = 'fire', flame = 'flame';
  static const gear = 'gear', grid = 'grid', heart = 'heart', hint = 'hint';
  static const info = 'info', lock = 'lock', moon = 'moon', motion = 'motion';
  static const pairs = 'pairs', pause = 'pause', play = 'play', replay = 'replay';
  static const restore = 'restore', shield = 'shield', shuffle = 'shuffle';
  static const sound = 'sound', sparkle = 'sparkle', star = 'star', sun = 'sun';
  static const text = 'text', tile = 'tile', trash = 'trash', trophy = 'trophy';
  static const undo = 'undo', user = 'user', vib = 'vib', video = 'video', x = 'x';

  static const all = [
    arrow, back, bag, cal, chart, check, chev, clock, door, eye, fire, flame, //
    gear, grid, heart, hint, info, lock, moon, motion, pairs, pause, play,
    replay, restore, shield, shuffle, sound, sparkle, star, sun, text, tile,
    trash, trophy, undo, user, vib, video, x,
  ];
}

/// Renders `assets/icons/<name>.svg` with `currentColor` mapped to [color]
/// (defaults to the ambient [IconTheme] colour).
class JwIcon extends StatelessWidget {
  const JwIcon(this.name, {super.key, this.size = 22, this.color, this.semanticLabel});

  final String name;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? const Color(0xFF4A3934);
    return SvgPicture.asset(
      'assets/icons/$name.svg',
      width: size,
      height: size,
      theme: SvgTheme(currentColor: c),
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
