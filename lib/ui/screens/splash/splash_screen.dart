import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/settings.dart';
import '../../../platform/analytics/analytics_service.dart';
import '../../../state/data_providers.dart';
import '../../../state/platform_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../router.dart';
import '../../theme/jw_background.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/reduce_motion.dart';

/// Splash (design/splash/SPLASH.md, option A handoff): starts on exactly the
/// native splash frame (flat surface colour, the mark's two tiles at the
/// native size and position), then fades the wordmark up and the clay
/// background in, and hands over to onboarding (first run) or home.
///
/// Never waits on the network: the only wait is the local settings read,
/// capped at [settingsTimeout].
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// Wordmark fade-up (MOTION: 320 ms easeOutSoft, 12 pt).
  static const wordmark = Duration(milliseconds: 320);

  /// Hold on the final frame before handing over.
  static const hold = Duration(milliseconds: 280);
  static const settingsTimeout = Duration(seconds: 2);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  static bool _appOpenLogged = false;

  late final AnimationController _ctrl = AnimationController(vsync: this, duration: SplashScreen.wordmark);
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
  static String get _markAsset => _a12 ? 'assets/brand/mark_tiles_a12.png' : 'assets/brand/mark_tiles.png';

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
    // The native splash centres its image in the whole window (edge to edge).
    // Android 12+: a 288 dp icon box (1152 px image); elsewhere the legacy
    // 760 px image drawn at 4x (190 dp wide).
    final a12 = _a12;
    final markSize = a12 ? const Size(288, 288) : const Size(190, 151.75);
    // Bottom of the tiles relative to the screen centre.
    final tilesBottom = a12 ? (736 - 576) / 4 : (496 - 303.5) / 4;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: jw.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: ColoredBox(
        color: jw.surface,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = JwMotion.easeOutSoft.transform(_ctrl.value);
            return Stack(
              fit: StackFit.expand,
              children: [
                Opacity(opacity: t, child: const JwBackground()),
                Positioned(
                  left: (size.width - markSize.width) / 2,
                  top: (size.height - markSize.height) / 2,
                  width: markSize.width,
                  height: markSize.height,
                  child: Image.asset(
                    _markAsset,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  top: size.height / 2 + tilesBottom + 30,
                  child: Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - t)),
                      child: Semantics(
                        label: '${l.appName}, ${l.splashSubtitle}',
                        excludeSemantics: true,
                        child: Column(
                          children: [
                            Text(l.appName, style: jw.text.display.copyWith(fontSize: 44, height: 1.1)),
                            const SizedBox(height: 14),
                            Text(
                              l.splashSubtitle.toUpperCase(),
                              style: jw.text.eyebrow.copyWith(fontSize: 14, letterSpacing: 14 * 0.2, color: jw.textMuted),
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
                  bottom: MediaQuery.paddingOf(context).bottom + 48,
                  child: Opacity(
                    opacity: t,
                    child: Text(
                      l.splashFooter,
                      textAlign: TextAlign.center,
                      style: jw.text.body.copyWith(fontSize: 16, color: jw.textMuted),
                    ),
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
