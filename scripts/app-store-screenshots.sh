#!/usr/bin/env bash
# Takes the App Store's screenshots: builds the app (Debug) with its screenshot UI tests
# (ios/DosarCuSinaScreenshots), then on each device, in light and in dark, launches the app at
# each screen of its made-up household (ScreenshotStage) and keeps the pictures.
#
#   scripts/app-store-screenshots.sh <output folder> <simulator> [<simulator>…]
#
# A simulator is named by its name ("iPhone 17 Pro Max") or its id. The pictures land in
# <output folder>/<simulator name>/<order>-<scene>-<light|dark>.png, at the device's own pixels.
# The status bar reads 9:41 with a full battery; Face ID is enrolled so a locked section opens.
#
# It never downloads a runtime. On GitHub (CI=true) a simulator that isn't there yet is made
# from the newest iOS runtime installed; on a Mac of ours it must already exist (AGENTS.md).
# The app keeps the screenshots' binder in a store of its own (BuildInfo.isScreenshotRun); on
# GitHub each simulator starts empty, so the household is made the day the pictures are taken.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/ios/DosarCuSina.xcodeproj"
OUT=${1:?"Usage: scripts/app-store-screenshots.sh <output folder> <simulator> [<simulator>…]"}
shift
[[ $# -gt 0 ]] || { echo "Name at least one simulator." >&2; exit 2; }
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dosar-screenshots.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
DERIVED="${DERIVED_DATA_PATH:-$WORK/DerivedData}"
# Every launch of this run shares one household, made at its first launch.
RUN=$(date +%Y%m%d%H%M%S)

# Simulators are made only on GitHub's runners; on our Macs only installed ones are used.
CREATE=()
[[ ${CI:-} == true ]] && CREATE=(--create)

echo "Building the app and its screenshot tests"
set -o pipefail
xcodebuild build-for-testing -quiet \
    -project "$PROJECT" -scheme DosarCuSinaScreenshots -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$WORK/build.log" | grep -E "error:|\*\* BUILD" || true
XCTESTRUN=$(find "$DERIVED/Build/Products" -name 'DosarCuSinaScreenshots*.xctestrun' | head -1)
[[ -n $XCTESTRUN ]] || { echo "The build made no test run; see the log above." >&2; exit 1; }

for wanted in "$@"; do
    found=$(python3 "$REPO_ROOT/scripts/find-simulator.py" "$wanted" ${CREATE[@]+"${CREATE[@]}"})
    udid=$(cut -f1 <<<"$found")
    name=$(cut -f2 <<<"$found")
    echo "Screenshots on $name ($udid)"
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null
    if [[ ${CI:-} == true ]]; then
        # A runner's simulator speaks Romanian too, so the iPad's status bar dates the Romanian way.
        xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array ro
        xcrun simctl spawn "$udid" defaults write -g AppleLocale ro_RO
        xcrun simctl shutdown "$udid"
        xcrun simctl boot "$udid"
        xcrun simctl bootstatus "$udid" -b >/dev/null
    fi
    # A clean status bar: 9:41, full signal, a full battery.
    xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 --operatorName "" --batteryState charged --batteryLevel 100
    # Face ID enrolled, so a locked section opens with the simulator's matching face.
    xcrun simctl spawn "$udid" notifyutil -s com.apple.BiometricKit.enrollmentChanged 1
    xcrun simctl spawn "$udid" notifyutil -p com.apple.BiometricKit.enrollmentChanged

    for appearance in light dark; do
        xcrun simctl ui "$udid" appearance "$appearance"
        results="$WORK/$udid-$appearance.xcresult"
        TEST_RUNNER_SCREENSHOT_APPEARANCE=$appearance TEST_RUNNER_SCREENSHOT_RUN=$RUN xcodebuild test-without-building \
            -xctestrun "$XCTESTRUN" -destination "id=$udid" -resultBundlePath "$results" \
            -parallel-testing-enabled NO > "$WORK/$udid-$appearance.log" 2>&1 || {
                grep -E "error:|failed|\*\* TEST" "$WORK/$udid-$appearance.log" | sort -u >&2 || true
                echo "Some screenshots on $name ($appearance) failed; the rest are kept." >&2
            }
        attachments="$WORK/$udid-$appearance-attachments"
        xcrun xcresulttool export attachments --path "$results" --output-path "$attachments" >/dev/null
        mkdir -p "$OUT/$name"
        # The manifest names each picture as the test did ("01-binder-light").
        python3 - "$attachments" "$OUT/$name" <<'PY'
import json, os, re, shutil, sys
source, target = sys.argv[1], sys.argv[2]
for test in json.load(open(os.path.join(source, "manifest.json"))):
    for attachment in test.get("attachments", []):
        # Only the pictures the tests kept; a failure's own snapshots and recordings stay out.
        kept = re.match(r"(\d\d-[a-z]+-(?:light|dark))_", attachment.get("suggestedHumanReadableName", ""))
        if kept:
            shutil.copy(os.path.join(source, attachment["exportedFileName"]), os.path.join(target, kept.group(1) + ".png"))
PY
    done
    xcrun simctl status_bar "$udid" clear
    xcrun simctl ui "$udid" appearance light
done
echo "The screenshots are in $OUT"
