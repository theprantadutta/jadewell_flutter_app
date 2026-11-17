import 'package:flutter/widgets.dart';

import '../components/fill_box.dart';
import '../theme/jw_tokens.dart';

/// The header logo tile (screens 11, 17a, 18): the tiles-only mark (white
/// tiles, mint beads) on a purple fill tile, radius 18. Its 5 pt base edge
/// paints below the box.
class JwLogoTile extends StatelessWidget {
  const JwLogoTile({super.key, this.size = 52});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: FillBox(
      fill: JwFill.purple,
      radius: size * 0.34,
      width: size,
      height: size,
      child: Center(
        child: Image.asset(
          'assets/brand/mark_tiles_only_512.png',
          width: size * 0.86,
          height: size * 0.86,
          filterQuality: FilterQuality.medium,
          cacheWidth: (size * 3).round(),
        ),
      ),
    ),
  );
}
