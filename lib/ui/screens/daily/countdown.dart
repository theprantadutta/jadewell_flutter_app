import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../theme/jw_tokens.dart';
import '../../widgets/reduce_motion.dart';

/// Time left until the next UTC midnight (when the daily board rolls over).
Duration untilNextUtcMidnight(DateTime now) {
  final u = now.toUtc();
  final next = DateTime.utc(u.year, u.month, u.day + 1);
  return next.difference(u);
}

/// `H:MM:SS` (hours unpadded), e.g. 1:15:07; never negative.
String formatCountdown(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// Rebuilds once a second with the countdown to the next UTC midnight.
class DailyCountdown extends StatefulWidget {
  const DailyCountdown({super.key, required this.builder, this.clock = DateTime.now});

  final Widget Function(BuildContext context, Duration left) builder;
  final DateTime Function() clock;

  @override
  State<DailyCountdown> createState() => _DailyCountdownState();
}

class _DailyCountdownState extends State<DailyCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    // Align ticks to the wall-clock second so the digits change on time.
    final now = widget.clock();
    _timer = Timer(Duration(milliseconds: 1000 - now.millisecond), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, untilNextUtcMidnight(widget.clock()));
}

/// Mono text whose changed characters roll in from −40% y with scale
/// 0.8 → 1 over 400 ms springSoft (MOTION_SPEC §4 "Counter ticks").
/// Reduce motion: instant change.
class RollingText extends StatelessWidget {
  const RollingText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final reduce = JwReduceMotion.of(context);
    if (reduce) return Text(text, style: style, maxLines: 1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < text.length; i++)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: JwMotion.springSoft,
            switchOutCurve: JwMotion.exit,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [...previous, ?current],
            ),
            transitionBuilder: (child, anim) {
              final incoming = child.key == ValueKey('${text.length}-$i-${text[i]}');
              if (!incoming) return FadeTransition(opacity: anim, child: child);
              return AnimatedBuilder(
                animation: anim,
                child: child,
                builder: (context, c) => Opacity(
                  opacity: anim.value.clamp(0.0, 1.0),
                  child: FractionalTranslation(
                    translation: Offset(0, -0.4 * (1 - anim.value)),
                    child: Transform.scale(scale: 0.8 + 0.2 * anim.value, child: c),
                  ),
                ),
              );
            },
            child: Text(text[i], key: ValueKey('${text.length}-$i-${text[i]}'), style: style),
          ),
      ],
    );
  }
}
