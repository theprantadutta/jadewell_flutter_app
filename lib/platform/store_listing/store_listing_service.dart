/// Where Play says this install stands.
enum UpdateState {
  /// Not checked yet, or the check failed. Debug and sideloaded builds always
  /// land here: Play only answers for installs it made.
  unknown,

  /// This is the latest version.
  upToDate,

  /// A newer version is on Play.
  available,

  /// A flexible update is downloading in the background.
  downloading,

  /// A flexible update is downloaded; restarting installs it.
  downloaded,
}

class UpdateCheck {
  const UpdateCheck({
    required this.state,
    this.priority = 0,
    this.immediateAllowed = false,
    this.flexibleAllowed = false,
  });

  static const unknown = UpdateCheck(state: UpdateState.unknown);

  final UpdateState state;

  /// The in-app update priority set on the release (0–5, Play Developer API).
  final int priority;
  final bool immediateAllowed;
  final bool flexibleAllowed;
}

/// Outcome of asking Play to start an update.
enum UpdateFlowResult { accepted, declined, failed }

/// Play in-app updates and store reviews.
///
/// In-app updates exist on Android only, and only for Play installs. Reviews
/// use Play's in-app review sheet (Android) or SKStoreReviewController (iOS);
/// both platforms rate-limit the sheet, so a request may show nothing.
abstract interface class StoreListingService {
  /// Android: in-app updates are possible on this platform.
  bool get supportsUpdates;

  Future<UpdateCheck> checkForUpdate();

  /// Full-screen Play update; the app restarts into the new version.
  Future<UpdateFlowResult> startImmediateUpdate();

  /// Play asks for consent, then downloads in the background. Completes when
  /// the download finishes, or when the player declines.
  Future<UpdateFlowResult> startFlexibleUpdate();

  /// Installs a downloaded flexible update (the app restarts).
  Future<void> completeFlexibleUpdate();

  /// The in-app review sheet. Never call this from a button: the platform
  /// may silently show nothing (quota). Buttons use [openStoreListing].
  Future<void> requestReview();

  /// Whether there is a store page to open (Android; iOS once listed).
  bool get canOpenStoreListing;

  /// Opens the store page, where the player can rate and review. False when
  /// nothing could be opened.
  Future<bool> openStoreListing();
}

class NoOpStoreListing implements StoreListingService {
  const NoOpStoreListing();
  @override
  bool get supportsUpdates => false;
  @override
  Future<UpdateCheck> checkForUpdate() async => UpdateCheck.unknown;
  @override
  Future<UpdateFlowResult> startImmediateUpdate() async => UpdateFlowResult.failed;
  @override
  Future<UpdateFlowResult> startFlexibleUpdate() async => UpdateFlowResult.failed;
  @override
  Future<void> completeFlexibleUpdate() async {}
  @override
  Future<void> requestReview() async {}
  @override
  bool get canOpenStoreListing => false;
  @override
  Future<bool> openStoreListing() async => false;
}
