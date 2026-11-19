import 'package:flutter/foundation.dart';
import 'package:refresh_rate/refresh_rate.dart';

import 'display_service.dart';

/// [DisplayService] on `package:refresh_rate`.
///
/// Android: [RefreshRate.enable] votes for the display's highest rate on the
/// Flutter surface (`Surface.setFrameRate`, API 30+; a window hint below
/// that), and [RefreshRate.disable] withdraws the vote. Other platforms only
/// read.
class RefreshRateDisplayService implements DisplayService {
  @override
  bool get canControl => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<DisplayRates?> read() async {
    try {
      final i = await RefreshRate.refresh();
      return DisplayRates(
        current: i.currentRate,
        max: i.maxRate,
        supported: [...i.supportedRates]..sort(),
        lowPower: i.isLowPowerMode ?? false,
      );
    } catch (e) {
      debugPrint('display: read failed: $e');
      return null;
    }
  }

  @override
  Future<void> setHighRefreshRate(bool enabled) async {
    if (!canControl) return;
    try {
      final r = enabled ? await RefreshRate.enable() : await RefreshRate.disable();
      debugPrint('display: high refresh ${enabled ? 'on' : 'off'}: ${r.status.name} via ${r.backend}${r.message == null ? '' : ' (${r.message})'}');
    } catch (e) {
      // An unsupported device is not an error worth surfacing.
      debugPrint('display: request failed: $e');
    }
  }
}
