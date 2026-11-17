#!/bin/sh
# Checks a release build of the app the way App Store Connect and review will see it:
#
#   - the app, its widgets and its share extension each carry a privacy manifest
#     (PrivacyInfo.xcprivacy) that is a valid property list and tracks nothing;
#   - the app has the words for every permission it asks (camera, Face ID, adding to Photos);
#   - the export-compliance answer is there (ITSAppUsesNonExemptEncryption = NO);
#   - every part carries the same version and build number;
#   - "remote-notification" is among the background modes exactly when release builds sync
#     (DOSAR_SYNC_SHIPS_IN_RELEASE_BUILDS in the project, scripts/background-modes.sh).
#
#   scripts/bundle-check.sh path/to/Release-iphoneos/DosarCuSina.app
#
# The release-build check runs it on GitHub; ReleaseReadinessTests checks the same things,
# and that the manifests match the code, in the development build.
set -eu

app=${1:?"Usage: scripts/bundle-check.sh path/to/DosarCuSina.app"}
root=$(cd "$(dirname "$0")/.." && pwd)
buddy=/usr/libexec/PlistBuddy
failed=0

fail() { echo "bundle-check: $*" >&2; failed=1; }
value() { "$buddy" -c "Print :$2" "$1/Info.plist" 2>/dev/null || true; }

for part in "$app" "$app/PlugIns/DosarCuSinaWidgets.appex" "$app/PlugIns/DosarCuSinaShare.appex"; do
    name=$(basename "$part")
    [ -d "$part" ] || { fail "$name is missing from the build"; continue; }
    manifest="$part/PrivacyInfo.xcprivacy"
    if [ ! -f "$manifest" ]; then
        fail "$name has no PrivacyInfo.xcprivacy: add it to the target's folder"
    elif ! plutil -lint -s "$manifest"; then
        fail "$name's PrivacyInfo.xcprivacy is not a valid property list"
    elif [ "$("$buddy" -c 'Print :NSPrivacyTracking' "$manifest" 2>/dev/null)" != false ]; then
        fail "$name's privacy manifest must say NSPrivacyTracking = false"
    fi
done

# An entitlements file is the build's input, never a file the app ships.
for part in "$app" "$app/PlugIns/DosarCuSinaWidgets.appex" "$app/PlugIns/DosarCuSinaShare.appex"; do
    if [ -n "$(find "$part" -maxdepth 1 -name '*.entitlements' 2>/dev/null)" ]; then
        fail "$(basename "$part") carries an entitlements file as a resource"
    fi
done

for key in NSCameraUsageDescription NSFaceIDUsageDescription NSPhotoLibraryAddUsageDescription; do
    [ -n "$(value "$app" "$key")" ] || fail "the app has no $key: set INFOPLIST_KEY_$key in the app target"
done

[ "$(value "$app" ITSAppUsesNonExemptEncryption)" = false ] || fail "ITSAppUsesNonExemptEncryption must be NO (only the encryption iOS provides)"

version=$(value "$app" CFBundleShortVersionString)
build=$(value "$app" CFBundleVersion)
for part in "$app/PlugIns/DosarCuSinaWidgets.appex" "$app/PlugIns/DosarCuSinaShare.appex"; do
    [ "$(value "$part" CFBundleShortVersionString)" = "$version" ] || fail "$(basename "$part") has another version than the app's $version"
    [ "$(value "$part" CFBundleVersion)" = "$build" ] || fail "$(basename "$part") has another build number than the app's $build"
done

ships=$(sed -n 's/^[[:space:]]*DOSAR_SYNC_SHIPS_IN_RELEASE_BUILDS = \([A-Z]*\);/\1/p' "$root/ios/DosarCuSina.xcodeproj/project.pbxproj" | sort -u)
if "$buddy" -c "Print :UIBackgroundModes" "$app/Info.plist" 2>/dev/null | grep -qx '[[:space:]]*remote-notification'; then
    [ "$ships" = YES ] || fail "a release build that doesn't sync asks for remote-notification: scripts/background-modes.sh should have taken it out"
else
    [ "$ships" = NO ] || fail "release builds sync but the app has no remote-notification background mode"
fi

[ "$failed" -eq 0 ] && echo "bundle-check: the release build is ready for App Store Connect's checks"
exit "$failed"
