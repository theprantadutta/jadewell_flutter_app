import 'package:flutter/foundation.dart';

import 'font_licenses_text.dart';

/// Bundled font families (declared in pubspec.yaml, never fetched at runtime).
abstract final class JwFonts {
  /// All UI text. Weights 400, 500, 600, 700.
  static const ui = 'Outfit';

  /// Every numeral that changes. Weights 500, 600, 700. Always tabular.
  static const mono = 'JetBrainsMono';

  /// Tile glyphs only, subset to the 24 distinct characters on the faces.
  /// Weights 700 and 900.
  static const glyph = 'NotoSansSC';

  /// Asset paths, used by tests to load the real fonts.
  static const assets = <String, List<String>>{
    ui: [
      'assets/fonts/Outfit-Regular.ttf',
      'assets/fonts/Outfit-Medium.ttf',
      'assets/fonts/Outfit-SemiBold.ttf',
      'assets/fonts/Outfit-Bold.ttf',
    ],
    mono: [
      'assets/fonts/JetBrainsMono-Medium.ttf',
      'assets/fonts/JetBrainsMono-SemiBold.ttf',
      'assets/fonts/JetBrainsMono-Bold.ttf',
    ],
    glyph: [
      'assets/fonts/NotoSansSC-Bold.ttf',
      'assets/fonts/NotoSansSC-Black.ttf',
    ],
  };
}

bool _licensesRegistered = false;

/// Adds the SIL OFL 1.1 licences of the bundled fonts to the [LicenseRegistry]
/// (shown by the licence page). Safe to call more than once.
void registerFontLicenses() {
  if (_licensesRegistered) return;
  _licensesRegistered = true;
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(['Outfit'], outfitOflText);
    yield const LicenseEntryWithLineBreaks(['JetBrains Mono'], jetBrainsMonoOflText);
    yield const LicenseEntryWithLineBreaks(['Noto Sans SC'], notoSansScOflText);
  });
}
