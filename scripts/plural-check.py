#!/usr/bin/env python3
"""Every counted string has Romanian plural forms in its String Catalog.

AGENTS.md: every count uses plural variations (1 zi, 2 zile, 20 de zile). The
compiler knows which interpolations are integers: when it builds the app, it
writes every localizable string of each Swift file to a .stringsdata file, with
an integer interpolation as %lld. This check reads those files after a build
and fails for any key with an integer that its catalog doesn't give plural
variations, so "\\(count) lucrări" can't ship as "20 lucrări".

    scripts/plural-check.py <DerivedData>    # after a build (tests/run_tests.sh runs it)
    scripts/plural-check.py --self-test      # the check against built-in examples

An integer that isn't a count (a page number, a step) is listed, with its
reason, in scripts/not-counts.txt.
"""
import json
import os
import re
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Which catalog a target's table lives in. Shared code names its table, "Shared",
# and both the app and the widgets compile it.
CATALOGS = {
    ("DosarCuSina", "Localizable"): "ios/DosarCuSina/Resources/Localizable.xcstrings",
    ("DosarCuSinaWidgets", "Localizable"): "ios/DosarCuSinaWidgets/Localizable.xcstrings",
    ("DosarCuSinaShare", "Localizable"): None,
    ("*", "Shared"): "ios/Shared/Shared.xcstrings",
}
TARGETS = {"DosarCuSina", "DosarCuSinaWidgets", "DosarCuSinaShare"}
INTEGER = re.compile(r"%(\d+\$)?(ll|l|h|hh|q|z|t|j)?[diuoxX]")


def catalog_path(target, table, root):
    path = CATALOGS.get((target, table)) or CATALOGS.get(("*", table))
    return os.path.join(root, path) if path else None


def has_plural(entry):
    """Plural variations for the source language, directly or in a substitution."""
    text = json.dumps(entry.get("localizations", {}))
    return '"plural"' in text


def load_catalog(path, cache):
    if path not in cache:
        cache[path] = json.load(open(path)).get("strings", {}) if path and os.path.exists(path) else {}
    return cache[path]


def not_counts(root):
    path = os.path.join(root, "scripts/not-counts.txt")
    if not os.path.exists(path):
        return set()
    keys = set()
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if line and not line.startswith("#"):
            keys.add(line.split("\t")[0])
    return keys


def target_of(path):
    parts = path.split(os.sep)
    if "Objects-normal" in parts:
        name = parts[parts.index("Objects-normal") - 1]
        if name.endswith(".build"):
            return name[: -len(".build")]
    return None


def check(derived_data, root):
    """Returns the problems found, as lines to print."""
    allowed = not_counts(root)
    cache = {}
    problems = set()
    seen_files = 0
    for folder, _, files in os.walk(derived_data):
        for name in files:
            if not name.endswith(".stringsdata"):
                continue
            path = os.path.join(folder, name)
            target = target_of(path)
            if target not in TARGETS:
                continue
            seen_files += 1
            data = json.load(open(path))
            source = os.path.relpath(data.get("source", name), root) if data.get("source", "").startswith(root) else data.get("source", name)
            for table, entries in data.get("tables", {}).items():
                for entry in entries:
                    key = entry["key"]
                    if not INTEGER.search(key) or key in allowed:
                        continue
                    catalog = catalog_path(target, table, root)
                    found = load_catalog(catalog, cache).get(key) if catalog else None
                    if found is not None and has_plural(found):
                        continue
                    line = entry.get("location", {}).get("startingLine", "?")
                    where = os.path.relpath(catalog, root) if catalog else f"a String Catalog for {target}"
                    problems.add(f"{source}:{line}: \"{key}\" counts something but has no plural variations in {where}.")
    if seen_files == 0:
        problems.add(f"No .stringsdata files under {derived_data}. Build the app first (SWIFT_EMIT_LOC_STRINGS).")
    return sorted(problems)


def self_test():
    with tempfile.TemporaryDirectory() as root:
        os.makedirs(os.path.join(root, "scripts"))
        os.makedirs(os.path.join(root, "ios/DosarCuSina/Resources"))
        os.makedirs(os.path.join(root, "ios/Shared"))
        plural = {"localizations": {"ro": {"variations": {"plural": {"one": {}, "few": {}, "other": {}}}}}}
        json.dump({"strings": {"%lld zile": plural}}, open(os.path.join(root, "ios/Shared/Shared.xcstrings"), "w"))
        json.dump({"strings": {"%lld poze": plural, "%lld lucrări": {}}}, open(os.path.join(root, "ios/DosarCuSina/Resources/Localizable.xcstrings"), "w"))
        open(os.path.join(root, "scripts/not-counts.txt"), "w").write("# reasons\nPagina %lld\tA page number\n")
        objects = os.path.join(root, "DD/Build/Intermediates.noindex/P.build/Debug/DosarCuSina.build/Objects-normal/arm64")
        os.makedirs(objects)

        def write(entries):
            json.dump({"source": os.path.join(root, "ios/DosarCuSina/X.swift"), "tables": entries, "version": 1},
                      open(os.path.join(objects, "X.stringsdata"), "w"))

        cases = [
            ({"Localizable": [{"key": "%lld poze"}], "Shared": [{"key": "%lld zile"}]}, 0, "plural entries pass"),
            ({"Localizable": [{"key": "Pagina %lld"}, {"key": "Gata, %@"}]}, 0, "not-counts and non-integers pass"),
            ({"Localizable": [{"key": "Revizie: %lld lucrări"}]}, 1, "a count with no entry fails"),
            ({"Localizable": [{"key": "%lld lucrări"}]}, 1, "an entry without plurals fails"),
            ({"Localizable": [{"key": "%lld zile"}]}, 1, "the wrong table fails"),
        ]
        failures = 0
        for entries, expected, name in cases:
            write(entries)
            found = check(os.path.join(root, "DD"), root)
            if len(found) != expected:
                print(f"  self-test: {name}: expected {expected} problem(s), got {found}", file=sys.stderr)
                failures += 1
        if failures:
            print("Plural check self-test failed.", file=sys.stderr)
            return 1
        print(f"Plural check self-test passed ({len(cases)} cases).")
        return 0


def main(argv):
    if argv == ["--self-test"]:
        return self_test()
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    problems = check(argv[0], ROOT)
    if problems:
        print("Counted strings without plural forms (1 zi, 2 zile, 20 de zile):", file=sys.stderr)
        for line in problems:
            print("  " + line, file=sys.stderr)
        print("Add plural variations (one, few, other) to the catalog entry, or list the key in scripts/not-counts.txt if it isn't a count.", file=sys.stderr)
        return 1
    print("Plural check passed: every counted string has plural forms.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
