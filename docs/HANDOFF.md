# Handoff

A living document: where work stands, so the next person or agent can pick up. Keep "Current state" and "In progress" true. Append to "Last sessions" at the end of every session (newest first).

[SPEC.md](../SPEC.md) describes behaviour in full; this file is the short version plus what's moving.

## Current state

The template-engine overhaul (waves 1 and 2) is merged. The app builds for iOS 26 with Swift 6 and has more than 470 tests in `ios/DosarCuSinaTests`.

| Area | What's built |
| :--- | :--- |
| Shell and navigation | Four labelled tabs, one `NavigationStack` per tab, every route through `ShellRouter`, `dosarcusina://` links, sheets that never stack, onboarding once. |
| Dosar (binder) | Grid of boxes with one status line each, zoom into a box, drag to reorder, category boxes (Acte, Garanții, Abonamente), Agenda last, empty first run with examples. |
| Subscriptions | One record per ongoing contract: the service, the codes its bills quote, the minimum period and its deadline, direct debit, the last bill; gas, electricity, water and internet or TV under their home, phone plans in Abonamente. Bills and contracts from capture find their subscription (`SubscriptionMatcher`), bills go in its history with their own due date to pay by, and a bill that hasn't come shows calmly in Urmează under "Din timp". Built-in catalog version 8. |
| Sections | Heroes per style (vehicle, home, document, pet, standard), the nine pockets in one global order, editing with discard guard, delete that asks about filed records, "Mută la…" for anything filed under something else, "Adaugă o secțiune" including custom categories. |
| Documents | Added for a person photo first or on one screen ("Scriu eu"), with variants as data on the document type; "Adaugă poza actului" on a document without a picture; the electronic identity card's two PIN codes as hidden secret fields. |
| Urmează | Acum / Curând / Mai târziu from the attention model, and "Din timp" for a bill that hasn't come; the obligation page with what to bring, actions, reminder setup and "add to Calendar". |
| Adaugă and capture | Camera, photos, files, typing; the capture engine with all four tiers ranked by evidence (`ReadingArbiter`), per-kind field rules, the label-layout reader (Romanian ID card front, both layouts); the AI provider as a second opinion, on a tap or automatically after a weak reading; review with other readers' values offered beside each field and the kind; filing; the visit flow with component checklists. |
| Share extension and inbox | Share from Mail, WhatsApp, Photos and Files into *De verificat*; the practice share in onboarding. |
| Widgets | Home Screen (small, medium) and Lock Screen (inline, rectangular), with "Gata". |
| Reminders | Each reminder carries its cycle; buttons, widget taps, Siri and Shortcuts go through one guarded way in (`IntentEngine.perform`) and re-plan after; a catch-up for a deadline added late; trimming by consequence with a last "open the app" reminder; background refresh; unsaved taps shown in Urmează. |
| Search | Diacritic-insensitive search over the whole binder, locked sections show titles only; read text from locked sections and anything shaped like a CNP are never indexed (`SearchPrivacy`). |
| Settings and locks | Reminder time, app lock and section locks (drawn in their own window above every sheet; links wait for unlocking), categories on the binder, backup, the optional AI provider and its key, examples, storage. |
| Engines | Obligation, asset, history, attachment and provider actions; recurrence (a series keeps its day of the month); reminder profiles with follow-up after a lapse; attention model; box status; readiness (requirements on screen, scenarios engine only); search; household rules (rental income declaration); wording. |
| Side effects | Notifications, badge and widget snapshot through `SideEffectsCoordinator`. |
| Archive | `.dosar` v3 export and import (merge or replace), optional password (whole file encrypted), Face ID before export and "Înlocuiește tot" when any lock is on, built-ins always from the app, v2 import, golden fixtures in `shared/`. |
| Localisation | Romanian String Catalog with plural variations; Romanian formats for dates and money. |
| Repository | README, SPEC, AGENTS, CONTRIBUTING, SECURITY, decision log, this handoff, pull request and proposal templates. Every pull request and push to `main` runs `privacy-check`, `architecture-check` (15 rules from AGENTS.md, with an exceptions list that only shrinks) and `build-and-test` (app, widgets, share extension and tests on GitHub's Xcode 27 Mac); the pre-commit hook runs the first two. |

## In progress

Nothing at the moment.

## Known gaps

- **Loose "Factură …" deadlines from before.** Bills filed by earlier versions made a payment deadline under the home, not tied to a subscription. They stay as they are; nothing migrates them. New bills remind only through their subscription.
- **Subscriptions: what isn't read yet.** The address of consumption isn't read, so with two homes a first bill whose codes no home keeps waits for the person to pick the home (later bills find it by its codes). "Plata prin debit direct" printed on a bill isn't read; turning direct debit on doesn't remove a bill reminder already made.

- **Capture doesn't know cazier, bank cards and the other document types.** A photo of one taken from a person is filed as one of their documents, without a type; the person picks it in Editează.

- **A counter reading lower than the last one is kept as a new reading.** It should replace the wrong one as a correction; until then a mistyped kilometre reading stays in the vehicle's history and can skew estimates.

- **iCloud sync** to the person's private iCloud. The schema is ready; the store is local only.
- **Android port.** Paused; `android/` is the first version. The `.dosar` format is the contract.
- **Import writes on the main thread.** Reading, checking and decrypting a backup run in the background; writing the records into the database still runs on the main thread, in one unit of work. A very large backup can pause the screen while it is written.
- **One merge rule for every record type.** History entries, line items, readings and documents are added only when new; they have no `updatedAt` to compare. A round-trip test over every stored property is still to write.
- **Removing `ios/Legacy/`** (and `tests/legacy/`). Kept as a way back; remove only once the new app has been used for a while and the owner agrees.
- **The visit wording as a template field.** The visit flow's title and wording should come from the template, not from code.
- **Box order is kept on the device only.** It isn't part of the household data, so it won't sync or travel in an archive.
- **Spotlight.** The coordinator has an indexer hook; no Spotlight indexer is registered.
- **Readiness scenarios** (trip abroad, selling a vehicle, insurance claim): the engine and tests exist, no screen uses them.
- **Permission descriptions** for Calendar, Reminders and Contacts in the project settings still describe the first version; the app now uses the system's event editor and contact picker without asking for those permissions.
- **Dates written in the phone's time zone.** Due days are worked out in the Bucharest calendar but written with `.formatted(.dateTime…)` in the phone's own time zone, so on a phone set to another zone every date reads a day early ("Expiră pe 11 august" for 12 August). The `build-and-test` check runs in UTC and shows it in five tests (binder wording, reminder presets, capture review, adding a person's document, subscriptions from capture). The fix belongs with one source for dates: `DosarFormat` and `DueWording` take the calendar's time zone, and the `date-format` exceptions go with it.
- **Architecture exceptions.** `scripts/architecture-exceptions.txt` lists 168 places that broke a rule before the check existed: built-in category keys in views (82), date formats outside `DosarFormat` (29), small tap targets, number readers, saves outside `UnitOfWork`, the system's error text, silent `try?` on actions and a few more. Each group says which piece of work removes it; remove lines as they're fixed.

- **Repairs waiting for the owner.** `CaptureRepairs` finds documents moved with their old place's links, visits saved without their invoice and firms kept twice, and repairs only what is approved. Nothing calls them yet; the repair list that asks comes with the numbers session.
- **Firms don't keep their CUI.** `ProviderActions.findOrCreate` matches by name; the filer and the visit already pass the CUI they read. Matching it first comes with the provider tax-ID field, in one coordinated step with the new database version, its migration and the `.dosar` mapping (together with the kind profiles).
- **Undo.** Only the visit's "Anulează" knows what it moved (a kept invoice goes back). Undo receipts for every action, deleting an older completion from Istoric, and the reading "Gata" leaves behind when undone are for a later session.

- **Deadlines an old reminder may have closed twice.** `LikelyDoubleCompletions.find` lists them and `undoSecond` undoes one (idempotent); nothing calls them yet. The coming repair list should show each one and run `undoSecond` only with the person's OK.
- **Siri and Shortcuts with the app lock on** open the app instead of answering. Not tried on a device yet.

## How to pick up work

1. Read [AGENTS.md](../AGENTS.md), [docs/DECISIONS.md](DECISIONS.md) and the last few entries below.
2. Pick something from "Known gaps", an open issue, or what the owner asked for. Check "In progress" so you don't overlap.
3. If it changes what a person sees or a decision, propose it first (issue with the **Proposal** template, or a draft pull request).
4. Branch as `<person>/<topic>`, work in small conventional commits, run the relevant tests as you go and the whole suite once at the end.
5. Open a pull request with the template. Update this file in the same pull request.

## Last sessions

Newest first. Copy this template:

```markdown
### YYYY-MM-DD — <person> (with <agent>, if any) — `<branch>`
- **Did:** what changed, in a line or two.
- **Tests:** suites run, and the simulator (name and iOS version).
- **Left open:** anything unfinished, placeholders still in place, known issues.
- **Next:** the most useful next step.
- **Decisions:** entries added to or questioned in DECISIONS.md, or "none".
```

Never write security findings, crash traces or local paths here. See [SECURITY.md](../SECURITY.md).

### 2026-11-02 — owner (with Claude) — `claude/fix-guardrails-350990`
- **Did:** the rules are checked on every pull request. A new workflow, `Checks`, runs `architecture-check` (on Linux, seconds) and `build-and-test` (on GitHub's `xcode-27` Mac: builds the app with its widgets and share extension and runs `DosarCuSinaTests` through `tests/run_tests.sh`, with the compiled system modules cached and a 60-minute limit). `scripts/architecture-check.sh` has 15 rules from AGENTS.md and the agreed fixes, each with a plain message, a failing and a passing fixture (`--self-test`), and today's 168 violations in `scripts/architecture-exceptions.txt`, which fails when a line is fixed but not removed and, on a pull request, when a line is added without the owner's `architecture-exception` label. The pre-commit hook runs it after the privacy check. `tests/run_tests.sh` picks the newest installed iOS at or above the project's deployment target (read from the project, not hard-coded) and can keep its build products and results for CI. README now asks for Xcode 27: the app uses the iOS 27 SDK.
- **Tests:** the check's self-test and a run over the tree with planted violations (a new one, a count too high, a fixed exception, an unknown rule, a stack in a tab root). The privacy check over the branch. The iOS suite runs in the pull request's `build-and-test`; not run locally, to keep the Mac free for the other sessions.
- **Left open:** the owner adds `privacy-check`, `architecture-check` and `build-and-test` as required checks in the `main` ruleset once they have run once, and creates the `architecture-exception` label when it's first needed. The other sessions running now (reminders, privacy and backups, capture and saves) will be asked by the check to remove the exception lines their fixes clear.
- **Next:** each agreed fix removes its own exceptions. Rules still to write as the fixes land: numbers through the shared reader once it exists (its file name `RomanianNumber*.swift` is already allowed), urgency and durations from the shared engines.
- **Decisions:** "Rules are checked, not remembered" in DECISIONS.md.

### 2026-11-02 — owner (with Claude) — `claude/privacy-locks-backups`
- **Did:** the lock and the app-switcher cover in their own window above every sheet (`LockWindowHost`, `LockCover`); links and opened backups wait for unlocking; the cover follows any lock that could have something on screen. Backups: Face ID before export and "Înlocuiește tot" whenever a lock is on, an optional password (`ArchiveEncryption`, documented in `shared/schemas/dosar-v3.md`), reading off the main thread with held-back progress, "Open in" files removed once read, the import through `UnitOfWork` (`BackupFlow`). Imports never change built-ins, never weaken a lock, file parents by the "Mută la…" rule, clamp future dates, and keep the phone's PIN codes in both modes; the app restores any built-in that differs at launch. Sealed values are recognised by their form at every exit. Search never indexes a locked section's read text or a CNP-shaped number; recent searches skip them. Personal values copy to this phone only, for a minute. "Cod secret" rows under Date importante. The zip writer refuses what a plain zip can't hold and reads slices. The database waits for the first unlock after a restart; the recovery screen promises only what it does.
- **Tests:** new `BackupRulesTests` (built-in rewrites in both modes, locks, parents, PINs and secret rows on restore, sealed values, encryption, zip limits, backup flow, lock cover, search privacy, secret rows, store opening); the whole suite once on iPhone 17e.
- **Left open:** not tried by eye in the simulator (the lock window over a sheet, the password sheet, the secret-row editor). Import still writes on the main thread (see "Known gaps"). `ExampleDataService` still saves directly (owned elsewhere).
- **Next:** try the lock over an open sheet and a password-protected restore on a phone; the round-trip test over every stored property.
- **Decisions:** "The lock and backups", "Search, copying and codes" and "A database that can't open yet" (2026-11-02).

### 2026-11-02 — owner (with Claude) — `claude/fix-capture-saves-e56b3c`
- **Did:** capture, filing and saving fixes from both reviews. A unit of work never waits, so another screen's save can't slip into it or be undone with it; actions don't roll back on their own; "Altceva…", example data and compaction are one step each. `CaptureFiler` is the only filer (review, "Am rezolvat" with the new document, visit with its invoice), with one deadline rule and `ProviderActions.findOrCreate`; `ObligationCompletion` is gone. `CapturedDocumentRef` with one claim per capture; a kept document that moves drops its old links. `CaptureSession` cancels reading and lets go of pages when its owner goes. The automatic AI reading asks before sending anything that may be an identity document or is headed for a locked section or a person's documents. `CaptureEngine.reinterpret` reads the page again when the kind changes, and the review lists the kind's missing fields. Examples become the person's only when they say so ("Păstrezi … ca al tău/a ta?"). `CaptureRepairs` for data already affected.
- **Tests:** new `UnitOfWorkTests` cases, `CapturedDocumentFilingTests` (one parameterised duplicate-photo test over the three entry points, shared twice in every order), `ExampleOwnershipTests`, `CaptureSessionTests`, `CaptureRepairTests`, `ProviderLookupTests`; `correctingTheKindBringsItsDeadline` replaced by tests that read real policy text. The covering suites while working and the whole suite once on iPhone 17 (E2A56DA4).
- **Left open:** see "Known gaps" (repairs not called yet, CUI on firms, undo). Not tried by eye in the simulator. When this branch takes in the guardrails pull request, remove the exception lines these fixes cleared.
- **Next:** the numbers session (one Romanian number reader) and the repair list that asks the owner.
- **Decisions:** "One filer, one document in one place, and steps that can't swallow each other" added.

### 2026-11-02 — owner (with Claude) — `claude/fix-reminders-87daeb`
- **Did:** reminders you can trust. One way in for every outside "done" and "amână" (`IntentEngine.perform`): reminders carry their cycle, a tap for a closed cycle changes nothing, shown reminders for closed cycles are cleared, and every outside action re-plans through the one coordinator (`SideEffectsCoordinator.shared(for:)`, passes one after another). Failed reminder buttons and widget taps show in Urmează ("Nu s-a salvat"). A catch-up reminder for deadlines added late; trimming by consequence then time, with the last place for „Deschide Dosar cu Șină o clipă”; background refresh (`BackgroundRefresh`, `UIBackgroundModes` fetch); durations worked out from the fire day. A monthly or yearly series keeps its day of the month, read from its completions. Siri and Shortcuts read `ObligationSnapshot.fetchForOutside` (no examples), need the phone unlocked, and open the app when the app lock is on. `LikelyDoubleCompletions` (`find`, and an idempotent `undoSecond`) for the coming repair list.
- **Tests:** new `OutsideActionsTests`, `CatchUpReminderTests`, `RecurrenceSeriesTests`; `notificationButtonsUseTheSameEngine` and `respectsTheSystemLimitByKeepingTheSoonest` changed on purpose (now `…ForTheirOwnCycle` and `…ByConsequenceThenTime`). Reminder, recurrence, widget and action suites while working; the whole suite once on iPhone 17 (iOS 26.4).
- **Left open:** background refresh, the Urmează notice and Siri with the app lock not tried on a device or by eye in the simulator. The repair list that uses `LikelyDoubleCompletions` belongs to the data-repair work.
- **Next:** try a reminder's "Am rezolvat" twice on a device, and the background refresh with Xcode's simulated launch.
- **Decisions:** "Reminders you can trust" added.

### 2026-11-02 — owner (with Claude) — `claude/subscriptions-from-capture`
- **Did:** subscriptions from capture. The subscription template carries the service (stable `service.*` keys), the codes (client code, contract number, POD, CLC, phone number), the start, the minimum period and its end, direct debit and the last bill, with "Se termină perioada minimă" and one "Factura de plătit"; catalog version 8. Contracts are a capture kind (`ContractReader` with a label table, classifier words, field rules, plausibility windows, the AI provider's schema). Bills and contracts find their subscription by their codes (`SubscriptionMatcher`, never across two homes), go under their home or stand on their own (phone plans), and a bill is logged in the subscription's history with its due date as the one bill reminder, none with direct debit. The loose "Factură …" deadline is disabled (kept in `CaptureFiler.looseBillReminder`). The trend of a subscription's bills in Bani and the missing bill in Urmează ("Din timp") come from `BillHistory`. "Mută la…" moves any subscription between homes and Abonamente. A derived field given with its inputs is now kept (a contract's printed end).
- **Tests:** new `SubscriptionTemplateTests`, `ContractCaptureTests`, `SubscriptionFilingTests`, `BillHistoryTests`; capture suites while working; the whole suite once on iPhone 17 (iOS 26.4). The privacy check passes across the branch.
- **Left open:** see "Known gaps" (old loose bills, the address of consumption, direct debit read off a bill). Not tried by eye in the simulator or with a live AI provider. The "Din timp" name for the calm section in Urmează is to confirm.
- **Next:** try a real ENGIE and Orange bill and contract; read "debit direct" off bills; consider reading the address of consumption to place a first bill in two-home households.
- **Decisions:** "Bills and contracts belong to their subscription" in DECISIONS.md.

### 2026-11-02 — owner (with Claude) — `claude/reading-arbitration`
- **Did:** readers ranked by evidence in one place, `ReadingArbiter` (the person's edits, then checked values, then the AI provider, then the phone's patterns, then Apple's model). The AI provider reads the whole page as a second opinion and names the kind; its kind replaces the phone's unless a checked zone, a payment barcode or a provider's format the classifier agrees with backs it. AI values missing from the phone's text are kept with "Verifică". What a reader read differently is offered beside the value ("Pe telefon am citit", "Pe telefon părea", "Gemini a citit", "Pe spatele actului scrie"), one mechanism for all. "Citește mai bine cu …" is always offered with a provider, and a new setting, "Citește automat când nu sunt sigur" (off by default), reads weak readings by itself. Reading again (the back of a card, or the AI) keeps the review on screen and merges into it.
- **Tests:** new `ReadingArbiterTests`; capture and AI suites while working; the whole suite once on iPhone 17 (iOS 26.4). The privacy check passes across the branch.
- **Left open:** not tried with a live provider or by eye in the simulator; the automatic reading doesn't run for invoices that open the visit flow; one AI date that repeats a phone label's date under another key now wins the consistency rule (the AI ranks above labels), so the label's date goes.
- **Next:** try a misread RCA policy and an angled identity card with a real key; watch how often "Citește automat" fires on ordinary bills.
- **Decisions:** "Reading by evidence: the AI provider as a second opinion" in DECISIONS.md, replacing the rule in "What a cloud provider's answer is worth".

### 2026-11-02 — owner (with Claude) — `claude/phone-fixes`
- **Did:** fixes from trying the app on a phone. A photo already in the binder is moved to where it's added; value buttons (copy, show) stay on one line and move under the value when they don't fit; a passport's trilingual labels are no longer read as its authority; bill lines only on documents that list them, only real lines, and editable in the review; a bill reader claims a document only when the classifier agrees; RCA and CASCO keep their own details on the vehicle (catalog version 7); a corrected kind brings its deadline, place and title; number fields no longer shrink a stored value (45724 km became 457).
- **Tests:** `DocumentPhotoTests`, `TrilingualLabelTests`, `LineItemRulesTests`, `PolicyFilingTests`, `NumberInputTests`; the whole suite on iPhone 17 (iOS 26.4). The privacy check passes.
- **Left open:** a car whose kilometres were saved wrong keeps the wrong reading in its history (see "Known gaps").
- **Next:** treat a counter reading lower than the last one as a correction.
- **Decisions:** "Number fields change only while the person types", "A corrected kind brings what depends on it", "Bill readers claim only bills", "Each car policy keeps its own details", "Bill lines: only real lines, and the person can fix them", "A photo already in the binder moves to where it's added now".

### 2026-11-02 — owner (with Claude) — `claude/model-picker`
- **Did:** a model picker in Settings → Inteligență artificială: the recommended model, the models the key can use (each provider's list request, one shared filter), or a name typed by hand. Listing works before a model is chosen (`AIProviderSettings.connection`).
- **Tests:** `AIModelListTests` with each provider's list format; the whole suite on iPhone 17 (iOS 26.4).
- **Left open:** nothing new.
- **Next:** try the picker with a real key.
- **Decisions:** none.

### 2026-11-02 — owner (with Claude) — `claude/documents-flow`
- **Did:** "Mută la…" for anything filed under something else (toolbar menu and edit sheet, a new person for documents, rename after the new holder, undo); adding a person's document photo first or on one "Scriu eu" screen, with variants as data on the document type and "Adaugă poza actului" on the document's page; the secret field type with the electronic identity card's two PIN codes (sealed, Face ID every time, never in search, widgets, notifications or archives). Built-in catalog version 6.
- **Tests:** the whole suite passes on iPhone 17e (iOS 26). New suites: `MoveTests`, `PersonalDocumentTests`, `SecretFieldTests`. The privacy check passes across the branch.
- **Left open:** document types capture doesn't know (see "Known gaps"); the CEI variant and the filed section's id were done right after, on the merge branch. Not checked on a device or in the simulator by eye.
- **Next:** teach capture the other personal document types (cazier, bank cards) through the same templates.
- **Decisions:** "Adding a document for a person, photo first", "Mută la…" and "Secret fields (PIN codes)" in DECISIONS.md.

### 2026-11-02 — owner (with Claude) — `claude/capture-reliability`
- **Did:** reading from imperfect library photos. Plausibility windows per document kind (and two-digit years resolved by them); the card found, flattened, turned and enlarged before reading, with the photo as taken kept; a dedicated pass for the machine-readable zone with check-digit-guided OCR-B repair; one retry with another view of a poorly read page and a calm "Poza e greu de citit" notice; the cloud tier rebuilt as an AI provider layer (Gemini, OpenAI, Claude, OpenAI-compatible) with one schema per document kind, shared grounding and checks, a key per provider and plain error messages.
- **Tests:** capture and AI provider suites while working; the whole suite (about 416 tests) passes on iPhone 17 (iOS 26.4). The privacy check passes.
- **Left open:** not tried on a real iPhone with library photos yet; the provider requests are checked against their documentation and canned answers, not against the live services; plain `http` to a home server may also need the app's local-network settings (Info.plist), not changed here.
- **Next:** try a handful of angled, glared library photos of each identity document on a device; tune the card-finding thresholds if a card is missed.
- **Decisions:** "AI providers: bring your own key, several providers, one contract", "What a cloud provider's answer is worth" and "Plausible dates per document kind" in DECISIONS.md.

### 2026-11-02 — owner (with Claude) — `claude/id-followups`
- **Did:** driving licences read as printed on the official Romanian specimen (shared rows, field 3 date, category boxes, a failed 4d kept with "Verifică"); the person's own edits kept when the back of a card is added, with a "Pe spatele actului scrie" note and "Folosește-l"; a new household member and their document saved in one save; the page viewer cross-fades with Reduce Motion.
- **Tests:** the whole suite passes on iPhone 17 (iOS 26.4). The privacy check passes.
- **Left open:** the health insurance card template; card regions for the templates (not measured on real specimens).
- **Next:** pick from "Known gaps".
- **Decisions:** "back of card vs the person's edits" in DECISIONS.md.

### 2026-11-02 — owner (with Claude) — `claude/project-review-quality-2252bc`
- **Did:** merged the identity-document templates (new and old identity card, passport, EU driving licence), column-aware reading with positions, date consistency rules, showing and filing identity data by person, the back-of-card prompt and the full-screen viewer; one duration wording for "how far away" ("2 luni și 3 săptămâni", "8 ani"); removed the unused developer key path and permission texts.
- **Tests:** the whole suite passes on iPhone 17 (iOS 26.4). The privacy check passes across the branch.
- **Left open:** the follow-ups under "In progress"; the health insurance card template (fields not confirmed against a specimen).
- **Next:** merge this pull request, then the follow-ups.
- **Decisions:** identity documents and durations entries in DECISIONS.md.

### 2026-11-02 — owner (with Claude) — documentation for collaborators
- **Did:** rewrote README and SPEC to match the code (old spec in `docs/archive/`), added the standing rule, architecture map and agent routine to AGENTS, added CONTRIBUTING, SECURITY, this handoff and the decision log, the pull request and proposal templates, CODEOWNERS, and the versioned privacy check with its pull request workflow.
- **Tests:** none needed (no app code changed). The privacy check was run against staged sample files and the branch's own history.
- **Left open:** turning on branch protection and private vulnerability reporting on GitHub (owner).
- **Next:** pick from "Known gaps".
- **Decisions:** added "Collaboration" (2026-11-02).
