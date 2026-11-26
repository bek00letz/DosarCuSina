#!/usr/bin/env bash
# Makes Android's golden archives from iOS golden archives made afresh, so that one failed
# run gives both refreshes. Android's (shared/fixtures/golden/android/) are the iOS golden
# household brought into an empty Android binder and written out again, so a change to what
# an iOS backup holds changes both sets.
#
#   scripts/golden-android-from-ios.sh <ios-dir> <out-dir> [<catalog-dir>]
#
# <ios-dir> is laid out as shared/fixtures/golden/ios/ (household.dosar,
# household-password.dosar, expected/): GoldenArchiveTests' TEST_RUNNER_GOLDEN_ARCHIVES_OUT
# folder, which a failed build-and-test run keeps as golden-archives/. The script copies it
# over shared/fixtures/golden/ios/ in this checkout, has GoldenAndroidArchivesTest write
# Android's golden archives from it (-PwriteGoldenArchives), and leaves them in <out-dir>,
# laid out as shared/fixtures/golden/android/ is. Both folders are what to commit.
#
# Android reads the built-in catalog from shared/catalog/, so a change to the catalog changes
# Android's golden archives too. <catalog-dir>, when given, is the catalog made afresh
# (CatalogExportTests' TEST_RUNNER_CATALOG_OUT folder, which a failed run keeps as catalog/):
# its JSON files replace shared/catalog/'s before Gradle runs, so Android's golden archives
# are made with the catalog that run made. Given the committed iOS golden archives as
# <ios-dir>, the script makes Android's for a change to the catalog alone.
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "Usage: $0 <ios-dir> <out-dir> [<catalog-dir>]" >&2
    exit 2
fi
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRESH="$(cd "$1" && pwd)"
OUT="$2"
CATALOG="${3:-}"
GOLDEN="$REPO_ROOT/shared/fixtures/golden"

for part in household.dosar household-password.dosar expected; do
    if [[ ! -e "$FRESH/$part" ]]; then
        echo "$FRESH has no $part: it isn't a golden archives folder." >&2
        exit 2
    fi
done

# The catalog made afresh, in place of the committed one (its README stays).
if [[ -n "$CATALOG" ]]; then
    CATALOG="$(cd "$CATALOG" && pwd)"
    if ! compgen -G "$CATALOG/*.json" > /dev/null; then
        echo "$CATALOG has no catalog files: it isn't a catalog folder." >&2
        exit 2
    fi
    rm -f "$REPO_ROOT"/shared/catalog/*.json
    cp "$CATALOG"/*.json "$REPO_ROOT/shared/catalog/"
fi

# The iOS archives made afresh, in place of the committed ones (nothing to copy when they
# are the committed ones).
if [[ "$FRESH" != "$(cd "$GOLDEN/ios" && pwd)" ]]; then
    cp "$FRESH/household.dosar" "$FRESH/household-password.dosar" "$GOLDEN/ios/"
    rm -rf "$GOLDEN/ios/expected"
    cp -R "$FRESH/expected" "$GOLDEN/ios/expected"
fi

# Android's, made from them.
(cd "$REPO_ROOT/android" && ./gradlew --quiet :archive:test --tests '*GoldenAndroidArchivesTest*' -PwriteGoldenArchives)

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$GOLDEN/android/household.dosar" "$GOLDEN/android/household-password.dosar" "$OUT/"
cp -R "$GOLDEN/android/expected" "$OUT/expected"
echo "Android's golden archives made afresh in $OUT (copy over shared/fixtures/golden/android/)."
