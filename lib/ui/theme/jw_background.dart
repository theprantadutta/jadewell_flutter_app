import 'package:flutter/widgets.dart';

import '../components/pop_background.dart';

/// Screen background. Delegates to the Clay Pop [PopBackground] (lavender /
/// indigo gradient plus static pastel blobs); kept so existing screens keep
/// compiling. [orbs] false draws the gradient only; [blobs] picks a
/// placement ([PopBlobs]).
class JwBackground extends StatelessWidget {
  const JwBackground({super.key, this.child, this.orbs = true, this.blobs});

  final Widget? child;

  /// Draw the decorative blobs.
  final bool orbs;

  /// Blob placement when [orbs] is true; defaults to [PopBlobs.standard].
  final List<PopBlob>? blobs;

  @override
  Widget build(BuildContext context) =>
      PopBackground(blobs: orbs ? (blobs ?? PopBlobs.standard) : PopBlobs.none, child: child);
}

/// Painter behind [JwBackground]; usable directly in other painters.
class JwBackgroundPainter extends PopBackgroundPainter {
  JwBackgroundPainter(super.jw, {bool orbs = true, super.devicePixelRatio})
    : super(blobs: orbs ? PopBlobs.standard : PopBlobs.none);
}
