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
BUNDLE_ID=com.ar.dosarcusina.app

# "udid" of the available simulator with this name or id, made on GitHub when it isn't there.
find_simulator() {
    local wanted=$1 udid
    udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
wanted = sys.argv[1]
devices = [d for runtime, ds in json.load(sys.stdin)["devices"].items() if "iOS" in runtime for d in ds]
match = [d["udid"] for d in devices if d["udid"] == wanted or d["name"] == wanted]
print(match[-1] if match else "")' "$wanted")
    if [[ -z $udid && ${CI:-} == true ]]; then
        local runtime type
        runtime=$(xcrun simctl list runtimes available -j | python3 -c '
import json, sys
print([r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS"][-1])')
        type=$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
print(next(t["identifier"] for t in json.load(sys.stdin)["devicetypes"] if t["name"] == sys.argv[1]))' "$wanted")
        udid=$(xcrun simctl create "$wanted" "$type" "$runtime")
    fi
    [[ -n $udid ]] || { echo "No simulator named $wanted is installed." >&2; exit 1; }
    echo "$udid"
}

echo "Building the app and its screenshot tests"
set -o pipefail
xcodebuild build-for-testing -quiet \
    -project "$PROJECT" -scheme DosarCuSinaScreenshots -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$WORK/build.log" | grep -E "error:|\*\* BUILD" || true
XCTESTRUN=$(find "$DERIVED/Build/Products" -name 'DosarCuSinaScreenshots*.xctestrun' | head -1)
[[ -n $XCTESTRUN ]] || { echo "The build made no test run; see the log above." >&2; exit 1; }

for wanted in "$@"; do
    udid=$(find_simulator "$wanted")
    name=$(xcrun simctl list devices -j | python3 -c '
import json, sys
print(next(d["name"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["udid"] == sys.argv[1]))' "$udid")
    echo "Screenshots on $name ($udid)"
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null
    # A clean status bar: 9:41, full signal, a full battery.
    xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 --operatorName "" --batteryState charged --batteryLevel 100
    # Face ID enrolled, so a locked section opens with the simulator's matching face.
    xcrun simctl spawn "$udid" notifyutil -s com.apple.BiometricKit.enrollmentChanged 1
    xcrun simctl spawn "$udid" notifyutil -p com.apple.BiometricKit.enrollmentChanged

    for appearance in light dark; do
        xcrun simctl ui "$udid" appearance "$appearance"
        results="$WORK/$udid-$appearance.xcresult"
        TEST_RUNNER_SCREENSHOT_APPEARANCE=$appearance xcodebuild test-without-building \
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
import json, os, shutil, sys
source, target = sys.argv[1], sys.argv[2]
for test in json.load(open(os.path.join(source, "manifest.json"))):
    for attachment in test.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName", "")
        base = name.split("_", 1)[0] if "_" in name else os.path.splitext(name)[0]
        shutil.copy(os.path.join(source, attachment["exportedFileName"]), os.path.join(target, base + ".png"))
PY
    done
    xcrun simctl status_bar "$udid" clear
    xcrun simctl ui "$udid" appearance light
done
echo "The screenshots are in $OUT"
