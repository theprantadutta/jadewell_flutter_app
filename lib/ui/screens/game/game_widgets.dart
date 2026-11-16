import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/widgets.dart';

/// `m:ss` (or `h:mm:ss` from one hour) for board times.
String formatClock(int ms) {
  final total = (ms < 0 ? 0 : ms) ~/ 1000;
  final h = total ~/ 3600, m = (total ~/ 60) % 60, s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// Text whose changed characters roll in (MOTION_SPEC §4 counter ticks):
/// from −40 % y with scale 0.8 → 1, 400 ms springSoft. Unchanged characters
/// stay still; nothing rolls on the first frame. Characters are aligned from
/// the right so "10" → "9" only rolls what changed. Use a mono style so
/// widths never shift.
class RollingText extends StatefulWidget {
  const RollingText(this.text, {super.key, required this.style, this.reduceMotion});

  final String text;
  final TextStyle style;
  final bool? reduceMotion;

  @override
  State<RollingText> createState() => _RollingTextState();
}

class _RollingTextState extends State<RollingText> {
  /// Generation per right-aligned index; bumps when that character changes.
  final List<int> _gen = [];

  @override
  void didUpdateWidget(RollingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = oldWidget.text.characters.toList(), b = widget.text.characters.toList();
    if (a.join() == b.join()) return;
    while (_gen.length < b.length) {
      _gen.add(0);
    }
    for (var r = 0; r < b.length; r++) {
      final before = r < a.length ? a[a.length - 1 - r] : null;
      if (before != b[b.length - 1 - r]) _gen[r]++;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (JwReduceMotion.of(context, widget.reduceMotion)) return Text(widget.text, style: widget.style);
    final chars = widget.text.characters.toList();
    while (_gen.length < chars.length) {
      _gen.add(0);
    }
    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < chars.length; i++)
            _RollingChar(
              key: ValueKey('${chars.length - 1 - i}:${_gen[chars.length - 1 - i]}'),
              char: chars[i],
              style: widget.style,
              animate: _gen[chars.length - 1 - i] > 0,
            ),
        ],
      ),
    );
  }
}

class _RollingChar extends StatefulWidget {
  const _RollingChar({super.key, required this.char, required this.style, required this.animate});

  final String char;
  final TextStyle style;
  final bool animate;

  @override
  State<_RollingChar> createState() => _RollingCharState();
}

class _RollingCharState extends State<_RollingChar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: JwMotion.gentle);

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(widget.char, style: widget.style);
    return AnimatedBuilder(
      animation: _c,
      child: text,
      builder: (context, child) {
        if (_c.value >= 1) return child!;
        final t = JwMotion.springSoft.transform(_c.value);
        return FractionalTranslation(
          translation: Offset(0, -0.4 * (1 - t)),
          child: Transform.scale(
            scale: 0.8 + 0.2 * t,
            child: Opacity(opacity: _c.value.clamp(0.0, 1.0), child: child),
          ),
        );
      },
    );
  }
}

/// Counter chip as [JwChip] (30 tall, e1, mono value + label) with a
/// rolling value; [accent] gives the accentSoft chip (streaks).
class GameCounterChip extends StatelessWidget {
  const GameCounterChip({super.key, required this.value, required this.label, this.accent = false});

  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final deco = accent ? jw.clay(ClayLevel.flat, color: jw.accentSoft, radius: 15) : jw.clay(ClayLevel.chip, radius: 15);
    return Semantics(
      label: '$value $label',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: deco,
        child: SizedBox(
          height: 30,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RollingText(value, style: jw.text.numM.copyWith(fontSize: 14.5)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: jw.text.callout.copyWith(
                    fontWeight: FontWeight.w400,
                    color: accent ? jw.textPrimary : jw.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The game's timer pill (46 tall, e2, accent pause glyph, mono 19 pt) with
/// digits that roll once per second. Polls [elapsedMs] while [running].
class GameTimerPill extends StatefulWidget {
  const GameTimerPill({
    super.key,
    required this.elapsedMs,
    required this.running,
    required this.onTap,
    required this.semanticLabel,
    this.icon = JwIcons.pause,
  });

  final int Function() elapsedMs;
  final bool running;
  final VoidCallback? onTap;
  final String Function(String time) semanticLabel;
  final String icon;

  @override
  State<GameTimerPill> createState() => _GameTimerPillState();
}

class _GameTimerPillState extends State<GameTimerPill> {
  Timer? _timer;
  late String _text = formatClock(widget.elapsedMs());

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(GameTimerPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
    _refresh();
  }

  void _sync() {
    if (widget.running && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _refresh());
    } else if (!widget.running) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _refresh() {
    final t = formatClock(widget.elapsedMs());
    if (t != _text && mounted) setState(() => _text = t);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return ClayPressable(
      decoration: jw.clay(ClayLevel.raised, radius: 23),
      onTap: widget.onTap,
      semanticLabel: widget.semanticLabel(_text),
      height: 46,
      dimWhenDisabled: false,
      padding: const EdgeInsets.only(left: 22, right: 22),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          JwIcon(widget.icon, size: 17, color: jw.accent),
          const SizedBox(width: 14),
          RollingText(_text, style: jw.text.numM.copyWith(fontSize: 19)),
        ],
      ),
    );
  }
}

/// A sunken rounded well holding an accent icon (sheet and dialog headers).
class GameIconWell extends StatelessWidget {
  const GameIconWell({super.key, required this.icon, this.size = 64});

  final String icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return DecoratedBox(
      decoration: jw.clay(ClayLevel.sunken, radius: size * 0.34),
      child: SizedBox.square(
        dimension: size,
        child: Center(child: JwIcon(icon, size: size * 0.42, color: jw.accent)),
      ),
    );
  }
}

/// Presents a sheet ([bottom]) or a centred card/dialog with the motion of
/// MOTION_SPEC §4: scrim 0 → 1 in 200 ms standard; content rises 40 pt and
/// fades in 400 ms springSoft; dismiss 250 ms exit. Reduce motion: 150 ms
/// crossfade.
Future<T?> showGameModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool bottom = false,
  bool dismissible = true,
  String? barrierLabel,
}) {
  final reduce = JwReduceMotion.of(context);
  return Navigator.of(context, rootNavigator: true).push(
    _GameModalRoute<T>(
      builder: builder,
      bottom: bottom,
      dismissible: dismissible,
      label: barrierLabel ?? MaterialLocalizations.of(context).modalBarrierDismissLabel,
      reduce: reduce,
      theme: Theme.of(context),
      jw: context.jw,
    ),
  );
}

class _GameModalRoute<T> extends PopupRoute<T> {
  _GameModalRoute({
    required this.builder,
    required this.bottom,
    required this.dismissible,
    required this.label,
    required this.reduce,
    required this.theme,
    required this.jw,
  });

  final WidgetBuilder builder;
  final bool bottom;
  final bool dismissible;
  final String label;
  final bool reduce;
  final ThemeData theme;
  final JwTheme jw;

  @override
  bool get barrierDismissible => dismissible;

  @override
  String? get barrierLabel => label;

  @override
  Color? get barrierColor => null;

  @override
  Duration get transitionDuration => reduce ? const Duration(milliseconds: 150) : JwMotion.gentle;

  @override
  Duration get reverseTransitionDuration => reduce ? const Duration(milliseconds: 150) : const Duration(milliseconds: 250);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final content = Theme(
      data: theme,
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(style: jw.text.body, child: Builder(builder: builder)),
      ),
    );
    return SafeArea(
      child: bottom
          ? Align(alignment: Alignment.bottomCenter, child: content)
          : Center(child: SingleChildScrollView(child: content)),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final v = animation.value;
        final forward = animation.status != AnimationStatus.reverse;
        final double scrim, rise, opacity;
        if (reduce) {
          scrim = v;
          rise = 0;
          opacity = v;
        } else if (forward) {
          scrim = JwMotion.standard.transform((v * 2).clamp(0.0, 1.0));
          rise = 40 * (1 - JwMotion.springSoft.transform(v));
          opacity = v;
        } else {
          scrim = v;
          rise = 40 * JwMotion.exit.transform(1 - v);
          opacity = v;
        }
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(child: ColoredBox(color: jw.scrim.withValues(alpha: jw.scrim.a * scrim))),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.translate(offset: Offset(0, rise), child: child),
              ),
            ),
          ],
        );
      },
    );
  }
}
