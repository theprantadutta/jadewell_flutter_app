# Rendering performance

Target: every scenario at 60 fps (16.7 ms per frame) on a mid-range phone
(Galaxy A24, Mali GPU, 1080 × 2340) and the Galaxy Tab A9, with Impeller
(Android/Vulkan).

The 60 fps target applies at a 60 Hz display rate; players running 90/120 Hz
get whatever their device gives them.

## Running the harness

```sh
flutter drive --profile --no-dds -d <device> \
  --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart
```

`--no-dds` is required. The test (`integration_test/perf_test.dart`) runs the
real app in profile mode, skips onboarding on a fresh install and traces four
scenarios:

| key | what it does |
|---|---|
| `home_scroll` | flings the collection down and up three times (clay cards, silhouettes) |
| `board_entry` | opens Fortress; 128 tiles drop in layer by layer |
| `hint_shuffle` | hint (bob + glow), then the shuffle dialog and a confirmed shuffle |
| `gameplay_clear` | debug autoplay matches the board to the end, then the cleared beat sheet |

Each writes `build/<key>.timeline_summary.json` (average / 90th / 99th
percentile / worst build and raster times, missed-frame counts) and
`build/<key>.timeline.json` (the raw trace; open it in Perfetto or
`chrome://tracing`). Budgets: raster p90 and build p90 under 16.7 ms, fewer
than 5 % missed raster frames. The run leaves a cleared Fortress on the device
(`adb shell pm clear com.pranta.jadewell` resets it); `flutter drive` installs
the test build over the app.

## Results

Times in ms as avg / p90 / p99 / worst; "missed" is frames over 16.7 ms.

### Galaxy A24 (phone)

| scenario | build before | build after | raster before | raster after | missed raster before → after |
|---|---|---|---|---|---|
| home_scroll | 6.6 / 13.5 / 18.5 / 19.0 | 3.0 / 5.0 / 8.7 / 12.6 | 55.8 / 64.7 / 104.3 / 107.8 | 5.6 / 7.5 / 9.8 / 11.2 | 90/90 → 0/208 |
| board_entry | 14.7 / 32.8 / 58.0 / 58.0 | 3.3 / 4.9 / 9.5 / 13.0 | 185.0 / 498.3 / 660.6 / 660.6 | 5.9 / 8.2 / 10.7 / 13.4 | 22/22 → 0/272 |
| hint_shuffle | 13.4 / 20.2 / 29.4 / 29.4 | 3.9 / 6.3 / 12.3 / 19.2 | 196.8 / 207.6 / 420.3 / 420.3 | 8.1 / 13.8 / 15.1 / 16.1 | 29/29 → 1/224 |
| gameplay_clear | 3.6 / 6.3 / 8.7 / 9.0 | 4.3 / 6.2 / 9.1 / 15.6 | 21.4 / 31.6 / 33.4 / 35.5 | 5.5 / 7.0 / 10.6 / 20.6 | 131/174 → 1/177 |

### Galaxy Tab A9 (tablet)

| scenario | build before | build after | raster before | raster after | missed raster before → after |
|---|---|---|---|---|---|
| home_scroll | 3.3 / 7.7 / 10.7 / 16.3 | 3.0 / 6.2 / 9.8 / 10.5 | 36.1 / 45.9 / 55.9 / 63.5 | 5.0 / 6.1 / 7.1 / 7.7 | 122/122 → 0/200 |
| board_entry | 11.9 / 27.6 / 44.2 / 44.2 | 4.3 / 6.5 / 13.2 / 25.1 | 183.6 / 613.9 / 789.4 / 789.4 | 5.7 / 6.8 / 8.9 / 9.3 | 22/22 → 0/236 |
| hint_shuffle | 11.6 / 17.4 / 28.0 / 28.0 | 4.5 / 6.9 / 17.4 / 23.9 | 170.4 / 181.9 / 454.7 / 454.7 | 6.1 / 7.5 / 14.2 / 16.4 | 33/33 → 1/213 |
| gameplay_clear | 4.2 / 6.0 / 9.9 / 12.1 | 4.7 / 6.9 / 9.6 / 10.9 | 13.7 / 17.7 / 25.3 / 36.3 | 6.4 / 8.3 / 11.6 / 12.0 | 46/182 → 0/185 |

Frame counts went up because the "before" runs could only produce a few
frames per second (the scenarios run for a fixed wall-clock time).

## What was slow, and why

Build times were mostly fine; the GPU (raster thread, `SurfaceFrame::Submit`)
was the bottleneck. **Impeller has no raster cache**: whatever a layer draws is
rendered again on every frame it is composited, even when the widgets did not
repaint. Under Skia, static blurred content was cached as a bitmap after a few
frames; under Impeller it is not.

- **Clay shadows.** `ClayDecoration` draws outer shadows with
  `MaskFilter.blur` behind an even-odd clip and inset shadows as blurred
  inverse paths. Each blurred path is an offscreen render pass plus a two-pass
  Gaussian blur. Caching the recorded `Picture` did not help: replaying a
  picture replays its blurs. A home screen had dozens of these per frame, and
  every tile on a board had four (on a tile-based Mali GPU, render-pass
  switches are especially expensive).
- **Per-tile layers.** Blocked tiles dimmed their glyphs through a
  `saveLayer` with a colour-filter matrix (about 100 layers on a full board);
  entry, exit and crossfades wrapped each tile in an `Opacity` widget (another
  `saveLayer` per tile per frame). Each tile also rebuilt a
  `ValueListenableBuilder` → `Transform` → `Opacity` subtree every tick, which
  is why board-entry build p90 was 33 ms.
- **Silhouettes.** Every layout card painted hundreds of tiny blurred rounded
  rects, again on every scrolled frame, plus an `Opacity` layer when locked.
- **Background orbs** re-blurred their shadow each frame (cheap, but free to
  remove).

## What changed

- `lib/ui/theme/jw_raster_cache.dart`: `JwRasterCache`, a byte-bounded LRU
  (96 MB) of textures made with `Picture.toImageSync` at device pixel ratio ×
  canvas scale (bucketed to 1/8 so spring jitter reuses a texture). Evicted
  textures are disposed; the cache empties on `didHaveMemoryPressure`.
  `JwRaster.paint` draws one textured quad (`FilterQuality.medium`), with
  opacity as paint alpha.
- `ClayDecoration` paints from a texture keyed by size, radius, fill/gradient,
  resolved shadows (so theme colours) and scale, covering the full shadow
  reach. Press cross-fades draw the pressed texture with alpha instead of a
  `saveLayer`. Boxes whose size animates (AnimatedSize, animated containers)
  replay the picture while moving and rasterize once they settle, so they do
  not render a texture per frame. Shadowless (flat) surfaces still draw
  directly.
- Tiles (`lib/ui/board/tile/tile_paint.dart`): `TileRaster` keeps one texture
  per (face, visual state, theme, scale) with the blocked look baked in. Each
  is built from the state's shared clay texture plus the glyph vectors, so the
  blurs run once per state and warming all 42 faces × playable/blocked before
  the entry (`BoardView._warmTiles`) is cheap. `TilePaint` / `RenderTilePaint`
  paints a tile from those textures and applies the motion transform, opacity,
  crossfade, blocker outline and flash itself, listening to the tile's
  `ValueNotifier`s. A tick only repaints; nothing rebuilds and no layers are
  pushed. All tiles sit in one `RepaintBoundary`. `TileRasterScope` passes the
  board-fit scale (with headroom on zoomable boards) so textures stay sharp
  under the `FittedBox`.
- `JwSilhouette` draws a cached texture per (layout, size, theme, scale); the
  locked look is that texture at 35 % alpha. `JwBackground` caches each orb.

Motion timings and curves are unchanged. On-device screenshots before and
after (home, collection, unlock sheet, settings, board with blocked, selected
and hinted tiles, shuffle dialog, pause, cleared, in both themes) match apart
from content that changed between runs and sub-pixel antialiasing at edges.
The goldens were regenerated for the same reason: the test renders textures
at the test view's 3× ratio and captures at 1×, so edges resample slightly.

## Demo mode (Nov 2026): the app plays itself

```sh
tool/perf/profile.sh <adb-serial> [seconds=420] [--no-build]
```

The script builds a profile APK with `--dart-define=JW_DEMO=true`, installs it,
launches it and collects the `JWPERF` log lines into `build/perf/`.

The demo (`lib/ui/demo/demo_driver.dart`) loops: home (scroll) → a full board
(turtle, fortress, pyramid, butterfly; with hints, an undo and a shuffle) →
the cleared screen → leaderboard, stats, settings, daily (scrolling each).
`FrameStats` (`lib/ui/demo/frame_stats.dart`) prints one line per segment
(p50/p90/p99/max build and raster, frames over 16.7 ms, frames over 33 ms)
and a total per kind after each loop.

- In demo mode progress, stats and dailies stay in memory, sync is off and
  ads are off, so a demo never touches the player's data or the leaderboards.
- `kDemoMode` is a compile-time `false` in release builds.
- The long-press-the-timer QA autoplay uses the same player
  (`GameController.demoPlay`); the solver runs on a background isolate.

### Finding the cause of a slow frame

Build with `--dart-define=JW_TRACE=true` as well; every widget build is then
named in the timeline (this slows builds down; don't read absolute numbers
from a trace build). Then:

```sh
flutter run --profile -d <serial> --use-application-binary build/app/outputs/flutter-apk/app-profile.apk
python tool/perf/trace.py <vm-service-uri> 300 build/perf/trace.json
python tool/perf/top_widgets.py build/perf/trace.json 12
```

`top_widgets.py` ranks the app's own widgets by self build time inside slow
build phases.

### Demo results (Galaxy A24, 2026-11-19, 7-minute run, ~30,000 frames)

| Part | Frames | Build p99 | Raster p99 | Over 16.7 ms |
|---|---|---|---|---|
| Gameplay (4 full boards) | 21,752 | 8.0 ms | 11.8 ms | 3 (0.01%) |
| Home | 1,340 | 7.2 ms | 11.2 ms | 3 (0.2%) |
| Cleared screen | 1,577 | 7.9 ms | 12.2 ms | 10 (0.6%) |
| Other screens (open + scroll) | 4,655 | 10.2 ms | 11.8 ms | 29 (0.6%) |
| Board deal | 497 | 26.9 ms | 13.6 ms | 10 (2.0%) |

What's left is one or two frames when a screen first opens: building a whole
screen (20–35 ms on the A24) and the Android page transition's one-time
snapshot. Turning the snapshot off was measured and was worse (drawing the
pages live cost ~17–18 ms per transition frame on Stats and Daily).

### Board tile rebuilds

`BoardView` caches each tile's widget together with its inputs and hands
Flutter the identical widget when nothing changed, so a tap rebuilds only the
tiles it affects (it used to rebuild all 144; worst gameplay build went from
19 ms to 13 ms on the A24). Whole-board rebuilds now only happen on a deal and
a shuffle, by design.

### High refresh rate (Settings, Android)

Flutter never asks Android for more than the default rate. Settings → High
refresh rate (off by default, saved in the Drift `settings` table, schema 2)
calls `package:refresh_rate`. That votes for the display's top rate on the
Flutter surface, and the plugin re-applies the vote when the surface comes
back after backgrounding. The row only shows on Android, and only when the
screen reports a rate above 60 Hz. iOS keeps its own cadence (no
`CADisableMinimumFrameDurationOnPhone`).

The vote is a request, and the phone's own setting wins. On Samsung, Motion
smoothness *High* pins every app to 90/120 Hz (SurfaceFlinger
`primaryRanges=[90, 90]` on the A24), and *Standard* caps every app at 60,
whatever the app asks. The budget stays at 16.7 ms either way: frame stats
and the rules below are judged at 60 Hz.

## Rules for future UI work

1. **No blur at frame time.** No `MaskFilter.blur`, `ImageFilter.blur`,
   `BackdropFilter` or `BoxShadow` with a blur radius on anything that is on
   screen while something animates, unless it goes through `JwRasterCache`.
   Use `jw.clay(...)` for raised/sunken looks and `jw.fill(...)` /
   `FillBox` / `FillPressable` (lib/ui/components) for Clay Pop fills; both
   are cached, and a fill press only moves textures and a plain edge rect.
   `PopBackground` caches its blobs.
2. **No per-item `saveLayer`.** Avoid `Opacity`, `ColorFiltered`,
   `ShaderMask` and `saveLayer` around list items, tiles or anything repeated.
   Bake static effects (desaturation, dimming) into the cached texture, and
   fade a single image with paint alpha (`JwRaster.paint(opacity:)`). One
   `Opacity`/`FadeTransition` around a whole screen or dialog is fine.
3. **Animate with paint, not rebuilds.** For per-frame motion of many items,
   listen to a `Listenable` in a render object or `CustomPainter(repaint:)`
   and call `markNeedsPaint`; do not rebuild widget subtrees every tick.
4. **Cache keys must capture every input to the pixels**: size, colours/theme,
   state and device scale (`JwRasterCache.bucket(dpr × canvasScale)`).
   Textures created before fonts load are stale (tests clear the cache in
   `loadJwFonts`).
5. **Don't rasterize what changes every frame.** A texture per animated size
   is worse than drawing directly; clay already guards against it. New
   cached painters should do the same.
6. **Measure on the A24.** Run the harness after any visual change to boards,
   cards or sheets and keep raster p90 under 16.7 ms. Look for
   `Canvas::saveLayer` counts and long `SurfaceFrame::Submit` /
   `SurfaceFrame::Encode` events in `build/<key>.timeline.json`.
7. **Use the demo for whole-app checks.** `tool/perf/profile.sh <serial>` plays
   every screen unattended and lists each frame over 16.7 ms.
