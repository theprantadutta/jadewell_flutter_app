import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../reduce_motion.dart';

/// Drives the light sweep of every [JwSkeletonBox] below it (MOTION_SPEC §4
/// "Loading / skeleton": 1500 ms linear, looping). With reduce motion the
/// boxes are static sunken blocks.
class JwSkeletonScope extends StatefulWidget {
  const JwSkeletonScope({super.key, required this.child, this.reduceMotion});

  final Widget child;
  final bool? reduceMotion;

  @override
  State<JwSkeletonScope> createState() => _JwSkeletonScopeState();
}

class _JwSkeletonScopeState extends State<JwSkeletonScope> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(JwSkeletonScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final reduce = JwReduceMotion.of(context, widget.reduceMotion);
    if (reduce) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      unawaited(_ctrl.repeat());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = JwReduceMotion.of(context, widget.reduceMotion);
    return _SkeletonSweep(sweep: reduce ? null : _ctrl, child: widget.child);
  }
}

class _SkeletonSweep extends InheritedWidget {
  const _SkeletonSweep({required this.sweep, required super.child});

  final Animation<double>? sweep;

  @override
  bool updateShouldNotify(_SkeletonSweep oldWidget) => oldWidget.sweep != sweep;
}

/// A sunken clay placeholder block (e0) with the skeleton light sweep.
/// Pass [width] / [height] or let the parent size it.
class JwSkeletonBox extends StatelessWidget {
  const JwSkeletonBox({super.key, this.width, this.height, this.radius = 24});

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final sweep = context.dependOnInheritedWidgetOfExactType<_SkeletonSweep>()?.sweep;
    Widget box = DecoratedBox(
      decoration: jw.clay(ClayLevel.sunken, radius: radius),
      child: SizedBox(width: width, height: height),
    );
    if (sweep != null) {
      box = CustomPaint(
        foregroundPainter: _SweepPainter(sweep, jw.isDark ? jw.highlight : jw.highlightSoft, radius),
        child: box,
      );
    }
    return ExcludeSemantics(child: RepaintBoundary(child: box));
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter(this.t, this.color, this.radius) : super(repaint: t);

  final Animation<double> t;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // A soft band 60% of the width travels from fully left to fully right.
    final band = size.width * 0.6;
    final x = -band + (size.width + band) * t.value;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [color.withValues(alpha: 0), color, color.withValues(alpha: 0)],
      ).createShader(Rect.fromLTWH(x, 0, band, size.height));
    canvas
      ..save()
      ..clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)))
      ..drawRect(Rect.fromLTWH(x, 0, band, size.height), paint)
      ..restore();
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.color != color || old.radius != radius || old.t != t;
}

/// Shows [skeleton] while [loading], following MOTION_SPEC §4: nothing at all
/// for the first 120 ms (fast loads skip the skeleton), and once shown the
/// skeleton stays for at least 300 ms. When content lands it is built with
/// [builder]; wrap its parts in [JwFadeUp] for the staggered fade-up.
class JwSkeletonSwitcher extends StatefulWidget {
  const JwSkeletonSwitcher({super.key, required this.loading, required this.skeleton, required this.builder});

  final bool loading;
  final Widget skeleton;
  final WidgetBuilder builder;

  static const skipBelow = Duration(milliseconds: 120);
  static const minVisible = Duration(milliseconds: 300);

  @override
  State<JwSkeletonSwitcher> createState() => _JwSkeletonSwitcherState();
}

class _JwSkeletonSwitcherState extends State<JwSkeletonSwitcher> {
  Timer? _timer;
  DateTime? _shownAt;
  bool _showSkeleton = false;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    if (widget.loading) _armSkip();
  }

  void _armSkip() {
    _timer?.cancel();
    _timer = Timer(JwSkeletonSwitcher.skipBelow, () {
      if (!mounted || !widget.loading) return;
      setState(() {
        _showSkeleton = true;
        _shownAt = DateTime.now();
      });
    });
  }

  @override
  void didUpdateWidget(JwSkeletonSwitcher old) {
    super.didUpdateWidget(old);
    if (widget.loading && !old.loading) {
      _armSkip();
    } else if (!widget.loading && old.loading) {
      _timer?.cancel();
      if (_showSkeleton && _shownAt != null) {
        final left = JwSkeletonSwitcher.minVisible - DateTime.now().difference(_shownAt!);
        if (left > Duration.zero) {
          _holding = true;
          _timer = Timer(left, () {
            if (mounted) {
              setState(() {
                _holding = false;
                _showSkeleton = false;
              });
            }
          });
          return;
        }
      }
      _showSkeleton = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading || _holding) {
      return _showSkeleton ? widget.skeleton : const SizedBox.shrink();
    }
    return widget.builder(context);
  }
}

/// Content fade-up: 14 pt rise + fade, 600 ms easeOutSoft, delayed
/// [index] × 60 ms (MOTION_SPEC §4). Reduce motion: 150 ms fade, no travel.
class JwFadeUp extends StatefulWidget {
  const JwFadeUp({super.key, required this.child, this.index = 0, this.enabled = true, this.reduceMotion});

  final Widget child;

  /// Stagger slot (60 ms each).
  final int index;

  /// False shows [child] immediately (e.g. after the first show).
  final bool enabled;
  final bool? reduceMotion;

  @override
  State<JwFadeUp> createState() => _JwFadeUpState();
}

class _JwFadeUpState extends State<JwFadeUp> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, value: widget.enabled ? 0 : 1);
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ctrl.value == 0 && !_ctrl.isAnimating && _delay == null) {
      final reduce = JwReduceMotion.of(context, widget.reduceMotion);
      _ctrl.duration = reduce ? const Duration(milliseconds: 150) : JwMotion.slow;
      final wait = reduce ? Duration.zero : Duration(milliseconds: 60 * widget.index.clamp(0, 10));
      _delay = Timer(wait, () {
        if (mounted) unawaited(_ctrl.forward());
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = JwReduceMotion.of(context, widget.reduceMotion);
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (context, child) {
        final t = reduce ? _ctrl.value : JwMotion.easeOutSoft.transform(_ctrl.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, reduce ? 0 : 14 * (1 - t)), child: child),
        );
      },
    );
  }
}

/// The layout-select skeleton of screen 18: a title, subtitle and progress
/// bars, the daily hero block, a section label and a 2-column card grid.
class JwSkeletonHome extends StatelessWidget {
  const JwSkeletonHome({super.key, required this.title, this.columns = 2, this.semanticLabel});

  /// Shown for real (the title never waits on data).
  final String title;
  final int columns;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Semantics(
      label: semanticLabel,
      liveRegion: true,
      child: JwSkeletonScope(
        child: LayoutBuilder(
          builder: (context, box) {
            const gap = 14.0;
            final cardW = (box.maxWidth - 32 - gap * (columns - 1)) / columns;
            return SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(title, style: jw.text.h1),
                  ),
                  const SizedBox(height: 14),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Align(alignment: Alignment.centerLeft, child: JwSkeletonBox(width: 180, height: 14, radius: 7)),
                  ),
                  const SizedBox(height: 14),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: JwSkeletonBox(height: 14, radius: 7),
                  ),
                  const SizedBox(height: 22),
                  const JwSkeletonBox(height: 164, radius: 30),
                  const SizedBox(height: 34),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Align(alignment: Alignment.centerLeft, child: JwSkeletonBox(width: 120, height: 16, radius: 8)),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var i = 0; i < columns * 2; i++) JwSkeletonBox(width: cardW, height: 190, radius: 26),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
