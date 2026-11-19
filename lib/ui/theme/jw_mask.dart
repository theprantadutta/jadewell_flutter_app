import 'package:flutter/painting.dart';

/// Alpha masks (only the alpha channel matters): edge fades on scrollables
/// (JwScrollFade). Not design tokens, so they live outside jw_tokens.dart.
abstract final class JwMask {
  static const clear = Color(0x00000000);
  static const solid = Color(0xFF000000);
}
