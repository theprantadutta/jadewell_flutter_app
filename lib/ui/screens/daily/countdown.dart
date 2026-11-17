import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../widgets/odometer_text.dart';

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

/// Countdown text that rolls like an odometer (new digits drop in from
/// above): see [OdometerText]. Reduce motion: instant change.
class RollingText extends StatelessWidget {
  const RollingText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => OdometerText(text, style: style, direction: OdometerDirection.down);
}
