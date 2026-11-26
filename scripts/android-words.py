#!/usr/bin/env python3
"""Android's words, generated from the iOS String Catalogs: one source of truth, so the
two apps' words can't drift (docs/DECISIONS.md, 2026-11-26).

Every entry of every catalog Android reads (scripts/string_catalogs.py, ANDROID_BOOKS: the
app's, the Shared table and the widgets') becomes:

- a resource in android/app/src/main/res/values/strings.xml, for the screens: a <string>, or
  a <plurals> with Romanian's CLDR categories (one, few, other) as the catalog holds them;
- an entry of android/core/src/main/resources/com/ar/dosarcusina/core/wording/words.json, the
  same words for the pure Kotlin modules, so core's wording engines (core.wording) write
  Romanian on the JVM and on the phone alike, and are tested on the JVM.

Both are written from the same reading of the catalogs, never edited by hand. The only words
of Android's own are the short list in shared/strings/android-differs.json: an iOS key, the
words Android says instead, and why. An entry there whose key no catalog has any more fails.

How a catalog's entry becomes Android's:

- its text is the Romanian the catalog holds (its value, else its key: Romanian is the source
  language);
- a plural variation becomes Android plurals; a substitution (`%#@lei@`) becomes plurals too,
  chosen by the argument it names (argNum), each form the whole sentence with that form in it;
  a category the catalog leaves out reads as its "other", as iOS reads it;
- a format specifier becomes Android's, numbered by its place: `%@` is `%N$s`, `%lld` is
  `%N$,d` (an integer written with the locale's grouping, as iOS's `String(localized:locale:)`
  writes it: „1.250 de zile”), positional ones (`%2$@`) keep their number;
- a key the code looks up at run time (`"extractionState": "manual"`) is kept like any other:
  every entry of a catalog is generated, whoever wrote it.

Resource names: `<book>_<slug>_<digest>`, from the key alone, so a word's name never changes
unless its key does: the book (app, shared, widgets), the key's first words folded to ASCII
(`%@` as „x”, `%lld` as „n”; at most 32 letters, whole words), and the first six hex digits
of the SHA-256 of the key's UTF-8. „%lld zile” in the Shared table is `shared_n_zile_65ffe0`.

    scripts/android-words.py                      # write both files afresh
    scripts/android-words.py --check              # fail when a committed file is out of date
    scripts/android-words.py --check --write-to <dir>   # and leave fresh copies in <dir>
    scripts/android-words.py --self-test          # the rules against built-in examples
"""
import hashlib
import json
import os
import re
import sys
import tempfile
import unicodedata

from string_catalogs import android_books, load_catalog

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIFFERS = "shared/strings/android-differs.json"
STRINGS_XML = "android/app/src/main/res/values/strings.xml"
WORDS_JSON = "android/core/src/main/resources/com/ar/dosarcusina/core/wording/words.json"
OUTPUTS = (STRINGS_XML, WORDS_JSON)
SCRIPT = "scripts/android-words.py"

# Romanian's plural categories (CLDR), in the order Android lists quantities.
CATEGORIES = ("one", "few", "other")
SLUG_LETTERS = 32
DIGEST_DIGITS = 6
# iOS writes an integer in a localized string with the app's locale, grouped („1.250”).
INTEGER_FLAGS = ","

# A specifier in a catalog's text: `%@`, `%lld` (or `%ld`, `%d`), positional or not, and `%%`.
SPECIFIER = re.compile(r"%(?:(\d+)\$)?(@|lld|ld|d|%)")
SUBSTITUTION = re.compile(r"%#@([A-Za-z0-9_]+)@")
TYPES = {"@": "text", "lld": "count", "ld": "count", "d": "count"}


class WordsError(Exception):
    """A catalog entry or an Android word that can't be generated, said in plain words."""


# --- Names --------------------------------------------------------------------


def slug(key):
    """The key's first words, folded to ASCII, lowercase, joined by „_”: „Expiră pe %@” is
    „expira_pe_x”. A specifier is „x” (text) or „n” (a number); nothing readable is „text”."""
    marked = SPECIFIER.sub(lambda m: " n " if TYPES.get(m.group(2)) == "count" else " x ", key)
    folded = "".join(c for c in unicodedata.normalize("NFKD", marked) if not unicodedata.combining(c))
    words = re.findall(r"[a-z0-9]+", folded.lower())
    picked, length = [], 0
    for word in words:
        word = word[:SLUG_LETTERS]
        extra = len(word) + (1 if picked else 0)
        if picked and length + extra > SLUG_LETTERS:
            break
        picked.append(word)
        length += extra
    return "_".join(picked) or "text"


def digest(key):
    return hashlib.sha256(key.encode("utf-8")).hexdigest()[:DIGEST_DIGITS]


def resource_name(book, key):
    """The one name of `key` in `book`, from the key alone."""
    return f"{book}_{slug(key)}_{digest(key)}"


# --- Templates ----------------------------------------------------------------


def parts(text, where):
    """`text` as [str | (argument number, type)], numbering `%@` and `%lld` by their place.
    Fails for a specifier Android's words can't carry yet and for numbered and unnumbered
    specifiers mixed in one text."""
    if SUBSTITUTION.search(text):
        raise WordsError(f"{where}: a substitution („{SUBSTITUTION.search(text).group(0)}”) where none is expected")
    pieces, at, next_number, kinds = [], 0, 1, set()
    for match in SPECIFIER.finditer(text):
        pieces.append(text[at:match.start()])
        at = match.end()
        if match.group(2) == "%":
            raise WordsError(f"{where}: a literal „%” isn't carried to Android yet; teach {SCRIPT} how")
        if match.group(1):
            kinds.add("numbered")
            number = int(match.group(1))
        else:
            kinds.add("in order")
            number = next_number
            next_number += 1
        pieces.append((number, TYPES[match.group(2)]))
    pieces.append(text[at:])
    stray = "".join(piece for piece in pieces if isinstance(piece, str))
    if "%" in stray:
        raise WordsError(f"{where}: a „%” that is no specifier Android's words know: {text!r}")
    if len(kinds) > 1:
        raise WordsError(f"{where}: numbered and unnumbered specifiers mixed: {text!r}")
    return [piece for piece in pieces if piece != ""]


def signature(key, where):
    """The arguments a key takes, in order: "text" or "count"."""
    numbered = {}
    for piece in parts(key, where):
        if isinstance(piece, tuple):
            numbered[piece[0]] = piece[1]
    if sorted(numbered) != list(range(1, len(numbered) + 1)):
        raise WordsError(f"{where}: its arguments aren't numbered 1 to {len(numbered)}")
    return [numbered[n] for n in sorted(numbered)]


def android_template(text, args, where):
    """`text` with Android's specifiers, checked against the key's arguments."""
    out = []
    for piece in parts(text, where):
        if isinstance(piece, str):
            out.append(piece)
            continue
        number, kind = piece
        if number > len(args) or args[number - 1] != kind:
            raise WordsError(f"{where}: argument {number} is a {kind}, but the key's arguments are {args}")
        out.append(f"%{number}$s" if kind == "text" else f"%{number}${INTEGER_FLAGS}d")
    return "".join(out)


# --- Reading a catalog's entry ---------------------------------------------------


def plural_forms(variations, where):
    """A plural variation's forms by category, a missing one read as „other”, as iOS does."""
    plural = variations.get("plural")
    if set(variations) != {"plural"} or not plural:
        raise WordsError(f"{where}: varies by {sorted(variations)}, and Android's words know only plurals")
    unknown = set(plural) - set(CATEGORIES) - {"zero", "two", "many"}
    if unknown or "other" not in plural:
        raise WordsError(f"{where}: plural forms {sorted(plural)} aren't Romanian's one, few and other")
    return {category: plural.get(category, plural["other"])["stringUnit"]["value"] for category in CATEGORIES}


def romanian(key, entry, where):
    """What the catalog says for `key`: ("text", template) or ("plural", counted argument,
    {category: template}), in the catalog's own specifiers."""
    local = entry.get("localizations", {}).get("ro", {})
    if "substitutions" in local:
        substitutions = local["substitutions"]
        if len(substitutions) != 1:
            raise WordsError(f"{where}: {len(substitutions)} substitutions; Android plurals vary by one number")
        (name, substitution), = substitutions.items()
        outer = local["stringUnit"]["value"]
        token = f"%#@{name}@"
        if outer.count(token) != 1:
            raise WordsError(f"{where}: „{token}” isn't in its text exactly once")
        forms = plural_forms(substitution.get("variations", {}), where)
        for category, form in forms.items():
            if "%" in form:
                raise WordsError(f"{where}: its {category} form has a specifier inside the substitution")
        return ("plural", int(substitution["argNum"]), {c: outer.replace(token, f) for c, f in forms.items()})
    if "variations" in local:
        args = signature(key, where)
        if len(args) != 1 or args[0] != "count":
            raise WordsError(f"{where}: plural forms on a key whose arguments are {args}; use a substitution")
        return ("plural", 1, plural_forms(local["variations"], where))
    if "stringUnit" in local:
        return ("text", local["stringUnit"]["value"])
    return ("text", key)


# --- Android's own words -----------------------------------------------------------


def read_differs(path):
    """shared/strings/android-differs.json as {(book, key): (Android's words, why)}."""
    if not os.path.exists(path):
        return {}
    document = json.load(open(path, encoding="utf-8"))
    found = {}
    for index, item in enumerate(document.get("words", [])):
        where = f"{DIFFERS} #{index + 1}"
        book, key, words, why = item.get("book"), item.get("key"), item.get("android"), item.get("why")
        if not book or key is None or words is None or not (why or "").strip():
            raise WordsError(f"{where}: needs a book, a key, Android's words and why")
        if (book, key) in found:
            raise WordsError(f"{where}: „{key}” is listed twice")
        found[(book, key)] = (words, why)
    return found


def with_differs(said, android, where):
    """The catalog's words with Android's in their place, in the same shape."""
    if said[0] == "text":
        if not isinstance(android, str):
            raise WordsError(f"{where}: the catalog has one text, so Android's words are one text")
        return ("text", android)
    if not isinstance(android, dict) or set(android) != set(CATEGORIES):
        raise WordsError(f"{where}: the catalog has plural forms, so Android's words are {list(CATEGORIES)}")
    return ("plural", said[1], dict(android))


# --- The words ---------------------------------------------------------------------


def words(root):
    """Every word Android has, as [(book, key, name, args, said, differs why or None)], in the
    catalogs' order; `said` in Android's specifiers."""
    differs = read_differs(os.path.join(root, DIFFERS))
    used, names, result = set(), {}, []
    for book, path in android_books(root):
        for key, entry in load_catalog(path).items():
            where = f"{os.path.relpath(path, root)} „{key}”"
            args = signature(key, where)
            said = romanian(key, entry, where)
            why = None
            if (book, key) in differs:
                android, why = differs[(book, key)]
                used.add((book, key))
                said = with_differs(said, android, f"{DIFFERS} „{key}”")
            if said[0] == "text":
                said = ("text", android_template(said[1], args, where))
            else:
                if said[1] > len(args) or args[said[1] - 1] != "count":
                    raise WordsError(f"{where}: its plural is chosen by argument {said[1]}, which isn't a number")
                said = ("plural", said[1], {c: android_template(t, args, where) for c, t in said[2].items()})
            name = resource_name(book, key)
            if name in names:
                raise WordsError(f"{where}: its name {name} is also „{names[name]}”'s")
            names[name] = key
            result.append((book, key, name, args, said, why))
    for book, key in sorted(set(differs) - used):
        raise WordsError(f"{DIFFERS}: „{key}” ({book}) is in no catalog any more; take it out or follow its new key")
    return result


# --- Writing -----------------------------------------------------------------------


def android_text(text):
    """`text` as an Android string resource's content: XML and Android's own escapes, every
    space that would be collapsed or trimmed, and every invisible character, written out."""
    out = []
    for index, char in enumerate(text):
        if char == "\\":
            out.append("\\\\")
        elif char in "'\"":
            out.append("\\" + char)
        elif char == "\n":
            out.append("\\n")
        elif char == "\t":
            out.append("\\t")
        elif char == "&":
            out.append("&amp;")
        elif char == "<":
            out.append("&lt;")
        elif char == ">":
            out.append("&gt;")
        elif char == " " and (index == 0 or index == len(text) - 1 or text[index - 1] == " "):
            out.append("\\u0020")
        elif char != " " and unicodedata.category(char) in ("Zs", "Zl", "Zp", "Cc", "Cf"):
            out.append(f"\\u{ord(char):04X}")
        else:
            out.append(char)
    written = "".join(out)
    return "\\" + written if written[:1] in ("@", "?") else written


def comment_text(text):
    """`text` safe inside an XML comment."""
    return text.replace("--", "- -").replace("\n", "\\n").rstrip("-")


HEADER = """<?xml version="1.0" encoding="utf-8"?>
<!-- GENERATED by {script} from the iOS String Catalogs. Never edit by hand: change the
     catalog (or {differs} for words Android says differently), then run
     python3 {script}. The android-lint check fails when this file is out of date.

     Romanian is the source language: these are the default resources.
     Names: <book>_<slug>_<digest>, from the iOS key alone, so a name changes only when its key
     does. The book is the catalog (app: ios/DosarCuSina/Resources/Localizable.xcstrings,
     shared: ios/Shared/Shared.xcstrings, widgets: ios/DosarCuSinaWidgets/Localizable.xcstrings);
     the slug is the key's first words folded to ASCII (%@ as x, %lld as n, at most 32 letters);
     the digest is the first six hex digits of the SHA-256 of the key's UTF-8.
     Specifiers: %@ is %N$s, %lld is %N$,d, numbered by their place. A comment gives the iOS key
     wherever the text isn't the key as it is. -->
<resources xmlns:tools="http://schemas.android.com/tools" tools:locale="ro" tools:ignore="UnusedResources,Typos">
"""


def strings_xml(entries):
    lines = [HEADER.format(script=SCRIPT, differs=DIFFERS)]
    book_now = None
    for book, key, name, _, said, why in entries:
        if book != book_now:
            lines.append(f"    <!-- {book} -->\n")
            book_now = book
        if why:
            lines.append(f"    <!-- iOS: {comment_text(key)} · Android says it differently: {comment_text(why)} -->\n")
        elif said[0] != "text" or said[1] != key:
            lines.append(f"    <!-- iOS: {comment_text(key)} -->\n")
        if said[0] == "text":
            lines.append(f'    <string name="{name}">{android_text(said[1])}</string>\n')
            continue
        lines.append(f'    <plurals name="{name}">\n')
        for category in CATEGORIES:
            lines.append(f'        <item quantity="{category}">{android_text(said[2][category])}</item>\n')
        lines.append("    </plurals>\n")
    lines.append("</resources>\n")
    return "".join(lines)


def words_json(entries):
    books = {}
    for book, key, name, args, said, _ in entries:
        entry = {"name": name, "args": args}
        if said[0] == "text":
            entry["text"] = said[1]
        else:
            entry["plural"] = {"arg": said[1], **{c: said[2][c] for c in CATEGORIES}}
        books.setdefault(book, {})[key] = entry
    about = f"GENERATED by {SCRIPT} from the iOS String Catalogs, with {DIFFERS}. Never edit by hand."
    # One word a line, so a change to a word is a change to its line.
    lines = ["{", f' "about": {json.dumps(about)},', f' "categories": {json.dumps(list(CATEGORIES))},', ' "books": {']
    for index, (book, entries_of_book) in enumerate(books.items()):
        lines.append(f"  {json.dumps(book)}: {{")
        items = list(entries_of_book.items())
        for position, (key, entry) in enumerate(items):
            comma = "," if position < len(items) - 1 else ""
            lines.append(f"   {json.dumps(key, ensure_ascii=False)}: {json.dumps(entry, ensure_ascii=False)}{comma}")
        lines.append("  }" + ("," if index < len(books) - 1 else ""))
    lines += [" }", "}"]
    return "\n".join(lines) + "\n"


def outputs(root):
    entries = words(root)
    return {STRINGS_XML: strings_xml(entries), WORDS_JSON: words_json(entries)}


def write(files, root):
    for path, text in files.items():
        full = os.path.join(root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)


def check(root, write_to=None):
    files = outputs(root)
    stale = []
    for path, text in files.items():
        full = os.path.join(root, path)
        committed = open(full, encoding="utf-8").read() if os.path.exists(full) else None
        if committed != text:
            stale.append(path)
    if not stale:
        print(f"android-words: Android's words are the String Catalogs' ({len(files)} files up to date)")
        return 0
    for path in stale:
        print(f"android-words: {path} is out of date with the String Catalogs")
    print(f"Run python3 {SCRIPT} and commit what it writes; never edit those files by hand.")
    if write_to:
        write({path: files[path] for path in stale}, write_to)
        print(f"Fresh copies are in {write_to}")
    return 1


# --- Self-test -----------------------------------------------------------------------


def self_test():
    failures = []

    def expect(name, got, wanted):
        if got != wanted:
            failures.append(f"{name}: got {got!r}, wanted {wanted!r}")

    def refuses(name, call):
        try:
            call()
        except WordsError:
            return
        failures.append(f"{name}: accepted")

    # The naming rule, pinned: a name changes only when its key does.
    expect("count name", resource_name("shared", "%lld zile"), "shared_n_zile_65ffe0")
    expect("text name", resource_name("app", "Expiră pe %@"), "app_expira_pe_x_" + digest("Expiră pe %@"))
    expect("diacritics", slug("Bun de călătorit până pe %@"), "bun_de_calatorit_pana_pe_x")
    expect("long key", slug("Termenul e într-o categorie protejată. Deschide-l în Dosar cu Șină"),
           "termenul_e_intr_o_categorie")
    expect("nothing readable", slug("·"), "text")
    expect("same slug, other names", resource_name("app", "%@ · %@") != resource_name("app", "%@ – %@"), True)
    expect("digest", digest("azi"), hashlib.sha256(b"azi").hexdigest()[:6])

    # Specifiers, numbered by their place.
    expect("in order", android_template("%@ și %@", ["text", "text"], "t"), "%1$s și %2$s")
    expect("numbered", android_template("%2$@ din %1$@", ["text", "text"], "t"), "%2$s din %1$s")
    expect("count", android_template("%lld de zile", ["count"], "t"), "%1$,d de zile")
    expect("no argument", android_template("o zi", ["count"], "t"), "o zi")
    refuses("wrong type", lambda: android_template("%1$lld", ["text"], "t"))
    refuses("mixed", lambda: parts("%@ și %2$@", "t"))
    refuses("literal percent", lambda: parts("50%% din preț", "t"))
    refuses("unknown specifier", lambda: parts("%f lei", "t"))

    # A catalog's entry.
    plural = {"localizations": {"ro": {"variations": {"plural": {
        "one": {"stringUnit": {"value": "o zi"}}, "other": {"stringUnit": {"value": "%lld de zile"}}}}}}}
    expect("missing few reads as other", romanian("%lld zile", plural, "t"),
           ("plural", 1, {"one": "o zi", "few": "%lld de zile", "other": "%lld de zile"}))
    lei = {"localizations": {"ro": {"stringUnit": {"value": "%1$@\u00a0%#@lei@"}, "substitutions": {"lei": {
        "argNum": 2, "formatSpecifier": "lld", "variations": {"plural": {
            "one": {"stringUnit": {"value": "leu"}}, "few": {"stringUnit": {"value": "lei"}},
            "other": {"stringUnit": {"value": "de lei"}}}}}}}}}
    expect("substitution", romanian("%@\u00a0%lld lei", lei, "t"),
           ("plural", 2, {"one": "%1$@\u00a0leu", "few": "%1$@\u00a0lei", "other": "%1$@\u00a0de lei"}))
    expect("no localization", romanian("azi", {}, "t"), ("text", "azi"))
    refuses("plural on two arguments", lambda: romanian("%@ %lld", plural, "t"))

    # Android's escapes.
    expect("apostrophe and quotes", android_text("n'a \"x\""), "n\\'a \\\"x\\\"")
    expect("xml", android_text("a < b & c"), "a &lt; b &amp; c")
    expect("no-break space", android_text("1\u00a0leu"), "1\\u00A0leu")
    expect("edges", android_text(" a  b "), "\\u0020a \\u0020b\\u0020")
    expect("at sign", android_text("@x"), "\\@x")
    expect("newline", android_text("a\nb"), "a\\nb")

    # The whole run, on a small household of catalogs.
    with tempfile.TemporaryDirectory() as root:
        def catalog(path, strings):
            full = os.path.join(root, path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            json.dump({"sourceLanguage": "ro", "strings": strings, "version": "1.0"}, open(full, "w"))

        catalog("ios/DosarCuSina/Resources/Localizable.xcstrings",
                {"Protejat cu Face ID": {}, "%@\u00a0%lld lei": lei, "Lipit": {"extractionState": "manual"}})
        catalog("ios/Shared/Shared.xcstrings", {"%lld zile": plural, "în %@": {}})
        catalog("ios/DosarCuSinaWidgets/Localizable.xcstrings", {})
        differs = os.path.join(root, DIFFERS)
        os.makedirs(os.path.dirname(differs))

        def say(items):
            json.dump({"words": items}, open(differs, "w"), ensure_ascii=False)

        say([{"book": "app", "key": "Protejat cu Face ID", "android": "Protejat cu amprenta", "why": "no Face ID"}])
        files = outputs(root)
        xml, book = files[STRINGS_XML], json.loads(files[WORDS_JSON])["books"]
        expect("android's words", book["app"]["Protejat cu Face ID"]["text"], "Protejat cu amprenta")
        expect("manual entry kept", "Lipit" in book["app"], True)
        expect("plural in json", book["shared"]["%lld zile"]["plural"]["other"], "%1$,d de zile")
        expect("lei in json", book["app"]["%@\u00a0%lld lei"]["plural"]["one"], "%1$s\u00a0leu")
        expect("plurals in xml", '<item quantity="few">%1$,d de zile</item>' in xml, True)
        expect("text in xml", '>în %1$s</string>' in xml, True)
        say([{"book": "app", "key": "Nu mai e", "android": "x", "why": "y"}])
        refuses("a key no catalog has", lambda: outputs(root))
        say([{"book": "app", "key": "Protejat cu Face ID", "android": "x"}])
        refuses("no reason", lambda: outputs(root))
        say([{"book": "shared", "key": "%lld zile", "android": "%lld zile", "why": "y"}])
        refuses("one text for plural forms", lambda: outputs(root))
        say([{"book": "shared", "key": "în %@", "android": "în %lld", "why": "y"}])
        refuses("another argument", lambda: outputs(root))
        say([])
        write(outputs(root), root)
        expect("up to date", check(root), 0)

    if failures:
        print("android-words self-test failed:\n  " + "\n  ".join(failures))
        return 1
    print("android-words self-test: every rule holds")
    return 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    try:
        if "--check" in argv:
            write_to = argv[argv.index("--write-to") + 1] if "--write-to" in argv else None
            return check(ROOT, write_to)
        write(outputs(ROOT), ROOT)
    except WordsError as error:
        print(f"android-words: {error}")
        return 1
    print(f"android-words: wrote {', '.join(OUTPUTS)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
