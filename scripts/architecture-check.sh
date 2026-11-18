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
# copies the value it is given; the unit replaces the first when it saves. Since when a
# deadline's cycle is known is kept the same way, by the unit (CycleTimes) and the importer.
rule change-time-outside-change-times "$app" \
    '^ios/DosarCuSina/Services/Persistence/(ChangeTimes|CycleTimes)\.swift$|^ios/DosarCuSina/Services/Archive/DossierImporter\.swift$' \
    '(^|[^A-Za-z0-9_])(updatedAt|cycleKnownAt) *=([^=]|$)' \
    '^[[:space:]]*self\.updatedAt = (Date\(\)|updatedAt)[[:space:]]*$' \
    "Change times, and since when a deadline's cycle is known, are written only by the unit of work (ChangeTimes, CycleTimes). Pass the step's clock to it (UnitOfWork.perform(in:now:), save(_:now:)), and open an app-made step with origin: .app."

# A stored JSON object is written through its model's accessor, which lays the new value over
# what was stored and so keeps what a newer build wrote (KeptObject, KeptList). The models write
# their own data; a repair that rewrites stored JSON in place, never reading it into this
# build's types, is the one other writer.
rule stored-json-outside-model "$app" \
    '^ios/DosarCuSina/Models/|^ios/DosarCuSina/Services/Repairs/UnitKeysRepairStep\.swift$' \
    '(^|[^A-Za-z0-9_])(valuesData|customFactsData|sectionsData|blueprintsData|componentsData|behaviorData|recurrenceData|framingData|remindersData) *=([^=]|$)' - \
    "Write a stored JSON object through its model's accessor (values, customFacts, sections, behavior, recurrence, framing, reminders), or its kept form for what a backup carries (keptValues, keptFacts, keptSections, keptBehavior, keptRecurrence, keptFraming, keptReminders), so what a newer build wrote is kept."

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

# A count compared with one or two that picks one of two wordings ("== 1 ?", "> 1 ?", "< 2 ?"), on
# one line or with the "?" and ":" on the lines after it. Saying something only for several (a
# wording or nothing: nil, "", Text(verbatim: "")) is not a plural, so the other branch must be
# words too.
words='("[^"]|Text\( *"|String\( *localized|LocalizedStringKey|NSLocalizedString)'
rule hand-written-plural "$app" - \
    "(==|!=|<=?|>=?) *[12] *\\? *$words.* +: *$words" - \
    'Counts use plural variations in the String Catalog (1 zi, 2 zile, 20 de zile), never a choice between two strings. A wording that leaves out the number for one ("un act", "le pui la locul lor") is a plural variation too.'

# A screen's sheet or full-screen cover is one the shell's router knows is up (dsSheet,
# dsFullScreenCover in Navigation/ScreenSheets.swift), so a route from a notification, a widget
# or a search result closes it, or waits while it holds unsaved work, and never lands under it.
# The shell's own sheet ($router.sheet) is the router's.
rule sheet-outside-router '^ios/DosarCuSina/' '^ios/DosarCuSina/Navigation/ScreenSheets\.swift$' \
    '\.(sheet|fullScreenCover)\(' '\$router\.sheet' \
    "Present a screen's sheet with .dsSheet or .dsFullScreenCover (a system picker with .dsPresents beside it), so the router knows it is up: a route then closes it, or waits while it holds unsaved work, and never lands under it."

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
# ...Labels, ...Words or ...Prefixes in any other file, is a second table. So is a label spelled
# inside a pattern: an abbreviation or a field's number with its dots made optional ("c\.?\s?u",
# "d\.?\s?1"), words apart by any space ("cod\s+fiscal"), or a field's number that starts a line
# ("^\s*b\."); a reader builds those from the table's rows (RomanianFieldExtractor.printed).
label_tables='^ios/DosarCuSina/Services/Capture/(CaptureKindProfile|CaptureLexicon|CompositeLabels|IdentityTemplates)\.swift$'
rule labels-outside-their-table '^ios/DosarCuSina/Services/Capture/' "$label_tables" \
    '(labelledDate\(|lines\(containing: *|contains\(any: *|labels: *)\[ *"|let +labels *= *\[ *"|(let|var) +[A-Za-z_]*([lL]abels|[wW]ords|[pP]refixes)([^A-Za-z0-9_=][^=]*)?= *\[|[a-z0-9]\\\.\?\\s\?[a-z0-9]|[a-z][a-z]+\\s\+[a-z][a-z]|\^\\s\*[a-z0-9]\\\.' - \
    "Labels and words are data in their table: a kind's in its profile (CaptureKindProfile.labels, commonLabels for what every document prints), the shared readers' in CaptureLexicon, a value in parts' in CompositeLabels, a personal document's in its template. Tell the reader the table, as profile.labels(for:), and build a pattern from its rows with RomanianFieldExtractor.printed or alternatives; never list labels or words where they are read, nor spell them inside a pattern."

# Codes, numbers, plates and names are compared one way: folded, in capitals, letters and digits
# only (RomanianText.compact), so a value with a diacritic, a space or a dash still matches.
rule compact-outside-romanian-text "$app" '^ios/Shared/RomanianText\.swift$' \
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
# What a section keeps whole from the card rule (a pet's microchip) comes only from a value and
# its field's type, through PaymentCardNumbers.keepsWhole: never from digits alone, since a chip
# and a card can be the same digits.
rule kept-whole-without-its-type "$app" '^ios/(Shared/CardNumberRule|DosarCuSina/Services/Security/PaymentCardNumbers)\.swift$' \
    'KeptWhole\( *checkedDigits:' - \
    "Make PaymentCardNumbers.KeptWhole from values and their fields: KeptWhole(_:fields:), KeptWhole(typed:) or KeptWhole(section:template:), which keep only what the field's type keeps whole."

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

# A reminder's moment reaches the system in one place, whose date parts carry the app's
# calendar: parts without one are read in the phone's calendar (Buddhist, Japanese, Hebrew…),
# where the year means another one.
rule trigger-outside-reminder-trigger "$app" '^ios/DosarCuSina/Services/Reminders/ReminderTrigger\.swift$' \
    'UN(Calendar|TimeInterval)NotificationTrigger *\(' - \
    "Hand a reminder's moment to the system with ReminderTrigger.make(firingAt:), whose date parts carry the app's calendar, so it fires on that day whatever calendar the phone is set to."

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

# A dictionary built so that two equal keys stop the app. Records are never sure to be one per
# id: the same binder on two devices brings two copies of each record through iCloud until
# RecordsMeet joins them, and every launch reads them before it does. Nothing in the app traps on
# a repeated key, records or not, so no list can be the one that does.
rule unique-keys "$app" - \
    'uniqueKeysWithValues' - \
    "Two records can share an id until RecordsMeet joins them, so a dictionary must never stop the app on a repeated key. Use Dictionary(_:uniquingKeysWith:) and say which one is kept (the first, or RecordsMeet's own choice), or read the records after RecordsMeet.join."

# Whether a section is locked never depends on its category's record being there: a category
# that hasn't arrived yet (iCloud, an import) is locked by this device's choice for its key, else
# as the catalog says, else locked (CategoryTemplate.isSensitive(key:template:in:)). Reading a
# missing record as open (an optional lock defaulted to false, compared with true, or a vault
# check of an optional template defaulted to false) is the way around it. So is asking whether
# anything of the binder is locked from the category records alone (records filtered or searched
# by their lock: \.isSensitive, { $0.isSensitive }), which leaves out a section whose category
# hasn't arrived: BinderLocks asks the one answer for every category a section names.
rule lock-without-its-category "$app" - \
    'isSensitive *[}]? *[?][?] *false|[?][.]isSensitive *(==|!=) *(true|false)|isLocked *(\([$]0\))? *[)]? *[}]? *[?][?] *false|(where: *|[(])[^A-Za-z0-9_?!( ][.]isSensitive *[)]|[{] *[$]0[.]isSensitive *[}]' - \
    "Whether a section is locked never depends on its category's record being there. Use asset.isSensitive(template:) or isSensitive(among:), CategoryTemplate.isSensitive(key:template:in:), or vault.isLocked(asset, template:); whether anything of the binder is locked, or which categories are, is BinderLocks (read(in:), anySectionLocked, lockedKeys): a category that hasn't arrived yet stays locked."

# A version's models are frozen the day the next version comes: code that names one by its
# version (an extension, a predicate, the schema itself) silently stays with the frozen copy.
# Only the schema, its frozen versions and the migration stages, all in Models/Schema/, name a
# version; everything else uses the model aliases and CurrentSchema.
rule frozen-schema-version "$app" '^ios/DosarCuSina/Models/Schema/' \
    '(^|[^A-Za-z0-9_])DosarSchemaV[0-9]+[[:space:]]*[.]|(^|[^A-Za-z0-9_])extension[[:space:]]+DosarSchemaV[0-9]+' - \
    "Name a model by its alias (Asset, Obligation…) and the schema as CurrentSchema, never a version: a version is frozen when the next one comes, and what names it stays with the frozen copy. Only Models/Schema/ (the schema, its frozen versions, the migration stages) names a version."

# Actions, the unit of work, and the steps that change data with no one to tell: the category
# store's changes, the repair list, the household's own deadlines. Reading a category is not
# a change and may fall back.
rule silent-action-failure "$app" - \
    'try\? *(await +)?[A-Za-z_.]*[aA]ctions[.(]|try\? *(await +)?UnitOfWork\.|try\? *(await +)?(TemplateStore\([^)]*\)|[A-Za-z_]*[sS]tore)\.(installBuiltIns|createCustom|editCustom|setPockets|update|delete|move|setOnHome|setGrouping|setSensitive)\(|try\? *(await +)?[A-Za-z_.]*(DataRepair[A-Za-z]*|[rR]epairs)[.(]|try\? *(await +)?[A-Za-z_.]*(HouseholdRules\.|reconcileHouseholdRules\()' - \
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

# One meaning per word (docs/COPY_GUIDE.md, "Words with one meaning"). Three words are one
# thing each, and each has one home in code: "Anulează" takes back the step just taken, only
# on the undo toast (DSToast); "Gata" marks a deadline done, from the kind's completion wording
# (CompletionShape.actionTitle) and the widget's button; "De verificat" is the share inbox, its
# header in Adaugă. A sheet is left with "Renunță" (DSCancelButton) and closed with "Închide";
# an editor saves with "Salvează". Only a whole literal is checked: a sentence that uses the
# word in its own meaning ("Gata. Următoarea scadență e pe…") isn't the button.
rule anuleaza-outside-undo "$app" '^ios/DosarCuSina/Views/DesignSystem/Components/DSUndoToast\.swift$' \
    '"Anulează"' - \
    '„Anulează” only takes back the step just taken, on the undo toast (DSToast.undo with its receipt). To leave a sheet or a flow without saving, use DSCancelButton ("Renunță"); a dialog'"'"'s cancel is "Renunță" or what it keeps ("Păstrează").'
rule gata-outside-done "$app" '^ios/DosarCuSina/Views/Upcoming/CompletionWording\.swift$|^ios/DosarCuSinaWidgets/UpcomingWidget\.swift$' \
    '"Gata"' - \
    '„Gata” only marks a deadline done: its words come from the kind (CompletionShape.actionTitle, menuTitle) and the way in is CompletionEntry. To close a sheet or a page say "Închide"; an editor that keeps what was typed says "Salvează".'
rule de-verificat-outside-inbox "$app" '^ios/DosarCuSina/Views/Add/AddRoot\.swift$' \
    '"(Date )?[Dd]e verificat"' - \
    '„De verificat” is only the share inbox in Adaugă. The repair list is „De corectat”; a readiness check worth a look is „Merită o privire”.'

# Checked in its own pass below: a shaped screen is one shared screen whose parts vary by a
# declared kind (the visit form, by VisitKind). It holds no words of its own: every word comes from
# its kind's description or the words every kind shares, so every category reads right and
# docs/COPY_MATRIX.md shows it. A string literal with a letter in it is text of the screen's own,
# besides a symbol's name (systemImage:, systemName:) and what is interpolated into a literal.
# The visit form, „Am rezolvat”, the deadline form, a section page's pockets, adding a section,
# the capture review and a record's page in Istoric.
shaped_screens='^ios/DosarCuSina/Views/(Add/(AddVisitFlow|DeadlineForm|Visit/[A-Za-z]+)|Upcoming/ObligationCompleteSheet|Section/(SectionPocket(s|Layout)|AddSection(Flow|Model)|HistoryEntryScreen|CustomCategoryForm|SectionLists)|Capture/(CaptureReviewView|KeepPhotoChoice))\.swift$'
rule text-in-shaped-screen "$shaped_screens" - '-' - \
    "A shaped screen's words come from its kind's description (VisitShape through VisitForm, CompletionKind, CaptureKindProfile, HistoryEntryShape, PhotoOnRequest, CategorySwitches.Counter, the category's own definition) or from the words every kind shares beside it (VisitFormWording, CompletionWording, PocketWording, SectionListWording, CaptureReviewWording, AddSectionWording, CustomCategoryWording, DeadlineFormWording, HistoryEntryWording). Add the words there and draw them from it."

# Checked in its own pass below: tab roots are the views AppShell puts inside
# NavigationStack(path:), and their body must not start another stack.
rule stack-in-tab-root "$app" - '-' - \
    'Tab roots live inside the stack AppShell gives each tab. Push with NavigationLink(value: AppRoute…) instead of adding a stack.'

# Checked in their own pass below, which follows braces: a screen's or a sheet's main action
# is pinned to its bottom edge by one modifier, .dsPinnedAction, which shows it at any sheet
# height and text size. A main action written inside a ScrollView's braces sits at the end of
# scrolling content, out of sight; a bottom inset that draws buttons or the bar itself is a
# second pinned bar. The pass sees what is written inside the braces, not a property they name.
# A pocket's card (DSPocketCard) is always part of a scrolling page, so a DSPrimaryButton inside
# its braces counts too, wherever the card is written. A primary button in a struct that some
# ScrollView names is not followed: a card at the top of a page and an empty state's action do
# that rightly, and braces can't tell them from the end of the content.
rule main-action-in-scroll '^ios/(DosarCuSina|DosarCuSinaShare)/' "$design_system" '-' - \
    "Pin a screen's or a sheet's main action with .dsPinnedAction { DSPrimaryButton(…) }, with note: for what is said above it and secondary: for the actions under it. Inside the ScrollView it is lost at the end of the content; in a pocket's card, add with DSSecondaryButton like every pocket."
rule hand-pinned-action "$app" '^ios/Shared/DSBottomBar\.swift$' '-' - \
    'Pin actions with .dsPinnedAction (note: and secondary: for what goes with them), the one bar, which keeps its height, material and keyboard behaviour everywhere.'
# Checked in its own pass below, one struct at a time: a sheet of a locked screen lives inside its
# gate. A screen's own sheets (dsSheet, dsFullScreenCover) are drawn behind the lock its gate
# declares (EnvironmentValues.screenLock, set by LockGate), so when the lock comes back a sheet
# still up shows the locked state. A struct that decides a lock itself (isLocked( …)) and
# presents a sheet draws its own gate, so it says which lock its sheets live behind.
rule sheet-outside-its-lock "^ios/DosarCuSina/Views/" "^ios/DosarCuSina/Views/Locks/" '-' - \
    "A sheet of a locked screen lives inside its gate. Draw the screen through LockGate (or RouteLockGate), which puts its sheets behind the section's lock; a screen that draws its own locked state declares the lock its sheets live behind with .screenLock(…), .open when they show nothing of a locked section."
# A modifier on a Section or a ForEach reaches each view inside it (and a Section's header and
# footer) one by one, so a sheet, an alert or a dialog there is presented once for each of them:
# the copies that can't present make UIKit dismiss from the root, and Settings closed with the
# backup's password sheet. Found by braces and parentheses (presentation-on-section, below).
rule presentation-on-section "$app" - '-' - \
    "Hang a sheet, alert or dialog on one view that stays while it is up: the row or button that opens it, or the section's header. On a Section or a ForEach it reaches every row inside (and the header and footer), is presented once for each, and the extra copies close the screen under it."

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
        FNR == 1 { path = path_of[FILENAME]; looking = 0; root_struct = 0; statement = ""; split("", found) }
        {
            code = code_of($0)
            if (code == "") next
            # A line that starts with "?" or ":" goes on with the ternary above it: the rules see
            # the whole statement, and a finding is reported once, on its first line.
            if (statement != "" && code ~ /^[[:space:]]*[?:]/) {
                statement = statement " " code
            } else {
                statement = code; starts = FNR; split("", found)
            }
            for (i = 1; i <= n; i++) {
                if (pat[i] == "-" || (i in found)) continue
                if (path !~ inc[i]) continue
                if (exc[i] != "-" && path ~ exc[i]) continue
                if (statement !~ pat[i]) continue
                if (unless[i] != "-" && statement ~ unless[i]) continue
                found[i] = 1
                print path "\t" id[i] "\t" starts
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
        FNR == 1 { path = path_of[FILENAME]; depth = 0; scroll_at = -1; inset_at = -1; pocket_at = -1; nesting = 0; held = 0; chained_at = -1 }
        {
            code = code_of($0)
            if (code == "") next
            # presentation-on-section: "nesting" counts braces and parentheses, so a modifier
            # written over several lines is read as one. A Section or ForEach that closes at the
            # level it opened at leaves "chained_at": the lines starting with "." at that level are
            # its modifiers, until a line that is not one.
            if (chained_at >= 0) {
                if (nesting < chained_at) chained_at = -1
                else if (nesting == chained_at) {
                    if (code ~ /^[[:space:]]*\./) {
                        if (code ~ /^[[:space:]]*\.(sheet|dsSheet|alert|confirmationDialog|fileImporter|fileExporter|fullScreenCover|dsFullScreenCover|dsPresents|popover|inspector|userErrorAlert|documentShare|photoFirstCapture|examplePrompt|readingPrompt)[[:space:]]*[({]/ && covers("presentation-on-section")) {
                            print path "\tpresentation-on-section\t" FNR
                        }
                    } else chained_at = -1
                }
            }
            if (code ~ /(^|[^A-Za-z0-9_.])(Section|ForEach)[[:space:]]*(\(.*\))?[[:space:]]*\{/) {
                held++; held_at[held] = nesting
            }
            nesting += gsub(/[{(]/, "&", code) - gsub(/[})]/, "&", code)
            while (held > 0 && nesting <= held_at[held]) { chained_at = held_at[held]; held-- }
            opens_scroll = scroll_at < 0 && code ~ /(^|[^A-Za-z0-9_])ScrollView[[:space:]]*(\([^)]*\))?[[:space:]]*\{/
            if (opens_scroll) scroll_at = depth
            opens_pocket = pocket_at < 0 && code ~ /(^|[^A-Za-z0-9_])DSPocketCard[[:space:]]*\(.*\{[[:space:]]*$/
            if (opens_pocket) pocket_at = depth
            if (((scroll_at >= 0 && !opens_scroll) || (pocket_at >= 0 && !opens_pocket)) \
                && code ~ /(^|[^A-Za-z0-9_])DSPrimaryButton[[:space:]]*\(/ && covers("main-action-in-scroll")) {
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
            if (pocket_at >= 0 && depth <= pocket_at) pocket_at = -1
            if (inset_at >= 0 && depth <= inset_at) inset_at = -1
        }
    ' "$rules" "$map" $files

    # Shaped screens (text-in-shaped-screen): a string literal with a letter in it, besides a
    # symbol's name, is text the screen holds of its own. What is interpolated into a literal
    # ("\(name)") is code, not text, so it is taken out before letters are looked for.
    # shellcheck disable=SC2086
    awk -F'\t' -v rules_file="$rules" -v map_file="$map" '
        function words_in(text,    out, i, c, depth) {
            out = ""; depth = 0
            for (i = 1; i <= length(text); i++) {
                c = substr(text, i, 1)
                if (depth == 0 && c == "\\" && substr(text, i + 1, 1) == "(") { depth = 1; i++; continue }
                if (depth > 0) {
                    if (c == "(") depth++
                    else if (c == ")") depth--
                    continue
                }
                out = out c
            }
            return out
        }
        FILENAME == rules_file { inc[$1] = $2; next }
        FILENAME == map_file { path_of[$2] = $1; next }
        FNR == 1 { path = path_of[FILENAME] }
        {
            if (path !~ inc["text-in-shaped-screen"]) next
            if ($0 ~ /^[[:space:]]*(\/\/|\/\*|\*)/) next
            rest = $0
            sub(/(^|[[:space:]])\/\/.*$/, "", rest)
            while (match(rest, /"([^"\\]|\\.)*"/)) {
                before = substr(rest, 1, RSTART - 1)
                literal = substr(rest, RSTART + 1, RLENGTH - 2)
                rest = substr(rest, RSTART + RLENGTH)
                if (before ~ /(systemImage|systemName):[[:space:]]*$/) continue
                if (words_in(literal) ~ /[A-Za-z]/) { print path "\ttext-in-shaped-screen\t" FNR; break }
            }
        }
    ' "$rules" "$map" $files

    # A sheet of a locked screen lives inside its gate (sheet-outside-its-lock): a top-level struct
    # that decides a lock itself and presents a sheet declares the lock its sheets live behind.
    # Strings and comments are left out before braces are counted.
    # shellcheck disable=SC2086
    awk -F'\t' -v rules_file="$rules" -v map_file="$map" '
        function code_of(line) {
            if (line ~ /^[[:space:]]*(\/\/|\/\*|\*)/) return ""
            sub(/(^|[[:space:]])\/\/.*$/, "", line)
            gsub(/"([^"\\]|\\.)*"/, "\"\"", line)
            return line
        }
        function settle() {
            if (open_struct && reads_lock && presents_at > 0 && !declares) print path "\tsheet-outside-its-lock\t" presents_at
            open_struct = 0; reads_lock = 0; presents_at = 0; declares = 0
        }
        FILENAME == rules_file { inc[$1] = $2; exc[$1] = $3; next }
        FILENAME == map_file { path_of[$2] = $1; next }
        FNR == 1 {
            settle()
            path = path_of[FILENAME]; depth = 0
            covered = path ~ inc["sheet-outside-its-lock"] && !(exc["sheet-outside-its-lock"] != "-" && path ~ exc["sheet-outside-its-lock"])
        }
        !covered { next }
        {
            code = code_of($0)
            if (code == "") next
            if (depth == 0 && code ~ /(^|[^A-Za-z0-9_])struct[[:space:]]+[A-Z]/) { settle(); open_struct = 1 }
            if (open_struct) {
                if (code ~ /(^|[^A-Za-z0-9_])isLocked\(/) reads_lock = 1
                if (presents_at == 0 && code ~ /\.(dsSheet|dsFullScreenCover)[[:space:]]*\(/) presents_at = FNR
                if (code ~ /\.screenLock\(/) declares = 1
            }
            depth += gsub(/\{/, "{", code) - gsub(/\}/, "}", code)
            if (open_struct && depth <= 0 && code ~ /\}/) settle()
        }
        END { settle() }
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
        # A rule that sees a mistake in more than one place has a failing fixture for each:
        # <rule>.fail.swift, then <rule>.fail-<what>.swift, each of which must break it alone.
        cases="fail"
        for extra in "$fixtures_dir/$rule_id".fail-*.swift; do
            [[ -f $extra ]] || continue
            extra=${extra##*/}; extra=${extra#"$rule_id".}; cases="$cases ${extra%.swift}"
        done
        for kind in $cases pass; do
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
            if [[ $kind == fail* ]] && ! grep -qx -- "$rule_id" <<<"$found"; then
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
