#!/usr/bin/env bash
# Fails when the compiler warned about the project's own Swift code.
#
# Usage: scripts/warnings-check.sh <build log>
#
# A warning is a bug waiting (an unused value, a `try` with nothing that throws, a check
# that can never fail): the build stays warning-free, so a new one stands out. Warnings
# from Apple's frameworks and the build system itself are left out; only lines that point
# into ios/ count.
set -euo pipefail
LOG="${1:?usage: scripts/warnings-check.sh <build log>}"
FOUND=$(grep -oE "ios/[^ :]+\.swift:[0-9]+:[0-9]+: warning: .*" "$LOG" | sort -u || true)
if [[ -n "$FOUND" ]]; then
    echo "The compiler warned about the project's own code. Fix each one where it is:" >&2
    echo "$FOUND" >&2
    exit 1
fi
echo "No compiler warnings in the project's own code."
