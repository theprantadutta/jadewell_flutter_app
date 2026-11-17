import 'package:flutter/widgets.dart';

import '../theme/jw_tokens.dart';
import 'reduce_motion.dart';

/// Which way changed digits travel.
enum OdometerDirection {
  /// New digit rolls up from below, the old one leaves through the top
  /// (counting up: timers, counters).
  up,

  /// New digit drops in from above (counting down: countdowns).
  down,
}

/// Mono text that animates like an odometer: every character that changes
/// slides out of its slot while the new one slides in, clipped to the slot,
/// so digits never float outside the pill. Characters are matched from the
/// right, so "9:59" → "10:00" still rolls the right digits. Reduce motion:
/// instant swap.
class OdometerText extends StatelessWidget {
  const OdometerText(
    this.text, {
    super.key,
    required this.style,
    this.direction = OdometerDirection.up,
    this.duration = const Duration(milliseconds: 380),
    this.reduceMotion,
  });

  final String text;
  final TextStyle style;
  final OdometerDirection direction;
  final Duration duration;

  /// Overrides the inherited reduce-motion flag (tests).
  final bool? reduceMotion;

  @override
  Widget build(BuildContext context) {
    if (JwReduceMotion.of(context, reduceMotion)) {
      return Text(text, style: style, maxLines: 1, softWrap: false);
    }
    final n = text.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < n; i++)
          _OdometerChar(
            // Keyed by position from the right so a length change (9:59 →
            // 10:00) keeps each digit on its own track.
            key: ValueKey<int>(n - 1 - i),
            char: text[i],
            style: style,
            direction: direction,
            duration: duration,
          ),
      ],
    );
  }
}

class _OdometerChar extends StatefulWidget {
  const _OdometerChar({
    super.key,
    required this.char,
    required this.style,
    required this.direction,
    required this.duration,
  });

  final String char;
  final TextStyle style;
  final OdometerDirection direction;
  final Duration duration;

  @override
  State<_OdometerChar> createState() => _OdometerCharState();
}

class _OdometerCharState extends State<_OdometerChar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration, value: 1);
  String? _previous;

  @override
  void didUpdateWidget(_OdometerChar old) {
    super.didUpdateWidget(old);
    if (old.char != widget.char) {
      _previous = old.char;
      _c
        ..duration = widget.duration
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = Text(widget.char, style: widget.style, maxLines: 1, softWrap: false);
    return AnimatedBuilder(
      animation: _c,
      child: current,
      builder: (context, child) {
        final previous = _previous;
        if (_c.value >= 1 || previous == null) return child!;
        final t = JwMotion.easeOutSoft.transform(_c.value);
        // up: new comes from +1 (below) to 0, old goes 0 → -1 (above).
        final sign = widget.direction == OdometerDirection.up ? 1.0 : -1.0;
        return ClipRect(
          child: Stack(
            alignment: Alignment.center,
            children: [
              FractionalTranslation(
                translation: Offset(0, -sign * t),
                child: Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: Text(previous, style: widget.style, maxLines: 1, softWrap: false),
                ),
              ),
              FractionalTranslation(translation: Offset(0, sign * (1 - t)), child: child),
            ],
          ),
        );
      },
    );
  }
}
