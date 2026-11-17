import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/catalogue.dart';
import '../../../platform/ads/ad_service.dart';
import '../../../platform/analytics/analytics_service.dart';
import '../../../state/data_providers.dart';
import '../../../state/platform_providers.dart';
import '../../components/components.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/widgets.dart';
import 'layout_labels.dart';

/// "Unlock [LayoutInfo.name] now? Watch a short video" for a locked layout. On a
/// completed rewarded ad the layout is unlocked and `layout_unlock_ad` logged.
Future<void> showUnlockLayoutSheet(BuildContext context, WidgetRef ref, LayoutInfo info) async {
  final l = AppLocalizations.of(context);
  final watch = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: JwBase.transparent,
    elevation: 0,
    useSafeArea: true,
    isScrollControlled: true,
    barrierColor: context.jw.scrim,
    builder: (context) => _UnlockSheet(info: info),
  );
  if (watch != true) return;
  final rewarded = await ref.read(adServiceProvider).showRewarded(RewardedPlacement.unlockLayout);
  if (rewarded) {
    await ref.read(progressRepositoryProvider).unlockWithAd(info.id);
    unawaited(ref.read(analyticsProvider).log(AnalyticsEvents.layoutUnlockAd, {'layout_id': info.id}));
    ref.read(hapticsProvider).success();
  }
  if (!context.mounted) return;
  final message = rewarded ? l.unlockSheetDone(info.name) : l.unlockSheetFailed(info.name);
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: JwToast(message: message, beadColor: rewarded ? null : context.jw.warning),
          ),
        ),
        backgroundColor: JwBase.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2400),
      ),
    );
}

/// The plate fill of [info] (its index among the chapter layouts).
JwFill _plateFor(WidgetRef ref, LayoutInfo info) {
  final layouts = ref.read(catalogueProvider).value?.chapterLayouts.toList() ?? const <LayoutInfo>[];
  final i = layouts.indexWhere((l) => l.id == info.id);
  return JwFills.plate(i < 0 ? 0 : i);
}

class _UnlockSheet extends ConsumerWidget {
  const _UnlockSheet({required this.info});

  final LayoutInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final haptics = ref.read(hapticsProvider);
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: JwSheet(
          semanticLabel: l.unlockSheetTitle(info.name),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              // The layout's own coloured plate, with a lock badge on its
              // corner: the same plate the card shows once it's unlocked.
              Center(
                child: SizedBox(
                  width: 156,
                  height: 112,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        top: 4,
                        right: 12,
                        bottom: 8,
                        child: DecoratedBox(
                          decoration: jw.fill(_plateFor(ref, info), radius: 20, edge: 4, glow: false),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: JwSilhouette(tiles: LayoutLabels.tiles(info)),
                          ),
                        ),
                      ),
                      const Positioned(
                        right: 0,
                        top: -6,
                        child: IconBadge(icon: JwIcons.lock, fill: JwFill.purple, size: 40),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(l.unlockSheetTitle(info.name), textAlign: TextAlign.center, style: jw.text.h3.copyWith(fontSize: 21)),
              const SizedBox(height: 6),
              Text(
                '${l.unlockSheetBody} · ${LayoutLabels.meta(l, info)}',
                textAlign: TextAlign.center,
                style: jw.text.body.copyWith(color: jw.textMuted),
              ),
              const SizedBox(height: 22),
              JwButton.primary(
                label: l.unlockSheetWatch,
                icon: JwIcons.video,
                expand: true,
                onHaptic: haptics.selection,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 6),
              JwButton.tertiary(
                label: l.unlockSheetNotNow,
                expand: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
