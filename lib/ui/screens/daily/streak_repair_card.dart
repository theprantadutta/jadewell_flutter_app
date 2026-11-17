import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/repositories/repositories.dart';
import '../../../platform/ads/ad_service.dart';
import '../../../platform/analytics/analytics_service.dart';
import '../../../state/data_providers.dart';
import '../../../state/platform_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../widgets/widgets.dart';

/// Non-null while yesterday's missed daily can be bridged with a rewarded ad.
final streakRepairOfferProvider = StreamProvider.autoDispose<StreakRepairOffer?>((ref) async* {
  final repo = await ref.watch(dailyRepositoryProvider.future);
  yield* repo.watchRepairOffer();
});

/// "Keep your N-day streak? Watch a short video" (shown only with an offer).
class StreakRepairCard extends ConsumerStatefulWidget {
  const StreakRepairCard({super.key});

  @override
  ConsumerState<StreakRepairCard> createState() => _StreakRepairCardState();
}

class _StreakRepairCardState extends ConsumerState<StreakRepairCard> {
  bool _busy = false;

  Future<void> _watch(StreakRepairOffer offer) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final warning = context.jw.warning;
    var repaired = false;
    try {
      final rewarded = await ref.read(adServiceProvider).showRewarded(RewardedPlacement.streakRepair);
      if (rewarded) {
        final repo = await ref.read(dailyRepositoryProvider.future);
        repaired = await repo.repairStreak();
        if (repaired) {
          unawaited(
            ref.read(analyticsProvider).log(AnalyticsEvents.streakRepaired, {'restored_streak': offer.restoredStreak}),
          );
          ref.read(hapticsProvider).success();
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: JwToast(
                message: repaired ? l.dailyRepairDone(offer.restoredStreak) : l.dailyRepairFailed,
                beadColor: repaired ? null : warning,
              ),
            ),
          ),
          backgroundColor: JwBase.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 2400),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final offer = ref.watch(streakRepairOfferProvider).value;
    if (offer == null) return const SizedBox.shrink();
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: DecoratedBox(
        decoration: jw.clay(ClayLevel.raised, radius: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              JwIconWell(icon: JwIcons.flame, color: jw.accent, size: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.dailyRepairTitle(offer.restoredStreak),
                      style: jw.text.body.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      l.dailyRepairBody,
                      style: jw.text.caption.copyWith(fontSize: 13.5, fontWeight: FontWeight.w400),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              JwButton.primary(
                key: const ValueKey('streak-repair-watch'),
                label: l.dailyRepairAction,
                icon: JwIcons.video,
                small: true,
                onHaptic: ref.read(hapticsProvider).selection,
                onPressed: _busy ? null : () => _watch(offer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
