#!/usr/bin/env bash
# Privacy check for Dosar cu Șină.
#
# The repository is public. This check stops private notes, credentials and
# real personal data from reaching it. The pre-commit hook and the pull request
# workflow both run it, so they always agree.
#
#   scripts/privacy-check.sh                    # staged changes (the pre-commit hook)
#   scripts/privacy-check.sh --range BASE HEAD  # every commit after BASE up to HEAD (CI)
#
# What it checks:
#   1. File paths: private notes folders, credential and signing files, local
#      configuration, environment files.
#   2. Added lines: API keys, access tokens and private keys.
#   3. Added lines: absolute paths into someone's home folder.
#   4. Added lines: Romanian personal numbers (CNP) with a valid control digit.
#      Made-up ones use county code 99 and pass.
#
# It lists patterns only. Never write a finding, a trace or a real value here.
# It never prints a matched value either: pull request logs are public.
set -euo pipefail

usage() {
    echo "Usage: scripts/privacy-check.sh [--staged | --range BASE HEAD]" >&2
    exit 2
}

mode=staged
base=""
head=""
case "${1:-}" in
    "" | --staged) ;;
    --range)
        [[ $# -eq 3 ]] || usage
        mode=range
        base="$2"
        head="$3"
        ;;
    *) usage ;;
esac

# Paths that never belong in the repository, at any depth. Keep in step with .gitignore.
forbidden_paths='(^|/)(private|\.private|internal|\.internal|security-vault|\.agents)/'
forbidden_paths+='|\.xcconfig$'
forbidden_paths+='|(^|/)Secrets\.(swift|kt)$'
forbidden_paths+='|(^|/)(local|keystore)\.properties$'
forbidden_paths+='|\.(jks|keystore|p12|p8|mobileprovision|secret|secrets)$'
forbidden_paths+='|(^|/)[^/]*\.env(\.[^/]*)?$'
forbidden_paths+='|(^|/)google-services\.json$'
forbidden_paths+='|(^|/)GoogleService-Info\.plist$'
forbidden_paths+='|\.(private|internal)\.'
forbidden_paths+='|VULNERABILIT|EXPLOIT'
# Templates and examples of those files are fine: they hold placeholders.
allowed_paths='\.(template|example|sample)$'

# Credentials in added lines.
secret_pattern='AIza[0-9A-Za-z_-]{35}'
secret_pattern+='|sk-ant-[0-9A-Za-z_-]{20,}'
secret_pattern+='|sk-[0-9A-Za-z]{20,}'
secret_pattern+='|AKIA[0-9A-Z]{16}'
secret_pattern+='|gh[pousr]_[A-Za-z0-9_]{16,}'
secret_pattern+='|github_pat_[A-Za-z0-9_]{20,}'
secret_pattern+='|xox[baprs]-[0-9A-Za-z-]{10,}'
secret_pattern+='|-----BEGIN [A-Z ]*PRIVATE KEY-----'

# Absolute paths on someone's machine. Links in the repository are relative.
home_path_pattern='(/Users/|/home/)[A-Za-z0-9._-]+/|file:/{3}'

# A 13-digit number that could be a CNP; validated below.
cnp_candidate='(^|[^0-9])[1-8][0-9]{12}([^0-9]|$)'

problems=0
report() {
    # $1 where, $2 what is wrong
    if [[ $problems -eq 0 ]]; then
        echo "Privacy check failed. The repository is public, so these can't go in:" >&2
        echo >&2
    fi
    problems=$((problems + 1))
    printf '  %s\n    %s\n' "$1" "$2" >&2
}

# 1. Paths.
if [[ $mode == staged ]]; then
    changed_paths=$(git diff --cached --name-only --diff-filter=ACMR)
else
    changed_paths=$(git log --format= --name-only --diff-filter=ACMR "$base..$head" | sort -u)
fi
while IFS= read -r path; do
    [[ -z $path ]] && continue
    if grep -Eq -- "$forbidden_paths" <<<"$path" && ! grep -Eq -- "$allowed_paths" <<<"$path"; then
        report "$path" "Private notes, credentials and local configuration stay on your own machine."
    fi
done <<<"$changed_paths"

# 2–4. Added lines, as "path<TAB>line<TAB>text".
if [[ $mode == staged ]]; then
    diff_text=$(git diff --cached -U0 --no-color --no-ext-diff --diff-filter=ACMR)
else
    diff_text=$(git log -p -U0 --format= --no-color --no-ext-diff --diff-filter=ACMR "$base..$head")
fi
added=$(awk '
    /^\+\+\+ / { path = substr($0, 5); sub(/^b\//, "", path); next }
    /^@@ / {
        split($0, parts, " "); start = parts[3]; sub(/^\+/, "", start)
        split(start, numbers, ","); line = numbers[1] + 0; next
    }
    /^\+/ { print path "\t" line "\t" substr($0, 2); line++ }
' <<<"$diff_text")

check_lines() {
    # $1 pattern, $2 message
    local matches
    matches=$(cut -f3- <<<"$added" | grep -nE -- "$1" | cut -d: -f1 || true)
    while IFS= read -r index; do
        [[ -z $index ]] && continue
        report "$(sed -n "${index}p" <<<"$added" | cut -f1,2 | tr '\t' ':')" "$2"
    done <<<"$matches"
}

if [[ -n $added ]]; then
    check_lines "$secret_pattern" \
        "This looks like a key or token. Remove it and keep it in the Keychain or an untracked file."
    check_lines "$home_path_pattern" \
        "This is a path on one person's machine. Use a path relative to the repository."

    # CNPs: control digit per the official weights 279146358279, a real month
    # and day, and any county code except 99, which marks made-up numbers.
    cnp_lines=$(cut -f3- <<<"$added" | grep -nE -- "$cnp_candidate" || true)
    if [[ -n $cnp_lines ]]; then
        flagged=$(awk -F: '
            function real_cnp(s,   i, sum, r, control, month, day, county) {
                if (substr(s, 1, 1) < "1" || substr(s, 1, 1) > "8") return 0
                month = substr(s, 4, 2) + 0; day = substr(s, 6, 2) + 0; county = substr(s, 8, 2)
                if (month < 1 || month > 12 || day < 1 || day > 31) return 0
                if (county == "99" || county + 0 < 1) return 0
                sum = 0
                for (i = 1; i <= 12; i++) sum += substr(s, i, 1) * substr("279146358279", i, 1)
                r = sum % 11; control = (r == 10) ? 1 : r
                return control == substr(s, 13, 1) + 0
            }
            {
                index_ = $1; text = substr($0, length($1) + 2)
                while (match(text, /[0-9]+/)) {
                    run = substr(text, RSTART, RLENGTH)
                    if (length(run) == 13 && real_cnp(run)) { print index_; break }
                    text = substr(text, RSTART + RLENGTH)
                }
            }
        ' <<<"$cnp_lines")
        while IFS= read -r index; do
            [[ -z $index ]] && continue
            report "$(sed -n "${index}p" <<<"$added" | cut -f1,2 | tr '\t' ':')" \
                "This looks like a real personal number (CNP). Use a made-up one with county code 99 and a valid control digit."
        done <<<"$flagged"
    fi
fi

if [[ $problems -gt 0 ]]; then
    echo >&2
    if [[ $mode == staged ]]; then
        echo "Fix or unstage them (git restore --staged <file>), then commit again." >&2
    else
        echo "Remove them from every commit in this pull request (rewrite the branch, don't just add a fix on top)." >&2
        echo "Found something sensitive that is already public? Report it privately, as SECURITY.md describes." >&2
    fi
    exit 1
fi

if [[ $mode == range ]]; then
    echo "Privacy check passed."
fi
