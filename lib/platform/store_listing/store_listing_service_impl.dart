import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:in_app_update/in_app_update.dart' as iau;
import 'package:url_launcher/url_launcher.dart';

import 'store_listing_service.dart';

/// [StoreListingService] on `package:in_app_update` (Play in-app updates)
/// and `package:in_app_review`.
class PlayStoreListingService implements StoreListingService {
  PlayStoreListingService({required this.packageName, this.appStoreId});

  /// Android application id, for the web fallback of the Play listing.
  final String packageName;

  /// iOS App Store id; null until the iOS app is on the App Store.
  final String? appStoreId;

  final _review = InAppReview.instance;

  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  bool get supportsUpdates => _android;

  @override
  Future<UpdateCheck> checkForUpdate() async {
    if (!_android) return UpdateCheck.unknown;
    try {
      final info = await iau.InAppUpdate.checkForUpdate();
      final state = switch ((info.installStatus, info.updateAvailability)) {
        (iau.InstallStatus.downloaded, _) => UpdateState.downloaded,
        (iau.InstallStatus.pending || iau.InstallStatus.downloading, _) => UpdateState.downloading,
        (_, iau.UpdateAvailability.updateAvailable) => UpdateState.available,
        // An immediate update the player left part-way: Play resumes it.
        (_, iau.UpdateAvailability.developerTriggeredUpdateInProgress) => UpdateState.available,
        (_, iau.UpdateAvailability.updateNotAvailable) => UpdateState.upToDate,
        _ => UpdateState.unknown,
      };
      return UpdateCheck(
        state: state,
        priority: info.updatePriority,
        immediateAllowed: info.immediateUpdateAllowed,
        flexibleAllowed: info.flexibleUpdateAllowed,
      );
    } catch (e) {
      // Not a Play install (debug, sideload), no Play Store, or offline.
      debugPrint('updates: check failed: $e');
      return UpdateCheck.unknown;
    }
  }

  @override
  Future<UpdateFlowResult> startImmediateUpdate() => _flow(iau.InAppUpdate.performImmediateUpdate);

  @override
  Future<UpdateFlowResult> startFlexibleUpdate() => _flow(iau.InAppUpdate.startFlexibleUpdate);

  Future<UpdateFlowResult> _flow(Future<iau.AppUpdateResult> Function() start) async {
    if (!_android) return UpdateFlowResult.failed;
    try {
      return switch (await start()) {
        iau.AppUpdateResult.success => UpdateFlowResult.accepted,
        iau.AppUpdateResult.userDeniedUpdate => UpdateFlowResult.declined,
        iau.AppUpdateResult.inAppUpdateFailed => UpdateFlowResult.failed,
      };
    } catch (e) {
      debugPrint('updates: flow failed: $e');
      return UpdateFlowResult.failed;
    }
  }

  @override
  Future<void> completeFlexibleUpdate() async {
    if (!_android) return;
    try {
      await iau.InAppUpdate.completeFlexibleUpdate();
    } catch (e) {
      debugPrint('updates: install failed: $e');
    }
  }

  @override
  Future<void> requestReview() async {
    try {
      if (await _review.isAvailable()) await _review.requestReview();
    } catch (e) {
      debugPrint('review: request failed: $e');
    }
  }

  @override
  bool get canOpenStoreListing => _android || appStoreId != null;

  @override
  Future<bool> openStoreListing() async {
    if (canOpenStoreListing) {
      try {
        await _review.openStoreListing(appStoreId: appStoreId);
        return true;
      } catch (e) {
        debugPrint('review: store listing failed: $e');
      }
    }
    if (!_android) return false;
    // No Play Store app: the web listing.
    try {
      return await launchUrl(
        Uri.https('play.google.com', '/store/apps/details', {'id': packageName}),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
