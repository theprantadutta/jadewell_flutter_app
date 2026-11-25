import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/ads/ad_service.dart';
import '../platform/analytics/analytics_service.dart';
import '../platform/audio/audio_service.dart';
import '../platform/display/display_service.dart';
import '../platform/haptics/haptic_service.dart';
import '../platform/notifications/notification_service.dart';
import '../platform/store_listing/store_listing_service.dart';

// Defaults are no-op/fake so screens and tests run anywhere; main.dart
// overrides them with the real implementations (`*_impl.dart`).
final analyticsProvider = Provider<AnalyticsService>((ref) => const NoOpAnalytics());
final audioProvider = Provider<AudioService>((ref) => const NoOpAudio());
final hapticsProvider = Provider<HapticService>((ref) => const NoOpHaptics());
final adServiceProvider = Provider<AdService>((ref) => FakeAdService());
final displayServiceProvider = Provider<DisplayService>((ref) => const NoOpDisplay());
final storeListingProvider = Provider<StoreListingService>((ref) => const NoOpStoreListing());
final notificationServiceProvider = Provider<NotificationService>((ref) => const NoOpNotifications());
