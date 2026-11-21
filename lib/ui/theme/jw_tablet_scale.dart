import 'package:material_ui/material_ui.dart';

/// Large tablets (iPad Pro / Air 13", iPad 11"): the screens are designed for
/// phones and small tablets, so on a 1032 pt wide iPad they would float small
/// in the middle with phone-sized text. Instead the whole UI is laid out on a
/// canvas whose short side is [designShortSide] and scaled up to fill the
/// screen. Phones and small tablets (factor <= [threshold]) are untouched.
///
/// The device pixel ratio is raised by the same factor so text, clay
/// decorations and rasterised tiles stay sharp after the scale.
class JwTabletScale extends StatelessWidget {
  const JwTabletScale({super.key, required this.child});

  final Widget child;

  /// Logical short side the UI is laid out at on large tablets.
  static const double designShortSide = 768;

  /// Below this factor (iPad mini, 7-10" Android tablets) scaling isn't worth it.
  static const double threshold = 1.05;

  /// Scale factor for a screen of [size] (1 = no scaling).
  static double factorFor(Size size) {
    final f = size.shortestSide / designShortSide;
    return f > threshold ? f : 1;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final f = factorFor(mq.size);
    if (f == 1) return child;
    final logical = mq.size / f;
    return MediaQuery(
      data: mq.copyWith(
        size: logical,
        devicePixelRatio: mq.devicePixelRatio * f,
        padding: mq.padding / f,
        viewPadding: mq.viewPadding / f,
        viewInsets: mq.viewInsets / f,
        systemGestureInsets: mq.systemGestureInsets / f,
      ),
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(size: logical, child: child),
      ),
    );
  }
}
