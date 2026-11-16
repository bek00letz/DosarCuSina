"""Where the app's localizable strings live: which String Catalog holds which
table of which target, and the strings a build found in the code.

The one map of targets, tables and catalogs, read by scripts/plural-check.py and
scripts/catalog-check.py. The compiler writes every localizable string of each
Swift file to a .stringsdata file when it builds (SWIFT_EMIT_LOC_STRINGS), with an
integer interpolation as %lld; Xcode fills the catalogs from those files, and the
checks read the same files.
"""
import json
import os

# Which catalog a target's table lives in. Shared code names its table, "Shared",
# and the app, the widgets and the share extension all compile it. Code in
# ios/Shared that names no table lands in the default table (Localizable) of
# whichever target compiles it. The share extension has no catalog of its own:
# its words are in the Shared table (ShareConfirmation), and what it compiles in
# its default table (a shared component's default label) is Romanian already.
CATALOGS = {
    ("DosarCuSina", "Localizable"): "ios/DosarCuSina/Resources/Localizable.xcstrings",
    ("DosarCuSinaWidgets", "Localizable"): "ios/DosarCuSinaWidgets/Localizable.xcstrings",
    ("DosarCuSinaShare", "Localizable"): None,
    ("*", "Shared"): "ios/Shared/Shared.xcstrings",
}
TARGETS = {"DosarCuSina", "DosarCuSinaWidgets", "DosarCuSinaShare"}


def catalog_path(target, table, root):
    """The catalog a target's table goes into, or None when it has none."""
    path = CATALOGS[(target, table)] if (target, table) in CATALOGS else CATALOGS.get(("*", table))
    return os.path.join(root, path) if path else None


def catalogs(root):
    """Every catalog, as {absolute path: its table name}."""
    found = {}
    for (_, table), path in CATALOGS.items():
        if path:
            found[os.path.join(root, path)] = table
    return found


def target_of(path):
    """The target a .stringsdata file was compiled for, from its DerivedData path."""
    parts = path.split(os.sep)
    if "Objects-normal" in parts:
        name = parts[parts.index("Objects-normal") - 1]
        if name.endswith(".build"):
            return name[: -len(".build")]
    return None


def stringsdata(derived_data):
    """Every .stringsdata file of the app's targets under a DerivedData folder, as
    (path, target, its contents). A file whose Swift source is gone (a DerivedData
    kept from before a file was deleted or moved) is left out: no code uses it."""
    for folder, _, files in os.walk(derived_data):
        for name in sorted(files):
            if not name.endswith(".stringsdata"):
                continue
            path = os.path.join(folder, name)
            target = target_of(path)
            if target not in TARGETS:
                continue
            data = json.load(open(path, encoding="utf-8"))
            source = data.get("source")
            if source and not os.path.exists(source):
                continue
            yield path, target, data


def relative_source(data, root, fallback):
    source = data.get("source", fallback)
    return os.path.relpath(source, root) if source.startswith(root) else source


def load_catalog(path, cache=None):
    """A catalog's entries by key; empty when there is no catalog."""
    if cache is not None and path in cache:
        return cache[path]
    entries = json.load(open(path, encoding="utf-8")).get("strings", {}) if path and os.path.exists(path) else {}
    if cache is not None:
        cache[path] = entries
    return entries
