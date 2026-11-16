import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'haptic_service.dart';

/// [HapticService] on [HapticFeedback]. On iOS these map to
/// `UIImpactFeedbackGenerator` (light/medium/heavy), `UISelectionFeedbackGenerator`
/// and `UINotificationFeedbackGenerator`; on Android to the matching
/// `HapticFeedbackConstants`. MOTION_SPEC.md picks the method per interaction.
///
/// Every call is fire-and-forget and swallows platform errors: a missing
/// vibrator must never surface in gameplay.
class HapticServiceImpl implements HapticService {
  HapticServiceImpl({this.selectionErrorGap = const Duration(milliseconds: 60)});

  /// Gap between the two light ticks of [selectionError] (MOTION_SPEC: 60 ms).
  final Duration selectionErrorGap;

  bool _enabled = true;
  Timer? _secondTick;

  @visibleForTesting
  bool get enabled => _enabled;

  @override
  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) {
      _secondTick?.cancel();
      _secondTick = null;
    }
  }

  @override
  void light() => _fire(HapticFeedback.lightImpact);

  @override
  void medium() => _fire(HapticFeedback.mediumImpact);

  @override
  void heavy() => _fire(HapticFeedback.heavyImpact);

  @override
  void selection() => _fire(HapticFeedback.selectionClick);

  /// Blocked-tile tap: two light ticks [selectionErrorGap] apart.
  @override
  void selectionError() {
    if (!_enabled) return;
    _fire(HapticFeedback.lightImpact);
    _secondTick?.cancel();
    _secondTick = Timer(selectionErrorGap, () {
      _secondTick = null;
      _fire(HapticFeedback.lightImpact);
    });
  }

  /// Board cleared (medal landing). iOS has a real success notification;
  /// Android's CONFIRM equivalent only exists from API 30, so Android uses a
  /// medium impact that every device supports.
  @override
  void success() => _fire(
        defaultTargetPlatform == TargetPlatform.iOS ? HapticFeedback.successNotification : HapticFeedback.mediumImpact,
      );

  void _fire(Future<void> Function() effect) {
    if (!_enabled) return;
    effect().catchError((Object e) {
      debugPrint('haptics: $e');
    });
  }
}
