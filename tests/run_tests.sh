#!/usr/bin/env bash
# Runs the iOS test target (Swift Testing) on an installed simulator.
#
#   ./tests/run_tests.sh              # iOS tests
#   ./tests/run_tests.sh --android    # also the Android Room scripts (paused platform)
#   SIMULATOR_ID=<udid> ./tests/run_tests.sh
#
# It never downloads runtimes or creates simulators: it picks an iPhone that
# is already installed with an iOS 27 or 26 runtime, or uses SIMULATOR_ID.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ANDROID=false
for arg in "$@"; do
    case "$arg" in
        --android) RUN_ANDROID=true ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

pick_simulator() {
    xcrun simctl list devices available | awk '
        /^-- iOS 27/ { runtime = 27; next }
        /^-- iOS 26/ { runtime = 26; next }
        /^-- / { runtime = 0; next }
        runtime > 0 && /iPhone/ {
            match($0, /\(([0-9A-F-]{36})\)/)
            id = substr($0, RSTART + 1, RLENGTH - 2)
            if (runtime > best) { best = runtime; chosen = id }
        }
        END { print chosen }'
}

DEVICE="${SIMULATOR_ID:-$(pick_simulator)}"
if [[ -z "$DEVICE" ]]; then
    echo "No installed iPhone simulator with iOS 26 or 27. Install one in Xcode, or set SIMULATOR_ID." >&2
    exit 1
fi

DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/dosarcusina-tests.XXXXXX")"
trap 'rm -rf "$DERIVED_DATA"' EXIT

echo "iOS tests on simulator $DEVICE"
LOG="$DERIVED_DATA/test.log"
set +e
xcodebuild test \
    -project "$REPO_ROOT/ios/DosarCuSina.xcodeproj" \
    -scheme DosarCuSina \
    -destination "id=$DEVICE" \
    -derivedDataPath "$DERIVED_DATA" \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO > "$LOG" 2>&1
STATUS=$?
set -e
grep -E "failed on|error:|warning:|\*\* TEST" "$LOG" | sort -u || true
if [[ $STATUS -ne 0 ]]; then
    echo "iOS tests failed (exit $STATUS)." >&2
    exit "$STATUS"
fi

if [[ "$RUN_ANDROID" == true ]]; then
    echo "Android Room scripts"
    python3 "$REPO_ROOT/tests/android/run_room_tests.py"
    python3 "$REPO_ROOT/tests/android/adversarial_room_stress_test.py"
fi
