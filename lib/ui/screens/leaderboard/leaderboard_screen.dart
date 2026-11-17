import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/api/api_result.dart';
import '../../../data/repositories/social_repository.dart';
import '../../../state/data_providers.dart';
import '../../../state/platform_providers.dart';
import '../../../state/social_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../router.dart';
import '../../theme/jw_theme.dart';
import '../../widgets/empty_state/jw_empty_state.dart';
import '../../widgets/skeleton/jw_skeleton.dart';
import '../../widgets/widgets.dart';
import '../settings/screen_chrome.dart';
import 'leaderboard_widgets.dart';

/// Leaderboard (screens 13 / 17b): Today · This week · Friends. The server
/// ranks (stars desc, then time asc); this screen only displays.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key, this.initialTab = LeaderboardKind.daily});

  final LeaderboardKind initialTab;

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  late LeaderboardKind _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    // The tab providers are kept alive; refresh on every visit so a result
    // you just posted (or anyone else's) shows up. The cached page stays
    // visible meanwhile.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(leaderboardProvider(_tab));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final haptic = ref.watch(hapticsProvider).selection;
    final view = ref.watch(leaderboardProvider(_tab));
    final daily = ref.watch(dailyProvider).value;
    final catalogue = ref.watch(catalogueProvider).value;
    final layoutId = daily?.layoutId ?? view.value?.page?.layoutId;
    final layoutName = layoutId == null ? null : catalogue?.layouts[layoutId]?.name;

    return JwPage(
      title: l.leaderboardTitle,
      // The weekly tab sums the week's dailies, so it isn't "Daily · <layout>".
      subtitle: _tab == LeaderboardKind.weekly
          ? l.leaderboardWeeklySubtitle
          : (layoutName == null ? l.leaderboardDaily : l.leaderboardDailyLayout(layoutName)),
      onHaptic: haptic,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: JwSegmented<LeaderboardKind>(
              segments: {
                LeaderboardKind.daily: l.leaderboardToday,
                LeaderboardKind.weekly: l.leaderboardThisWeek,
                LeaderboardKind.friends: l.leaderboardFriends,
              },
              selected: _tab,
              onHaptic: haptic,
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: JwReduceMotion.of(context) ? const Duration(milliseconds: 150) : const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey(_tab),
                child: _TabBody(
                  kind: _tab,
                  view: view,
                  layoutName: layoutName,
                  onHaptic: haptic,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBody extends ConsumerWidget {
  const _TabBody({required this.kind, required this.view, required this.layoutName, this.onHaptic});

  final LeaderboardKind kind;
  final AsyncValue<LeaderboardView> view;
  final String? layoutName;
  final VoidCallback? onHaptic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final v = view.value;
    final loading = v == null;
    Future<void> refresh() => ref.read(leaderboardProvider(kind).notifier).refresh();

    return JwSkeletonSwitcher(
      loading: loading,
      skeleton: const JwSkeletonScope(child: LeaderboardSkeleton()),
      builder: (context) {
        final page = v!.page;
        final others = page?.entries.where((e) => !e.isMe).length ?? 0;

        // Friends tab with nobody to compare against.
        if (kind == LeaderboardKind.friends && (page != null || v.isUnavailable) && others == 0) {
          return _centered(
            JwEmptyState(
              illustration: const EmptyPodium(),
              title: l.leaderboardNoFriendsTitle,
              body: l.leaderboardNoFriendsBody,
              actionLabel: l.leaderboardAddFriends,
              actionIcon: JwIcons.user,
              onHaptic: onHaptic,
              onAction: () => context.push(AppRoutes.friends),
            ),
          );
        }

        if (page == null || page.isEmpty) {
          final offline = !v.isUnavailable &&
              (v.failure == ApiFailure.offlineOrTransport ||
                  v.failure == ApiFailure.timeout ||
                  v.failure == ApiFailure.serverUnavailable);
          if (offline) {
            return _centered(
              JwEmptyState(
                icon: JwIcons.restore,
                title: l.commonOfflineTitle,
                body: l.leaderboardOfflineBody,
                actionLabel: l.commonRetry,
                actionIcon: JwIcons.replay,
                onHaptic: onHaptic,
                onAction: () => unawaited(refresh()),
              ),
            );
          }
          final weekly = kind == LeaderboardKind.weekly;
          return _centered(
            JwEmptyState(
              illustration: const EmptyPodium(),
              title: weekly ? l.leaderboardEmptyWeekTitle : l.leaderboardEmptyTitle,
              body: layoutName == null ? l.leaderboardEmptyBodyGeneric : l.leaderboardEmptyBody(layoutName!),
              actionLabel: l.leaderboardPlayToday,
              actionIcon: JwIcons.play,
              onHaptic: onHaptic,
              onAction: () => context.push(AppRoutes.dailyPlay),
            ),
          );
        }

        final top = page.entries.take(3).toList();
        final rest = page.entries.skip(3).toList();
        final me = page.me;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: RefreshIndicator(
                color: context.jw.accent,
                backgroundColor: context.jw.surfaceRaised,
                onRefresh: refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, 18, 16, me == null ? 24 + MediaQuery.paddingOf(context).bottom : 16),
                  children: [
                    JwFadeUp(child: Podium(entries: top)),
                    if (rest.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      JwFadeUp(
                        index: 1,
                        child: JwListGroup(children: [for (final e in rest) LeaderboardRow(entry: e)]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (me != null)
              Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.paddingOf(context).bottom),
                child: YouRow(me: me, caption: _youCaption(l, me, page)),
              ),
          ],
        );
      },
    );
  }

  String _youCaption(AppLocalizations l, LeaderboardMe me, LeaderboardPage page) {
    final pct = me.topPercent;
    return switch (kind) {
      LeaderboardKind.friends => l.leaderboardYouFriends(me.entry.rank, page.entries.length),
      LeaderboardKind.weekly => pct == null ? l.leaderboardYouRank(me.entry.rank) : l.leaderboardYouTopWeek(pct),
      LeaderboardKind.daily => pct == null ? l.leaderboardYouRank(me.entry.rank) : l.leaderboardYouTopToday(pct),
    };
  }

  static Widget _centered(Widget child) => LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 48),
            // Upper half, as in 17b.
            child: Align(alignment: const Alignment(0, -0.5), child: child),
          ),
        ),
      );
}
