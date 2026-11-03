# AGENTS.md — Dosar cu Șină

Instructions for AI coding agents and the people who run them. Read this whole file before you change anything. The repository is **public**.

Read next, in this order: [docs/DECISIONS.md](docs/DECISIONS.md), [docs/HANDOFF.md](docs/HANDOFF.md), [SPEC.md](SPEC.md), [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/COPY_GUIDE.md](docs/COPY_GUIDE.md).

# The standing rule

**Everything we make together — apps, sites, scripts with UI, artifacts, dashboards, even CLI output — has to look and feel like something Apple shipped.**

This is not about a visual style (not "make it white", not "add Liquid Glass"). It's about the small details people never notice consciously but always feel. Before calling anything done, check it against this list:

## Feel
- Motion uses springs, not linear or default ease curves. Short (≈0.2–0.4s), interruptible, and it respects Reduce Motion.
- Every interaction answers back right away: press states, hover states, focus rings, haptics where the platform has them.
- Nothing jumps. Layout shifts, content popping in, and spinners that flash for 50ms are bugs. Use skeletons or fade-ins, and hold back loading indicators until a delay has passed.
- Sensible defaults so the first run already feels right. Fewer settings, not more.

## Look
- Typography does the hierarchy: the system font stack (SF Pro / -apple-system), tight tracking on large titles, a real type scale, tabular numbers where digits line up.
- Spacing sits on a consistent grid (4/8pt). Optical alignment wins over mathematical alignment when they disagree.
- Concentric corner radii (inner radius = outer radius − padding), continuous/squircle corners where possible.
- Restrained color: one accent, semantic colors, real dark mode (not inverted), hairline separators instead of heavy borders.
- Icons are SF Symbols, or match their weight and optical size.

## Care
- Empty states, error states, and edge cases get designed too, not left as defaults. Error messages are human, specific, and say what to do next.
- Copy is short and plain, in sentence case. No jargon, no exclamation marks.
- Accessibility is built in: Dynamic Type / scalable text, contrast, VoiceOver labels, keyboard navigation, hit targets of 44pt or more.
- Works at every size: phone width, narrow windows, huge screens. No horizontal scroll, no clipped text.
- Small touches nobody asked for: a correct app/tab icon, a sensible window title, remembered state, natural keyboard shortcuts, smart truncation.

When a tradeoff comes up between shipping fast and getting these details right, flag it instead of quietly dropping the detail.

# Framework, not patch

**Framework, not patch.** Fix the cause, not the symptom: a change that only makes one scenario look right isn't done, and say plainly when something is only a mitigation. Build for every case of its kind (every device, size, user and source), not the one on my desk: no hard-coded models, sizes, addresses or names. One source of truth, never a second path that does the same thing slightly differently. Pin the behaviour with tests. When a decision comes up, give the right long-term design, not the easy one.

# How agents work here

1. **Read first.** [docs/DECISIONS.md](docs/DECISIONS.md) says what was decided and why; [docs/HANDOFF.md](docs/HANDOFF.md) says where work stands and what the last session left. Don't undo a decision quietly: if you think one is wrong, say so in the pull request or an issue.
2. **One branch per task**, named `<person>/<topic>`, for example `ana/visit-wording`. Branch from an up-to-date `main`.
3. **Never push to `main`.** Open a pull request into `main` using the template. The owner reviews every one.
4. **Conventional commits** (see section 7), each one building on its own.
5. **Test lightly while working, fully once.** Run only the suites that cover your change while you iterate; after a fix, rerun only what failed. Run the whole suite (`./tests/run_tests.sh`) once before opening the pull request, and say in it which simulator you used. The pull request runs it again on GitHub (see "Checks on every pull request").
6. **Only simulators that are already installed.** Pick from `xcrun simctl list devices available`. Never download a simulator runtime or platform, and don't create devices for other OS versions. If a task truly needs one that isn't there, ask.
7. **No screenshots without asking.** Verify with builds and tests first. If only a screenshot or the simulator can show something, ask the person you work with before taking one, or ask them to look.
8. **Placeholder data only**, everywhere: code, tests, previews, fixtures, screenshots, commit messages. Plates like `B-123-ABC`, cars like `VW Golf 2018`, firms like `ENGIE Romania S.A.`, email like `nume@exemplu.ro`. A made-up CNP uses county code `99` with a valid control digit, such as `1800101990006`; the privacy check rejects any other CNP that passes the checksum.
9. **End each session by updating [docs/HANDOFF.md](docs/HANDOFF.md)**: append a "last session" entry and fix anything in "current state" your work changed.
10. **Ask before design choices.** When a layout or product change could reasonably go more than one way, name the options and ask. Obvious bugs with one clear fix: just fix them.
11. **Keep a way back.** When replacing something that works, keep the old version disabled (not deleted) until the new one is proven, and ask before removing it. `ios/Legacy/` and `tests/legacy/` are kept this way.
12. **Security problems are never written in the repository.** See section 5.

Turn on the hooks once per clone: `git config core.hooksPath .githooks`. Before each commit they run the privacy check and the architecture check.

# Checks on every pull request

Rules are checked, not remembered. Every pull request, and every push to `main`, runs three checks; all three must pass before the owner merges.

| Check | What it does | When it fails |
| :--- | :--- | :--- |
| `privacy-check` | [scripts/privacy-check.sh](scripts/privacy-check.sh) over every commit: no private paths, keys, home-folder paths or real CNPs. | Remove the value from every commit (rewrite the branch). |
| `architecture-check` | [scripts/architecture-check.sh](scripts/architecture-check.sh): code that goes around the paths in the architecture map below, such as `context.save()` outside `UnitOfWork`, `localizedDescription` shown to people, `String(format:)`, a hand-written plural, an animation curve outside `DS.Motion`, a bare `ProgressView()`, a notification or widget reload outside `SideEffectsCoordinator`, a built-in category key in a view, a stack in a tab root. Comments and tests don't count. | Each line names the file, the rule and what to use instead. Use that. |
| `build-and-test` | Builds the app, its widgets and share extension and runs `DosarCuSinaTests` through `./tests/run_tests.sh`, on GitHub's Xcode 27 Mac with an iPhone simulator it finds there. | The log is in the run; a failed run keeps the full log and result bundle as `test-results`. Reproduce with `./tests/run_tests.sh`. |

Run the architecture check yourself with `scripts/architecture-check.sh` (about a second). Code that broke a rule before the rule existed is listed in [scripts/architecture-exceptions.txt](scripts/architecture-exceptions.txt). That list only shrinks:

- When you fix a listed line, remove it (or lower its count) in the same commit. The check fails until you do, so a fixed problem can't come back.
- **Never add a line or raise a count without the owner's OK.** The pull request check fails on that unless the owner labels the pull request `architecture-exception`.
- A new rule comes with a failing and a passing fixture in `scripts/architecture-fixtures/` (`scripts/architecture-check.sh --self-test`) and lists today's violations as exceptions.
- A rule that seems wrong is a question for the owner: say so in the pull request. Never work around a pattern.

# Architecture map

One path per job. If you need to do one of these things, use the type listed. Never add a second path that does the same thing slightly differently; extend the existing one instead. Paths are relative to `ios/DosarCuSina/` unless they say otherwise.

## Changing household data

Every action saves once and rolls back on failure. Views never write models directly.

| Job | Use | File |
| :--- | :--- | :--- |
| Complete, undo, snooze, reschedule, pause, archive, delete or create an obligation; change its reminders | `ObligationActions` | [Services/Obligations/ObligationActions.swift](ios/DosarCuSina/Services/Obligations/ObligationActions.swift) |
| Record a visit, repair or purchase with its line items; rate a job | `HistoryActions` | [Services/History/HistoryActions.swift](ios/DosarCuSina/Services/History/HistoryActions.swift) |
| Create, edit, measure, re-parent or delete an asset | `AssetActions` | [Services/Obligations/AssetActions.swift](ios/DosarCuSina/Services/Obligations/AssetActions.swift) |
| Move something to another parent ("Mută la…"), with undo | `AssetActions.move`, `undoMove`, `moveDestinations` | [Services/Obligations/AssetActions+Move.swift](ios/DosarCuSina/Services/Obligations/AssetActions+Move.swift) |
| Name a personal document after its holder, or rename it for a new one | `DocumentNaming` | [Services/Documents/DocumentNaming.swift](ios/DosarCuSina/Services/Documents/DocumentNaming.swift) |
| What a document can be: its types, their variants and the names they give | `DocumentType` (`variants`, `documentName`) | [Models/Fields/ChoiceOptions.swift](ios/DosarCuSina/Models/Fields/ChoiceOptions.swift) |
| File, replace, archive or delete a document | `AttachmentActions` (`fileCaptured` for capture, `refile` for a photo already kept) | [Services/Documents/AttachmentActions.swift](ios/DosarCuSina/Services/Documents/AttachmentActions.swift), [CapturedDocumentFiling.swift](ios/DosarCuSina/Services/Documents/CapturedDocumentFiling.swift) |
| Create or edit a person or firm | `ProviderActions` | [Services/History/ProviderDirectory.swift](ios/DosarCuSina/Services/History/ProviderDirectory.swift) |
| Install, upgrade, create, order, hide, lock or delete a category | `TemplateStore` (built-ins defined once in `BuiltInTemplates`) | [Services/Templates/TemplateStore.swift](ios/DosarCuSina/Services/Templates/TemplateStore.swift), [BuiltInTemplates.swift](ios/DosarCuSina/Services/Templates/BuiltInTemplates.swift) |
| Find the subscription a bill or contract belongs to, or where a new one goes (codes first, never across two homes) | `SubscriptionMatcher`, with the template's keys in `SubscriptionFields` | [Services/Subscriptions/SubscriptionMatcher.swift](ios/DosarCuSina/Services/Subscriptions/SubscriptionMatcher.swift), [SubscriptionFields.swift](ios/DosarCuSina/Services/Subscriptions/SubscriptionFields.swift) |
| Obligations that belong to the household, not an asset | `HouseholdRules` | [Services/Templates/HouseholdRules.swift](ios/DosarCuSina/Services/Templates/HouseholdRules.swift) |
| Load or remove example data | `ExampleDataService` | [Services/Examples/ExampleDataService.swift](ios/DosarCuSina/Services/Examples/ExampleDataService.swift) |
| Export or import a `.dosar` archive | `DossierArchiveService` (what an import may change: `DossierImporter`; a password: `ArchiveEncryption`) | [Services/Archive/DossierArchiveService.swift](ios/DosarCuSina/Services/Archive/DossierArchiveService.swift), [DossierImporter.swift](ios/DosarCuSina/Services/Archive/DossierImporter.swift), [ArchiveEncryption.swift](ios/DosarCuSina/Services/Archive/ArchiveEncryption.swift) |
| The backup screen: Face ID first, the password, reading off the main thread, files from "Open in" | `BackupFlow` | [Views/Settings/BackupFlow.swift](ios/DosarCuSina/Views/Settings/BackupFlow.swift) |

Pure engines (no database) sit beside them: `RecurrenceEngine`, `AttentionModel` (with `missingBills`, the calm notes in Urmează), `BoxStatus`, `ReminderPlanner`, `MaintenanceLog`, `BillHistory` (a subscription's bill trend and the missing bill), `ReadinessEngine`, `SearchEngine`. Ranking, dates and wording come from these; screens never recompute them.

## Everything outside the database

`UnitOfWork` ([Services/Persistence/UnitOfWork.swift](ios/DosarCuSina/Services/Persistence/UnitOfWork.swift)) is how actions save. Every action saves through `UnitOfWork.save(context)`; never call `context.save()` from an action or a view. When one tap does several things (file a document under a new person, log a visit with its invoice, complete a deadline with the new document), wrap them in `UnitOfWork.perform(in:)`: the actions inside only record their changes and the unit saves once, everything or nothing. Work that must only happen once the changes are kept (releasing a capture's pages) goes in `UnitOfWork.afterCommit(in:)`. Show save failures with `SaveFailure.message(for:formKept:)`, never the system's error text.

`SideEffectsCoordinator` ([Services/SideEffects/SideEffectsCoordinator.swift](ios/DosarCuSina/Services/SideEffects/SideEffectsCoordinator.swift)) is the **only** path to notifications, the app badge, the widget snapshot and Spotlight (through its indexer hook). Actions save; the coordinator reacts to the save. Never schedule a notification, reload a widget or index anything from a view or an action. Notification permission is asked only with `setNeedsReconcile(allowPermissionPrompt: true)`, after the in-app explanation or from Settings.

## Secret fields

A field of type `secret` (an electronic identity card's PIN codes) and a secret row under Date importante (`CustomFact.isSecret`, an alarm or Wi-Fi code) follow one set of rules, in [Services/Security/SecretFields.swift](ios/DosarCuSina/Services/Security/SecretFields.swift):

- `AssetActions` seals every secret with `SecretSealer` before saving (`sealing`, `sealingFacts`); the database holds only sealed text. The key lives in the Keychain on this device only.
- Showing or copying one goes through `SecretReveal`, which asks `BiometricVaultManager.authenticateForReveal` every time and never changes the session. The screens use `DSSecretValueRow` to show and `DSSecretField` to type.
- Anything that carries values out of the binder (search, widgets, notifications, archives, logs) leaves secrets out: use `FieldDefinition.isIndexable`, `SecretFields.stripping` and `SecretFields.strippingFacts`. A sealed value is recognised by its own form, whatever the template says; `FieldFormatter.display` shows it only as a mask.
- An import never brings a secret and keeps the phone's own for the same records, in both modes (`keepingLocalSecrets`, `keepingLocalSecretFacts`).
- Never offer a secret field for a bank card, and never write a real-looking code in tests or examples (use `0000`).

## Capture

| Job | Use | File |
| :--- | :--- | :--- |
| Read a photo, scan, PDF or pasted text | `CaptureEngine` (`CaptureEngine.standard()`), the one way in for the app and the share extension | [Services/Capture/CaptureEngine.swift](ios/DosarCuSina/Services/Capture/CaptureEngine.swift) |
| Tiers 1–2: deterministic and heuristic | `CaptureAnalyzer` with `MRZParser`, `RomanianFieldExtractor`, `IdentityCardExtractor`, `DocumentClassifier` and the invoice parsers | [Services/Capture/](ios/DosarCuSina/Services/Capture/) |
| Tiers 3–4: on-device model, the person's optional AI provider, and grounding their answers | `OnDeviceModelExtractor`, `CloudCaptureExtractor` (with `CloudSchema` and `CloudAnswerMapper`) | [CaptureLanguageModels.swift](ios/DosarCuSina/Services/Capture/CaptureLanguageModels.swift), [CloudCaptureExtractor.swift](ios/DosarCuSina/Services/Capture/CloudCaptureExtractor.swift) |
| Prepare a photo for reading (find the card, flatten, turn, enlarge; the retry view) | `DocumentImageNormalizer` | [CaptureVision.swift](ios/DosarCuSina/Services/Capture/CaptureVision.swift) |
| When a document's dates can fall, and the century of two-digit years | `.within` rules in `CaptureConsistency`, identity windows in `IdentityTemplates` | [CaptureConsistency.swift](ios/DosarCuSina/Services/Capture/CaptureConsistency.swift) |
| AI providers: configuration, keys, one adapter per provider | `AIProviderSettings`, `AIProvider.adapter`, `AIClient` | [Services/AI/](ios/DosarCuSina/Services/AI/) |
| Decide between readers: which kind, which value when they disagree, what is offered beside it, and when a reading is weak | `ReadingArbiter` | [Services/Capture/ReadingArbiter.swift](ios/DosarCuSina/Services/Capture/ReadingArbiter.swift) |
| Which fields a kind of document may carry, after every tier | `CaptureFieldRules` | [Services/Capture/CaptureFieldRules.swift](ios/DosarCuSina/Services/Capture/CaptureFieldRules.swift) |
| Read label–value layouts (ID cards, licences, certificates) | `LabelledLayout`, with a label table per document kind | [Services/Capture/LabelledLayout.swift](ios/DosarCuSina/Services/Capture/LabelledLayout.swift) |
| What ties a bill or a contract to its ongoing contract: codes, service, a contract's terms | `ContractReader` (its label table through `LabelledLayout`) | [Services/Capture/ContractReader.swift](ios/DosarCuSina/Services/Capture/ContractReader.swift) |
| Save a reviewed capture | `CaptureFiler`, which only calls the actions above | [Views/Capture/Filing/CaptureFiler.swift](ios/DosarCuSina/Views/Capture/Filing/CaptureFiler.swift) |
| Things shared from other apps | `ShareInbox` (written by the extension), `IntakeInbox` (read by the app) | [ios/Shared/ShareInbox.swift](ios/Shared/ShareInbox.swift), [Views/Capture/IntakeInbox.swift](ios/DosarCuSina/Views/Capture/IntakeInbox.swift) |

A new document layout is a new label table, not new reading code. A new field rule goes in `CaptureFieldRules`, never inside one tier. A new AI provider is a new adapter; grounding and checks stay shared. Which reader wins is decided only in `ReadingArbiter`, never by the order the tiers run in.

## Locks

- `BiometricVaultManager` is the one unlock session for the app lock and the section locks. `confirmWholeBinder` asks before a backup or "Înlocuiește tot" whenever any lock is on.
- `LockCover.decide` is the one rule for when the app is covered, and `LockWindowHost` draws the lock and the app-switcher cover in a window above every sheet ([Views/Locks/LockWindow.swift](ios/DosarCuSina/Views/Locks/LockWindow.swift)). Never draw a lock as an overlay of one screen.
- `AppNavigator` hands out no route or opened file while the app is locked.
- What search may keep is decided in `SearchPrivacy` ([Services/Search/SearchPrivacy.swift](ios/DosarCuSina/Services/Search/SearchPrivacy.swift)).

## Navigation

- `AppRoute` is every place the app can open; `DeepLink` builds and parses `dosarcusina://` links ([Navigation/AppRoute.swift](ios/DosarCuSina/Navigation/AppRoute.swift)).
- `ShellRouter` and `ShellRouting.plan(for:)` turn a route into a tab, a path and maybe a sheet ([App/ShellRouter.swift](ios/DosarCuSina/App/ShellRouter.swift)). Notifications, widgets, links, Shortcuts and search results all go through it.
- `AppShell` owns one `NavigationStack` per tab and registers every route as a destination ([Views/Shell/AppShell.swift](ios/DosarCuSina/Views/Shell/AppShell.swift)). Tab roots must not add a stack of their own; push with `NavigationLink(value: AppRoute…)`.

## Design system

Everything visual comes from [Views/DesignSystem/](ios/DosarCuSina/Views/DesignSystem/). One component per job; extend it rather than drawing a look-alike.

- **Tokens:** `DS.Space` (4/8 grid), `DS.Radius` with `DS.Radius.concentric(outer:padding:)`, `DS.Motion` springs and `dsAnimation` (Reduce Motion handled), palette and type styles.
- **Full-width actions:** `DSPrimaryButton` for the main action, `DSSecondaryButton` for any other (with `role: .destructive` for deletions).
- **Checklists and single choices:** `DSCheckRow`, the whole row is the target.
- **Ratings:** `DSStarRating`, read-only or tappable.
- **Example data:** `DSExampleBadge` marks every example record.
- **Value rows:** `DSReadOnlyValueRow` for amounts and facts, `DSActionValueRow` for a value with one labelled action (copy, call), `DSSecretValueRow` for a masked code shown or copied after Face ID. Every copy goes through `Clipboard.copy(_:_:)`: `.personal` for anything read off an identity document, a sensitive value or anything from a locked section (this phone only, gone after a minute). Their buttons sit beside the value, or under it when they don't fit (`DSValueWithActions`), and never wrap their label.
- **States and feedback:** `DSEmptyState`, `DSErrorState`, `DSLockedState`, `DSDelayedProgress` (waits before showing), `DSToast.undo`, `dsDiscardGuard`.
- **Fields:** the `DS…Field` controls under `Fields/`, one per field type (`DSSecretField` for secrets). Number and money fields turn text into a value only while the person types; showing a value never changes it.
- [DesignSystemGallery.swift](ios/DosarCuSina/Views/DesignSystem/Gallery/DesignSystemGallery.swift) shows every component. Add new ones there.

## Words, numbers and dates

- **String Catalog:** [Resources/Localizable.xcstrings](ios/DosarCuSina/Resources/Localizable.xcstrings) (the widgets have their own in `ios/DosarCuSinaWidgets/`). Romanian is the source language. Every count uses plural variations (*1 zi*, *2 zile*, *20 de zile*); never write `count == 1 ? … : …`.
- **Distances in time:** `DurationWording` (days, then weeks, months and weeks, years and months; never rounded up), `DayCount` and `CalendarCount`, in [Services/Attention/BoxStatus.swift](ios/DosarCuSina/Services/Attention/BoxStatus.swift).
- **Money and dates:** `Money.formatted` and `Locale.dosarDefault` ([Models/Values/Money.swift](ios/DosarCuSina/Models/Values/Money.swift)), `CalendarDay` for due days. Never `String(format:)`.
- Copy follows [docs/COPY_GUIDE.md](docs/COPY_GUIDE.md).

## The placeholder-view contract

Screens know each other only by type name and initializer, such as `SectionScreen(assetID:)`, `ObligationScreen(obligationID:)`, `AddVisitFlow(assetID:)` or `OnboardingFlow(onFinish:)`, and move between each other with `AppRoute`. When two branches build screens in parallel, the branch that needs a screen first adds a placeholder with the agreed name and initializer (a `DSEmptyState`), so both branches build on their own. The branch that builds the real screen replaces the placeholder in place and keeps the name and initializer. Never change a screen's name or initializer without updating every caller in the same commit, and list any placeholder still in place in [docs/HANDOFF.md](docs/HANDOFF.md).

# Craftsmanship details

The standing rule above is the bar. These are the SwiftUI specifics.

## 1. Philosophy
- **Restraint and intentionality:** every element, border and margin needs a reason to exist. Chrome recedes so content leads.
- **Invisible polish:** fluid transitions, forgiving touch targets, instant responses, state that's kept.
- **Respect for the person:** never confuse, startle or overwhelm. No dark patterns, no needless modal interruptions. Respect the system settings: appearance, Reduce Motion, Increase Contrast, Dynamic Type.

## 2. Visual and typographic hierarchy
- **System fonts and the type scale** from the design system's type styles, with primary, secondary and tertiary labels.
- **Real typography:** Romanian quotes („ ”), apostrophes (’), en and em dashes, the ellipsis character (…), ș and ț with a comma below.
- **Concentric geometry:** nested corners follow inner radius = outer radius − padding (`DS.Radius.concentric`). All corners are continuous (`style: .continuous`). No sharp children inside rounded containers.
- **Depth:** soft, layered shadows, hairline separators, semantic materials. No heavy borders.

## 3. Motion and tactility
- **Springs only,** from `DS.Motion` (0.2–0.4 s), through `dsAnimation` so Reduce Motion turns movement into a short fade.
- **Physical transitions:** things grow from where they came from (the binder's boxes zoom open).
- **Feedback:** press states on everything tappable, `sensoryFeedback` for success, failure and selection.
- **No layout shift:** reserve space for content that loads, and hold back progress indicators with `DSDelayedProgress`.

# 4. Security and privacy in a public repository

## 4.1 No secrets, no personal data
- **No credentials in the repository:** no API keys, tokens, passwords, keystores, certificates or provisioning profiles.
- **Bring your own key:** the optional AI keys (one per provider: Google Gemini, OpenAI, Anthropic Claude, an OpenAI-compatible service) are entered by the person in Settings and kept in the iOS Keychain (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so they never leave the device). They are sent only in request headers, never in a URL. Developers use the same Settings screen with their own key; there is no build-time key. Never commit a key, even a test one.
- **Placeholder data only** (see "How agents work here", item 8). This covers names, emails, phone numbers, plates, VINs, CNPs, document numbers and addresses.
- **Local first, no central database:** data lives in SwiftData on the device. Sync, when it comes, uses the person's own private iCloud. There are no servers of ours, no accounts, no analytics and no telemetry. Don't add any SDK that phones home.

## 4.2 What protects the repository
- The versioned pre-commit hook [.githooks/pre-commit](.githooks/pre-commit) and the pull request workflow [.github/workflows/privacy-check.yml](.github/workflows/privacy-check.yml) run the same script, [scripts/privacy-check.sh](scripts/privacy-check.sh). It blocks private and credential paths, keys and tokens, home-folder paths and real-looking CNPs.
- The script lists patterns only. Never add a finding, a trace or a real value to it.
- Links in documents are relative to the repository. Never write an absolute path from your machine.

# 5. Security findings and the private vault

- `private/` exists **only on the owner's machine**. It holds security findings, internal bug traces and anything else that must never be published. It is ignored by git and blocked by the privacy check. Collaborators don't have it and don't need it.
- **Collaborators and their agents report security problems through GitHub's private vulnerability reporting**, as [SECURITY.md](SECURITY.md) explains. Never in issues, commits, code comments, pull request text, test names or documentation.
- Describe behaviour in public, never weaknesses. A fix's commit message says what now happens ("ask before replacing the household"), not how it could be abused.
- If you are the owner's agent: findings go in `private/VULNERABILITY_REGISTER.md`, crash logs and traces with local paths in `private/INTERNAL_BUGS.md`.

# 6. App Store distribution and feature tiers

To meet the App Store Review Guidelines (2.1 and 3.1.1):
- **Free:** the app is free to download and use, with no paywalls.
- **Complete without a key:** everything works offline and without an AI key: unlimited sections, deadlines and reminders, on-device reading of documents, widgets, backups.
- **Optional AI provider:** a key the person brings (Gemini, OpenAI, Claude or a compatible service) improves reading of a document they choose. The UI never blocks or nags anyone who doesn't add one.

# 7. Commits and workflow

## 7.1 Conventional commits

```text
<type>(<scope>): <short description in the imperative>

[optional body explaining why]

Co-Authored-By: <agent> <noreply@…>   (when an agent wrote it)
```

Types:
- `feat` — a new user-facing feature or screen, e.g. `feat(scanner): add live vision preview`.
- `fix` — a bug fix, e.g. `fix(reminders): ask for permission only after the explanation`.
- `docs` — documentation, e.g. `docs(spec): describe the share inbox`.
- `refactor` — restructuring without changing behaviour.
- `chore` — maintenance, build settings, tooling, templates.
- `test` — adding or modernising tests.

## 7.2 Atomic commits
- **One logical change per commit.** Don't mix a fix with a feature or with unrelated formatting.
- **Every commit builds** (`xcodebuild`) and keeps the tests that cover it passing.
- **Check what you stage** (`git status`, `git diff --cached`) so no temporary files, credentials or private notes slip in.

## 7.3 Where things are documented

| What changed | Update |
| :--- | :--- |
| Product behaviour or architecture | [SPEC.md](SPEC.md) |
| A product or architecture decision | [docs/DECISIONS.md](docs/DECISIONS.md) (newest first, with the reason) |
| Where work stands, what's next | [docs/HANDOFF.md](docs/HANDOFF.md) |
| Setup, build, run, test | [README.md](README.md) |
| How we work together | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Engineering and quality rules, the architecture map | [AGENTS.md](AGENTS.md) |
| A rule the architecture check enforces | [scripts/architecture-check.sh](scripts/architecture-check.sh), its fixtures, and "Checks on every pull request" above |
| How the app writes | [docs/COPY_GUIDE.md](docs/COPY_GUIDE.md) |
| The `.dosar` format | [shared/schemas/dosar-v3.md](shared/schemas/dosar-v3.md) and its fixtures |
| How to report a security problem | [SECURITY.md](SECURITY.md) |
| Security findings, crash traces | Never in the repository. Collaborators: private vulnerability reporting. Owner: `private/` on their own machine. |
