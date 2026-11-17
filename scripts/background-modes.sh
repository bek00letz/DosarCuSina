#!/bin/sh
# Keeps the built app's "remote-notification" background mode only in a build that syncs
# with iCloud, the one thing it is for: iCloud's mirroring wakes the app with a silent push
# when another device changed the binder.
#
# The rule is PersistenceController.syncIsBuiltIn's, read from the same build setting the
# code is compiled with:
#   a development build (DEBUG)                      keeps it, as it syncs
#   a release build (TestFlight, the App Store)      keeps it only once sync ships there,
#                                                    DOSAR_SYNC_SHIPS_IN_RELEASE_BUILDS = YES
#                                                    (compiled as SYNC_SHIPS_IN_RELEASE_BUILDS_YES,
#                                                    PersistenceController.syncShipsInReleaseBuilds)
# So turning sync on for release builds brings the mode back by itself, and a release build
# never asks to be woken for a sync it doesn't do.
#
# Xcode runs it in the app's last build phase, after the Info.plist is generated and before
# signing. SupportingFiles/DosarCuSina-Info.plist lists the mode; this only ever removes it.
set -eu

plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
[ -f "$plist" ] || exit 0

case " ${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-} " in
    *" DEBUG "* | *" SYNC_SHIPS_IN_RELEASE_BUILDS_YES "*) exit 0 ;;
esac

buddy=/usr/libexec/PlistBuddy
index=0
while mode=$("$buddy" -c "Print :UIBackgroundModes:$index" "$plist" 2>/dev/null); do
    if [ "$mode" = remote-notification ]; then
        "$buddy" -c "Delete :UIBackgroundModes:$index" "$plist"
    else
        index=$((index + 1))
    fi
done
