import 'package:flutter/widgets.dart';

import '../theme/clay.dart';
import '../theme/jw_palette.dart';
import '../theme/jw_tokens.dart';
import 'reduce_motion.dart';

/// Minimum hit target (pt) for every interactive component.
const double kJwMinHitTarget = 44;

/// Shared press behaviour for clay surfaces (MOTION_SPEC §4 "Button press"):
/// on pointer down the shadow cross-fades to [pressedDecoration] and the
/// surface scales to 0.97 over `quick` (180 ms, easeOutSoft); on release it
/// springs back over 250 ms `springSoft`. With reduce motion the shadow
/// cross-fades in 120 ms and nothing scales.
///
/// Primary (purple fill) decorations use the Clay Pop fill press instead
/// (MOTION_SPEC: down 4 pt losing the base edge in `instant` 120 ms
/// `standard`, spring back over 280 ms `springPop`); reduce motion keeps
/// only the 120 ms dip to the pressed texture.
///
/// Hit area is at least [kJwMinHitTarget] in both axes (the layout grows,
/// the visual stays centred).
class ClayPressable extends StatefulWidget {
  const ClayPressable({
    super.key,
    required this.decoration,
    required this.child,
    this.pressedDecoration,
    this.onTap,
    this.onHaptic,
    this.semanticLabel,
    this.reduceMotion,
    this.pressedScale = 0.97,
    this.width,
    this.height,
    this.padding = EdgeInsets.zero,
    this.isButton = true,
    this.toggled,
    this.selected,
    this.dimWhenDisabled = true,
  });

  final ClayDecoration decoration;

  /// Defaults to [decoration] with [ClayLevel.pressed] shadows, same fill.
  final ClayDecoration? pressedDecoration;
  final Widget child;
  final VoidCallback? onTap;

  /// Called on every successful tap, before [onTap]. Wire it to the haptic
  /// service (selection tick / light impact).
  final VoidCallback? onHaptic;
  final String? semanticLabel;

  /// Explicit reduce-motion flag; null reads [JwReduceMotion].
  final bool? reduceMotion;
  final double pressedScale;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final bool isButton;
  final bool? toggled;
  final bool? selected;

  /// Fade to 50% when [onTap] is null.
  final bool dimWhenDisabled;

  @override
  State<ClayPressable> createState() => _ClayPressableState();
}

class _ClayPressableState extends State<ClayPressable>
    with SingleTickerProviderStateMixin {
  static const _release = Duration(milliseconds: 250);

  // Unbounded so the springSoft release can overshoot slightly.
  late final AnimationController _press = AnimationController.unbounded(vsync: this);
  bool _reduce = false;

  bool get _enabled => widget.onTap != null;

  bool get _fill => widget.decoration.level == ClayLevel.primary;
  TickerFuture? _downFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = JwReduceMotion.of(context, widget.reduceMotion);
  }

  @override
  void didUpdateWidget(ClayPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reduce = JwReduceMotion.of(context, widget.reduceMotion);
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _down() {
    if (!_enabled) return;
    if (_reduce) {
      _downFuture = _press.animateTo(1, duration: JwMotion.instant, curve: JwMotion.linear);
    } else if (_fill) {
      _downFuture = _press.animateTo(1, duration: JwMotion.instant, curve: JwMotion.standard);
    } else {
      _downFuture = _press.animateTo(1, duration: JwMotion.quick, curve: JwMotion.easeOutSoft);
    }
  }

  void _up() {
    void release() {
      if (!mounted) return;
      if (_reduce) {
        _press.animateTo(0, duration: JwMotion.instant, curve: JwMotion.linear);
      } else if (_fill) {
        _press.animateTo(0, duration: JwMotion.base, curve: JwMotion.springPop);
      } else {
        _press.animateTo(0, duration: _release, curve: JwMotion.springSoft);
      }
    }

    // A quick tap still shows the whole fill press before springing back.
    final down = _downFuture;
    _downFuture = null;
    if (_fill && down != null && _press.isAnimating && _press.value < 1) {
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
    final pressed = widget.pressedDecoration ??
        widget.decoration.copyWith(level: ClayLevel.pressed);
    final surface = AnimatedBuilder(
      animation: _press,
      child: Padding(padding: widget.padding, child: widget.child),
      builder: (context, child) {
        final v = _press.value;
        final box = DecoratedBox(
          decoration: ClayBlendDecoration(widget.decoration, pressed, v.clamp(0.0, 1.0)),
          child: SizedBox(width: widget.width, height: widget.height, child: child),
        );
        if (_reduce || v == 0) return box;
        if (_fill) return Transform.translate(offset: Offset(0, JwFills.pressDepth * v), child: box);
        return Transform.scale(scale: 1 - (1 - widget.pressedScale) * v, child: box);
      },
    );
    return Semantics(
      container: true,
      button: widget.isButton,
      enabled: _enabled,
      toggled: widget.toggled,
      selected: widget.selected,
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
          constraints: const BoxConstraints(
            minWidth: kJwMinHitTarget,
            minHeight: kJwMinHitTarget,
          ),
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
