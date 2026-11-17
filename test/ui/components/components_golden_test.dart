// Goldens for the Clay Pop primitives (lib/ui/components/), one per widget,
// in light and dark.
import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/ui/components/components.dart';
import 'package:jadewell_flutter_app/ui/theme/jw_theme.dart';
import 'package:jadewell_flutter_app/ui/theme/jw_tokens.dart';
import 'package:jadewell_flutter_app/ui/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

import '../golden_helpers.dart';

void main() {
  setUpAll(loadJwFonts);

  final cases = <String, (Widget, double)>{
    'fill_box': (
      Wrap(
        spacing: 16,
        runSpacing: 20,
        children: [
          for (final f in JwFill.all) FillBox(fill: f, width: 110, height: 76),
          const FillBox(width: 110, height: 76, pressed: 1),
          const FillBox(fill: JwFill.mint, width: 110, height: 76, edge: 3, glow: false),
        ],
      ),
      330,
    ),
    'icon_badge': (
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 12, children: [for (final f in JwFill.all) IconBadge(icon: JwIcons.star, fill: f)]),
          const SizedBox(height: 16),
          const Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              IconBadge(icon: JwIcons.hint, fill: JwFill.yellow, size: 26),
              IconBadge(icon: JwIcons.hint, fill: JwFill.yellow, size: 34),
              IconBadge(icon: JwIcons.hint, fill: JwFill.yellow, size: 48),
              IconBadge(icon: JwIcons.shuffle, fill: JwFill.pink, size: 68),
              IconBadge(fill: JwFill.coral, size: 34, child: Text('3')),
            ],
          ),
        ],
      ),
      170,
    ),
    'counter_chip': (
      const Wrap(
        spacing: 10,
        runSpacing: 14,
        children: [
          CounterChip(icon: JwIcons.tile, value: '86', label: 'tiles', fill: JwFill.mint),
          CounterChip(icon: JwIcons.pairs, value: '6', label: 'pairs open', fill: JwFill.pink),
          CounterChip(icon: JwIcons.flame, value: '×6', fill: JwFill.coral),
        ],
      ),
      140,
    ),
    'fill_knob': (
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          FillKnob(icon: JwIcons.hint, label: 'Hint', fill: JwFill.yellow, badge: 3, onPressed: () {}),
          FillKnob(icon: JwIcons.undo, label: 'Undo', fill: JwFill.sky, onPressed: () {}),
          FillKnob(icon: JwIcons.shuffle, label: 'Shuffle', fill: JwFill.pink, onPressed: () {}),
          const FillKnob(icon: JwIcons.undo, label: 'Off', fill: JwFill.sky),
        ],
      ),
      140,
    ),
    'hero_card': (
      Builder(
        builder: (context) {
          final jw = context.jw;
          return HeroCard(
            confetti: true,
            height: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Daily · Sun 15 Nov', style: jw.text.callout.copyWith(fontWeight: FontWeight.w600, color: JwFill.purple.on)),
                Text('Lotus', style: jw.text.h1.copyWith(color: JwFill.purple.on)),
                const Spacer(),
                PrimaryButton(label: 'Play', fill: JwFill.yellow, height: 40, onPressed: () {}),
              ],
            ),
          );
        },
      ),
      240,
    ),
    'pop_background': (
      const SizedBox(height: 300, child: PopBackground(blobs: PopBlobs.board)),
      340,
    ),
    'primary_button': (
      Column(
        children: [
          PrimaryButton(label: 'Primary', icon: JwIcons.play, expand: true, onPressed: () {}),
          const SizedBox(height: 18),
          PrimaryButton(label: 'Next: Bridge', trailingIcon: JwIcons.arrow, height: 60, expand: true, onPressed: () {}),
          const SizedBox(height: 18),
          const PrimaryButton(label: 'Disabled', expand: true),
          const SizedBox(height: 18),
          Row(
            children: [
              PrimaryButton(label: 'Small', height: 42, onPressed: () {}),
              const SizedBox(width: 14),
              PrimaryButton(label: 'Play', fill: JwFill.yellow, height: 42, onPressed: () {}),
            ],
          ),
        ],
      ),
      320,
    ),
  };

  for (final MapEntry(key: name, value: (widget, height)) in cases.entries) {
    for (final b in Brightness.values) {
      testWidgets('$name ${b.name}', (tester) async {
        await expectGolden(
          tester,
          goldenFrame(brightness: b, child: widget),
          'goldens/${name}_${b.name}.png',
          surface: Size(420, height),
        );
      });
    }
  }
}
