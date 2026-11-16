#!/usr/bin/env python3
"""Every string the code shows is in its String Catalog, and the catalogs keep
nothing the code no longer uses.

AGENTS.md: the words live in String Catalogs (the app's, the widgets', and the
Shared table for code in ios/Shared). When the app builds, the compiler writes
every localizable string of each Swift file to a .stringsdata file; Xcode fills
the catalogs from those files. This check reads the same files after a build and
fails for:

- a string in the code that its catalog doesn't list (text added without it);
- an entry no code uses any more (Xcode would mark it stale), unless the entry is
  managed by hand ("extractionState": "manual": a key the code looks up at run time).

    scripts/catalog-check.py <DerivedData>                   # after a build (tests/run_tests.sh runs it)
    scripts/catalog-check.py <DerivedData> --sync            # bring the catalogs up to date, as Xcode does
    scripts/catalog-check.py <DerivedData> --write-to <dir>  # check; when it fails, put up-to-date copies in <dir>
    scripts/catalog-check.py --self-test                     # the check against built-in examples

--sync runs Xcode's own tool (xcrun xcstringstool sync) on each catalog with the
strings of the targets that compile it, after taking out what no code uses, so the
catalogs come out exactly as Xcode writes them. It never changes wording: a new
entry's text is its key, and every entry already there keeps its forms.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

from string_catalogs import catalog_path, catalogs, load_catalog, relative_source, stringsdata, TARGETS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANUAL = "manual"
SHOWN = 40


def used_strings(derived_data, root):
    """What the code uses, as ({catalog: {key: "file:line"}}, {catalog: {path of each
    .stringsdata with that catalog's table}}, the targets seen)."""
    used = {path: {} for path in catalogs(root)}
    files = {path: set() for path in catalogs(root)}
    seen = set()
    for path, target, data in stringsdata(derived_data):
        seen.add(target)
        source = relative_source(data, root, os.path.basename(path))
        for table, entries in data.get("tables", {}).items():
            catalog = catalog_path(target, table, root)
            if catalog is None:
                continue
            files.setdefault(catalog, set()).add(path)
            for entry in entries:
                line = entry.get("location", {}).get("startingLine", "?")
                used.setdefault(catalog, {}).setdefault(entry["key"], f"{source}:{line}")
    return used, files, seen


def unused(entries, keys):
    """The entries no code uses and nobody manages by hand."""
    return sorted(key for key, entry in entries.items()
                  if key not in keys and entry.get("extractionState") != MANUAL)


def check(derived_data, root):
    """Returns the problems found, as lines to print."""
    used, _, seen = used_strings(derived_data, root)
    problems = []
    if not seen:
        return [f"No .stringsdata files under {derived_data}. Build the app first (SWIFT_EMIT_LOC_STRINGS)."]
    for target in sorted(TARGETS - seen):
        problems.append(f"No strings found for {target}: build all of the app's targets before the check.")
    if problems:
        return problems
    for catalog, keys in sorted(used.items()):
        entries = load_catalog(catalog)
        name = os.path.relpath(catalog, root)
        missing = sorted(key for key in keys if key not in entries)
        stale = unused(entries, keys)
        for key in missing[:SHOWN]:
            problems.append(f"{keys[key]}: \"{key}\" is not in {name}.")
        if len(missing) > SHOWN:
            problems.append(f"… and {len(missing) - SHOWN} more strings not in {name}.")
        for key in stale[:SHOWN]:
            problems.append(f"{name}: \"{key}\" is used by no code.")
        if len(stale) > SHOWN:
            problems.append(f"… and {len(stale) - SHOWN} more entries of {name} used by no code.")
    return problems


def write_catalog(path, document):
    with open(path, "w", encoding="utf-8") as file:
        json.dump(document, file, ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True)
        file.write("\n")


def sync(derived_data, root, destination=None):
    """Brings every catalog up to date: adds what the code uses, takes out what no
    code uses (keeping entries managed by hand), through Xcode's own tool. Writes
    in place, or into `destination` at the same relative paths. Returns the
    (added, removed) counts by catalog."""
    if shutil.which("xcrun") is None:
        raise RuntimeError("--sync needs Xcode's command-line tools (xcrun xcstringstool).")
    used, files, _ = used_strings(derived_data, root)
    counts = {}
    for catalog, table in sorted(catalogs(root).items()):
        keys = used.get(catalog, {})
        document = json.load(open(catalog, encoding="utf-8"))
        entries = document.get("strings", {})
        removed = unused(entries, keys)
        added = [key for key in keys if key not in entries]
        for key in removed:
            del entries[key]
        target = catalog if destination is None else os.path.join(destination, os.path.relpath(catalog, root))
        os.makedirs(os.path.dirname(target), exist_ok=True)
        write_catalog(target, document)
        with tempfile.TemporaryDirectory() as scratch:
            # Only this catalog's table, from only the targets that compile it.
            inputs = []
            for index, path in enumerate(sorted(files.get(catalog, ()))):
                data = json.load(open(path, encoding="utf-8"))
                data["tables"] = {table: data["tables"][table]}
                inputs.append(os.path.join(scratch, f"{index}.stringsdata"))
                with open(inputs[-1], "w", encoding="utf-8") as file:
                    json.dump(data, file, ensure_ascii=False)
            command = ["xcrun", "xcstringstool", "sync", target]
            for path in inputs:
                command += ["--stringsdata", path]
            subprocess.run(command, check=True)
        left = [key for key, entry in json.load(open(target, encoding="utf-8")).get("strings", {}).items()
                if entry.get("extractionState") == "stale"]
        if left:
            raise RuntimeError(f"xcstringstool kept {len(left)} stale entries in {target} the check counts as used, such as \"{left[0]}\".")
        counts[os.path.relpath(catalog, root)] = (len(added), len(removed))
    return counts


def self_test():
    failures = 0
    with tempfile.TemporaryDirectory() as root:
        app = "ios/DosarCuSina/Resources/Localizable.xcstrings"
        widgets = "ios/DosarCuSinaWidgets/Localizable.xcstrings"
        shared = "ios/Shared/Shared.xcstrings"
        for path in (app, widgets, shared):
            os.makedirs(os.path.dirname(os.path.join(root, path)), exist_ok=True)
        source = os.path.join(root, "ios/DosarCuSina/X.swift")
        with open(source, "w") as file:
            file.write("")
        derived = os.path.join(root, "DD/Build/Intermediates.noindex/P.build/Debug")

        def catalog(path, strings):
            write_catalog(os.path.join(root, path), {"sourceLanguage": "ro", "strings": strings, "version": "1.0"})

        def code(target, tables, source_path=source):
            folder = os.path.join(derived, f"{target}.build/Objects-normal/arm64")
            os.makedirs(folder, exist_ok=True)
            location = {"startingColumn": 1, "startingLine": 1, "startingOffset": 0}
            with open(os.path.join(folder, "X.stringsdata"), "w") as file:
                json.dump({"source": source_path, "version": 1,
                           "tables": {name: [{"key": key, "location": location} for key in keys] for name, keys in tables.items()}},
                          file)

        def reset():
            shutil.rmtree(os.path.join(root, "DD"), ignore_errors=True)
            code("DosarCuSina", {"Localizable": ["Salvează"], "Shared": ["Închide"]})
            code("DosarCuSinaWidgets", {"Localizable": ["Gata"], "Shared": ["Renunță"]})
            code("DosarCuSinaShare", {"Localizable": ["Se încarcă…"], "Shared": ["Închide"]})
            catalog(app, {"Salvează": {}})
            catalog(widgets, {"Gata": {}})
            catalog(shared, {"Închide": {}, "Renunță": {}})

        def case(name, expected, change=lambda: None):
            nonlocal failures
            reset()
            change()
            found = check(os.path.join(root, "DD"), root)
            if len(found) != expected:
                print(f"  self-test: {name}: expected {expected} problem(s), got {found}", file=sys.stderr)
                failures += 1

        case("complete catalogs pass; the share extension's own table needs none", 0)
        case("a string missing from its catalog fails", 1,
             lambda: code("DosarCuSina", {"Localizable": ["Salvează", "Adaugă o mașină"], "Shared": ["Închide"]}))
        case("a string in another target's catalog fails", 1,
             lambda: code("DosarCuSinaWidgets", {"Localizable": ["Gata", "Salvează"], "Shared": ["Renunță"]}))
        case("an entry no code uses fails", 1, lambda: catalog(app, {"Salvează": {}, "Vechi": {}}))
        case("an entry Xcode marked stale fails", 1,
             lambda: catalog(app, {"Salvează": {}, "Vechi": {"extractionState": "stale"}}))
        case("an entry managed by hand passes", 0,
             lambda: catalog(app, {"Salvează": {}, "Cheie": {"extractionState": MANUAL}}))
        case("a Shared string one target uses is used", 0,
             lambda: code("DosarCuSina", {"Localizable": ["Salvează"], "Shared": []}))
        case("a file whose source is gone uses nothing", 1,
             lambda: code("DosarCuSina", {"Localizable": ["Salvează", "Șters"], "Shared": ["Închide"]},
                          source_path=os.path.join(root, "ios/DosarCuSina/Gone.swift")))
        case("a target left unbuilt fails", 1,
             lambda: shutil.rmtree(os.path.join(derived, "DosarCuSinaWidgets.build")))

        if shutil.which("xcrun"):
            reset()
            code("DosarCuSina", {"Localizable": ["Salvează", "%lld zile"], "Shared": ["Închide"]})
            plural = {"localizations": {"ro": {"variations": {"plural": {"one": {"stringUnit": {"state": "translated", "value": "o zi"}}}}}}}
            catalog(app, {"Salvează": {}, "%lld zile": plural, "Vechi": plural, "Cheie": {"extractionState": MANUAL}})
            catalog(shared, {"Închide": {}})
            counts = sync(os.path.join(root, "DD"), root)
            synced = load_catalog(os.path.join(root, app))
            if check(os.path.join(root, "DD"), root) or "Vechi" in synced or "Cheie" not in synced \
                    or synced["%lld zile"] != plural or "Renunță" not in load_catalog(os.path.join(root, shared)):
                print(f"  self-test: --sync: the catalogs didn't come out complete: {counts}", file=sys.stderr)
                failures += 1
        else:
            print("  self-test: --sync skipped, no xcrun on this machine.")

    if failures:
        print("Catalog check self-test failed.", file=sys.stderr)
        return 1
    print("Catalog check self-test passed.")
    return 0


def main(argv):
    if argv == ["--self-test"]:
        return self_test()
    if len(argv) == 2 and argv[1] == "--sync":
        for name, (added, removed) in sync(argv[0], ROOT).items():
            print(f"{name}: {added} added, {removed} taken out.")
        return 0
    if len(argv) not in (1, 3) or (len(argv) == 3 and argv[1] != "--write-to"):
        print(__doc__, file=sys.stderr)
        return 2
    problems = check(argv[0], ROOT)
    if not problems:
        print("Catalog check passed: every string in the code is in its String Catalog, and nothing else is.")
        return 0
    print("String Catalogs out of step with the code:", file=sys.stderr)
    for line in problems:
        print("  " + line, file=sys.stderr)
    print("Bring them up to date with Xcode's extraction: build, then run "
          "scripts/catalog-check.py <DerivedData> --sync (wording stays as it is). "
          "An entry the code looks up at run time is marked \"extractionState\": \"manual\".", file=sys.stderr)
    if len(argv) == 3:
        try:
            sync(argv[0], ROOT, argv[2])
            print(f"Up-to-date catalogs are in {argv[2]}, at their paths in the repository.", file=sys.stderr)
        except (RuntimeError, subprocess.CalledProcessError) as error:
            print(f"Couldn't write up-to-date catalogs: {error}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
