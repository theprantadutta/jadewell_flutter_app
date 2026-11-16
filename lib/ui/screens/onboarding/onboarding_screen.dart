import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../platform/analytics/analytics_service.dart';
import '../../../state/data_providers.dart';
import '../../../state/platform_providers.dart';
import '../../board/tile/tile_face_spec.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../router.dart';
import '../../theme/clay.dart';
import '../../theme/jw_background.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/widgets.dart';
import 'onboarding_illustrations.dart';

/// The 42 tile faces (asset, loads in a few ms).
final onboardingFacesProvider = FutureProvider<List<TileFaceSpec>>((ref) => TileFaceSpec.load());

/// Onboarding x3: match, free rule, solvable (screens 02a-02c).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  static const pageCount = 3;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _logStep(0);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _logStep(int index) =>
      unawaited(ref.read(analyticsProvider).log(AnalyticsEvents.onboardingStep, {'step': index + 1}));

  void _onPageChanged(int index) {
    setState(() => _page = index);
    _logStep(index);
  }

  void _next() {
    if (_page >= OnboardingScreen.pageCount - 1) {
      unawaited(_finish(skipped: false));
      return;
    }
    final reduce = JwReduceMotion.of(context);
    if (reduce) {
      _pages.jumpToPage(_page + 1);
    } else {
      unawaited(_pages.nextPage(duration: JwMotion.gentle, curve: JwMotion.easeOutSoft));
    }
  }

  Future<void> _finish({required bool skipped}) async {
    if (_finishing) return;
    _finishing = true;
    unawaited(ref.read(analyticsProvider).log(AnalyticsEvents.onboardingComplete, {
      'skipped': skipped,
      'step': _page + 1,
    }));
    await ref.read(settingsProvider.notifier).change((s) => s.copyWith(onboardingDone: true));
    if (mounted) context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final haptics = ref.read(hapticsProvider);
    final faces = ref.watch(onboardingFacesProvider).value;
    final last = _page == OnboardingScreen.pageCount - 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: jw.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: JwBackground(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                l.onboardingStepOf(_page + 1, OnboardingScreen.pageCount),
                                style: jw.text.body.copyWith(fontSize: 16, color: jw.textMuted),
                              ),
                            ),
                          ),
                          JwButton.tertiary(
                            key: const ValueKey('onboarding-skip'),
                            label: l.onboardingSkip,
                            onHaptic: haptics.selection,
                            onPressed: () => _finish(skipped: true),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView(
                        controller: _pages,
                        onPageChanged: _onPageChanged,
                        children: [
                          _Page(
                            title: l.onboardingMatchTitle,
                            body: Text(l.onboardingMatchBody),
                            illustration: (s) => faces == null
                                ? const SizedBox.shrink()
                                : MatchIllustration(faces: faces, s: s, badge: l.onboardingMatchBadge),
                          ),
                          _Page(
                            title: l.onboardingFreeTitle,
                            body: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: '${l.onboardingFreeBodyLead} '),
                                  TextSpan(
                                    text: l.onboardingFreeBodyAnd,
                                    style: TextStyle(fontWeight: FontWeight.w700, color: jw.textPrimary),
                                  ),
                                  TextSpan(text: ' ${l.onboardingFreeBodyTail}'),
                                ],
                              ),
                            ),
                            illustration: (s) => faces == null
                                ? const SizedBox.shrink()
                                : FreeRuleIllustration(
                                    faces: faces,
                                    s: s,
                                    labels: FreeRuleLabels(
                                      leftClear: l.onboardingFreeLeftClear,
                                      bothBlocked: l.onboardingFreeBothBlocked,
                                      covered: l.onboardingFreeCovered,
                                      middle: l.onboardingFreeMiddle,
                                      edge: l.onboardingFreeEdge,
                                    ),
                                  ),
                          ),
                          _Page(
                            title: l.onboardingSolvableTitle,
                            body: Text(l.onboardingSolvableBody),
                            illustration: (s) => faces == null
                                ? const SizedBox.shrink()
                                : SolvableIllustration(faces: faces, s: s, badge: l.onboardingSolvableBadge),
                          ),
                        ],
                      ),
                    ),
                    _Dots(count: OnboardingScreen.pageCount, index: _page),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 26, 24, 16),
                      child: _NextButton(
                        key: const ValueKey('onboarding-next'),
                        label: last ? l.onboardingStart : l.onboardingNext,
                        onHaptic: last ? haptics.medium : haptics.light,
                        onPressed: _next,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.body, required this.illustration});

  final String title;
  final Widget body;
  final Widget Function(double scale) illustration;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return LayoutBuilder(
      builder: (context, box) {
        final cardW = box.maxWidth - 48;
        // Leave ~40% of the height for the title and body.
        final s = math.min(cardW / kIllustrationFrame.width, (box.maxHeight * 0.6 - 24) / kIllustrationFrame.height);
        final cardH = kIllustrationFrame.height * s;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: jw.clay(ClayLevel.sunken, radius: 40),
                child: SizedBox(
                  width: cardW,
                  height: cardH,
                  child: Center(
                    child: SizedBox(
                      width: kIllustrationFrame.width * s,
                      height: cardH,
                      child: ExcludeSemantics(child: illustration(s)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 34),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Semantics(header: true, child: Text(title, style: jw.text.h2.copyWith(fontSize: 27, height: 1.15))),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: DefaultTextStyle.merge(
                  style: jw.text.body.copyWith(fontSize: 16.5, height: 1.4, color: jw.textMuted),
                  child: body,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final reduce = JwReduceMotion.of(context);
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3.5),
              child: AnimatedContainer(
                duration: reduce ? Duration.zero : JwMotion.base,
                curve: JwMotion.springSoft,
                width: i == index ? 22 : 9,
                height: 9,
                decoration: i == index
                    ? BoxDecoration(color: jw.accent, borderRadius: BorderRadius.circular(5))
                    : jw.clay(ClayLevel.sunken, radius: 5),
              ),
            ),
        ],
      ),
    );
  }
}

/// Primary button with a trailing arrow ("Next →").
class _NextButton extends StatelessWidget {
  const _NextButton({super.key, required this.label, required this.onPressed, this.onHaptic});

  final String label;
  final VoidCallback onPressed;
  final VoidCallback? onHaptic;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final deco = jw.clay(ClayLevel.primary);
    return ClayPressable(
      decoration: deco,
      pressedDecoration: deco.copyWith(level: ClayLevel.pressed),
      onTap: onPressed,
      onHaptic: onHaptic,
      semanticLabel: label,
      height: 56,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: jw.text.button.copyWith(color: jw.onAccent, fontSize: 17))),
          const SizedBox(width: 12),
          JwIcon(JwIcons.arrow, size: 20, color: jw.onAccent),
        ],
      ),
    );
  }
}
