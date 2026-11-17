#!/usr/bin/env python3
"""Checks that the Xcode project file is written the way Xcode itself writes it.

Usage: scripts/project-check.py [project.pbxproj]

Xcode rewrites the project file whenever it opens it. A file edited by hand in another
order shows up as a local change on every machine that opens it, and hides the real
changes in that noise. Xcode's form, as Xcode 27 writes it:

- the object sections in alphabetical order of their kind (PBXBuildFile, PBXContainerItemProxy,
  PBXCopyFilesBuildPhase, …), each between its Begin and End comments;
- inside a section, the objects in order of their identifiers;
- inside each buildSettings block, the settings in alphabetical order;
- an exception set's comment is its kind, PBXFileSystemSynchronizedBuildFileExceptionSet;
- no entitlements file listed among a synchronized folder's membership exceptions (Xcode
  never makes one a member of a target, and drops the line).
"""
import os
import re
import sys

DEFAULT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ios", "DosarCuSina.xcodeproj", "project.pbxproj")
BEGIN = re.compile(r"^/\* Begin (\w+) section \*/$")
END = re.compile(r"^/\* End (\w+) section \*/$")
OBJECT = re.compile(r"^\t\t([0-9A-F]{24}) /\*")
SETTING = re.compile(r"^\t\t\t\t([A-Za-z0-9_\[\]=*\"\-]+) = ")


def problems(text):
    found = []
    lines = text.split("\n")
    sections = []
    current = None
    ids = []
    settings = None
    for number, line in enumerate(lines, 1):
        begin, end = BEGIN.match(line), END.match(line)
        if begin:
            current, ids = begin.group(1), []
            sections.append(current)
            continue
        if end:
            if ids != sorted(ids):
                found.append(f"{current}: its objects aren't in order of their identifiers.")
            current = None
            continue
        if current:
            match = OBJECT.match(line)
            if match:
                ids.append(match.group(1))
            if current == "PBXFileSystemSynchronizedBuildFileExceptionSet" and match and "/* PBXFileSystemSynchronizedBuildFileExceptionSet */" not in line:
                found.append(f"line {number}: an exception set's comment is its kind, as Xcode writes it.")
        if line.strip() == "buildSettings = {":
            settings = []
            continue
        if settings is not None:
            if line.strip() == "};":
                keys = [key.strip('"') for key in settings]
                if keys != sorted(keys, key=str.lower) and keys != sorted(keys):
                    found.append(f"line {number}: a buildSettings block isn't in alphabetical order.")
                settings = None
            else:
                match = SETTING.match(line)
                if match:
                    settings.append(match.group(1))
        if re.search(r"^\t\t\t\t[\w.-]+\.entitlements,$", line):
            found.append(f"line {number}: an entitlements file among a folder's membership exceptions; Xcode drops it.")
    if sections != sorted(sections):
        found.append("The object sections aren't in alphabetical order of their kind.")
    return found


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    found = problems(open(path, encoding="utf-8").read())
    if found:
        print("The project file isn't written the way Xcode writes it:", file=sys.stderr)
        for line in found:
            print("  " + line, file=sys.stderr)
        print("Open the project in Xcode, let it save, and commit what it wrote (only the project file).", file=sys.stderr)
        return 1
    print("The project file is written the way Xcode writes it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
