import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../platform/analytics/analytics_service.dart';
import '../../../platform/audio/audio_service.dart';
import '../../../state/platform_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../widgets/widgets.dart';
import '../settings/screen_chrome.dart';
import 'store_controller.dart';

/// Remove ads (screen 16): hero, benefits, one-time purchase and restore.
///
/// Price comes from the store. With no billing or no product in the store
/// yet, the purchase area shows a calm "Not available yet" card instead.
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});

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

    final bottom = MediaQuery.paddingOf(context).bottom;
    return JwPage(
      title: null,
      close: true,
      onHaptic: haptic,
      trailing: store.adsRemoved
          ? null
          : JwButton.tertiary(
              label: l.storeRestore,
              onHaptic: haptic,
              onPressed: store.busy ? null : _restore,
            ),
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 16 - bottom),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Center(child: _CelebratingHero(key: ValueKey(_celebrations), celebrate: _celebrations > 0)),
                  const SizedBox(height: 36),
                  Text(
                    store.adsRemoved ? l.storePurchasedTitle : l.storeTitle,
                    textAlign: TextAlign.center,
                    style: jw.text.h1.copyWith(fontSize: 31),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    store.adsRemoved ? l.storePurchasedSubtitle : l.storeSubtitle,
                    textAlign: TextAlign.center,
                    style: jw.text.body.copyWith(fontSize: 17, color: jw.textMuted),
                  ),
                  const SizedBox(height: 44),
                  JwListGroup(
                    children: [
                      _Benefit(icon: JwIcons.check, text: l.storeBenefitNoAds),
                      _Benefit(icon: JwIcons.video, text: l.storeBenefitRewarded),
                      _Benefit(icon: JwIcons.sparkle, text: l.storeBenefitIndie),
                    ],
                  ),
                  const Spacer(),
                  const SizedBox(height: 32),
                  _PurchaseArea(
                    store: store,
                    onHaptic: haptic,
                    onBuy: () => unawaited(ref.read(storeControllerProvider.notifier).purchaseRemoveAds()),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l.storeFootnote,
                    textAlign: TextAlign.center,
                    style: jw.text.caption.copyWith(fontSize: 13.5, fontWeight: FontWeight.w400),
                  ),
                ],
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
        return Center(child: JwChip.accent(value: '✓', label: l.storePurchased));
      case StoreView.notAvailable:
        return _NoticeCard(title: l.storeNotAvailableTitle, body: l.storeNotAvailableBody);
      case StoreView.pending:
        return _NoticeCard(title: l.storePendingTitle, body: l.storePendingBody, bead: jw.warning);
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

/// A quiet sunken card: "Not available yet", "Payment pending".
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.title, required this.body, this.bead});

  final String title;
  final String body;
  final Color? bead;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: jw.clay(ClayLevel.sunken, radius: 22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  JwBead(color: bead ?? jw.jade, size: 14),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(title, style: jw.text.h2.copyWith(fontSize: 18), textAlign: TextAlign.center),
                  ),
                ],
              ),
              const SizedBox(height: 6),
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
  const _Benefit({required this.icon, required this.text});

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 62),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            JwIconWell(icon: icon),
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
    final deco = jw.clay(ClayLevel.primary);
    final fg = jw.onAccent;
    final textStyle = jw.text.button.copyWith(color: fg, fontSize: 17);
    final spinner = SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
    );
    final price = this.price;
    return ClayPressable(
      decoration: deco,
      pressedDecoration: deco.copyWith(level: ClayLevel.pressed),
      onTap: busy ? null : onPressed,
      onHaptic: onHaptic,
      semanticLabel: busy ? (busyLabel ?? label) : (price == null ? label : '$label, $price'),
      height: 60,
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
                    Text(price, style: jw.text.numM.copyWith(color: fg, fontSize: 19, fontWeight: FontWeight.w700)),
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

/// The app-icon-like hero: an accent clay square holding two tilted tiles,
/// each with a jade bead.
class _RemoveAdsHero extends StatelessWidget {
  const _RemoveAdsHero();

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final fill = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color.lerp(jw.accent, const Color(0xFFFFFFFF), 0.3)!, jw.accent, Color.lerp(jw.accent, const Color(0xFF000000), 0.12)!],
      stops: const [0, 0.55, 1],
    );
    Widget tile(double angle, Offset offset) => Transform.translate(
          offset: offset,
          child: Transform.rotate(
            angle: angle,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: jw.tileEdge,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: jw.shadow, blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: jw.tileFace, borderRadius: BorderRadius.circular(11)),
                  child: SizedBox(
                    width: 42,
                    height: 54,
                    child: Center(child: JwBead(color: jw.jade, size: 20)),
                  ),
                ),
              ),
            ),
          ),
        );
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: jw.clay(ClayLevel.raised, radius: 34, gradient: fill),
        child: SizedBox.square(
          dimension: 132,
          child: Stack(
            alignment: Alignment.center,
            children: [
              tile(-0.12, const Offset(-18, 2)),
              tile(0.10, const Offset(18, -1)),
            ],
          ),
        ),
      ),
    );
  }
}
