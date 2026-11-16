import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../state/platform_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../widgets/widgets.dart';
import '../settings/screen_chrome.dart';
import '../settings/settings_screen.dart' show kRemoveAdsPrice;
import 'store_controller.dart';

/// Remove ads (screen 16): hero, benefits, one-time purchase and restore.
class StoreScreen extends ConsumerWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final jw = context.jw;
    final store = ref.watch(storeControllerProvider);
    final haptic = ref.watch(hapticsProvider).selection;

    Future<void> run(Future<StoreOutcome> Function(StoreController c) action) async {
      final outcome = await action(ref.read(storeControllerProvider.notifier));
      if (!context.mounted) return;
      final message = switch (outcome) {
        StoreOutcome.comingSoon => l.storeComingSoon,
        StoreOutcome.purchased => l.storeThanks,
        StoreOutcome.restored => l.storeRestored,
        StoreOutcome.nothingToRestore => l.storeNothingToRestore,
        StoreOutcome.failed => l.storeFailed,
        StoreOutcome.cancelled => null,
      };
      if (message != null) showJwToast(context, message);
    }

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
              onPressed: store.busy ? null : () => run((c) => c.restore()),
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
                  const Center(child: _RemoveAdsHero()),
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
                  if (store.adsRemoved)
                    Center(child: JwChip.accent(value: '✓', label: l.storePurchased))
                  else
                    _PriceButton(
                      label: l.storeBuy,
                      price: kRemoveAdsPrice,
                      busy: store.busy,
                      onHaptic: haptic,
                      onPressed: () => run((c) => c.purchaseRemoveAds()),
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

/// "Remove ads · $1.99" with the price in mono.
class _PriceButton extends StatelessWidget {
  const _PriceButton({
    required this.label,
    required this.price,
    required this.onPressed,
    this.busy = false,
    this.onHaptic,
  });

  final String label;
  final String price;
  final VoidCallback onPressed;
  final bool busy;
  final VoidCallback? onHaptic;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final deco = jw.clay(ClayLevel.primary);
    final fg = jw.onAccent;
    return ClayPressable(
      decoration: deco,
      pressedDecoration: deco.copyWith(level: ClayLevel.pressed),
      onTap: busy ? null : onPressed,
      onHaptic: onHaptic,
      semanticLabel: '$label, $price',
      height: 60,
      width: double.infinity,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(label, style: jw.text.button.copyWith(color: fg, fontSize: 17)),
            Text(' · ', style: jw.text.button.copyWith(color: fg, fontSize: 17)),
            Text(price, style: jw.text.numM.copyWith(color: fg, fontSize: 19, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
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
