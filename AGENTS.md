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
8. **Placeholder data only**, everywhere: code, tests, previews, fixtures, screenshots, commit messages. Plates like `B-123-ABC`, cars like `VW Golf 2018`, firms like `ENGIE Romania S.A.`, email like `nume@exemplu.ro`. A made-up CNP uses county code `99` with a valid control digit, such as `1800101990006`; the privacy check rejects any other CNP that passes the checksum. Card numbers are only the published test numbers, such as `4111 1111 1111 1111`; the privacy check rejects any other number that passes the card check digit.
9. **End each session by updating [docs/HANDOFF.md](docs/HANDOFF.md)**: append a "last session" entry and fix anything in "current state" your work changed.
10. **Ask before design choices.** When a layout or product change could reasonably go more than one way, name the options and ask. Obvious bugs with one clear fix: just fix them.
11. **Keep a way back.** When replacing something that works, keep the old version disabled (not deleted) until the new one is proven, and ask before removing it. `ios/Legacy/` and `tests/legacy/` are kept this way.
12. **Security problems are never written in the repository.** See section 5.

Turn on the hooks once per clone: `git config core.hooksPath .githooks`. Before each commit they run the privacy check and the architecture check.

# Checks on every pull request

Rules are checked, not remembered. Every pull request, and every push to `main`, runs three checks; all three must pass before the owner merges.

| Check | What it does | When it fails |
| :--- | :--- | :--- |
| `privacy-check` | [scripts/privacy-check.sh](scripts/privacy-check.sh) over every commit: no private paths, keys, home-folder paths, real CNPs or card numbers. | Remove the value from every commit (rewrite the branch). |
| `architecture-check` | [scripts/architecture-check.sh](scripts/architecture-check.sh): code that goes around the paths in the architecture map below, such as `context.save()` outside `UnitOfWork`, `localizedDescription` shown to people, `String(format:)`, a hand-written plural, an animation curve outside `DS.Motion`, a bare `ProgressView()`, a notification or widget reload outside `SideEffectsCoordinator`, a built-in category key in a view, a stack in a tab root. Comments and tests don't count. | Each line names the file, the rule and what to use instead. Use that. |
| `build-and-test` | Builds the app, its widgets and share extension and runs `DosarCuSinaTests` through `./tests/run_tests.sh`, on GitHub's Xcode 27 Mac with an iPhone simulator it finds there. | The log is in the run; a failed run keeps the full log and result bundle as `test-results`. Reproduce with `./tests/run_tests.sh`. |
| `release-build` | Builds the app, its widgets and share extension in the Release configuration, the one TestFlight and the App Store get, without signing. | Usually code that builds only in development: something outside its `#if DEBUG` that needs what is inside. Reproduce with `xcodebuild build -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`. |

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
| Complete, snooze, reschedule, pause, archive, delete or create an obligation; change its reminders or how it repeats | `ObligationActions` | [Services/Obligations/ObligationActions.swift](ios/DosarCuSina/Services/Obligations/ObligationActions.swift) |
| Take back the step just taken ("Anulează") | The action's `UndoReceipt` (`UnitOfWork.performUndoable` makes it), shown with `DSToast.undo` | [Services/Persistence/UndoReceipt.swift](ios/DosarCuSina/Services/Persistence/UndoReceipt.swift), [RecordState.swift](ios/DosarCuSina/Services/Persistence/RecordState.swift) |
| Record a visit, repair or purchase with its line items; rate a job; delete an older record from Istoric | `HistoryActions` (`delete` does what `HistoryDeletion` says) | [Services/History/HistoryActions.swift](ios/DosarCuSina/Services/History/HistoryActions.swift), [HistoryDeletion.swift](ios/DosarCuSina/Services/History/HistoryDeletion.swift) |
| Create, edit, measure, re-parent or delete an asset | `AssetActions` | [Services/Obligations/AssetActions.swift](ios/DosarCuSina/Services/Obligations/AssetActions.swift) |
| Give a section's deadlines the reminders a changed value asks for (a document's type, a pet's species), unless the person set them (`Obligation.remindersCustomized`, set by `ObligationActions.setReminders` and `setFollowUpAfterLapse`) | `DeadlineReminders` (`follow`, run by `AssetActions.update`; `expected` and `refresh` for the repair list). Never write a deadline's profile from its section anywhere else | [Services/Obligations/DeadlineReminders.swift](ios/DosarCuSina/Services/Obligations/DeadlineReminders.swift) |
| Move something to another parent ("Mută la…"), with undo | `AssetActions.move` (returns its receipt), `moveDestinations` | [Services/Obligations/AssetActions+Move.swift](ios/DosarCuSina/Services/Obligations/AssetActions+Move.swift) |
| Name a personal document after its holder, or rename it for a new one | `DocumentNaming` | [Services/Documents/DocumentNaming.swift](ios/DosarCuSina/Services/Documents/DocumentNaming.swift) |
| What a document can be: its types, their variants and the names they give | `DocumentType` (`variants`, `documentName`) | [Models/Fields/ChoiceOptions.swift](ios/DosarCuSina/Models/Fields/ChoiceOptions.swift) |
| File, replace, archive or delete a document | `AttachmentActions` (`resolve` a capture's `CapturedDocumentRef`, then `fileCaptured`: new pages, or a kept copy that moves here with none of its old links) | [Services/Documents/AttachmentActions.swift](ios/DosarCuSina/Services/Documents/AttachmentActions.swift), [CapturedDocumentFiling.swift](ios/DosarCuSina/Services/Documents/CapturedDocumentFiling.swift) |
| Something of the person's added to an example | `ExampleOwnership.requireReal` in every creating action, which throws `ExampleSectionQuestion`; screens ask with `.examplePrompt` and `ExampleDataService.adopt` | [Services/Examples/ExampleOwnership.swift](ios/DosarCuSina/Services/Examples/ExampleOwnership.swift) |
| A situation's checklist (a trip, selling the car, a claim): where it is offered, its route, every rule and what a row's tap does | `ReadinessSituation` (the one list of situations), `ReadinessEngine.checklist`, drawn by `ReadinessScreen` with `DSReadinessRow`; a trip is kept by `TripPlanStore` | [Services/Readiness/ReadinessModels.swift](ios/DosarCuSina/Services/Readiness/ReadinessModels.swift), [ReadinessEngine.swift](ios/DosarCuSina/Services/Readiness/ReadinessEngine.swift), [Views/Readiness/](ios/DosarCuSina/Views/Readiness/) |
| Ask for a photo of a paper that belongs on a section ("Adaugă poza actului", a claim's policy) | `photoFirstCapture(isPresented:title:assetID:…)` | [Views/Capture/PhotoFirstCapture.swift](ios/DosarCuSina/Views/Capture/PhotoFirstCapture.swift) |
| Repair data an earlier version saved wrongly | `DataRepairs`: an ordered registry of idempotent steps with stored ids, run after `installBuiltIns` at launch and after every import; each step lists findings in plain words and changes only what the owner approved, in one `UnitOfWork`. A new repair is a new step at the end of `DataRepairs.steps`. `DataRepairCenter` feeds the list in Settings and the calm prompt | [Services/Repairs/DataRepairs.swift](ios/DosarCuSina/Services/Repairs/DataRepairs.swift), [DataRepairSteps.swift](ios/DosarCuSina/Services/Repairs/DataRepairSteps.swift), [PolicyRepairSteps.swift](ios/DosarCuSina/Services/Repairs/PolicyRepairSteps.swift), [TravelCutoffRepairStep.swift](ios/DosarCuSina/Services/Repairs/TravelCutoffRepairStep.swift), [UnitKeysRepairStep.swift](ios/DosarCuSina/Services/Repairs/UnitKeysRepairStep.swift) |
| The repairs capture and reminders need (documents with old links, visits without their invoice, firms kept twice, deadlines closed twice) | `CaptureRepairs`, `LikelyDoubleCompletions`, called only by their `DataRepairs` steps | [Services/Documents/CaptureRepairs.swift](ios/DosarCuSina/Services/Documents/CaptureRepairs.swift), [Intents/LikelyDoubleCompletions.swift](ios/DosarCuSina/Intents/LikelyDoubleCompletions.swift) |
| Record a counter or measured reading (edit form, visit, "Gata", capture, examples) | `HouseholdMutations.recordReading` (inside actions), `AssetActions.recordReading` on its own: the source (person, document, estimate: never stored), a lower counter throws `LowerReadingQuestion` (screens ask with `.readingPrompt` and save again with the answer), the hero value worked out from the readings | [Services/History/Readings.swift](ios/DosarCuSina/Services/History/Readings.swift) |
| Create or edit a person or firm; find who issued a document (`findOrCreate`: by its CUI, then by name, before a new one) | `ProviderActions`, `ProviderTaxID` | [Services/History/ProviderDirectory.swift](ios/DosarCuSina/Services/History/ProviderDirectory.swift) |
| Install, upgrade, create, order, hide, lock or delete a category | `TemplateStore` (built-ins defined once in `BuiltInTemplates`) | [Services/Templates/TemplateStore.swift](ios/DosarCuSina/Services/Templates/TemplateStore.swift), [BuiltInTemplates.swift](ios/DosarCuSina/Services/Templates/BuiltInTemplates.swift) |
| What a category of one's own keeps (*Are acte*, *Are facturi și contracte*, *Are revizii* and how often, its box), as its pockets, behaviour, counter and service blueprint (whose rule holds the interval) | `CategorySwitches` (read from and written to the definition), saved with `TemplateStore.createCustom(switches:)` and `editCustom`; asked by `CustomCategoryForm` | [Services/Templates/CategorySwitches.swift](ios/DosarCuSina/Services/Templates/CategorySwitches.swift), [Views/Section/CustomCategoryForm.swift](ios/DosarCuSina/Views/Section/CustomCategoryForm.swift) |
| What a category does: its box on the grid, what its page lists, its part (a person, personal documents, a subscription, a home), the pocket it shows in | `CategoryBehavior` on the template; find one by its part with `TemplateStore.template(withRole:)` | [Models/Templates/TemplateDefinition.swift](ios/DosarCuSina/Models/Templates/TemplateDefinition.swift), [Services/Templates/CategoryRoles.swift](ios/DosarCuSina/Services/Templates/CategoryRoles.swift) |
| A deadline's facts (insurer, policy number, claims phone; a car's RCA and CASCO, a home's PAD and optional policy each have their own) | `BlueprintFacts` on the blueprint, read with `DeadlineFacts` | [Models/Obligations/ObligationTypes.swift](ios/DosarCuSina/Models/Obligations/ObligationTypes.swift), [Services/Obligations/DeadlineFacts.swift](ios/DosarCuSina/Services/Obligations/DeadlineFacts.swift) |
| Whether something is still valid on a day; whether a deadline is worth making | `Obligation.isValid(on:)` and `DueDayValidity`; `ObligationBlueprint.isWorthScheduling` | [Models/Obligations/DueDayValidity.swift](ios/DosarCuSina/Models/Obligations/DueDayValidity.swift) |
| Built-in field and deadline keys that code names | `VehicleFields`, `HomeFields`, `DocumentFields`, `PetFields`, `PurchaseFieldKeys`, `BuiltInBlueprints`, `SubscriptionFields` | [Services/Templates/BuiltInFieldKeys.swift](ios/DosarCuSina/Services/Templates/BuiltInFieldKeys.swift) |
| Find the subscription a bill or contract belongs to, or where a new one goes (codes first, then the supply address with `house(at:among:)` and `PostalAddress`, never across two homes) | `SubscriptionMatcher`, with the template's keys in `SubscriptionFields` | [Services/Subscriptions/SubscriptionMatcher.swift](ios/DosarCuSina/Services/Subscriptions/SubscriptionMatcher.swift), [SubscriptionFields.swift](ios/DosarCuSina/Services/Subscriptions/SubscriptionFields.swift) |
| Keep a subscription's "Factura de plătit" in step with its direct debit (paused while the bank pays, back for a bill still to pay) | `BillReminders.follow`, run only by `AssetActions.update`; the next bill takes up a paused one through `CaptureFilingPlan.existingDeadline` | [Services/Subscriptions/BillReminders.swift](ios/DosarCuSina/Services/Subscriptions/BillReminders.swift) |
| Obligations that belong to the household, not an asset | `HouseholdRules` | [Services/Templates/HouseholdRules.swift](ios/DosarCuSina/Services/Templates/HouseholdRules.swift) |
| Load or remove example data | `ExampleDataService` | [Services/Examples/ExampleDataService.swift](ios/DosarCuSina/Services/Examples/ExampleDataService.swift) |
| Add a deadline to a section, from anywhere (its category's usual ones or one of the person's own) | `DeadlineForm`; a deadline of one's own takes its kind and reminders from `DeadlineChoice` | [Views/Add/DeadlineForm.swift](ios/DosarCuSina/Views/Add/DeadlineForm.swift) |
| Make a new section, from anywhere | `AddSectionFlow` with an `AddSectionRequest` | [Views/Section/AddSectionFlow.swift](ios/DosarCuSina/Views/Section/AddSectionFlow.swift) |
| Search the binder; keep its index up to date | `SearchIndexStore.shared(for:)` over `SearchIndexer` (off the main thread, reads again only what a save touched), built by `SearchIndexBuilder` | [Services/Search/SearchIndexer.swift](ios/DosarCuSina/Services/Search/SearchIndexer.swift), [SearchIndexBuilder.swift](ios/DosarCuSina/Services/Search/SearchIndexBuilder.swift) |
| What the iPhone's search (Spotlight) shows, and opening a result | `SpotlightCatalog` (the entries, by `SearchPrivacy`'s rules), kept by `SpotlightIndexer` through the coordinator; a result opens with `AppNavigator.open(spotlightIdentifier:)` | [Services/SideEffects/SpotlightCatalog.swift](ios/DosarCuSina/Services/SideEffects/SpotlightCatalog.swift), [SpotlightIndexer.swift](ios/DosarCuSina/Services/SideEffects/SpotlightIndexer.swift) |
| Export or import a `.dosar` archive | `DossierArchiveService` (what an import may change: `DossierImporter`; a password: `ArchiveEncryption`; from a screen, `importPackageAway`, written off the main thread) | [Services/Archive/DossierArchiveService.swift](ios/DosarCuSina/Services/Archive/DossierArchiveService.swift), [DossierImporter.swift](ios/DosarCuSina/Services/Archive/DossierImporter.swift), [ArchiveEncryption.swift](ios/DosarCuSina/Services/Archive/ArchiveEncryption.swift) |
| The backup screen: Face ID first, the password, reading off the main thread, files from "Open in" | `BackupFlow` | [Views/Settings/BackupFlow.swift](ios/DosarCuSina/Views/Settings/BackupFlow.swift) |

Pure engines (no database) sit beside them: `ReadingSeries` (the one cleaned series of readings every rate and projection reads), `RecurrenceEngine`, `AttentionModel` (with `missingBills`, the calm notes in Urmează), `BoxStatus`, `ReminderPlanner`, `MaintenanceLog`, `BillHistory` (a subscription's bill trend and the missing bill), `ReadinessEngine`, `SearchEngine`. Ranking, dates and wording come from these; screens never recompute them.

## The database's shape

Models live in the current `VersionedSchema` ([Models/Schema/DosarSchema.swift](ios/DosarCuSina/Models/Schema/DosarSchema.swift)); code uses the type aliases, never a version. A change to what is stored is a new version: freeze the one before it in [Models/Schema/Versions/](ios/DosarCuSina/Models/Schema/Versions/) (stored attributes and relationships only, exactly as they were), add a stage to `DosarMigrationPlan`, and pin both in `SchemaMigrationTests` (the frozen shape's fingerprint, and a store written by the version before that opens with everything in it). Keep it CloudKit-shaped: optional or defaulted, no unique constraints. Existing data that needs fixing goes through a `DataRepairs` step, which asks first.

## How urgent, and how long

| Job | Use | File |
| :--- | :--- | :--- |
| How urgent a deadline is, on any surface (Urmează, boxes, badges, hero, expiry fields, deadline page, widget, badge, Siri, reminders) | `UrgencyRule` (`ReminderProfile.urgencyRule`; `AttentionModel.entry(for:)` for a snapshot, `Obligation.urgency()` for a model) | [ios/Shared/Urgency.swift](ios/Shared/Urgency.swift) |
| The rule behind a date shown on a page (an expiry, a warranty's end) | `DateUrgency.rule(for:on:)`, and `rule(forField:…)` in a form | [Services/Attention/DateUrgency.swift](ios/DosarCuSina/Services/Attention/DateUrgency.swift) |
| When a reminder's lead falls (whole months are calendar months) | `ReminderLead` | [ios/Shared/Urgency.swift](ios/Shared/Urgency.swift) |
| When a document stops being good for travel (only a passport: six months before it expires) | Declared once as data, `DocumentType.travelMargins`; carried by `ReminderProfile.travelMarginDays` (stored on the deadline) into `UrgencyRule.travelCutoff` and `reminderAnchor`, which reminders, urgency, the page (`DueWording.travelLines`, `ReminderWording`) and the trip check read. Never test for a passport in code | [Models/Fields/ChoiceOptions.swift](ios/DosarCuSina/Models/Fields/ChoiceOptions.swift), [ios/Shared/Urgency.swift](ios/Shared/Urgency.swift) |
| How long, how far, and when in a few words | `DurationWording.distance` and `.lead`, `DurationWording.inside` for "în 5 zile" / "într-o lună" (never write "în \(…)" yourself), `WhenWording`, `DayCount`, `CalendarCount` | [ios/Shared/DurationWording.swift](ios/Shared/DurationWording.swift) |

Screens draw an urgency's tone (`DSStatus(tone)`, `DSStatusBadge(urgency:daysRemaining:)`, `DSStatusBadge(expiry:daysRemaining:)`); they never compare a number of days with a threshold (the `urgency-threshold` check).

## Everything outside the database

`UnitOfWork` ([Services/Persistence/UnitOfWork.swift](ios/DosarCuSina/Services/Persistence/UnitOfWork.swift)) is how actions save. Every action saves through `UnitOfWork.save(context)`; never call `context.save()` from an action or a view. When one tap does several things (file a document under a new person, log a visit with its invoice, complete a deadline with the new document), wrap them in `UnitOfWork.perform(in:)`: the actions inside only record their changes and the unit saves once, everything or nothing. A unit never waits: it takes synchronous work only, so gather what takes time (a capture's pages, Face ID) before it opens; then no other save can slip into it or be rolled back with it. Actions never roll back on their own; an action that does several things wraps them in `perform`, which joins the caller's unit. Work that must only happen once the changes are kept goes in `UnitOfWork.afterCommit(in:)`. A context one background task made for itself and no one else touches (a backup being written) saves through `UnitOfWork.performPrivate(in:)`: once, everything or nothing. An action the person can take back opens its unit with `UnitOfWork.performUndoable(in:)` and returns the `UndoReceipt`; there is no other undo, and an action that can't be undone returns no receipt. A new stored property goes into its model's `storedProperties` list too (`UndoReceiptTests` fails otherwise). Show save failures with `SaveFailure.message(for:formKept:)`, never the system's error text.

`SideEffectsCoordinator` ([Services/SideEffects/SideEffectsCoordinator.swift](ios/DosarCuSina/Services/SideEffects/SideEffectsCoordinator.swift)) is the **only** path to notifications, the app badge, the widget snapshot and Spotlight (through its indexer hook). Spotlight has one indexer, `SpotlightIndexer` ([Services/SideEffects/SpotlightIndexer.swift](ios/DosarCuSina/Services/SideEffects/SpotlightIndexer.swift)), registered by `shared(for:)`; what it may show is decided once in `SpotlightCatalog` with `SearchPrivacy.mayShowOutside` and `outsideText` ([SpotlightCatalog.swift](ios/DosarCuSina/Services/SideEffects/SpotlightCatalog.swift)). A new kind of result is a new entry there, never a second indexer. Actions save; the coordinator reacts to the save. Never schedule a notification, reload a widget or index anything from a view or an action. Notification permission is asked only with `setNeedsReconcile(allowPermissionPrompt: true)`, after the in-app explanation or from Settings.

Every "done" or "amână" from outside the app (reminder buttons, the widget's *Gata*, Siri and Shortcuts) goes through `IntentEngine.perform` ([Intents/IntentEngine.swift](ios/DosarCuSina/Intents/IntentEngine.swift)), with the cycle the person saw; never call `ObligationActions` from a notification, widget or intent directly. Get the coordinator with `SideEffectsCoordinator.shared(for:)`, never a second instance. Anything that carries obligations out of the app (reminders, the badge, widgets, intents, Spotlight) reads `ObligationSnapshot.fetchForOutside`, which leaves examples out.

## Secret fields

A field of type `secret` (an electronic identity card's PIN codes) and a secret row under Date importante (`CustomFact.isSecret`, an alarm or Wi-Fi code) follow one set of rules, in [Services/Security/SecretFields.swift](ios/DosarCuSina/Services/Security/SecretFields.swift):

- `AssetActions` seals every secret with `SecretSealer` before saving (`sealing`, `sealingFacts`); the database holds only sealed text. The key lives in the Keychain on this device only.
- Showing or copying one goes through `SecretReveal`, which asks `BiometricVaultManager.authenticateForReveal` every time and never changes the session. The screens use `DSSecretValueRow` to show and `DSSecretField` to type.
- Anything that carries values out of the binder (search, widgets, notifications, archives, logs) leaves secrets out: use `FieldDefinition.isIndexable`, `SecretFields.stripping` and `SecretFields.strippingFacts`. A sealed value is recognised by its own form, whatever the template says; `FieldFormatter.display` shows it only as a mask.
- An import never brings a secret and keeps the phone's own for the same records, in both modes (`keepingLocalSecrets`, `keepingLocalSecretFacts`).
- Never offer a secret field for a bank card, and never write a real-looking code in tests or examples (use `0000`).
- A bank card keeps its last four digits and never its number, security code or PIN. Any text the binder keeps or shows outside goes through `PaymentCardNumbers`; never add a field, a log line or an index entry that could hold a card number. Tests use the networks' published test numbers only (`4111 1111 1111 1111`, `5555 5555 5555 4444`).

## Capture

| Job | Use | File |
| :--- | :--- | :--- |
| Read a photo, scan, PDF or pasted text | `CaptureEngine` (`CaptureEngine.standard()`), the one way in for the app and the share extension | [Services/Capture/CaptureEngine.swift](ios/DosarCuSina/Services/Capture/CaptureEngine.swift) |
| What a kind of document means: its category, its deadline (by cover for a policy), the field that dates it, how it is kept, the issuer's trade, the fields it carries, the visit form, its title | `CaptureKindProfile` (`kind.profile`), one entry per kind, read by the router, the field rules, the AI provider's questions, the review and the filer | [Services/Capture/CaptureKindProfile.swift](ios/DosarCuSina/Services/Capture/CaptureKindProfile.swift) |
| What saving a review does (where the values land, the deadline made or moved, how early it reminds, who issued it) | `CaptureFilingPlan`, shown by the review's reminder line and carried out by `CaptureFiler` | [Views/Capture/Filing/CaptureFilingPlan.swift](ios/DosarCuSina/Views/Capture/Filing/CaptureFilingPlan.swift) |
| Tiers 1–2: deterministic and heuristic | `CaptureAnalyzer` with `MRZParser`, `RomanianFieldExtractor`, `IdentityCardExtractor`, `DocumentClassifier` and the invoice parsers | [Services/Capture/](ios/DosarCuSina/Services/Capture/) |
| Tiers 3–4: on-device model, the person's optional AI provider, and grounding their answers | `OnDeviceModelExtractor`, `CloudCaptureExtractor` (with `CloudSchema` and `CloudAnswerMapper`) | [CaptureLanguageModels.swift](ios/DosarCuSina/Services/Capture/CaptureLanguageModels.swift), [CloudCaptureExtractor.swift](ios/DosarCuSina/Services/Capture/CloudCaptureExtractor.swift) |
| Prepare a photo for reading (find the card, flatten, turn, enlarge; the retry view) | `DocumentImageNormalizer` | [CaptureVision.swift](ios/DosarCuSina/Services/Capture/CaptureVision.swift) |
| When a document's dates can fall, and the century of two-digit years | `.within` rules in `CaptureConsistency`, identity windows in `IdentityTemplates` | [CaptureConsistency.swift](ios/DosarCuSina/Services/Capture/CaptureConsistency.swift) |
| AI providers: configuration, keys, one adapter per provider | `AIProviderSettings`, `AIProvider.adapter`, `AIClient` | [Services/AI/](ios/DosarCuSina/Services/AI/) |
| Decide between readers: which kind, which value when they disagree, what is offered beside it, and when a reading is weak | `ReadingArbiter` | [Services/Capture/ReadingArbiter.swift](ios/DosarCuSina/Services/Capture/ReadingArbiter.swift) |
| Which fields a kind of document may carry, after every tier | `CaptureFieldRules` | [Services/Capture/CaptureFieldRules.swift](ios/DosarCuSina/Services/Capture/CaptureFieldRules.swift) |
| Read label–value layouts (ID cards, licences, certificates) | `LabelledLayout`, with a label table per document kind | [Services/Capture/LabelledLayout.swift](ios/DosarCuSina/Services/Capture/LabelledLayout.swift) |
| A value printed in parts, a series and a number (a policy's, an identity card's, an invoice's, a contract's, the CIV): its shape, reading it in any layout, writing it one way, a stray "document number" folded into a document's own (`CaptureKindProfile.numberKey`), and two readers' parts agreeing | `CompositeValue` (shapes as data), `LabelledLayout.composite`, `CompositeLabels` (tables for documents without a template), `CompositeValue.reconcile`, `ReadingArbiter.agreedValue` | [Services/Capture/CompositeValue.swift](ios/DosarCuSina/Services/Capture/CompositeValue.swift) |
| Find an amount on a line, and the one a label states | `RomanianFieldExtractor.amounts(inLine:)` (never a digit glued to letters), `statedAmount`, `standsAlone`, reading with `RomanianNumber` | [Services/Capture/RomanianFieldExtractor.swift](ios/DosarCuSina/Services/Capture/RomanianFieldExtractor.swift) |
| A personal document's layout (identity card, passport, licence, cazier, European health card, bank card) | One `IdentityTemplate` in `IdentityTemplates`, read by `IdentityDocumentReader`; the kind is personal (`isPersonalDocument`) when its profile names a `DocumentType` | [Services/Capture/IdentityTemplates.swift](ios/DosarCuSina/Services/Capture/IdentityTemplates.swift) |
| Keep a bank card's number out: of capture results, a document's text, fields, imports, search and Spotlight | `PaymentCardNumbers` (`redact`, `sanitizing`), `CaptureResult.withoutCardNumbers` at the engine's door; a card photo only with `CaptureReview.keepsPhotoOnRequest` | [Services/Security/PaymentCardNumbers.swift](ios/DosarCuSina/Services/Security/PaymentCardNumbers.swift), [CaptureResult+CardNumbers.swift](ios/DosarCuSina/Services/Capture/CaptureResult+CardNumbers.swift) |
| A document valid for a set time after its issue (a cazier judiciar, six months) | `DocumentType.validityMonthsAfterIssue`, worked out by `FieldDerivation.validityAfterIssue` and by the review | [Models/Fields/ChoiceOptions.swift](ios/DosarCuSina/Models/Fields/ChoiceOptions.swift) |
| What ties a bill or a contract to its ongoing contract: codes, service, the supply address, "debit direct" (`statesDirectDebit`, for every reader), a contract's terms | `ContractReader` (its label tables through `LabelledLayout`) | [Services/Capture/ContractReader.swift](ios/DosarCuSina/Services/Capture/ContractReader.swift), [ContractReader+Supply.swift](ios/DosarCuSina/Services/Capture/ContractReader+Supply.swift) |
| File any captured document: the review, "Am rezolvat" with the new document, a visit with its invoice | `CaptureFiler.file(_:)` with its `Intent`, which only calls the actions above (one rule for a new document's date: `renew`) | [Views/Capture/Filing/CaptureFiler.swift](ios/DosarCuSina/Views/Capture/Filing/CaptureFiler.swift) |
| Name a capture's document | `CapturedDocumentRef`: pages waiting with this capture's own claim, or a document already kept | [Services/Capture/CaptureDocumentStore.swift](ios/DosarCuSina/Services/Capture/CaptureDocumentStore.swift) |
| Read a picked document, read it again, end it with its screen | `CaptureSession` (cancels reading and lets go of its pages when its owner goes) | [Views/Capture/CaptureSources.swift](ios/DosarCuSina/Views/Capture/CaptureSources.swift) |
| Read a page again as another kind | `CaptureEngine.reinterpret(_:as:)`, for the AI's kind and the person's correction alike | [Services/Capture/CaptureEngine.swift](ios/DosarCuSina/Services/Capture/CaptureEngine.swift) |
| Find a keyword in read text, and fold text for comparing | `CaptureText.containsWord` (folded, phrase-aware, never the middle of a word) and `RomanianText.fold`, the one fold for search, choices and capture | [Services/Capture/CaptureText.swift](ios/DosarCuSina/Services/Capture/CaptureText.swift), [Models/Values/RomanianText.swift](ios/DosarCuSina/Models/Values/RomanianText.swift) |
| Things shared from other apps | `ShareInbox` (written by the extension; a versioned manifest, unreadable items set aside with `contents()`, the practice known by `expectPractice`), `IntakeInbox` (read by the app) | [ios/Shared/ShareInbox.swift](ios/Shared/ShareInbox.swift), [Views/Capture/IntakeInbox.swift](ios/DosarCuSina/Views/Capture/IntakeInbox.swift) |

A new document layout is a new label table, not new reading code. A value printed in parts is a `CompositeValue` shape read with `LabelledLayout.composite`, never a pattern of its own. A new field rule goes in `CaptureFieldRules`, never inside one tier. A new AI provider is a new adapter; grounding and checks stay shared. A new kind of document is a new `CaptureKindProfile` entry naming real catalog keys (the contract tests check them); how early its deadline reminds is its blueprint's, never capture's. Which reader wins is decided only in `ReadingArbiter`, never by the order the tiers run in.

## Locks

- `BiometricVaultManager` is the one unlock session for the app lock and the section locks. `confirmWholeBinder` asks before a backup or "Înlocuiește tot" whenever any lock is on.
- `LockCover.decide` is the one rule for when the app is covered, and `LockWindowHost` draws the lock and the app-switcher cover in a window above every sheet ([Views/Locks/LockWindow.swift](ios/DosarCuSina/Views/Locks/LockWindow.swift)). Never draw a lock as an overlay of one screen.
- `AppNavigator` hands out no route or opened file while the app is locked.
- What search may keep, and what may be shown outside the app in the iPhone's search, is decided in `SearchPrivacy` ([Services/Search/SearchPrivacy.swift](ios/DosarCuSina/Services/Search/SearchPrivacy.swift)).

## Navigation

- `AppRoute` is every place the app can open; `DeepLink` builds and parses `dosarcusina://` links ([Navigation/AppRoute.swift](ios/DosarCuSina/Navigation/AppRoute.swift)).
- `ShellRouter` and `ShellRouting.plan(for:)` turn a route into a tab, a path and maybe a sheet ([App/ShellRouter.swift](ios/DosarCuSina/App/ShellRouter.swift)). Notifications, widgets, links, Shortcuts and search results all go through it.
- `AppShell` owns one `NavigationStack` per tab and registers every route as a destination ([Views/Shell/AppShell.swift](ios/DosarCuSina/Views/Shell/AppShell.swift)). Tab roots must not add a stack of their own; push with `NavigationLink(value: AppRoute…)`.

## Design system

Everything visual comes from [Views/DesignSystem/](ios/DosarCuSina/Views/DesignSystem/). One component per job; extend it rather than drawing a look-alike.

- **Tokens:** `DS.Space` (4/8 grid), `DS.Radius` with `DS.Radius.concentric(outer:padding:)`, `DS.Control` (44 pt tap targets and the buttons' label heights), `DS.Motion` springs and `dsAnimation` (Reduce Motion handled), palette and type styles. `DS.Motion`, `dsAnimation` and `DSDelayedProgress` live in [ios/Shared/DSMotion.swift](ios/Shared/DSMotion.swift) so the widgets and the share extension use them too.
- **Full-width actions:** `DSPrimaryButton` for the main action, `DSSecondaryButton` for any other (with `role: .destructive` for deletions); `dsFullWidthButton(prominent:)` with a `DSButtonLabel` for a control that isn't a plain button (a `ShareLink`). A small action beside a row is `DSCompactButton`.
- **Rows that give way:** `DSAdaptiveStack`, side by side when the pieces fit at their natural width, stacked otherwise. Never `ViewThatFits` or a check of the text size for a row.
- **Checklists and single choices:** `DSCheckRow`, the whole row is the target.
- **A check's outcome:** `DSReadinessRow` (ready, worth a look, to fix, not in the binder), its colour from `DSStatus(readiness:)`; the whole row opens or adds.
- **Ratings:** `DSStarRating`, read-only or tappable.
- **Example data:** `DSExampleBadge` marks every example record.
- **Value rows:** `DSReadOnlyValueRow` for amounts and facts, `DSActionValueRow` for a value with one labelled action (copy, call), `DSSecretValueRow` for a masked code shown or copied after Face ID. Every copy goes through `Clipboard.copy(_:_:)`: `.personal` for anything read off an identity document, a sensitive value or anything from a locked section (this phone only, gone after a minute). Their buttons sit beside the value, or under it when they don't fit (`DSValueWithActions`), and never wrap their label.
- **Status badges:** `DSStatusBadge(urgency:daysRemaining:)` for a due day and `DSStatusBadge(expiry:daysRemaining:)` for an expiry draw the urgency the rule gives them; the design system draws a tone, never decides one.
- **States and feedback:** `DSEmptyState`, `DSErrorState`, `DSLockedState`, `DSDelayedProgress` (waits before showing), `DSToast.undo` (takes the action's receipt), `DSToast.failure`, `dsDiscardGuard`.
- **Fields:** the `DS…Field` controls under `Fields/`, one per field type (`DSSecretField` for secrets). Number and money fields turn text into a value only while the person types; showing a value never changes it.
- [DesignSystemGallery.swift](ios/DosarCuSina/Views/DesignSystem/Gallery/DesignSystemGallery.swift) shows every component. Add new ones there.

## Words, numbers and dates

- **String Catalog:** [Resources/Localizable.xcstrings](ios/DosarCuSina/Resources/Localizable.xcstrings) (the widgets have their own in `ios/DosarCuSinaWidgets/`, and code in `ios/Shared` uses the `Shared` table, [ios/Shared/Shared.xcstrings](ios/Shared/Shared.xcstrings), which both compile). Romanian is the source language. Every count uses plural variations (*o zi*, *2 zile*, *20 de zile*: a count of one is a word, in the "one" variant); never write `count == 1 ? … : …`. `scripts/plural-check.py` fails the test run for a counted string without them; an integer that isn't a count goes in `scripts/not-counts.txt` with its reason.
- **Distances in time:** `DurationWording.distance` (days, then weeks, months and weeks, years and months; never rounded up), `DurationWording.lead` for a reminder's lead, `WhenWording` for "azi", "în 5 zile", "depășit de 3 zile", `DayCount` and `CalendarCount`, in [ios/Shared/DurationWording.swift](ios/Shared/DurationWording.swift).
- **Units:** `MeasurementUnit` ([Models/Values/MeasurementUnit.swift](ios/DosarCuSina/Models/Values/MeasurementUnit.swift)) for a field's unit, a reading's, a counted deadline's and capture's: compare and store its `key`, show its `label`, write a number with its unit through `MeasurementUnit.written`. Never compare or store a unit's display text; a new unit is a new catalog entry.
- **Reading numbers:** `RomanianNumber.read(_:as:from:)` ([Models/Values/RomanianNumber.swift](ios/DosarCuSina/Models/Values/RomanianNumber.swift)), told the kind (money, count, meter index, kilometres), for every capture reader and every field; `RomanianNumber.format` writes what it reads back; `canonical` reads the machine form of archives and stored JSON. Never parse a number another way.
- **Money and dates:** `Money.formatted` ([Models/Values/Money.swift](ios/DosarCuSina/Models/Values/Money.swift)) and `Locale.dosarDefault`, the one app locale, Romanian whatever the phone's region ([ios/Shared/DosarLocale.swift](ios/Shared/DosarLocale.swift)). Never `String(format:)`.
- **Writing dates:** `DosarFormat` ([ios/Shared/DosarFormat.swift](ios/Shared/DosarFormat.swift)) for every date the app, widgets, notifications and search write, and `DueWording` ([Services/Attention/DueWording.swift](ios/DosarCuSina/Services/Attention/DueWording.swift)) for "Expiră în 5 zile · 7 noiembrie". A due day is a `CalendarDay` ([ios/Shared/CalendarDay.swift](ios/Shared/CalendarDay.swift)) and is written as one, never turned into a `Date` first: midnight in one time zone is the evening before in another. A moment (`Date`) is written in the time zone of the calendar the days are counted in.
- **Values from a newer version:** keep what can't be read raw (`FieldValues` keeps unknown entries), behave as the loudest case (`Consequence(stored:)`, `ObligationKind(stored:)`), never write back a downgraded value.
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
- The versioned pre-commit hook [.githooks/pre-commit](.githooks/pre-commit) and the pull request workflow [.github/workflows/privacy-check.yml](.github/workflows/privacy-check.yml) run the same script, [scripts/privacy-check.sh](scripts/privacy-check.sh). It blocks private and credential paths, keys and tokens, home-folder paths, real-looking CNPs and card numbers other than the published test numbers it lists.
- The script lists patterns only. Never add a finding, a trace or a real value to it.
- A past commit the card-number rule flags, once the owner has checked that it holds nobody's real number and a later commit fixed it, can be listed in [scripts/privacy-reviewed-commits.txt](scripts/privacy-reviewed-commits.txt): its commit id and a reason only. Only the owner adds to that list.
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
