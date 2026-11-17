import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/settings.dart';
import '../../../platform/analytics/analytics_service.dart';
import '../../../state/data_providers.dart';
import '../../../state/platform_providers.dart';
import '../../components/components.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../router.dart';
import '../../theme/clay.dart';
import '../../theme/jw_background.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/widgets.dart';

/// Splash (design/splash/SPLASH.md, option A handoff): starts on exactly the
/// native splash frame (flat surface colour, the purple plate and the mark's
/// two tiles at the native size and position), then plays A's last beats:
/// blobs fade in, the mint beads pop, the wordmark fades up and the
/// "Every board is solvable" chip appears (~600 ms); then hands over to
/// onboarding (first run) or home.
///
/// Never waits on the network: the only wait is the local settings read,
/// capped at [settingsTimeout].
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// The whole handoff: blobs 0–280 ms, beads 140–500 ms, wordmark
  /// 280–600 ms (320 ms easeOutSoft, 12 pt).
  static const total = Duration(milliseconds: 600);

  /// Hold on the final frame before handing over.
  static const hold = Duration(milliseconds: 120);
  static const settingsTimeout = Duration(seconds: 2);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  static bool _appOpenLogged = false;

  late final AnimationController _ctrl = AnimationController(vsync: this, duration: SplashScreen.total);
  bool _started = false;
  bool _deferred = false;

  @override
  void initState() {
    super.initState();
    // Hold the native splash until the mark image is decoded, so the first
    // Flutter frame already shows it (no one-frame blink). Real app only.
    final binding = WidgetsBinding.instance;
    if (binding.runtimeType == WidgetsFlutterBinding && !binding.firstFrameRasterized) {
      binding.deferFirstFrame();
      _deferred = true;
    }
  }

  void _allowFirstFrame() {
    if (!_deferred) return;
    _deferred = false;
    WidgetsBinding.instance.allowFirstFrame();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(
      precacheImage(AssetImage(_markAsset), context)
          .timeout(const Duration(milliseconds: 400), onTimeout: () {})
          .whenComplete(_allowFirstFrame),
    );
    if (!_appOpenLogged) {
      _appOpenLogged = true;
      unawaited(ref.read(analyticsProvider).log(AnalyticsEvents.appOpen));
    }
    unawaited(_run(JwReduceMotion.of(context)));
  }

  Future<void> _run(bool reduce) async {
    final settingsFuture = ref
        .read(settingsProvider.future)
        .timeout(SplashScreen.settingsTimeout, onTimeout: () => const AppSettings())
        .catchError((Object _) => const AppSettings());
    if (reduce) {
      _ctrl.value = 1;
    } else {
      await _ctrl.forward().orCancel.catchError((Object _) {});
    }
    final settings = await settingsFuture;
    await Future<void>.delayed(reduce ? const Duration(milliseconds: 200) : SplashScreen.hold);
    if (!mounted) return;
    context.go(settings.onboardingDone ? AppRoutes.home : AppRoutes.onboarding);
  }

  static bool get _a12 => defaultTargetPlatform == TargetPlatform.android;
  static const _markAsset = 'assets/brand/mark_tiles_a12.png';

  @override
  void dispose() {
    _allowFirstFrame();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the settings stream listened (Riverpod pauses unlistened providers).
    ref.watch(settingsProvider);
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    // The native splash centres its icon in the whole window (edge to edge).
    // Android 12+: the OEM-masked #634FE0 plate (156 dp on One UI) with the
    // tiles foreground drawn in a 288 dp box (the 1152 px image). Elsewhere
    // the same mark on a 192 pt rounded plate (the 768 px image at 4x).
    final a12 = _a12;
    final plate = a12 ? 156.0 : 192.0;
    final markBox = plate * 288 / 156;
    final centre = Offset(size.width / 2, size.height / 2);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: jw.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: ColoredBox(
        color: jw.surface,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final ms = _ctrl.value * SplashScreen.total.inMilliseconds;
            double p(double start, double dur) => ((ms - start) / dur).clamp(0.0, 1.0);
            // Blobs and the plate's gradient fade in (280 ms).
            final bg = JwMotion.easeOutSoft.transform(p(0, 280));
            // Beads pop (300 ms springPop, the right one 60 ms behind).
            final beadL = JwMotion.springPop.transform(p(140, 300));
            final beadR = JwMotion.springPop.transform(p(200, 300));
            // Wordmark fades up 12 pt (320 ms easeOutSoft).
            final word = JwMotion.easeOutSoft.transform(p(280, 320));
            final beadD = plate * 24.4 / 156;
            Widget bead(double dx, double s) => Positioned(
              left: centre.dx + dx * plate / 156 - beadD / 2,
              top: centre.dy - 1.6 * plate / 156 - beadD / 2,
              width: beadD,
              height: beadD,
              child: Opacity(
                opacity: s <= 0 ? 0 : 1,
                child: Transform.scale(
                  scale: s,
                  child: RepaintBoundary(child: CustomPaint(painter: JwBeadPainter(JwFill.mint.mid))),
                ),
              ),
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                Opacity(opacity: bg, child: const JwBackground(blobs: PopBlobs.corners)),
                Positioned(
                  left: centre.dx - plate / 2,
                  top: centre.dy - plate / 2,
                  width: plate,
                  height: plate,
                  child: CustomPaint(painter: SplashPlatePainter(gradient: bg, superellipse: a12)),
                ),
                Positioned(
                  left: centre.dx - markBox / 2,
                  top: centre.dy - markBox / 2,
                  width: markBox,
                  height: markBox,
                  child: Image.asset(
                    _markAsset,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  ),
                ),
                bead(-22.3, beadL),
                bead(22.3, beadR),
                Positioned(
                  left: 24,
                  right: 24,
                  top: centre.dy + plate / 2 + 30,
                  child: Opacity(
                    opacity: word,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - word)),
                      child: Semantics(
                        label: '${l.appName}, ${l.splashSubtitle}',
                        excludeSemantics: true,
                        child: Column(
                          children: [
                            Text(l.appName, style: jw.text.display.copyWith(fontSize: 40, height: 1.1)),
                            const SizedBox(height: 12),
                            Text(
                              l.splashSubtitle.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: jw.text.eyebrow.copyWith(fontSize: 13, letterSpacing: 13 * 0.22, color: jw.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: MediaQuery.paddingOf(context).bottom + 34,
                  child: Opacity(
                    opacity: word,
                    child: Center(child: _SolvableChip(label: l.splashFooter)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "Every board is solvable": a white pill with a mint check badge.
class _SolvableChip extends StatelessWidget {
  const _SolvableChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return DecoratedBox(
      decoration: jw.clay(ClayLevel.chip, radius: 19),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 4, 16, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: const Offset(0, -1.5),
              child: const IconBadge(icon: JwIcons.check, fill: JwFill.mint),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: jw.text.callout.copyWith(fontSize: 15, fontWeight: FontWeight.w500, color: jw.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The mark's purple plate: starts flat `#634FE0` in the native splash's
/// shape (Android 12+: the One UI superellipse, n ≈ 2.7; elsewhere the
/// icon's rounded square) and fades to the purple fill gradient with a soft
/// top-left highlight as [gradient] goes 0 → 1.
class SplashPlatePainter extends CustomPainter {
  SplashPlatePainter({required this.gradient, required this.superellipse});

  final double gradient;
  final bool superellipse;

  static Path shape(Size size, {required bool superellipse}) {
    if (!superellipse) {
      return Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width * 0.225)));
    }
    const n = 2.7;
    final a = size.width / 2, b = size.height / 2;
    final path = Path();
    const steps = 96;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps * 2 * math.pi;
      final c = math.cos(t), s = math.sin(t);
      final x = a + a * c.sign * math.pow(c.abs(), 2 / n);
      final y = b + b * s.sign * math.pow(s.abs(), 2 / n);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = shape(size, superellipse: superellipse);
    final rect = Offset.zero & size;
    canvas.drawPath(path, Paint()..color = JwFill.purple.mid);
    if (gradient <= 0) return;
    final g = gradient.clamp(0.0, 1.0);
    canvas
      ..drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [JwFill.purple.top.withValues(alpha: g), JwFill.purple.mid.withValues(alpha: g), JwFill.purple.edge.withValues(alpha: g)],
            stops: const [0, 0.55, 1],
          ).createShader(rect),
      )
      ..drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.56, -0.72),
            radius: 0.6,
            colors: [JwFill.purple.on.withValues(alpha: 0.26 * g), JwFill.purple.on.withValues(alpha: 0)],
          ).createShader(rect),
      );
  }

  @override
  bool shouldRepaint(SplashPlatePainter old) => old.gradient != gradient || old.superellipse != superellipse;
}
