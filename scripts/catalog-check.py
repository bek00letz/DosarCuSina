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
  managed by hand ("extractionState": "manual": a key the code looks up at run time);
- a catalog not written the way Xcode writes it, so that building in Xcode never changes
  the file: Xcode's own sync (xcrun xcstringstool sync), no string that only a #Preview
  uses (Xcode leaves those out), the entries in Xcode's order (Finder's order,
  localizedStandardCompare, in English: scripts/xcode-catalog-order.swift) and no newline
  at the end. It needs Xcode's tools and is skipped without them.

A development build and a release build must find the same strings, or each would
rewrite the catalog the other wrote: the release build's job runs this check too.

    scripts/catalog-check.py <DerivedData>                   # after a build (tests/run_tests.sh runs it)
    scripts/catalog-check.py <DerivedData> --sync            # bring the catalogs up to date, as Xcode does
    scripts/catalog-check.py <DerivedData> --write-to <dir>  # check; when it fails, put up-to-date copies in <dir>
    scripts/catalog-check.py --self-test                     # the check against built-in examples

--sync runs Xcode's own tool (xcrun xcstringstool sync) on each catalog with the
strings of the targets that compile it, after taking out what no code uses, and puts
the entries in Xcode's order, so the catalogs come out exactly as Xcode's build writes
them (checked against a build in the Xcode app). It never changes wording: a new
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
ORDER_HELPER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "xcode-catalog-order.swift")
MANUAL = "manual"
SHOWN = 40
PREVIEW = "#Preview"


class Sources:
    """The lines of the Swift files strings come from, read once."""

    def __init__(self):
        self.lines = {}

    def in_preview(self, data, entry):
        """Whether `entry` was found in a #Preview, which Xcode leaves out of the catalog:
        the compiler places a preview's strings on the line of its #Preview macro."""
        source = data.get("source")
        line = entry.get("location", {}).get("startingLine")
        if not source or not line:
            return False
        if source not in self.lines:
            try:
                self.lines[source] = open(source, encoding="utf-8").read().split("\n")
            except OSError:
                self.lines[source] = []
        lines = self.lines[source]
        return 0 < line <= len(lines) and lines[line - 1].lstrip().startswith(PREVIEW)


# --- The form Xcode writes ----------------------------------------------------

def parse_catalog(text):
    """A catalog's text as (lines before the entries, [(key, lines)], lines after), read
    line by line so each entry keeps exactly the text it has."""
    lines = text.split("\n")
    start = lines.index('  "strings" : {')
    end = next(i for i in range(start + 1, len(lines)) if lines[i] in ("  },", "  }"))
    blocks = []
    for line in lines[start + 1:end]:
        if line.startswith('    "'):
            key, _ = json.JSONDecoder().raw_decode(line, 4)
            blocks.append((key, [line]))
        else:
            blocks[-1][1].append(line)
    return lines[:start + 1], blocks, lines[end:]


def render_catalog(head, blocks, tail):
    """The catalog's text from its parts, as Xcode writes it: an entry with nothing in it
    as an empty pair of lines, commas between entries, no newline at the end."""
    body = []
    for index, (key, lines) in enumerate(blocks):
        lines = [line.rstrip(",") if n == len(lines) - 1 else line for n, line in enumerate(lines)]
        if len(lines) == 1 and lines[0].endswith("{}"):
            lines = [lines[0][:-1], "", "    }"]
        if index < len(blocks) - 1:
            lines[-1] += ","
        body += lines
    return "\n".join(head + body + tail).rstrip("\n")


_order_binary = None


def xcode_order(keys):
    """`keys` in the order Xcode writes a catalog's entries, by Foundation's own comparison."""
    global _order_binary
    if _order_binary is None:
        scratch = tempfile.mkdtemp()
        _order_binary = os.path.join(scratch, "order")
        subprocess.run(["xcrun", "swiftc", "-O", ORDER_HELPER, "-o", _order_binary], check=True)
    lines = "\n".join(json.dumps(key, ensure_ascii=False) for key in keys) + "\n"
    out = subprocess.run([_order_binary], input=lines, capture_output=True, text=True, check=True).stdout
    return [json.loads(line) for line in out.splitlines() if line]


def xcode_form(text, without=()):
    """`text` as Xcode writes it, leaving out the entries named in `without`."""
    head, blocks, tail = parse_catalog(text)
    by_key = {key: lines for key, lines in blocks if key not in without}
    return render_catalog(head, [(key, by_key[key]) for key in xcode_order(list(by_key))], tail)


def has_xcode_tools():
    return shutil.which("xcrun") is not None


def used_strings(derived_data, root, sources=None):
    """What the code uses, as ({catalog: {key: "file:line"}}, {catalog: {path of each
    .stringsdata with that catalog's table}}, the targets seen). A string only a #Preview
    uses isn't used: Xcode leaves it out."""
    sources = sources or Sources()
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
                if sources.in_preview(data, entry):
                    continue
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
    code uses (keeping entries managed by hand), through Xcode's own tool, and writes
    it in the form Xcode writes. Writes in place, or into `destination` at the same
    relative paths. Returns the (added, removed) counts by catalog."""
    if not has_xcode_tools():
        raise RuntimeError("--sync needs Xcode's command-line tools (xcrun xcstringstool, xcrun swiftc).")
    sources = Sources()
    used, files, _ = used_strings(derived_data, root, sources)
    counts = {}
    for catalog, table in sorted(catalogs(root).items()):
        keys = used.get(catalog, {})
        text = open(catalog, encoding="utf-8").read()
        entries = json.loads(text).get("strings", {})
        removed = unused(entries, keys)
        added = [key for key in keys if key not in entries]
        target = catalog if destination is None else os.path.join(destination, os.path.relpath(catalog, root))
        os.makedirs(os.path.dirname(target), exist_ok=True)
        head, blocks, tail = parse_catalog(text)
        with open(target, "w", encoding="utf-8") as file:
            file.write(render_catalog(head, [(key, lines) for key, lines in blocks if key not in removed], tail))
        with tempfile.TemporaryDirectory() as scratch:
            # Only this catalog's table, from only the targets that compile it, without
            # what only a #Preview uses.
            inputs = []
            for index, path in enumerate(sorted(files.get(catalog, ()))):
                data = json.load(open(path, encoding="utf-8"))
                data["tables"] = {table: [entry for entry in data["tables"][table] if not sources.in_preview(data, entry)]}
                inputs.append(os.path.join(scratch, f"{index}.stringsdata"))
                with open(inputs[-1], "w", encoding="utf-8") as file:
                    json.dump(data, file, ensure_ascii=False)
            command = ["xcrun", "xcstringstool", "sync", target]
            for path in inputs:
                command += ["--stringsdata", path]
            subprocess.run(command, check=True)
        synced = open(target, encoding="utf-8").read()
        left = [key for key, entry in json.loads(synced).get("strings", {}).items()
                if entry.get("extractionState") == "stale"]
        if left:
            raise RuntimeError(f"xcstringstool kept {len(left)} stale entries in {target} the check counts as used, such as \"{left[0]}\".")
        with open(target, "w", encoding="utf-8") as file:
            file.write(xcode_form(synced))
        counts[os.path.relpath(catalog, root)] = (len(added), len(removed))
    return counts


def form_problems(derived_data, root):
    """The catalogs not written as Xcode writes them, from this build's strings."""
    if not has_xcode_tools():
        return []
    problems = []
    with tempfile.TemporaryDirectory() as scratch:
        sync(derived_data, root, scratch)
        for catalog in sorted(catalogs(root)):
            name = os.path.relpath(catalog, root)
            if open(catalog, encoding="utf-8").read() != open(os.path.join(scratch, name), encoding="utf-8").read():
                problems.append(f"{name} isn't written the way Xcode writes it (its entries' order, their comments, its spacing): "
                                "building in Xcode would change it.")
    return problems


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

        if has_xcode_tools():
            # Xcode's order: „ before %, numbers by value, case and accents aside; no newline at the end.
            reset()
            catalog(app, {"Salvează": {}, "10 zile": {}, "2 zile": {}, "„%@”": {}, "%@": {}, "adaugă": {}, "Ă": {}})
            ordered = list(json.loads(xcode_form(open(os.path.join(root, app), encoding="utf-8").read()))["strings"])
            if ordered != ["„%@”", "%@", "2 zile", "10 zile", "Ă", "adaugă", "Salvează"] \
                    or xcode_form(open(os.path.join(root, app), encoding="utf-8").read()).endswith("\n"):
                print(f"  self-test: Xcode's order: got {ordered}", file=sys.stderr)
                failures += 1
            # A string only a #Preview uses is left out, as Xcode leaves it out.
            reset()
            with open(source, "w") as file:
                file.write("Text(\"Salvează\")\n#Preview {\n    Text(\"Doar aici\")\n}\n")
            folder = os.path.join(derived, "DosarCuSina.build/Objects-normal/arm64")
            with open(os.path.join(folder, "X.stringsdata"), "w") as file:
                at = lambda line: {"startingColumn": 1, "startingLine": line, "startingOffset": 0}
                json.dump({"source": source, "version": 1, "tables": {
                    "Localizable": [{"key": "Salvează", "location": at(1)}, {"key": "Doar aici", "location": at(2)}],
                    "Shared": [{"key": "Închide", "location": at(1)}]}}, file)
            if check(os.path.join(root, "DD"), root):
                print("  self-test: a string only a #Preview uses still counts as used", file=sys.stderr)
                failures += 1
            with open(source, "w") as file:
                file.write("")
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
        problems = form_problems(argv[0], ROOT)
    if not problems:
        print("Catalog check passed: every string in the code is in its String Catalog, nothing else is, "
              "and each is written the way Xcode writes it.")
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
