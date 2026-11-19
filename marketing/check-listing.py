#!/usr/bin/env python3
"""Checks the App Store listings in marketing/app-store/*.md against App Store Connect's limits.

Usage: python3 marketing/check-listing.py

A field is a "## Title (limit)" heading followed by a ```text block: its text must fit the
limit (App Store Connect counts characters). Keywords are comma-separated with no space after
a comma, and no field has an exclamation mark (docs/COPY_GUIDE.md).
"""
import pathlib
import re
import sys

FOLDER = pathlib.Path(__file__).resolve().parent / "app-store"
FIELD = re.compile(r"^## (.+?) \((\d+)\)\n(?:.*?\n)??```text\n(.*?)\n```", re.S | re.M)


def problems(path):
    found = []
    text = path.read_text(encoding="utf-8")
    for title, limit, value in FIELD.findall(text):
        count = len(value)
        print(f"{path.name}: {title}: {count} of {limit}")
        if count > int(limit):
            found.append(f"{path.name}: {title} has {count} characters; the limit is {limit}.")
        if "!" in value:
            found.append(f"{path.name}: {title} has an exclamation mark.")
        if title.lower().startswith(("cuvinte-cheie", "keywords")) and re.search(r",\s", value):
            found.append(f"{path.name}: {title} has a space after a comma; it counts against the limit.")
    return found


def main():
    found = [line for path in sorted(FOLDER.glob("*.md")) for line in problems(path)]
    for line in found:
        print(line, file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
