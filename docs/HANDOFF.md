# Handoff

A living document: where work stands, so the next person or agent can pick up. Keep "Current state" and "In progress" true. Append to "Last sessions" at the end of every session (newest first).

[SPEC.md](../SPEC.md) describes behaviour in full; this file is the short version plus what's moving.

## Current state

The template-engine overhaul (waves 1 and 2) is merged. The app builds for iOS 26 with Swift 6 and has about 330 tests in `ios/DosarCuSinaTests`.

| Area | What's built |
| :--- | :--- |
| Shell and navigation | Four labelled tabs, one `NavigationStack` per tab, every route through `ShellRouter`, `dosarcusina://` links, sheets that never stack, onboarding once. |
| Dosar (binder) | Grid of boxes with one status line each, zoom into a box, drag to reorder, category boxes (Acte, Garanții, Abonamente), Agenda last, empty first run with examples. |
| Sections | Heroes per style (vehicle, home, document, pet, standard), the nine pockets in one global order, editing with discard guard, delete that asks about filed records, "Adaugă o secțiune" including custom categories. |
| Urmează | Acum / Curând / Mai târziu from the attention model; the obligation page with what to bring, actions, reminder setup and "add to Calendar". |
| Adaugă and capture | Camera, photos, files, typing; the capture engine with all four tiers, per-kind field rules, the label-layout reader (Romanian ID card front, both layouts); review and filing; the visit flow with component checklists. |
| Share extension and inbox | Share from Mail, WhatsApp, Photos and Files into *De verificat*; the practice share in onboarding. |
| Widgets | Home Screen (small, medium) and Lock Screen (inline, rectangular), with "Gata". |
| Search | Diacritic-insensitive search over the whole binder, locked sections show titles only. |
| Settings and locks | Reminder time, app lock and section locks, categories on the binder, backup, Gemini key, examples, storage. |
| Engines | Obligation, asset, history, attachment and provider actions; recurrence; reminder profiles with follow-up after a lapse; attention model; box status; readiness (requirements on screen, scenarios engine only); search; household rules (rental income declaration); wording. |
| Side effects | Notifications, badge and widget snapshot through `SideEffectsCoordinator`. |
| Archive | `.dosar` v3 export and import (merge or replace), v2 import, golden fixtures in `shared/`. |
| Localisation | Romanian String Catalog with plural variations; Romanian formats for dates and money. |
| Repository | README, SPEC, AGENTS, CONTRIBUTING, SECURITY, decision log, this handoff, pull request and proposal templates, the versioned privacy check and its workflow. |

## In progress

- **Identity-document templates and column-aware reading**, on a separate branch, not merged yet: per-document templates and cross-checks for the new and old identity card, the passport and the EU driving licence, and reading values that sit in columns. Don't start overlapping work in `Services/Capture/` without checking with the owner.

## Known gaps

- **iCloud sync** to the person's private iCloud. The schema is ready; the store is local only.
- **Android port.** Paused; `android/` is the first version. The `.dosar` format is the contract.
- **Password-protected export** of `.dosar` archives.
- **Removing `ios/Legacy/`** (and `tests/legacy/`). Kept as a way back; remove only once the new app has been used for a while and the owner agrees.
- **The visit wording as a template field.** The visit flow's title and wording should come from the template, not from code.
- **Box order is kept on the device only.** It isn't part of the household data, so it won't sync or travel in an archive.
- **Spotlight.** The coordinator has an indexer hook; no Spotlight indexer is registered.
- **Readiness scenarios** (trip abroad, selling a vehicle, insurance claim): the engine and tests exist, no screen uses them.
- **Permission descriptions** for Calendar, Reminders and Contacts in the project settings still describe the first version; the app now uses the system's event editor and contact picker without asking for those permissions.
- **Developer Gemini key file.** `ios/Config.xcconfig.template` is tracked, but the project doesn't read a `Config.xcconfig`. Enter a key in the app's Settings instead.
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

### 2026-11-02 — owner (with Claude) — documentation for collaborators
- **Did:** rewrote README and SPEC to match the code (old spec in `docs/archive/`), added the standing rule, architecture map and agent routine to AGENTS, added CONTRIBUTING, SECURITY, this handoff and the decision log, the pull request and proposal templates, CODEOWNERS, and the versioned privacy check with its pull request workflow.
- **Tests:** none needed (no app code changed). The privacy check was run against staged sample files and the branch's own history.
- **Left open:** turning on branch protection and private vulnerability reporting on GitHub (owner).
- **Next:** pick from "Known gaps"; the identity-document branch is the active capture work.
- **Decisions:** added "Collaboration" (2026-11-02).
