/// Semantic haptics from MOTION_SPEC.md (light/medium impact, selection
/// error = two light ticks 60 ms apart). Respects the Haptics setting.
abstract interface class HapticService {
  void setEnabled(bool enabled);
  void light();
  void medium();
  void heavy();
  void selection();

  /// Blocked-tile tap.
  void selectionError();
  void success();
}

class NoOpHaptics implements HapticService {
  const NoOpHaptics();
  @override
  void setEnabled(bool enabled) {}
  @override
  void light() {}
  @override
  void medium() {}
  @override
  void heavy() {}
  @override
  void selection() {}
  @override
  void selectionError() {}
  @override
  void success() {}
}
