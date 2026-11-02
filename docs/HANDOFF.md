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
| Search | Diacritic-insensitive search over the whole binder, locked sections show titles only. |
| Settings and locks | Reminder time, app lock and section locks, categories on the binder, backup, the optional AI provider and its key, examples, storage. |
| Engines | Obligation, asset, history, attachment and provider actions; recurrence; reminder profiles with follow-up after a lapse; attention model; box status; readiness (requirements on screen, scenarios engine only); search; household rules (rental income declaration); wording. |
| Side effects | Notifications, badge and widget snapshot through `SideEffectsCoordinator`. |
| Archive | `.dosar` v3 export and import (merge or replace), v2 import, golden fixtures in `shared/`. |
| Localisation | Romanian String Catalog with plural variations; Romanian formats for dates and money. |
| Repository | README, SPEC, AGENTS, CONTRIBUTING, SECURITY, decision log, this handoff, pull request and proposal templates, the versioned privacy check and its workflow. |

## In progress

Nothing at the moment.

## Known gaps

- **Loose "Factură …" deadlines from before.** Bills filed by earlier versions made a payment deadline under the home, not tied to a subscription. They stay as they are; nothing migrates them. New bills remind only through their subscription.
- **Subscriptions: what isn't read yet.** The address of consumption isn't read, so with two homes a first bill whose codes no home keeps waits for the person to pick the home (later bills find it by its codes). "Plata prin debit direct" printed on a bill isn't read; turning direct debit on doesn't remove a bill reminder already made.

- **Capture doesn't know cazier, bank cards and the other document types.** A photo of one taken from a person is filed as one of their documents, without a type; the person picks it in Editează.

- **iCloud sync** to the person's private iCloud. The schema is ready; the store is local only.
- **Android port.** Paused; `android/` is the first version. The `.dosar` format is the contract.
- **Password-protected export** of `.dosar` archives.
- **Removing `ios/Legacy/`** (and `tests/legacy/`). Kept as a way back; remove only once the new app has been used for a while and the owner agrees.
- **The visit wording as a template field.** The visit flow's title and wording should come from the template, not from code.
- **Box order is kept on the device only.** It isn't part of the household data, so it won't sync or travel in an archive.
- **Spotlight.** The coordinator has an indexer hook; no Spotlight indexer is registered.
- **Readiness scenarios** (trip abroad, selling a vehicle, insurance claim): the engine and tests exist, no screen uses them.
- **Permission descriptions** for Calendar, Reminders and Contacts in the project settings still describe the first version; the app now uses the system's event editor and contact picker without asking for those permissions.
- **No build in CI.** Only the privacy check runs on pull requests. A macOS workflow that builds and runs the tests could come later.

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
