#!/usr/bin/env bash
# Runs the iOS test target (Swift Testing) on an installed simulator. The pull
# request workflow runs this same script, so a local run and CI agree.
#
#   ./tests/run_tests.sh              # iOS tests
#   ./tests/run_tests.sh --android-legacy  # also the first Android version's Room scripts
#                                          # (tests/legacy/android; the new Android app is
#                                          # tested by Gradle, see README)
#   SIMULATOR_ID=<udid> ./tests/run_tests.sh
#
# Building for the tests builds the app with its widgets and share extension.
# After the tests, scripts/catalog-check.py checks that every string the build
# found is in its String Catalog and that the catalogs keep nothing else, and
# scripts/plural-check.py that every counted string has plural forms there.
#
# It never downloads runtimes or creates simulators: it picks an iPhone that is
# already installed with the newest iOS the project supports (its deployment
# target or later), or uses SIMULATOR_ID.
#
# For CI:
#   DERIVED_DATA_PATH=<dir>  keep build products there (cached between runs)
#   RESULTS_DIR=<dir>        keep the full log and the result bundle there, up-to-date
#                            String Catalogs (string-catalogs/) when they fell behind, and
#                            the golden archives made afresh (golden-archives/, laid out as
#                            shared/fixtures/golden/ios/) when GoldenArchiveTests finds them
#                            out of date
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/ios/DosarCuSina.xcodeproj"
RUN_ANDROID=false
for arg in "$@"; do
    case "$arg" in
        --android-legacy) RUN_ANDROID=true ;;
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
# GoldenArchiveTests leaves the golden archives as they should be here when the committed
# ones are out of date (xcodebuild hands TEST_RUNNER_ variables to the tests without the prefix).
if [[ -n "${RESULTS_DIR:-}" ]]; then
    rm -rf "$RESULTS/golden-archives"
    export TEST_RUNNER_GOLDEN_ARCHIVES_OUT="$RESULTS/golden-archives"
fi

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

# Every string is in its String Catalog, and every counted one has plural forms.
# The build wrote each file's localizable strings, integers marked, to DerivedData;
# the checks read them against the catalogs.
CATALOGS=0
PLURALS=0
WARNINGS=0
"$REPO_ROOT/scripts/warnings-check.sh" "$LOG" || WARNINGS=$?
if [[ -d "$DERIVED_DATA/Build/Intermediates.noindex" ]]; then
    python3 "$REPO_ROOT/scripts/catalog-check.py" "$DERIVED_DATA" \
        ${RESULTS_DIR:+--write-to "$RESULTS/string-catalogs"} || CATALOGS=$?
    python3 "$REPO_ROOT/scripts/plural-check.py" "$DERIVED_DATA" || PLURALS=$?
fi

if [[ $STATUS -ne 0 ]]; then
    echo "iOS tests failed (exit $STATUS)." >&2
    [[ -n "${RESULTS_DIR:-}" ]] && echo "The full log is $LOG, the result bundle $RESULT_BUNDLE." >&2
    if [[ -d "$RESULTS/golden-archives" ]]; then
        echo "The golden archives are out of date; made afresh in $RESULTS/golden-archives (copy over shared/fixtures/golden/ios/ and review the diff of expected/)." >&2
    fi
    exit "$STATUS"
fi
if [[ $CATALOGS -ne 0 ]]; then
    exit "$CATALOGS"
fi
if [[ $PLURALS -ne 0 ]]; then
    exit "$PLURALS"
fi
if [[ $WARNINGS -ne 0 ]]; then
    exit "$WARNINGS"
fi

if [[ "$RUN_ANDROID" == true ]]; then
    echo "The first Android version's Room scripts"
    python3 "$REPO_ROOT/tests/legacy/android/run_room_tests.py"
    python3 "$REPO_ROOT/tests/legacy/android/adversarial_room_stress_test.py"
fi
