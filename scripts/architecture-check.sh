#!/usr/bin/env bash
# Architecture check for Dosar cu Șină.
#
# AGENTS.md names one path for each job. This check keeps code on those paths:
# each rule is a pattern that marks a way around a shared helper, with a plain
# message saying what to use instead. The pull request workflow and the
# pre-commit hook both run it, so they always agree.
#
#   scripts/architecture-check.sh               # the working tree
#   scripts/architecture-check.sh --staged      # what is about to be committed (the pre-commit hook)
#   scripts/architecture-check.sh --base REF    # the working tree, and the exceptions compared with REF (CI)
#   scripts/architecture-check.sh --self-test   # the rules against their fixtures
#
# Code that broke a rule before the rule existed is listed in
# scripts/architecture-exceptions.txt as "path:rule" or "path:rule:count". That
# list may only shrink:
#   - a violation that isn't listed fails;
#   - a listed one that is gone fails too, so its line is removed and can't be
#     used again;
#   - with --base, a line that is new or allows more than before fails unless
#     ARCHITECTURE_EXCEPTIONS_APPROVED=true (the owner's label on the pull request).
#
# It reads app code only: ios/DosarCuSina, ios/DosarCuSinaWidgets,
# ios/DosarCuSinaShare and ios/Shared. Tests and ios/Legacy are left alone, and
# comments never count.
#
# Written for the bash 3.2 and awk that ship with macOS, and for Linux runners.
set -euo pipefail

usage() {
    echo "Usage: scripts/architecture-check.sh [--staged | --base REF | --self-test]" >&2
    exit 2
}

mode=tree
base=""
case "${1:-}" in
    "") ;;
    --staged) mode=staged ;;
    --base)
        [[ $# -eq 2 ]] || usage
        base="$2"
        ;;
    --self-test) mode=self-test ;;
    *) usage ;;
esac

root="$(git rev-parse --show-toplevel)"
cd "$root"
exceptions_path=scripts/architecture-exceptions.txt
fixtures_dir=scripts/architecture-fixtures

work="$(mktemp -d "${TMPDIR:-/tmp}/architecture-check.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# --- Rules ------------------------------------------------------------------
# One line per rule, tab-separated:
#   id, paths it covers, paths it leaves out ("-" for none), pattern,
#   lines it leaves out ("-" for none), message.
# Patterns are POSIX extended regular expressions, read by awk, so they work the
# same on macOS and Linux: no \b, \s or \d. Awk variable names avoid gawk's own
# words (include, switch, case…): Linux runners use gawk.

app='^ios/(DosarCuSina|DosarCuSinaWidgets|DosarCuSinaShare|Shared)/'
views='^ios/DosarCuSina/Views/'
design_system='^ios/DosarCuSina/Views/DesignSystem/'

rules="$work/rules.tsv"
rule() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >>"$rules"
}

rule save-outside-unit-of-work "$app" '^ios/DosarCuSina/Services/Persistence/UnitOfWork\.swift$' \
    '[cC]ontext\??\.save\(\)' - \
    'Save through UnitOfWork.save(context). When one tap does several things, wrap them in UnitOfWork.perform(in:).'

# When a record last changed is written by the unit of work as it saves (ChangeTimes), with the
# step's clock and whose change it is, and by a backup's importer, which writes the archive's
# times. A model's initializer gives the moment it is made, and a value type's own initializer
# copies the value it is given; the unit replaces the first when it saves.
rule change-time-outside-change-times "$app" \
    '^ios/DosarCuSina/Services/Persistence/ChangeTimes\.swift$|^ios/DosarCuSina/Services/Archive/DossierImporter\.swift$' \
    '(^|[^A-Za-z0-9_])updatedAt *=([^=]|$)' \
    '^[[:space:]]*self\.updatedAt = (Date\(\)|updatedAt)[[:space:]]*$' \
    "Change times are written only by the unit of work (ChangeTimes). Pass the step's clock to it (UnitOfWork.perform(in:now:), save(_:now:)), and open an app-made step with origin: .app."

# SwiftData saves a context by itself unless told not to, around the unit of work. Every
# container and context is made in one file, which turns that off.
rule context-outside-persistence "$app" '^ios/DosarCuSina/Services/Persistence/PersistenceController\.swift$' \
    '(^|[^A-Za-z0-9_.])Model(Context|Container)\(|autosaveEnabled *= *true' - \
    'Make a container with PersistenceController.makeContainer and a context of its own with PersistenceController.context(in:). They save only through UnitOfWork, never by themselves.'

rule system-error-text "$app" - \
    '\.localizedDescription([^A-Za-z0-9_]|$)' - \
    "The system's error text isn't written for people. Show SaveFailure.message(for:formKept:), or give the error a UserFacingError message."

rule format-string "$app" - \
    'String\(format:' - \
    'Use Money.formatted, CalendarDay, or .formatted(...) with Locale.dosarDefault. Machine text such as a hash or an ISO day goes through MachineText.'

rule hand-written-plural "$app" - \
    '(==|!=) *1 *\? *("|Text\(|String\(localized|LocalizedStringKey|NSLocalizedString)' - \
    'Counts use plural variations in the String Catalog (1 zi, 2 zile, 20 de zile), never a choice between two strings.'

# Screens, widgets and Siri draw an urgency; they never work one out from a number of days.
rule urgency-threshold '^ios/(DosarCuSina/(Views|Intents)|DosarCuSinaWidgets)/' - \
    '[dD]ays[A-Za-z]* *(<|<=|>|>=) *-?[0-9]|soonWithinDays' - \
    "How urgent a date is comes from the one rule: UrgencyRule (ReminderProfile.urgencyRule, DateUrgency for a date on a page). Draw its tone and WhenWording; don't compare days yourself."

rule animation-curve "$app" '^ios/Shared/DSMotion\.swift$' \
    '\.(easeInOut|easeIn|easeOut|linear)([^A-Za-z0-9_]|$)|\.spring\(|\.interpolatingSpring|\.(bouncy|snappy|smooth)([^A-Za-z0-9_]|$)|UIView\.animate|Animation\.default' \
    'progressViewStyle|gaugeStyle' \
    'Animate with a DS.Motion spring through dsAnimation, so Reduce Motion turns movement into a short fade.'

# Numbers in text, a model's answers included, are read by one reader: RomanianNumber.read for
# what is printed or typed, RomanianNumber.canonical for the machine form, and, for a model's
# answer, ModelQuestions.number(_:as:) over both. Never a number made from text another way,
# and never through floating point ("Decimal(string: String(double))").
rule number-parser "$app" '(^|/)RomanianNumber[^/]*\.swift$' \
    'Decimal\(string: *([a-z]|String\()|(^|[^A-Za-z0-9_.])(Double|Float)\( *("|[A-Za-z_.]*([tT]ext|[sS]tring|[rR]aw)\))|replacingOccurrences\(of: *",", *with: *"\."\)|NumberFormatter\(\)|\.number\.parseStrategy|ParseStrategy' - \
    "Read numbers from text with the one shared reader: RomanianNumber.read (or .value) for what is printed or typed, RomanianNumber.canonical for the machine form, ModelQuestions.number(_:as:) for a model's answer. Readers that disagree turn 45,724 into 45.724, and a detour through Double changes amounts."

# A kind's printed labels are data: its profile's table (CaptureKindProfile.labels), or the one
# every document shares (CaptureKindProfile.commonLabels). Words the shared readers look for that
# are no one kind's (stop words, the buyer's block, an issuer's prefixes, address labels) are the
# capture lexicon's (CaptureLexicon); a value printed in parts, CompositeLabels'; a personal
# document's layout, its template (IdentityTemplates). Capture's readers are told the table, so a
# wording added there is read with no new code; a list written where it is read, or a list named
# ...Labels, ...Words or ...Prefixes in any other file, is a second table.
label_tables='^ios/DosarCuSina/Services/Capture/(CaptureKindProfile|CaptureLexicon|CompositeLabels|IdentityTemplates)\.swift$'
rule labels-outside-their-table '^ios/DosarCuSina/Services/Capture/' "$label_tables" \
    '(labelledDate\(|lines\(containing: *|contains\(any: *|labels: *)\[ *"|let +labels *= *\[ *"|(let|var) +[A-Za-z_]*([lL]abels|[wW]ords|[pP]refixes)([^A-Za-z0-9_=][^=]*)?= *\[' - \
    "Labels and words are data in their table: a kind's in its profile (CaptureKindProfile.labels, commonLabels for what every document prints), the shared readers' in CaptureLexicon, a value in parts' in CompositeLabels, a personal document's in its template. Tell the reader the table, as profile.labels(for:); never list labels or words where they are read."

# Codes, numbers, plates and names are compared one way: folded, in capitals, letters and digits
# only (RomanianText.compact), so a value with a diacritic, a space or a dash still matches.
rule compact-outside-romanian-text "$app" '^ios/DosarCuSina/Models/Values/RomanianText\.swift$' \
    'uppercased\(\)\.filter *(\(\{|\{) *\$0\.is(Letter|Number) *\|\| *\$0\.is(Letter|Number)' - \
    'Compare and check codes, numbers, plates and names with RomanianText.compact: folded, in capitals, letters and digits only, the one way.'

rule bare-progress-view "$app" "$design_system|^ios/Shared/DSMotion\\.swift\$" \
    'ProgressView\(' - \
    'Use DSDelayedProgress: it waits before it shows and keeps its space, so fast work never flashes a spinner.'

rule pasteboard-write "$app" "$design_system" \
    'UIPasteboard\.general\.([A-Za-z]+ *=[^=]|set[A-Z]|add[A-Z])' - \
    "Copy with the design system's value rows (DSActionValueRow, DSSecretValueRow), which confirm the copy and keep secrets off other devices."

rule tap-gesture-beside-action "$app" "$design_system" \
    'simultaneousGesture\( *TapGesture' - \
    "A tap gesture beside a link or a button makes every tap wait to be told apart from a hold. Do the work in the button's action, or read it from the navigation."

# One named exception: ios/Shared/InboxNotice.swift, the share's own notice. The share
# extension runs while the app doesn't, so it posts that one notice itself (only when
# notifications are already allowed); the coordinator withdraws it. See AGENTS.md.
rule side-effect-outside-coordinator "$app" \
    '^ios/DosarCuSina/Services/SideEffects/|^ios/DosarCuSina/Services/Reminders/NotificationReconciler\.swift$|^ios/DosarCuSinaWidgets/|^ios/Shared/InboxNotice\.swift$' \
    'WidgetCenter|UNNotificationRequest\(|UNUserNotificationCenter\.current\(\)\.(add|remove|setBadgeCount)|setBadgeCount\(|CSSearchableIndex|ControlCenter\.shared\.reload' - \
    'Notifications, the badge, widgets and Spotlight change only through SideEffectsCoordinator. Save through an action and let the coordinator react.'

# Built-in category keys, read from BuiltInTemplates so the rule never falls behind.
keys=$(awk '
    /enum Key[[:space:]]*\{/ { inside = 1; next }
    inside && /^[[:space:]]*\}/ { exit }
    inside && match($0, /"[a-z_]+"/) { printf "%s%s", (n++ ? "|" : ""), substr($0, RSTART + 1, RLENGTH - 2) }
' ios/DosarCuSina/Services/Templates/BuiltInTemplates.swift)
[[ -n $keys ]] || { echo "Architecture check: couldn't read the built-in keys from BuiltInTemplates.swift." >&2; exit 2; }
rule built-in-key-in-views "$views" - \
    "BuiltInTemplates\\.Key\\.|(^|[^A-Za-z0-9_.])Key\\.($keys)([^A-Za-z0-9_]|\$)|(==|!=|case|,|\\(|\\[|:) *\"($keys)\"" - \
    "Screens don't branch on a built-in category. Ask the template what it does (its kind, its fields' roles), so a custom category behaves the same."

rule date-format "$app" '(^|/)(DosarFormat|DueWording)\.swift$' \
    '\.dateTime([^A-Za-z0-9_]|$)|(^|[^A-Za-z0-9_])DateFormatter\(\)|\.formatted\(date:|Text\([^)]*, *style: *\.(date|time|relative|offset|timer)' - \
    'Write dates with DosarFormat (or DueWording and CalendarDay for due days), so every screen, widget and notification writes them the same way.'

rule romanian-locale "$app" '^ios/Shared/DosarLocale\.swift$' \
    'Locale\(identifier: *"ro' - \
    'Use Locale.dosarDefault, the one place that decides which Romanian locale the app writes in.'

# One calendar counts days everywhere, Gregorian whatever the phone is set to, the way one
# locale writes them: Calendar.dosar, or Calendar.dosar(in:) for a set time zone.
rule app-calendar "$app" '^ios/Shared/DosarCalendar\.swift$' \
    'Calendar\.(current|autoupdatingCurrent)([^A-Za-z0-9_]|$)|Calendar *= *\.(current|autoupdatingCurrent)([^A-Za-z0-9_]|$)|[cC]alendar: *\.(current|autoupdatingCurrent)([^A-Za-z0-9_]|$)|(startDate|noonDate|dueDay)\(in: *\.(current|autoupdatingCurrent)([^A-Za-z0-9_]|$)|(^|[^A-Za-z0-9_.])Calendar\(identifier:' - \
    "Count days in Calendar.dosar, the app's one calendar (Gregorian, Romanian, the phone's time zone), or Calendar.dosar(in:) for a set time zone. The phone's own calendar may count years and months another way."

# A month's length is the calendar's, known in one place: CalendarDay's month arithmetic
# (month ends, 29 February, the day a series keeps). Never a table of month lengths, a
# switch over the short months or a leap-year rule of its own.
rule month-length "$app" '^ios/Shared/CalendarDay\.swift$' \
    '31 *, *2[89] *, *31|case +4 *, *6 *, *9 *, *11|case +1 *, *3 *, *5 *, *7 *, *8|[lL]eap_?[yY]ear|% *400([^0-9]|$)|% *100 *[!=]= *0|[yY]ear[A-Za-z]* *% *4([^0-9]|$)|range\(of: *\.day, *in: *\.month' - \
    "Move a day by months with CalendarDay.adding(months:dayOfMonth:) and ask a month's length with CalendarDay.daysInMonth(calendar:): the calendar knows month ends and 29 February once."

# Machine JSON writes a moment one way and reads every form earlier versions wrote: the
# shared coders in MachineText, so the widget snapshot, the share inbox, a widget's
# completions and archives can't drift apart.
rule json-date-coding "$app" '^ios/Shared/MachineText\.swift$' \
    'date(En|De)codingStrategy' - \
    "Code machine JSON with MachineText.jsonEncoder() and MachineText.jsonDecoder() (.readable for an archive): one way to write a moment, and one reader for every form earlier versions wrote."

# A picture is drawn on one bitmap canvas, ImageScaling.canvas: the page turned and the PDF
# page drawn (DocumentPicture, PDFPageRendering) draw on it too, and sizes change only
# through ImageScaling. A PDF being written (a context on a consumer) is another job.
rule own-canvas "$app" '^ios/DosarCuSina/Services/Documents/ImageScaling\.swift$' \
    '(^|[^A-Za-z0-9_.])CGContext\(|UIGraphicsImageRenderer|UIGraphicsBeginImageContext|CGBitmapContextCreate' \
    'CGContext\( *consumer:' \
    "Draw a picture on ImageScaling.canvas(width:height:onWhite:), and change its size with ImageScaling.scaled or decoded: one canvas and one scaler, the same quality everywhere."

# A row that gives way is DSAdaptiveStack, laid out once so a field or a button keeps its
# state. Widgets are left out on purpose: a Lock Screen line (accessoryInline) shows one
# line of text the system lays out itself, ignoring any layout of the app's, and offers
# shorter wordings only through ViewThatFits; the design system isn't in the widget either.
rule view-that-fits "$app" '^ios/DosarCuSinaWidgets/' \
    'ViewThatFits' - \
    "A row that gives way is DSAdaptiveStack: side by side when the pieces fit, stacked otherwise, laid out once so a field or a button keeps its state."

# A minimum under 44 anywhere; a fixed height under 44 on a line that is tapped
# (a button, a tap gesture, a tap shape). The rule reads one line at a time, so a
# button whose label sets the height on a later line isn't seen.
small='([0-9]|[1-3][0-9]|4[0-3])([^0-9.]|$)'
rule small-hit-target "$app" - \
    "min(Height|Width): *$small|(Button|onTapGesture|contentShape|Toggle|Link).*[^A-Za-z]height: *$small" - \
    'Tap targets are at least 44 pt (DS.Space and the DS buttons already are). If nothing here is tapped, drop the minimum instead.'

# Actions, the unit of work, and the steps that change data with no one to tell: the category
# store's changes, the repair list, the household's own deadlines. Reading a category is not
# a change and may fall back.
rule silent-action-failure "$app" - \
    'try\? *(await +)?[A-Za-z_.]*[aA]ctions[.(]|try\? *(await +)?UnitOfWork\.|try\? *(await +)?(TemplateStore\([^)]*\)|[A-Za-z_]*[sS]tore)\.(installBuiltIns|createCustom|editCustom|setPockets|update|delete|move|setOnHome|setSensitive)\(|try\? *(await +)?[A-Za-z_.]*(DataRepair[A-Za-z]*|[rR]epairs)[.(]|try\? *(await +)?[A-Za-z_.]*(HouseholdRules\.|reconcileHouseholdRules\()' - \
    "Don't drop a change's failure with try?. Catch it and show SaveFailure.message(for:formKept:), let it throw to a caller that does, or, for a step no one sees (launch, the repair list), log it with PersistenceLog.attempt."

# A question for the person is made by its one rule, which changes nothing, so every action
# asks it before its unit of work writes (StepQuestion). The design system's gallery shows them.
rule question-outside-its-rule "$app" \
    "^ios/DosarCuSina/Services/History/Readings\\.swift\$|^ios/DosarCuSina/Services/Examples/ExampleOwnership\\.swift\$|$design_system" \
    '(LowerReadingQuestion|ExampleSectionQuestion)\(' - \
    "Ask with the question's one rule, before the step's unit of work writes anything: HouseholdMutations.askAboutReading with the step's PlannedReading, or ExampleOwnership.requireReal."

# A wait of a set time written where it waits, anywhere in the app, its widgets, the share
# extension and ios/Shared: code waits for the event it needs instead. A wait with no event
# to wait for (a service's backoff before a retry, the coordinator's debounce) is a named
# duration beside the code that owns it, saying why.
rule guessed-pause '^ios/(DosarCuSina|DosarCuSinaWidgets|DosarCuSinaShare|Shared)/' - \
    '(Task\.sleep|asyncAfter|Thread\.sleep|usleep|\.delay|scheduledTimer|Timer\.publish)[[:space:]]*\(.*[^A-Za-z0-9_][0-9]' - \
    "Wait for the event this needs (a dismissal, a layout, an answer, an animation's completion), never a set time. A pause that only lets motion finish comes from DS.Motion; a debounce, a backoff before a retry, or how long something stays, is a named duration that says why."

# Checked in its own pass below: tab roots are the views AppShell puts inside
# NavigationStack(path:), and their body must not start another stack.
rule stack-in-tab-root "$app" - '-' - \
    'Tab roots live inside the stack AppShell gives each tab. Push with NavigationLink(value: AppRoute…) instead of adding a stack.'

# Checked in their own pass below, which follows braces: a screen's or a sheet's main action
# is pinned to its bottom edge by one modifier, .dsPinnedAction, which shows it at any sheet
# height and text size. A main action written inside a ScrollView's braces sits at the end of
# scrolling content, out of sight; a bottom inset that draws buttons or the bar itself is a
# second pinned bar. The pass sees what is written inside the braces, not a property they name.
rule main-action-in-scroll '^ios/(DosarCuSina|DosarCuSinaShare)/' "$design_system" '-' - \
    "Pin a screen's or a sheet's main action with .dsPinnedAction { DSPrimaryButton(…) }, with note: for what is said above it and secondary: for the actions under it. Inside the ScrollView it is lost at the end of the content."
rule hand-pinned-action "$app" '^ios/Shared/DSBottomBar\.swift$' '-' - \
    'Pin actions with .dsPinnedAction (note: and secondary: for what goes with them), the one bar, which keeps its height, material and keyboard behaviour everywhere.'

# --- The scan ----------------------------------------------------------------

# Prints "path<TAB>rule<TAB>line" for every match. $1 is a file of
# "path<TAB>file on disk" lines: the path the rules see, and where to read it.
scan() {
    local map="$1" files
    files=$(cut -f2 "$map")
    [[ -n $files ]] || return 0
    # shellcheck disable=SC2086 # one argument per file; paths have no spaces
    awk -F'\t' -v rules_file="$rules" -v map_file="$map" '
        function code_of(line) {
            # Comments never count: whole comment lines, then a trailing // comment.
            if (line ~ /^[[:space:]]*(\/\/|\/\*|\*)/) return ""
            sub(/(^|[[:space:]])\/\/.*$/, "", line)
            return line
        }
        FILENAME == rules_file {
            n++; id[n] = $1; inc[n] = $2; exc[n] = $3; pat[n] = $4; unless[n] = $5
            next
        }
        FILENAME == map_file { path_of[$2] = $1; next }
        FNR == 1 { path = path_of[FILENAME]; looking = 0; root_struct = 0 }
        {
            code = code_of($0)
            if (code == "") next
            for (i = 1; i <= n; i++) {
                if (pat[i] == "-") continue
                if (path !~ inc[i]) continue
                if (exc[i] != "-" && path ~ exc[i]) continue
                if (code !~ pat[i]) continue
                if (unless[i] != "-" && code ~ unless[i]) continue
                print path "\t" id[i] "\t" FNR
            }
        }
    ' "$rules" "$map" $files

    # Braces: a DSPrimaryButton inside a ScrollView's braces (main-action-in-scroll), and a
    # bottom inset that draws the bar or a full-width button (hand-pinned-action). Strings and
    # comments are left out before braces are counted.
    # shellcheck disable=SC2086
    awk -F'\t' -v rules_file="$rules" -v map_file="$map" '
        function code_of(line) {
            if (line ~ /^[[:space:]]*(\/\/|\/\*|\*)/) return ""
            sub(/(^|[[:space:]])\/\/.*$/, "", line)
            gsub(/"([^"\\]|\\.)*"/, "\"\"", line)
            return line
        }
        function covers(rule_id) {
            return path ~ inc[rule_id] && !(exc[rule_id] != "-" && path ~ exc[rule_id])
        }
        FILENAME == rules_file { inc[$1] = $2; exc[$1] = $3; next }
        FILENAME == map_file { path_of[$2] = $1; next }
        FNR == 1 { path = path_of[FILENAME]; depth = 0; scroll_at = -1; inset_at = -1 }
        {
            code = code_of($0)
            if (code == "") next
            if (scroll_at < 0 && code ~ /(^|[^A-Za-z0-9_])ScrollView[[:space:]]*(\([^)]*\))?[[:space:]]*\{/) {
                scroll_at = depth
            } else if (scroll_at >= 0 && code ~ /(^|[^A-Za-z0-9_])DSPrimaryButton[[:space:]]*\(/ && covers("main-action-in-scroll")) {
                print path "\tmain-action-in-scroll\t" FNR
            }
            if (code ~ /safeAreaInset\(edge: *\.bottom/) {
                if (inset_at < 0) inset_at = depth
            }
            if (inset_at >= 0 && code ~ /(^|[^A-Za-z0-9_])(DSBottomBar|DSPrimaryButton|DSSecondaryButton)[[:space:]]*[({]|dsFullWidthButton\(/ && covers("hand-pinned-action")) {
                print path "\thand-pinned-action\t" FNR
            }
            opened = gsub(/\{/, "{", code); closed = gsub(/\}/, "}", code)
            depth += opened - closed
            if (scroll_at >= 0 && depth <= scroll_at) scroll_at = -1
            if (inset_at >= 0 && depth <= inset_at) inset_at = -1
        }
    ' "$rules" "$map" $files

    # Tab roots: the first view inside each NavigationStack(path:) in the shell.
    local roots
    # shellcheck disable=SC2086
    roots=$(awk '
        /^[[:space:]]*(\/\/|\/\*|\*)/ { next }
        /NavigationStack\(path:/ { waiting = 1; next }
        waiting && /[^[:space:]]/ {
            waiting = 0
            if (match($0, /^[[:space:]]*[A-Z][A-Za-z0-9_]*[[:space:]]*\(/)) {
                name = substr($0, RSTART, RLENGTH); gsub(/[[:space:](]/, "", name)
                printf "%s%s", (count++ ? " " : ""), name
            }
        }
    ' $files)
    [[ -n $roots ]] || return 0
    # shellcheck disable=SC2086
    awk -F'\t' -v map_file="$map" -v roots="$roots" -v covered="$app" '
        BEGIN { split(roots, list, " "); for (i in list) is_root[list[i]] = 1 }
        FILENAME == map_file { path_of[$2] = $1; next }
        FNR == 1 { path = path_of[FILENAME]; current = ""; in_body = 0 }
        path !~ covered { next }
        /^[[:space:]]*(\/\/|\/\*|\*)/ { next }
        match($0, /^[[:space:]]*((public|private|fileprivate|internal)[[:space:]]+)?struct[[:space:]]+[A-Z][A-Za-z0-9_]*/) {
            name = substr($0, RSTART, RLENGTH); sub(/.*struct[[:space:]]+/, "", name)
            current = (name in is_root) ? name : ""; in_body = 0; next
        }
        current != "" && /var body: some View[[:space:]]*\{/ { in_body = 1; next }
        in_body && /[^[:space:]]/ {
            if ($0 ~ /^[[:space:]]*NavigationStack([[:space:]({]|$)/) print path "\tstack-in-tab-root\t" FNR
            in_body = 0; current = ""
        }
    ' "$map" $files
}

# Every Swift file the rules cover, as "path<TAB>file on disk".
app_paths() {
    git ls-files "$@" -- 'ios/DosarCuSina/*.swift' 'ios/DosarCuSinaWidgets/*.swift' \
        'ios/DosarCuSinaShare/*.swift' 'ios/Shared/*.swift' | sort -u
}

# --- Self-test ---------------------------------------------------------------
# Each rule has scripts/architecture-fixtures/<rule>.fail.swift, which must break
# it, and <rule>.pass.swift, which must break nothing. A fixture's first line
# names the path it pretends to live at: "// path: ios/…".

if [[ $mode == self-test ]]; then
    failures=0
    ids=$(cut -f1 "$rules")
    for rule_id in $ids; do
        for kind in fail pass; do
            fixture="$fixtures_dir/$rule_id.$kind.swift"
            if [[ ! -f $fixture ]]; then
                echo "  missing fixture $fixture" >&2
                failures=$((failures + 1))
                continue
            fi
            pretend=$(sed -n '1s|^// path: *||p' "$fixture")
            [[ -n $pretend ]] || { echo "  $fixture: the first line must be \"// path: ios/…\"" >&2; failures=$((failures + 1)); continue; }
            # The tab-root rule needs the shell that names the roots.
            map="$work/self-test.map"
            printf '%s\t%s\n' "$pretend" "$fixture" >"$map"
            if [[ $rule_id == stack-in-tab-root ]]; then
                printf '%s\t%s\n' "ios/DosarCuSina/Views/Shell/AppShell.swift" "$fixtures_dir/stack-in-tab-root.shell.swift" >>"$map"
            fi
            found=$(scan "$map" | cut -f2 | sort -u)
            if [[ $kind == fail ]] && ! grep -qx -- "$rule_id" <<<"$found"; then
                echo "  $fixture should break $rule_id, and doesn't" >&2
                failures=$((failures + 1))
            elif [[ $kind == pass && -n $found ]]; then
                echo "  $fixture should break nothing, and breaks: $(tr '\n' ' ' <<<"$found")" >&2
                failures=$((failures + 1))
            fi
        done
    done
    if [[ $failures -gt 0 ]]; then
        echo "Architecture check self-test failed ($failures)." >&2
        exit 1
    fi
    echo "Architecture check self-test passed ($(wc -l <"$rules" | tr -d ' ') rules)."
    exit 0
fi

# --- What to scan --------------------------------------------------------------

map="$work/files.map"
if [[ $mode == staged ]]; then
    staged="$work/staged"
    mkdir -p "$staged"
    paths=$(app_paths --cached)
    if [[ -n $paths ]]; then
        # shellcheck disable=SC2086
        git checkout-index --prefix="$staged/" -- $paths
    fi
    while IFS= read -r path; do
        [[ -n $path ]] && printf '%s\t%s\n' "$path" "$staged/$path"
    done <<<"$paths" >"$map"
    exceptions_file="$work/exceptions.txt"
    git show ":$exceptions_path" >"$exceptions_file" 2>/dev/null || : >"$exceptions_file"
else
    while IFS= read -r path; do
        [[ -n $path && -f $path ]] && printf '%s\t%s\n' "$path" "$path"
    done < <(app_paths --cached --others --exclude-standard) >"$map"
    exceptions_file="$exceptions_path"
    [[ -f $exceptions_file ]] || { exceptions_file="$work/exceptions.txt"; : >"$exceptions_file"; }
fi

findings="$work/findings.tsv"
scan "$map" | sort -t$'\t' -k1,1 -k2,2 -k3,3n >"$findings"

# --- Findings against the exceptions --------------------------------------------

# Exceptions as "path<TAB>rule<TAB>count", without comments or blank lines.
read_exceptions() {
    awk '
        { sub(/#.*/, ""); gsub(/[[:space:]]+/, "") }
        $0 == "" { next }
        {
            n = split($0, part, ":")
            count = (n >= 3) ? part[3] : 1
            print part[1] "\t" part[2] "\t" count
        }
    ' "$1"
}

read_exceptions "$exceptions_file" >"$work/exceptions.tsv"
result=$(awk -F'\t' -v rules_file="$rules" -v exceptions_file="$work/exceptions.tsv" '
    FILENAME == rules_file { known[$1] = 1; message[$1] = $6; next }
    FILENAME == exceptions_file {
        key = $1 "\t" $2
        if (!($2 in known)) { print "unknown\t" $1 "\t" $2; next }
        allowed[key] += $3; next
    }
    {
        key = $1 "\t" $2
        found[key]++; lines[key] = lines[key] (lines[key] == "" ? "" : ",") $3
    }
    END {
        for (key in found) {
            if (found[key] > allowed[key]) {
                split(key, part, "\t")
                print "new\t" part[1] "\t" part[2] "\t" found[key] "\t" (allowed[key] + 0) "\t" lines[key] "\t" message[part[2]]
            }
        }
        for (key in allowed) {
            if (found[key] < allowed[key]) {
                split(key, part, "\t")
                print "stale\t" part[1] "\t" part[2] "\t" (found[key] + 0) "\t" allowed[key]
            }
        }
    }
' "$rules" "$work/exceptions.tsv" "$findings" | sort)

problems=0
heading() {
    if [[ $problems -eq 0 ]]; then
        echo "Architecture check failed. AGENTS.md names one path for each job:" >&2
        echo >&2
    fi
    problems=$((problems + 1))
}

while IFS=$'\t' read -r kind path rule_id found allowed lines message; do
    [[ -z ${kind:-} ]] && continue
    case "$kind" in
        new)
            heading
            for line in ${lines//,/ }; do
                printf '  %s:%s  [%s]\n' "$path" "$line" "$rule_id" >&2
                if [[ -n ${GITHUB_ACTIONS:-} ]]; then
                    printf '::error file=%s,line=%s,title=%s::%s\n' "$path" "$line" "$rule_id" "$message"
                fi
            done
            printf '    %s\n' "$message" >&2
            if [[ $allowed -gt 0 ]]; then
                printf '    (%s found here, %s allowed by %s)\n' "$found" "$allowed" "$exceptions_path" >&2
            fi
            ;;
        stale)
            heading
            if [[ $found -eq 0 ]]; then
                printf '  %s:%s\n    Fixed, thank you. Remove this line from %s so it stays fixed.\n' \
                    "$path" "$rule_id" "$exceptions_path" >&2
            else
                printf '  %s:%s\n    %s allowed, %s left. Change the count in %s to %s.\n' \
                    "$path" "$rule_id" "$allowed" "$found" "$exceptions_path" "$found" >&2
            fi
            ;;
        unknown)
            heading
            printf '  %s:%s\n    No rule has this name. Remove the line from %s.\n' "$path" "$rule_id" "$exceptions_path" >&2
            ;;
    esac
done <<<"$result"

# --- The exceptions only shrink ---------------------------------------------------

if [[ -n $base ]]; then
    if git cat-file -e "$base:$exceptions_path" 2>/dev/null; then
        git show "$base:$exceptions_path" >"$work/base-exceptions.txt"
        read_exceptions "$work/base-exceptions.txt" >"$work/base.tsv"
        read_exceptions "$exceptions_file" >"$work/head.tsv"
        grown=$(awk -F'\t' '
            FILENAME == ARGV[1] { before[$1 "\t" $2] += $3; next }
            { now[$1 "\t" $2] += $3 }
            END { for (key in now) if (now[key] > before[key] + 0) { split(key, p, "\t"); print p[1] ":" p[2] "\t" (before[key] + 0) "\t" now[key] } }
        ' "$work/base.tsv" "$work/head.tsv" | sort)
        if [[ -n $grown && ${ARCHITECTURE_EXCEPTIONS_APPROVED:-false} != true ]]; then
            while IFS=$'\t' read -r entry before now; do
                heading
                printf '  %s\n    The exceptions list allows %s here, up from %s. Exceptions are only removed, never added:\n    ask the owner, who approves by labelling the pull request "architecture-exception".\n' \
                    "$entry" "$now" "$before" >&2
            done <<<"$grown"
        elif [[ -n $grown ]]; then
            echo "Exceptions added with the owner's approval:"
            awk -F'\t' '{ printf "  %s: %s, up from %s\n", $1, $3, $2 }' <<<"$grown"
        fi
    fi
fi

if [[ $problems -gt 0 ]]; then
    echo >&2
    echo "Use the path the message names. A rule that seems wrong is a question for the owner: say so in the pull request." >&2
    exit 1
fi

if [[ $mode != staged ]]; then
    listed=$(read_exceptions "$exceptions_file" | awk -F'\t' '{ sum += $3 } END { print sum + 0 }')
    echo "Architecture check passed ($(wc -l <"$rules" | tr -d ' ') rules, $listed known exceptions left)."
fi
