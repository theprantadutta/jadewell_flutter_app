#!/usr/bin/env bash
# Builds a profile APK in demo mode, runs it on a device and prints the
# per-segment frame timings (docs/PERFORMANCE.md).
#
#   tool/perf/profile.sh <adb-serial> [seconds=420] [--no-build]
#
# The app plays itself (lib/ui/demo/demo_driver.dart) and logs `JWPERF`
# lines; they are saved to build/perf/<serial>-<time>.log. Demo mode keeps
# progress in memory and never syncs, so the device's real data is untouched.
# The app is force-stopped at the end.
set -euo pipefail

SERIAL="${1:?usage: tool/perf/profile.sh <adb-serial> [seconds] [--no-build]}"
SECONDS_TO_RUN="${2:-420}"
BUILD=1
for a in "$@"; do [[ "$a" == "--no-build" ]] && BUILD=0; done

PKG=com.pranta.jadewell
cd "$(dirname "$0")/../.."
APK=build/app/outputs/flutter-apk/app-profile.apk
mkdir -p build/perf
LOG="build/perf/${SERIAL}-$(date +%Y%m%d-%H%M%S).log"

if [[ $BUILD == 1 ]]; then
  flutter build apk --profile --dart-define=JW_DEMO=true
fi

adb -s "$SERIAL" install -r "$APK" >/dev/null
adb -s "$SERIAL" shell am force-stop "$PKG"
adb -s "$SERIAL" logcat -c
adb -s "$SERIAL" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1

echo "Demo running on $SERIAL for ${SECONDS_TO_RUN}s → $LOG"
timeout "$SECONDS_TO_RUN" adb -s "$SERIAL" logcat -v brief flutter:I '*:S' | tee "$LOG" | grep --line-buffered JWPERF || true

adb -s "$SERIAL" shell am force-stop "$PKG"
echo
echo "== Over-budget frames (>16.7 ms) per segment =="
grep -o 'seg=[^ ]* frames=[0-9]*.*over_budget=[0-9]* ([0-9.]*%) severe=[0-9]*' "$LOG" \
  | sed -E 's/build_p50.*raster_max=[0-9.]* //' || true
echo
grep 'JWPERF total=' "$LOG" | tail -12 || true
