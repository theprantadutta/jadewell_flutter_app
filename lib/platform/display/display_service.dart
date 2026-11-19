/// What the screen can do and what it is doing now.
class DisplayRates {
  const DisplayRates({required this.current, required this.max, this.supported = const [], this.lowPower = false});

  /// The rate the display is running at right now, in Hz (0 = unknown).
  final double current;

  /// The fastest rate at the current resolution, in Hz (0 = unknown).
  final double max;

  /// Every rate at the current resolution, ascending.
  final List<double> supported;

  /// Battery saver is on; the OS may hold the display at its base rate.
  final bool lowPower;

  /// Faster than 60 Hz (the 61 Hz margin absorbs 60.0001-style reports).
  bool get supportsHighRefresh => max > 61;
}

/// The display's refresh rate (Settings → High refresh rate).
///
/// Flutter never asks Android for more than the default, so a 90/120 Hz phone
/// runs Jadewell at 60 Hz until [setHighRefreshRate] asks for the display's
/// fastest rate. That is a request, not a guarantee: battery saver, heat and
/// the OEM still decide. Jadewell is built and profiled for 60 Hz
/// (docs/PERFORMANCE.md); faster is the player's choice.
abstract interface class DisplayService {
  /// Whether this platform lets the app change the rate (Android 6+ only;
  /// iOS keeps its own cadence).
  bool get canControl;

  /// Reads the display now; null when it can't be read.
  Future<DisplayRates?> read();

  /// Asks for the fastest rate (true) or hands the choice back to the OS
  /// (false). The request survives backgrounding: it is re-applied natively
  /// when the surface comes back.
  Future<void> setHighRefreshRate(bool enabled);
}

class NoOpDisplay implements DisplayService {
  const NoOpDisplay();
  @override
  bool get canControl => false;
  @override
  Future<DisplayRates?> read() async => null;
  @override
  Future<void> setHighRefreshRate(bool enabled) async {}
}
