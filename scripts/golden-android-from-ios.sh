#!/usr/bin/env bash
# Makes Android's golden archives from iOS golden archives made afresh, so that one failed
# run gives both refreshes. Android's (shared/fixtures/golden/android/) are the iOS golden
# household brought into an empty Android binder and written out again, so a change to what
# an iOS backup holds changes both sets.
#
#   scripts/golden-android-from-ios.sh <ios-dir> <out-dir>
#
# <ios-dir> is laid out as shared/fixtures/golden/ios/ (household.dosar,
# household-password.dosar, expected/): GoldenArchiveTests' TEST_RUNNER_GOLDEN_ARCHIVES_OUT
# folder, which a failed build-and-test run keeps as golden-archives/. The script copies it
# over shared/fixtures/golden/ios/ in this checkout, has GoldenAndroidArchivesTest write
# Android's golden archives from it (-PwriteGoldenArchives), and leaves them in <out-dir>,
# laid out as shared/fixtures/golden/android/ is. Both folders are what to commit.
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <ios-dir> <out-dir>" >&2
    exit 2
fi
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRESH="$(cd "$1" && pwd)"
OUT="$2"
GOLDEN="$REPO_ROOT/shared/fixtures/golden"

for part in household.dosar household-password.dosar expected; do
    if [[ ! -e "$FRESH/$part" ]]; then
        echo "$FRESH has no $part: it isn't a golden archives folder." >&2
        exit 2
    fi
done

# The iOS archives made afresh, in place of the committed ones.
cp "$FRESH/household.dosar" "$FRESH/household-password.dosar" "$GOLDEN/ios/"
rm -rf "$GOLDEN/ios/expected"
cp -R "$FRESH/expected" "$GOLDEN/ios/expected"

# Android's, made from them.
(cd "$REPO_ROOT/android" && ./gradlew --quiet :archive:test --tests '*GoldenAndroidArchivesTest*' -PwriteGoldenArchives)

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$GOLDEN/android/household.dosar" "$GOLDEN/android/household-password.dosar" "$OUT/"
cp -R "$GOLDEN/android/expected" "$OUT/expected"
echo "Android's golden archives made afresh in $OUT (copy over shared/fixtures/golden/android/)."
