import 'package:flutter/widgets.dart';

import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';
import '../widgets/clay_pressable.dart';
import '../widgets/reduce_motion.dart';

/// A box painted with a Clay Pop fill ([FillDecoration]): 160° gradient,
/// inner highlight and shade, a solid base [edge] below and an optional
/// same-hue [glow]. [pressed] (0…1) shows the pressed look statically; for
/// an interactive fill use [FillPressable].
///
/// The edge paints outside the box: leave [edge] pt below it.
class FillBox extends StatelessWidget {
  const FillBox({
    super.key,
    this.fill = JwFill.purple,
    this.radius = JwRadius.lg,
    this.edge = JwFills.cardEdge,
    this.glow = true,
    this.pressed = 0,
    this.width,
    this.height,
    this.padding = EdgeInsets.zero,
    this.child,
  });

  final JwFill fill;
  final double radius;

  /// Base edge height: 5 for cards/knobs/buttons, 3 for badges, 0 for none.
  final double edge;
  final bool glow;
  final double pressed;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return DecoratedBox(
      decoration: jw.fill(fill, radius: radius, edge: edge, glow: glow, pressed: pressed),
      child: SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: padding,
          child: Transform.translate(offset: Offset(0, JwFills.pressDepth * pressed), child: child),
        ),
      ),
    );
  }
}

/// A tappable fill (knobs, primary buttons, tappable badges) with the Clay
/// Pop fill press (MOTION_SPEC): on press the body moves down
/// [JwFills.pressDepth] and its base edge disappears in `instant` 120 ms
/// `standard`; on release it springs back over `base` 280 ms `springPop`.
/// Reduce motion: a 120 ms brightness dip, nothing moves.
///
/// Each frame only moves cached textures and slides the plain edge rect;
/// the child moves with the body. Hit area is at least [kJwMinHitTarget].
class FillPressable extends StatefulWidget {
  const FillPressable({
    super.key,
    required this.fill,
    required this.child,
    this.onTap,
    this.onHaptic,
    this.radius = JwRadius.lg,
    this.edge = JwFills.cardEdge,
    this.glow = true,
    this.width,
    this.height,
    this.padding = EdgeInsets.zero,
    this.semanticLabel,
    this.reduceMotion,
    this.isButton = true,
    this.dimWhenDisabled = true,
    this.held = false,
  });

  final JwFill fill;
  final Widget child;
  final VoidCallback? onTap;

  /// Called on every successful tap, before [onTap].
  final VoidCallback? onHaptic;
  final double radius;
  final double edge;
  final bool glow;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  /// Explicit reduce-motion flag; null reads [JwReduceMotion].
  final bool? reduceMotion;
  final bool isButton;

  /// Fade to 50 % when [onTap] is null.
  final bool dimWhenDisabled;

  /// Hold the pressed pose (e.g. the Hint knob while a hint shows); it
  /// animates like a press when this changes.
  final bool held;

  @override
  State<FillPressable> createState() => _FillPressableState();
}

class _FillPressableState extends State<FillPressable> with SingleTickerProviderStateMixin {
  // Unbounded so the springPop release can overshoot.
  late final AnimationController _press = AnimationController.unbounded(vsync: this);
  TickerFuture? _downFuture;
  bool _reduce = false;

  bool get _enabled => widget.onTap != null;

  @override
  void initState() {
    super.initState();
    if (widget.held) _press.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = JwReduceMotion.of(context, widget.reduceMotion);
  }

  @override
  void didUpdateWidget(FillPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reduce = JwReduceMotion.of(context, widget.reduceMotion);
    if (widget.held != oldWidget.held) widget.held ? _down() : _up();
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _down() {
    _downFuture = _press.animateTo(
      1,
      duration: JwMotion.instant,
      curve: _reduce ? JwMotion.linear : JwMotion.standard,
    );
  }

  void _up() {
    void release() {
      if (!mounted || widget.held) return;
      if (_reduce) {
        _press.animateTo(0, duration: JwMotion.instant, curve: JwMotion.linear);
      } else {
        _press.animateTo(0, duration: JwMotion.base, curve: JwMotion.springPop);
      }
    }

    // A quick tap still shows the whole press before springing back.
    final down = _downFuture;
    _downFuture = null;
    if (down != null && _press.isAnimating && _press.value < 1) {
      down.whenCompleteOrCancel(release);
    } else {
      release();
    }
  }

  void _tap() {
    widget.onHaptic?.call();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final surface = AnimatedBuilder(
      animation: _press,
      child: Padding(padding: widget.padding, child: widget.child),
      builder: (context, child) {
        final v = _press.value;
        return DecoratedBox(
          decoration: jw.fill(
            widget.fill,
            radius: widget.radius,
            edge: widget.edge,
            glow: widget.glow,
            pressed: v,
            dip: _reduce,
          ),
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: _reduce || v == 0 ? child : Transform.translate(offset: Offset(0, JwFills.pressDepth * v), child: child),
          ),
        );
      },
    );
    return Semantics(
      container: true,
      button: widget.isButton,
      enabled: _enabled,
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      onTap: _enabled ? _tap : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => _down() : null,
        onTapUp: _enabled ? (_) => _up() : null,
        onTapCancel: _enabled ? _up : null,
        onTap: _enabled ? _tap : null,
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: kJwMinHitTarget, minHeight: kJwMinHitTarget),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Opacity(opacity: _enabled || !widget.dimWhenDisabled ? 1 : 0.5, child: surface),
          ),
        ),
      ),
    );
  }
}
