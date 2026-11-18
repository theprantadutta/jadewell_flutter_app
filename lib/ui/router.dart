import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/account/account_screen.dart';
import 'screens/cleared/cleared_screen.dart';
import 'screens/daily/daily_screen.dart';
import 'screens/dev_gallery/dev_gallery_screen.dart';
import 'screens/friends/friends_screen.dart';
import 'screens/game/game_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/leaderboard/leaderboard_screen.dart';
import 'screens/legal/legal_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/stats/stats_screen.dart';
import 'screens/store/store_screen.dart';

/// Route paths. Navigate with `context.go(AppRoutes.home)` /
/// `context.push(AppRoutes.game('turtle'))`.
abstract final class AppRoutes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const home = '/home';
  static String game(String layoutId) => '/game/$layoutId';
  static const dailyPlay = '/daily/play';
  static String cleared(String layoutId) => '/cleared/$layoutId';
  static const daily = '/daily';
  static const leaderboard = '/leaderboard';
  static const stats = '/stats';
  static const settings = '/settings';
  static const store = '/store';
  static const account = '/account';
  static const friends = '/friends';
  static String legal(LegalDoc doc) => '/legal/${doc.name}';
  static const devGallery = '/dev/gallery';
}

final rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createAppRouter({List<NavigatorObserver> observers = const []}) => GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: AppRoutes.splash,
      observers: observers,
      routes: [
        GoRoute(path: AppRoutes.splash, name: 'splash', pageBuilder: (_, s) => _fade(s, const SplashScreen())),
        GoRoute(
          path: AppRoutes.onboarding,
          name: 'onboarding',
          pageBuilder: (_, s) => _fade(s, const OnboardingScreen()),
        ),
        GoRoute(path: AppRoutes.home, name: 'home', pageBuilder: (_, s) => _fade(s, const HomeScreen())),
        GoRoute(
          path: '/game/:layoutId',
          name: 'game',
          builder: (_, s) => GameScreen(layoutId: s.pathParameters['layoutId']!),
        ),
        GoRoute(
          path: AppRoutes.dailyPlay,
          name: 'dailyPlay',
          builder: (_, _) => const GameScreen(layoutId: '', daily: true),
        ),
        GoRoute(
          path: '/cleared/:layoutId',
          name: 'cleared',
          builder: (_, s) => ClearedScreen(layoutId: s.pathParameters['layoutId']!),
        ),
        GoRoute(path: AppRoutes.daily, name: 'daily', builder: (_, _) => const DailyScreen()),
        GoRoute(path: AppRoutes.leaderboard, name: 'leaderboard', builder: (_, _) => const LeaderboardScreen()),
        GoRoute(path: AppRoutes.stats, name: 'stats', builder: (_, _) => const StatsScreen()),
        GoRoute(path: AppRoutes.settings, name: 'settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(path: AppRoutes.store, name: 'store', builder: (_, _) => const StoreScreen()),
        GoRoute(path: AppRoutes.account, name: 'account', builder: (_, _) => const AccountScreen()),
        GoRoute(path: AppRoutes.friends, name: 'friends', builder: (_, _) => const FriendsScreen()),
        GoRoute(
          path: '/legal/:doc',
          name: 'legal',
          builder: (_, s) => LegalScreen(doc: LegalDoc.fromName(s.pathParameters['doc'])),
        ),
        if (kDebugMode)
          GoRoute(path: AppRoutes.devGallery, name: 'devGallery', builder: (_, _) => const DevGalleryScreen()),
      ],
    );

/// 200 ms cross-fade (SPLASH.md handoff: splash → onboarding/home).
CustomTransitionPage<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      name: state.name,
      child: child,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    );
