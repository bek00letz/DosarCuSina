#!/usr/bin/env bash
# Runs the iOS test target (Swift Testing) on an installed simulator. The pull
# request workflow runs this same script, so a local run and CI agree.
#
#   ./tests/run_tests.sh              # iOS tests
#   ./tests/run_tests.sh --android    # also the Android Room scripts (paused platform)
#   SIMULATOR_ID=<udid> ./tests/run_tests.sh
#
# Building for the tests builds the app with its widgets and share extension.
# After the tests, scripts/plural-check.py checks that every counted string the
# build found has plural forms in its String Catalog.
#
# It never downloads runtimes or creates simulators: it picks an iPhone that is
# already installed with the newest iOS the project supports (its deployment
# target or later), or uses SIMULATOR_ID.
#
# For CI:
#   DERIVED_DATA_PATH=<dir>  keep build products there (cached between runs)
#   RESULTS_DIR=<dir>        keep the full log and the result bundle there
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/ios/DosarCuSina.xcodeproj"
RUN_ANDROID=false
for arg in "$@"; do
    case "$arg" in
        --android) RUN_ANDROID=true ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

# The oldest iOS the app runs on, read from the project so it never falls behind.
MIN_IOS=$(awk -F' = ' '/IPHONEOS_DEPLOYMENT_TARGET/ { gsub(/[;" ]/, "", $2); print $2; exit }' "$PROJECT/project.pbxproj")
MIN_MAJOR="${MIN_IOS%%.*}"

# "udid<TAB>name<TAB>iOS version": the first iPhone under the newest iOS major
# version that is at least the deployment target.
pick_simulator() {
    xcrun simctl list devices available | awk -v min="$MIN_MAJOR" '
        /^-- iOS [0-9]/ {
            version = $3; major = version; sub(/\..*/, "", major); major += 0; next
        }
        /^-- / { major = 0; next }
        major >= min && major > best && /iPhone/ {
            match($0, /\(([0-9A-F-]{36})\)/)
            id = substr($0, RSTART + 1, RLENGTH - 2)
            name = $0; sub(/^[[:space:]]+/, "", name); sub(/[[:space:]]+\(.*$/, "", name)
            best = major; chosen = id "\t" name "\t" version
        }
        END { print chosen }'
}

if [[ -n "${SIMULATOR_ID:-}" ]]; then
    DEVICE="$SIMULATOR_ID"
    DESCRIPTION="$SIMULATOR_ID"
else
    PICKED="$(pick_simulator)"
    DEVICE="$(cut -f1 <<<"$PICKED")"
    DESCRIPTION="$(cut -f2 <<<"$PICKED"), iOS $(cut -f3 <<<"$PICKED") ($DEVICE)"
fi
if [[ -z "$DEVICE" ]]; then
    echo "No installed iPhone simulator with iOS $MIN_MAJOR or later. Install one in Xcode, or set SIMULATOR_ID." >&2
    exit 1
fi

if [[ -n "${DERIVED_DATA_PATH:-}" ]]; then
    DERIVED_DATA="$DERIVED_DATA_PATH"
    mkdir -p "$DERIVED_DATA"
    SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/dosarcusina-tests.XXXXXX")"
else
    DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/dosarcusina-tests.XXXXXX")"
    SCRATCH="$DERIVED_DATA"
fi
trap 'rm -rf "$SCRATCH"' EXIT

RESULTS="${RESULTS_DIR:-$SCRATCH}"
mkdir -p "$RESULTS"
LOG="$RESULTS/test.log"
RESULT_BUNDLE="$RESULTS/DosarCuSinaTests.xcresult"
rm -rf "$RESULT_BUNDLE"

echo "iOS tests on $DESCRIPTION"
set +e
xcodebuild test \
    -project "$PROJECT" \
    -scheme DosarCuSina \
    -destination "id=$DEVICE" \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$RESULT_BUNDLE" \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO > "$LOG" 2>&1
STATUS=$?
set -e
# Build errors and warnings, each failed test with what it expected, and the verdict.
grep -E "failed on|error:|warning:|\*\* TEST" "$LOG" | sort -u || true
grep -E "^✘ |^↳ " "$LOG" || true

# Every counted string has plural forms. The build wrote each file's localizable
# strings, integers marked, to DerivedData; the check reads them against the catalogs.
PLURALS=0
if [[ -d "$DERIVED_DATA/Build/Intermediates.noindex" ]]; then
    python3 "$REPO_ROOT/scripts/plural-check.py" "$DERIVED_DATA" || PLURALS=$?
fi

if [[ $STATUS -ne 0 ]]; then
    echo "iOS tests failed (exit $STATUS)." >&2
    [[ -n "${RESULTS_DIR:-}" ]] && echo "The full log is $LOG, the result bundle $RESULT_BUNDLE." >&2
    exit "$STATUS"
fi
if [[ $PLURALS -ne 0 ]]; then
    exit "$PLURALS"
fi

if [[ "$RUN_ANDROID" == true ]]; then
    echo "Android Room scripts"
    python3 "$REPO_ROOT/tests/android/run_room_tests.py"
    python3 "$REPO_ROOT/tests/android/adversarial_room_stress_test.py"
fi
