import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../platform/analytics/analytics_service.dart';
import '../../../platform/audio/audio_service.dart';
import '../../../state/platform_providers.dart';
import '../../components/components.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/clay.dart';
import '../../theme/jw_background.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/widgets.dart';
import '../settings/screen_chrome.dart';
import 'store_controller.dart';

/// Remove ads (screen 16): hero, benefits, one-time purchase and restore.
///
/// Price comes from the store. With no billing or no product in the store
/// yet, the purchase area shows a calm "Not available yet" card instead.
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});

  /// Screen 16 blobs: yellow and pink below the hero (the purple corner
  /// blob would sit behind the hero).
  static const blobs = [
    PopBlob(JwFill.yellow, Offset(0.0, 0.7), 0.11),
    PopBlob(JwFill.pink, Offset(1.0, 0.76), 0.1),
  ];

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  /// Bumped on a fresh purchase: replays the hero's celebration bounce.
  int _celebrations = 0;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(analyticsProvider).log(AnalyticsEvents.iapView));
  }

  void _celebrate() {
    ref.read(hapticsProvider).success();
    ref.read(audioProvider).play(Sfx.unlock);
    setState(() => _celebrations++);
    showJwToast(context, AppLocalizations.of(context).storeThanks, beadColor: context.jw.jade);
  }

  Future<void> _restore() async {
    final l = AppLocalizations.of(context);
    final outcome = await ref.read(storeControllerProvider.notifier).restore();
    if (!mounted) return;
    showJwToast(context, switch (outcome) {
      RestoreOutcome.restored => l.storeRestored,
      RestoreOutcome.nothingToRestore => l.storeNothingToRestore,
      RestoreOutcome.unavailable => l.storeRestoreUnavailable,
      RestoreOutcome.failed => l.storeFailed,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final jw = context.jw;
    final store = ref.watch(storeControllerProvider);
    final haptic = ref.watch(hapticsProvider).selection;

    ref.listen<StoreState>(storeControllerProvider, (prev, next) {
      const inFlight = {StoreView.purchasing, StoreView.verifying, StoreView.pending};
      if (next.view == StoreView.purchased && !next.restoredOnly && prev != null && inFlight.contains(prev.view)) {
        _celebrate();
      }
    });

    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final top = MediaQuery.viewPaddingOf(context).top;
    final on = JwFill.purple.on;
    final close = MaterialLocalizations.of(context).closeButtonTooltip;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White status icons over the purple hero.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: jw.surface,
        body: JwBackground(
          blobs: StoreScreen.blobs,
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: EdgeInsets.only(bottom: 24 + bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - 24 - bottom),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Full-bleed purple hero (§5 row 16): bottom radius 40;
                      // the top corners sit above the screen edge.
                      Transform.translate(
                        offset: const Offset(0, -40),
                        child: HeroCard(
                          radius: 40,
                          confetti: true,
                          confettiCount: 5,
                          confettiSeed: 1,
                          padding: EdgeInsets.fromLTRB(16, 40 + top + 12, 16, 30),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  _HeroIconButton(
                                    semanticLabel: close,
                                    onHaptic: haptic,
                                    onPressed: () => JwPage.defaultBack(context),
                                  ),
                                  const Spacer(),
                                  if (!store.adsRemoved)
                                    _HeroTextButton(
                                      label: l.storeRestore,
                                      onHaptic: haptic,
                                      onPressed: store.busy ? null : _restore,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Center(child: _CelebratingHero(key: ValueKey(_celebrations), celebrate: _celebrations > 0)),
                              const SizedBox(height: 22),
                              Text(
                                store.adsRemoved ? l.storePurchasedTitle : l.storeTitle,
                                textAlign: TextAlign.center,
                                style: jw.text.h1.copyWith(fontSize: 27, color: on),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                store.adsRemoved ? l.storePurchasedSubtitle : l.storeSubtitle,
                                textAlign: TextAlign.center,
                                style: jw.text.body.copyWith(fontSize: 15.5, fontWeight: FontWeight.w600, color: on),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // The hero's layout slot is 40 pt taller than what shows;
                      // pull the benefits up to sit ~26 pt below it.
                      Transform.translate(
                        offset: const Offset(0, -14),
                        child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        child: JwListGroup(
                          children: [
                            _Benefit(icon: JwIcons.check, fill: JwFill.mint, text: l.storeBenefitNoAds),
                            _Benefit(icon: JwIcons.video, fill: JwFill.sky, text: l.storeBenefitRewarded),
                            _Benefit(icon: JwIcons.sparkle, fill: JwFill.pink, text: l.storeBenefitIndie),
                          ],
                        ),
                      ),
                      ),
                      const Spacer(),
                      const SizedBox(height: 28),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _PurchaseArea(
                          store: store,
                          onHaptic: haptic,
                          onBuy: () => unawaited(ref.read(storeControllerProvider.notifier).purchaseRemoveAds()),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          l.storeFootnote,
                          textAlign: TextAlign.center,
                          style: jw.text.caption.copyWith(fontSize: 13.5, fontWeight: FontWeight.w400),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hero's close button: a translucent white circle with a white ×.
class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton({required this.semanticLabel, required this.onPressed, this.onHaptic});

  final String semanticLabel;
  final VoidCallback onPressed;
  final VoidCallback? onHaptic;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final on = JwFill.purple.on;
    final deco = jw.clay(ClayLevel.flat, color: on.withValues(alpha: 0.18));
    return ClayPressable(
      decoration: deco,
      pressedDecoration: jw.clay(ClayLevel.flat, color: on.withValues(alpha: 0.28)),
      onTap: onPressed,
      onHaptic: onHaptic,
      semanticLabel: semanticLabel,
      width: 46,
      height: 46,
      child: Center(child: JwIcon(JwIcons.x, size: 22, color: on)),
    );
  }
}

/// "Restore" in white on the hero.
class _HeroTextButton extends StatelessWidget {
  const _HeroTextButton({required this.label, required this.onPressed, this.onHaptic});

  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onHaptic;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final on = JwFill.purple.on;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onPressed == null
            ? null
            : () {
                onHaptic?.call();
                onPressed!();
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 46, minWidth: 64),
          child: Center(
            widthFactor: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                label,
                style: jw.text.button.copyWith(fontSize: 16.5, color: on.withValues(alpha: onPressed == null ? 0.6 : 1)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bottom of the screen for each [StoreView].
class _PurchaseArea extends StatelessWidget {
  const _PurchaseArea({required this.store, required this.onBuy, this.onHaptic});

  final StoreState store;
  final VoidCallback onBuy;
  final VoidCallback? onHaptic;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final jw = context.jw;
    switch (store.view) {
      case StoreView.purchased:
        return Center(child: _PurchasedChip(label: l.storePurchased));
      case StoreView.notAvailable:
        return _NoticeCard(title: l.storeNotAvailableTitle, body: l.storeNotAvailableBody, icon: JwIcons.info, fill: JwFill.sky);
      case StoreView.pending:
        return _NoticeCard(title: l.storePendingTitle, body: l.storePendingBody, icon: JwIcons.clock, fill: JwFill.yellow);
      case StoreView.loading:
        return _PriceButton(label: l.storeBuy, busyLabel: l.storeLoadingPrice, busy: true, onPressed: onBuy);
      case StoreView.purchasing:
        return _PriceButton(label: l.storeBuy, price: store.price, busy: true, onPressed: onBuy);
      case StoreView.verifying:
        return _PriceButton(label: l.storeVerifying, busy: true, onPressed: onBuy);
      case StoreView.ready:
        return _PriceButton(label: l.storeBuy, price: store.price, onHaptic: onHaptic, onPressed: onBuy);
      case StoreView.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.storeErrorBody,
              textAlign: TextAlign.center,
              style: jw.text.body.copyWith(fontSize: 15, color: jw.danger),
            ),
            const SizedBox(height: 12),
            _PriceButton(label: l.storeRetry, price: store.price, onHaptic: onHaptic, onPressed: onBuy),
          ],
        );
    }
  }
}

/// Mint "✓ Purchased" chip (mint = success).
class _PurchasedChip extends StatelessWidget {
  const _PurchasedChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    const fill = JwFill.mint;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: jw.fillFlat(fill, radius: 22, extraShadows: jw.clay(ClayLevel.chip).resolvedShadows.where((s) => !s.inset).toList()),
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                JwIcon(JwIcons.check, size: 18, color: fill.on, strokeWidth: JwIcon.badgeStroke),
                const SizedBox(width: 8),
                Text(label, style: jw.text.button.copyWith(fontSize: 16, color: fill.on)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet sunken card: "Not available yet", "Payment pending".
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.title, required this.body, required this.icon, required this.fill});

  final String title;
  final String body;
  final String icon;
  final JwFill fill;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: jw.clay(ClayLevel.sunken, radius: 24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.translate(offset: const Offset(0, -1.5), child: IconBadge(icon: icon, fill: fill, size: 30)),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(title, style: jw.text.h3.copyWith(fontSize: 18), textAlign: TextAlign.center),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: jw.text.body.copyWith(fontSize: 15, color: jw.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.fill, required this.text});

  final String icon;
  final JwFill fill;
  final String text;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            JwIconWell(icon: icon, fill: fill),
            const SizedBox(width: 16),
            Expanded(child: Text(text, style: jw.text.body.copyWith(fontSize: 16))),
          ],
        ),
      ),
    );
  }
}

/// "Remove ads · $1.99" with the price in mono; a spinner while busy.
class _PriceButton extends StatelessWidget {
  const _PriceButton({
    required this.label,
    required this.onPressed,
    this.price,
    this.busy = false,
    this.busyLabel,
    this.onHaptic,
  });

  final String label;
  final String? price;
  final VoidCallback onPressed;
  final bool busy;

  /// Semantic label while busy (e.g. "Checking the store").
  final String? busyLabel;
  final VoidCallback? onHaptic;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final fg = JwFill.purple.on;
    final textStyle = jw.text.button.copyWith(color: fg, fontSize: 17.5);
    final spinner = SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
    );
    final price = this.price;
    // 64 pt purple CTA (§5 row 16); stays fully coloured while busy.
    return FillPressable(
      fill: JwFill.purple,
      radius: 32,
      onTap: busy ? null : onPressed,
      onHaptic: onHaptic,
      semanticLabel: busy ? (busyLabel ?? label) : (price == null ? label : '$label, $price'),
      dimWhenDisabled: false,
      height: 64,
      width: double.infinity,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (busy && price == null && busyLabel != null)
                  spinner
                else ...[
                  Text(label, style: textStyle),
                  if (busy) ...[
                    const SizedBox(width: 12),
                    spinner,
                  ] else if (price != null) ...[
                    Text(' · ', style: textStyle),
                    Text(price, style: jw.text.numM.copyWith(color: fg, fontSize: 20, fontWeight: FontWeight.w700)),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The hero, with a one-shot bounce when [celebrate] (fresh purchase).
class _CelebratingHero extends StatelessWidget {
  const _CelebratingHero({super.key, this.celebrate = false});

  final bool celebrate;

  @override
  Widget build(BuildContext context) {
    if (!celebrate || JwReduceMotion.of(context)) return const _RemoveAdsHero();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(scale: 0.85 + 0.15 * t, child: child),
      child: const _RemoveAdsHero(),
    );
  }
}

/// The hero mark: the tiles-only logo (two white tiles with mint beads)
/// floating on the purple hero.
class _RemoveAdsHero extends StatelessWidget {
  const _RemoveAdsHero();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(
      'assets/brand/mark_tiles_only_512.png',
      width: 150,
      height: 150,
      filterQuality: FilterQuality.medium,
      cacheWidth: 450,
    ),
  );
}
