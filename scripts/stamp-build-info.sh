#!/bin/sh
# Stamps a built target's Info.plist with which build it is, so the app can
# show it at the bottom of Settings and anyone can tell which code a phone runs.
#
#   CFBundleVersion  the number of commits on the built branch: it only goes up
#                    as work lands, and it's the same for the app, its widgets and
#                    its share extension, as iOS expects
#   DosarCommit      the short commit hash
#
# Xcode runs it as the last build phase of each target, after the Info.plist is
# generated (it's the phase's input) and before signing.
# Outside a git checkout it stamps nothing and the build goes on.
set -eu
: > "${SCRIPT_OUTPUT_FILE_0}"

plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
[ -f "$plist" ] || exit 0
cd "${SRCROOT}"
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

count=$(git rev-list --count HEAD)
commit=$(git rev-parse --short=7 HEAD)

# Declared as this phase's output, so Xcode waits for the stamp before it
# embeds an extension in the app: every part of the app carries the same build.
printf '%s %s\n' "$count" "$commit" > "${SCRIPT_OUTPUT_FILE_0}"

buddy=/usr/libexec/PlistBuddy
current() { "$buddy" -c "Print :$1" "$plist" 2>/dev/null || true; }
[ "$(current CFBundleVersion)" = "$count" ] && [ "$(current DosarCommit)" = "$commit" ] && exit 0

set_value() {
    "$buddy" -c "Delete :$1" "$plist" >/dev/null 2>&1 || true
    "$buddy" -c "Add :$1 $2 $3" "$plist"
}
set_value CFBundleVersion string "$count"
set_value DosarCommit string "$commit"
