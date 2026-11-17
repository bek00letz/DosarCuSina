#!/usr/bin/env python3
"""Every counted string has Romanian plural forms in its String Catalog, and every
number a string writes is written the app's way.

AGENTS.md: every count uses plural variations (1 zi, 2 zile, 20 de zile). The
compiler knows which interpolations are integers: when it builds the app, it
writes every localizable string of each Swift file to a .stringsdata file, with
an integer interpolation as %lld. This check reads those files after a build
and fails for any key with an integer that its catalog doesn't give plural
variations, so "\\(count) lucrări" can't ship as "20 lucrări"; and fails for any
catalog entry whose "other" form, the one for 20 and more, counts without „de” between
the number and what it counts („20 de zile”, a substitution's „de cafele”).

It also fails for a String(localized:) or LocalizedStringResource(...) with a number
in it (an integer or a decimal) that doesn't pass the app's locale,
`locale: .dosarDefault`: without it the number is written in the phone's region
(„1,250 de zile” on a phone set to the United States), whatever the app's language.
A Text with a number takes the screen's locale, which every root sets to the app's
(`.dosarLocaleAndCalendar()`), so it needs none.

    scripts/plural-check.py <DerivedData>    # after a build (tests/run_tests.sh runs it)
    scripts/plural-check.py --self-test      # the check against built-in examples

An integer that isn't a count (a page number, a step) is listed, with its
reason, in scripts/not-counts.txt; it is written in the app's locale all the same.
"""
import json
import os
import re
import sys
import tempfile

from string_catalogs import catalog_path, catalogs, load_catalog, relative_source, stringsdata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

INTEGER = re.compile(r"%(\d+\$)?(ll|l|h|hh|q|z|t|j)?[diuoxX]")
# Any number a format writes: an integer, or a decimal (%lf, %f, %g…).
NUMBER = re.compile(r"%(\d+\$)?(ll|l|h|hh|q|z|t|j|L)?[diuoxXfFeEgGaA]")

# The calls that write their numbers with the locale they are given, the phone's when none:
# the literal follows one of these, with only spaces between.
LOCALE_TAKING_CALL = re.compile(r"(?:(?<![A-Za-z0-9_])String|AttributedString)\(\s*localized:\s*$|(?<![A-Za-z0-9_])LocalizedStringResource\(\s*$")
APP_LOCALE = re.compile(r"(?:^|[,(\s])locale:\s*(?:Locale)?\.dosarDefault(?![A-Za-z0-9_])")


def skip_string(text, i):
    """The index after the Swift string literal starting at `i`, interpolations and all."""
    delimiter = '"""' if text.startswith('"""', i) else '"'
    i += len(delimiter)
    while i < len(text):
        if text[i] == "\\":
            if text.startswith("\\(", i):
                i = skip_call(text, i + 1)[0]
                continue
            i += 2
            continue
        if text.startswith(delimiter, i):
            return i + len(delimiter)
        i += 1
    return i


def skip_call(text, i):
    """From the "(" at `i`: the index after its ")", and the code in between with every
    string literal emptied and comments left out."""
    depth = 0
    code = []
    while i < len(text):
        c = text[i]
        if c == '"':
            i = skip_string(text, i)
            code.append('""')
            continue
        if text.startswith("//", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                code.append(c)
                return i + 1, "".join(code)
        code.append(c)
        i += 1
    return i, "".join(code)


def misses_app_locale(text, offset):
    """Whether the literal at `offset` of `text` is a String(localized:) or a
    LocalizedStringResource(...) that doesn't pass `locale: .dosarDefault`. Nil when the
    literal is something else (a Text, a key resolved by the screen)."""
    before = text[:offset]
    match = LOCALE_TAKING_CALL.search(before)
    if not match:
        return None
    _, code = skip_call(text, before.rfind("(", match.start()))
    return not APP_LOCALE.search(code)


def offset_of(text, line, column):
    """The offset of a 1-based line and column."""
    lines = text.split("\n")
    if line < 1 or line > len(lines):
        return None
    return sum(len(l) + 1 for l in lines[: line - 1]) + max(column - 1, 0)


def locale_problem(data, entry, root, source, sources):
    """A line to print when a string with a number in it doesn't name the app's locale."""
    key = entry["key"]
    if not NUMBER.search(key):
        return None
    location = entry.get("location", {})
    line, column = location.get("startingLine"), location.get("startingColumn")
    if line is None or column is None:
        return None
    path = os.path.join(root, source) if not os.path.isabs(source) else source
    if path not in sources:
        sources[path] = open(path, encoding="utf-8").read() if os.path.exists(path) else None
    text = sources[path]
    offset = offset_of(text, line, column) if text is not None else None
    if offset is None or not misses_app_locale(text, offset):
        return None
    return (f"{source}:{line}: \"{key}\" writes its number in the phone's region: pass `locale: .dosarDefault` "
            "(after `table:`, before `comment:`), so it reads 1.250 on every phone.")


def has_plural(entry):
    """Plural variations for the source language, directly or in a substitution."""
    text = json.dumps(entry.get("localizations", {}))
    return '"plural"' in text


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


# In a counted string's "other" form (20 de zile, 1.250 de cafele: Romanian's 20-99, 100,
# 120 and on), the number and what it counts: a placeholder followed by a word, or a
# substitution's own words, which follow the number they count.
NUMBER_THEN_WORD = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|arg)[ \u00a0]+([^\W\d_][\w-]*)")
SUBSTITUTION_WORD = re.compile(r"^[ \u00a0]*([^\W\d_][\w-]*)")


def other_forms(entry):
    """The source language's "other" plural forms of a catalog entry, as (where, its words, whether
    the words follow a number): the string's own, and each substitution's."""
    ro = entry.get("localizations", {}).get("ro", {})
    found = []
    other = ro.get("variations", {}).get("plural", {}).get("other", {}).get("stringUnit", {}).get("value")
    if other is not None:
        found.append(("", other, False))
    for name, substitution in ro.get("substitutions", {}).items():
        value = substitution.get("variations", {}).get("plural", {}).get("other", {}).get("stringUnit", {}).get("value")
        if value is not None:
            found.append((name, value, True))
    return found


def missing_de(root):
    """Counted strings whose "other" form counts without „de”: „20 zile”, „1.250 cafele”.
    Returns the problems found, as lines to print."""
    problems = []
    for path in sorted(catalogs(root)):
        for key, entry in load_catalog(path).items():
            for name, words, follows_number in other_forms(entry):
                if follows_number and "%" not in words:
                    match = SUBSTITUTION_WORD.match(words)
                    word = match.group(1) if match else None
                else:
                    match = NUMBER_THEN_WORD.search(words)
                    word = match.group(1) if match else None
                if word is not None and word != "de":
                    where = os.path.relpath(path, root)
                    part = f" (its „{name}”)" if name else ""
                    problems.append(f"{where}: \"{key}\"{part} counts 20 and more as „{words}”: put „de” between the number and „{word}”.")
    return problems


def check(derived_data, root):
    """Returns the problems found, as lines to print."""
    allowed = not_counts(root)
    cache = {}
    sources = {}
    problems = set(missing_de(root))
    seen_files = 0
    for path, target, data in stringsdata(derived_data):
        seen_files += 1
        source = relative_source(data, root, os.path.basename(path))
        for table, entries in data.get("tables", {}).items():
            for entry in entries:
                key = entry["key"]
                problem = locale_problem(data, entry, root, source, sources)
                if problem:
                    problems.add(problem)
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
        # The source the entries point at: line 1 is a Text, which takes the screen's locale.
        source_lines = [
            'Text("\\(n) poze")',
            'let a = String(localized: "\\(n) poze", locale: .dosarDefault, comment: "Counts.")',
            'let b = String(localized: "\\(n) poze", comment: "Counts.")',
            'let c = String(localized: "\\(n) zile", table: "Shared", locale: .dosarDefault, comment: "Has (parentheses) and \\(f(x)) inside.")',
            'let d = String(',
            '    localized: "\\(n) poze",',
            '    comment: "Split over lines, no locale."',
            ')',
            'let e = LocalizedStringResource("Pagina \\(n)", comment: "A resource, no locale.")',
            'let f = String(localized: "Gata, \\(name)", comment: "No number.")',
            'let g = String(localized: "\\(n) poze", locale: Locale.current, comment: "The phone\'s locale.")',
        ]
        open(os.path.join(root, "ios/DosarCuSina/X.swift"), "w").write("\n".join(source_lines) + "\n")

        def at(key, line):
            column = source_lines[line - 1].index('"') + 1
            return {"key": key, "location": {"startingLine": line, "startingColumn": column}}

        def write(entries):
            json.dump({"source": os.path.join(root, "ios/DosarCuSina/X.swift"), "tables": entries, "version": 1},
                      open(os.path.join(objects, "X.stringsdata"), "w"))

        cases = [
            ({"Localizable": [{"key": "%lld poze"}], "Shared": [{"key": "%lld zile"}]}, 0, "plural entries pass"),
            ({"Localizable": [{"key": "Pagina %lld"}, {"key": "Gata, %@"}]}, 0, "not-counts and non-integers pass"),
            ({"Localizable": [{"key": "Revizie: %lld lucrări"}]}, 1, "a count with no entry fails"),
            ({"Localizable": [{"key": "%lld lucrări"}]}, 1, "an entry without plurals fails"),
            ({"Localizable": [{"key": "%lld zile"}]}, 1, "the wrong table fails"),
            ({"Localizable": [at("%lld poze", 1)]}, 0, "a Text takes the screen's locale"),
            ({"Localizable": [at("%lld poze", 2)]}, 0, "String(localized:) with the app's locale passes"),
            ({"Localizable": [at("%lld poze", 3)]}, 1, "String(localized:) with a number and no locale fails"),
            ({"Shared": [at("%lld zile", 4)]}, 0, "the locale after the table, with parentheses in the comment, passes"),
            ({"Localizable": [at("%lld poze", 6)]}, 1, "a call split over lines without the locale fails"),
            ({"Localizable": [at("Pagina %lld", 9)]}, 1, "a LocalizedStringResource without the locale fails, a page number too"),
            ({"Localizable": [at("Gata, %@", 10)]}, 0, "no number, no locale needed"),
            ({"Localizable": [at("%lld poze", 11)]}, 1, "the phone's locale fails"),
        ]
        failures = 0
        for entries, expected, name in cases:
            write(entries)
            found = check(os.path.join(root, "DD"), root)
            if len(found) != expected:
                print(f"  self-test: {name}: expected {expected} problem(s), got {found}", file=sys.stderr)
                failures += 1
        # „de” in the "other" form, from 20 on: the string's own and a substitution's.
        def forms(one, few, other):
            return {"one": {"stringUnit": {"value": one}}, "few": {"stringUnit": {"value": few}}, "other": {"stringUnit": {"value": other}}}
        de_cases = [
            ({"localizations": {"ro": {"variations": {"plural": forms("o zi", "%lld zile", "%lld de zile")}}}}, 0, "„20 de zile” passes"),
            ({"localizations": {"ro": {"variations": {"plural": forms("o zi", "%lld zile", "%lld zile")}}}}, 1, "„20 zile” fails"),
            ({"localizations": {"ro": {"stringUnit": {"value": "%1$@ %#@u@"}, "substitutions": {"u": {"variations": {"plural": forms("cafea", "cafele", "de cafele")}}}}}}, 0,
             "a substitution's „de cafele” passes"),
            ({"localizations": {"ro": {"stringUnit": {"value": "%1$@ %#@u@"}, "substitutions": {"u": {"variations": {"plural": forms("cafea", "cafele", "cafele")}}}}}}, 1,
             "a substitution's „cafele” fails"),
        ]
        for entry, expected, name in de_cases:
            json.dump({"strings": {"%lld x": entry}}, open(os.path.join(root, "ios/Shared/Shared.xcstrings"), "w"))
            found = missing_de(root)
            if len(found) != expected:
                print(f"  self-test: {name}: expected {expected} problem(s), got {found}", file=sys.stderr)
                failures += 1
        if failures:
            print("Plural check self-test failed.", file=sys.stderr)
            return 1
        print(f"Plural check self-test passed ({len(cases) + len(de_cases)} cases).")
        return 0


def main(argv):
    if argv == ["--self-test"]:
        return self_test()
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    problems = check(argv[0], ROOT)
    if problems:
        print("Counted strings without plural forms, without „de” from 20 on (1 zi, 2 zile, 20 de zile), or numbers written in the phone's region:", file=sys.stderr)
        for line in problems:
            print("  " + line, file=sys.stderr)
        print("Add plural variations (one, few, other) to the catalog entry, or list the key in scripts/not-counts.txt if it isn't a count. A String(localized:) with a number passes locale: .dosarDefault.", file=sys.stderr)
        return 1
    print("Plural check passed: every counted string has plural forms, and every number is written in the app's locale.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
