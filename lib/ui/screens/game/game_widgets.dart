import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../components/components.dart';
import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/widgets.dart';
import '../settings/screen_chrome.dart' show kJwCardMaxWidth, kJwSheetMaxWidth;

/// `m:ss` (or `h:mm:ss` from one hour) for board times.
String formatClock(int ms) {
  final total = (ms < 0 ? 0 : ms) ~/ 1000;
  final h = total ~/ 3600, m = (total ~/ 60) % 60, s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// Mono text that rolls like an odometer when it changes (game timer and
/// counters): see [OdometerText]. Reduce motion: instant change.
class RollingText extends StatelessWidget {
  const RollingText(this.text, {super.key, required this.style, this.reduceMotion});

  final String text;
  final TextStyle style;
  final bool? reduceMotion;

  @override
  Widget build(BuildContext context) => OdometerText(text, style: style, reduceMotion: reduceMotion);
}

/// Game counter (DESIGN_SYSTEM §11 `cchip`): a [CounterChip] with a
/// leading [fill] badge and a rolling value. Tiles = mint, pairs = pink,
/// streak = coral.
class GameCounterChip extends StatelessWidget {
  const GameCounterChip({
    super.key,
    required this.value,
    this.label,
    required this.icon,
    required this.fill,
    this.semanticLabel,
  });

  final String value;
  final String? label;

  /// A [JwIcons] name for the badge.
  final String icon;
  final JwFill fill;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return CounterChip(
      icon: icon,
      value: value,
      label: label,
      fill: fill,
      semanticLabel: semanticLabel,
      valueWidget: RollingText(value, style: CounterChip.valueStyle(jw)),
    );
  }
}

/// The game's timer pill (46 tall, raised, a 32 pt yellow pause badge, mono
/// 19/700) with digits that roll once per second. Polls [elapsedMs] while [running].
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
      padding: const EdgeInsets.only(left: 7, right: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Lift the badge 1.5 pt so its 3 pt edge sits inside the pill.
          Transform.translate(
            offset: const Offset(0, -1.5),
            child: IconBadge(icon: widget.icon, fill: JwFill.yellow, size: 32),
          ),
          const SizedBox(width: 12),
          RollingText(_text, style: jw.text.numM.copyWith(fontSize: 19, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// The 56–68 pt fill badge that leads game sheets and dialogs (DESIGN_SYSTEM
/// §11: pink shuffle, yellow pause / rewards).
class GameIconWell extends StatelessWidget {
  const GameIconWell({super.key, required this.icon, this.fill = JwFill.purple, this.size = 64});

  final String icon;
  final JwFill fill;
  final double size;

  @override
  Widget build(BuildContext context) =>
      // The 4 pt base edge paints below the box; leave room for it.
      Padding(padding: const EdgeInsets.only(bottom: 4), child: IconBadge(icon: icon, fill: fill, size: size, edge: 4));
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
  });

  final WidgetBuilder builder;
  final bool bottom;
  final bool dismissible;
  final String label;
  final bool reduce;

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
    // Read the theme here (not when pushed) so an open modal follows a
    // light/dark switch.
    final content = Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(style: context.jw.text.body, child: Builder(builder: builder)),
    );
    // Cards and sheets keep phone proportions on tablets instead of
    // stretching edge to edge (the caps are wider than any phone).
    return SafeArea(
      child: bottom
          ? Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kJwSheetMaxWidth), child: content),
            )
          : Center(
              child: SingleChildScrollView(
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kJwCardMaxWidth), child: content),
              ),
            ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final jw = context.jw;
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
