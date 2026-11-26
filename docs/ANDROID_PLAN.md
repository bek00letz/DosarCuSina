# Dosar cu Șină for Android: the plan

A plan for the owner, written 25 November 2026. **The owner took all four recommendations the same day** (reading documents with an open-source reader that runs only on the phone, after a side-by-side test; the binder on the phone with `.dosar` backups for the first release; Android's own look with the same care; Kotlin, Compose and Room, Android 11 and later, Google Play, `com.ar.dosarcusina.app`). They are in [DECISIONS.md](DECISIONS.md) (2026-11-25). Where the phases stand is in [HANDOFF.md](HANDOFF.md).

## What we are making

The iOS app, in Kotlin, for Android phones, as close to all of it as Android allows. The iOS app stays the reference: [SPEC.md](../SPEC.md) says what "all of it" is, and when Android has to do something differently, this plan says so.

**The one rule that never bends:** a binder exported from the iPhone (`.dosar`, with or without a password) opens on Android with everything in it, and a binder exported from Android opens on the iPhone the same way. Nothing lost, either direction. That is built and proven first, before any screen.

## How big this is

The iOS app is about 90 000 lines of app code and 43 000 lines of tests, built over many waves. The port is the same amount of behaviour again. It goes in phases, each ending in something that works and is tested on GitHub, and each split between several agents working at once in their own branches. The old Android code in `android/` (from the first version, before the template engine and the v3 format) is kept as a way back, moved to `android/Legacy/` the way `ios/Legacy/` is kept, and only used for reference.

## How parity is kept, so the two apps don't drift

Copying 90 000 lines by hand and hoping they agree is a patch, not a framework. Four shared mechanisms keep the two apps saying and doing the same thing:

1. **One catalog, exported.** The built-in categories (their fields, deadlines, reminder profiles, components, words) are defined once, in the iOS code. An iOS test writes them to `shared/catalog/` as JSON, the way `CopyMatrixTests` writes [COPY_MATRIX.md](COPY_MATRIX.md), and fails when the committed file is out of date. Android reads that file; it never has a catalog of its own. The same goes for capture's label tables (`CaptureKindProfile`), the travel rules and the countries: data that is data on iOS is data in `shared/`, read by both.
2. **Shared test cases.** For each engine (reading Romanian numbers, recurrence, urgency, reminder planning, the attention list, readings and counters, capture on sample text), a set of cases in `shared/test-vectors/`: an input and the answer the iOS app gives. Both test suites run them. A case that one app answers differently fails on GitHub.
3. **The copy matrix, compared.** Android writes its own copy matrix from its shaped screens, and a check fails unless it matches the iOS one word for word (with a short, written list of words Android must say differently, such as „Face ID”).
4. **Archives both ways, on every pull request.** Golden archives made by each app are committed in `shared/fixtures/` (an iOS export and an Android export, each with and without a password). Each app's tests import the other app's golden archive and compare what came in, record by record, with what was meant to. Each app also checks that its own committed golden archive is still what its writer makes today (its contents, not its bytes: the export time and the salt change every time). So a change to either writer that the other can't read fails before it merges.

Rules that are checked, not remembered, carry over too: the Android build gets a check like `scripts/architecture-check.sh` (Android Lint and detekt rules for the same things: no phone calendar instead of the app's, no hand-written plurals, no save outside the unit of work, no notification outside the side-effects coordinator, and so on), and the privacy check covers `android/`.

## Phases, in order

### Phase 0: groundwork (one agent) — done
**Done** on 25 November 2026 (`claude/android-phase-0-f26361`): `core`, `archive` and `app` in `android/`, the first version in `android/Legacy/`, and the checks `android-build-and-test` and `android-lint` (Android Lint and detekt, warnings as errors; detekt is a 2.0 alpha, the first built for Kotlin 2.4). [README.md](../README.md#android) says how to build and test.

- A new Gradle project in `android/`, the old one moved to `android/Legacy/`.
- An Android workflow on GitHub (build, unit tests, lint, the architecture rules) that runs on every pull request beside the four iOS checks. You add it as a required check in the repository's settings (I can't change branch protection without your OK).
- Pure Kotlin modules for everything that doesn't need a phone (the archive, the engines, capture's readers), so their tests run in seconds on GitHub's Linux machines, with no emulator.

### Phase 1: the archive, both ways (three or four agents at once) — done
**Done** on 26 November 2026: a binder exported on either app imports on the other with nothing lost, checked on every pull request both ways (`GoldenIosArchivesTest` on Android, `AndroidGoldenArchiveTests` on iOS). What Phase 2 plugs into is listed in [HANDOFF.md](HANDOFF.md)'s Phase 1 entry.

- The value rules first: days kept as days (`CalendarDay`), times in UTC to the second (`MachineText`), Romanian numbers, values a newer version wrote kept raw and written back (`KeptObject`, `KeptList`, `JSONValue.laying`). **Done** (`claude/android-p1-values`): in `android/core` (`com.ar.dosarcusina.core.values`), with money's stored form, unit keys and the app's calendar, pinned by the iOS app's own answers in `shared/test-vectors/values/` (written by `ValueVectorsTests`, fresh or failing, `TEST_RUNNER_VALUE_VECTORS_WRITE=1`).
- The ZIP reader and writer with the same limits as iOS (`DosarZipEngine.Limits.standard`), never ZIP64, never the whole archive in memory. **Done** (`claude/android-p1-zip`): `DosarZipEngine` in `:archive`, with the iOS tests ported and [shared/test-vectors/archive](../shared/test-vectors/archive) read by both apps (each one's archives, and 17 crafted archives both refuse with the same kind of error).
- The password format (PBKDF2, then AES-GCM in chunks), byte for byte as [dosar-v3.md](../shared/schemas/dosar-v3.md) describes. **Done** (`claude/android-p1-zip`): `ArchiveEncryption` and the opening rule (`ArchiveOpening`, the iOS app's `DossierArchiveReader.opened`), with only `javax.crypto` and `java.text.Normalizer`; each app opens the other's protected archive.
- The importer: which copy wins (`ArchiveMerge`), "Adaugă" and "Înlocuiește tot", secrets never written or read, locks only ever raised, version 2 archives still read. **Done** (`claude/android-p1-importer`): `DossierArchiveReader`, `DossierImporter`, `ArchiveMerge` and `SecretRules` in `:archive`, its decisions pure, writing through `ArchiveTarget` (Phase 2's Room store implements it; the tests use `InMemoryBinder`), and version 2 through `DossierV2Converter`.
- The golden archives and the checks above, on both sides. *iOS half done* (`claude/android-p1-golden-ios`): `shared/fixtures/golden/ios/` holds an iOS export, its password-protected twin and their contents unpacked, kept fresh by `GoldenArchiveTests`, which also imports both back into an empty binder; `shared/fixtures/golden/README.md` says how. *Android half done* (`claude/android-p1-writer`): `DossierArchiveWriter` writes v3, with or without a password; `shared/fixtures/golden/android/` holds Android's export of the iOS household brought into an empty Android binder (iOS → Android → iOS), kept fresh by `GoldenAndroidArchivesTest` (`-PwriteGoldenArchives`, or a failed run's `android-golden-archives`), and imported by the iOS suite's `AndroidGoldenArchiveTests`; its data files come out byte for byte the iOS ones. **Done when** both fixtures, an iOS export and its password-protected twin import on Android with nothing lost, and an Android export imports in the iOS test suite with nothing lost.
- Scanned pages may be HEIC or JPEG (the owner's OK, 25 November; [dosar-v3.md](../shared/schemas/dosar-v3.md) says so). Android writes HEIC where the phone can (the Pixel 6a can) and JPEG where it can't. The iOS writer, which already keeps a page as JPEG where HEIC isn't available but names every page `.heic`, names a JPEG page `.jpg`, with a test; both readers know a picture by its bytes. *iOS done* (`claude/android-p1-golden-ios`): pages and thumbnails are named by their bytes (`DossierV3.Path.pictureExtension`), pinned by `ArchivePicturesTests`, with an older archive's JPEG named `.heic` still coming in.

### Phase 2: the store and the one way to save (two or three agents) — done
**Done** on 26 November 2026, in seven pull requests (#153 to #159); what each left for later phases is in [HANDOFF.md](HANDOFF.md)'s Phase 2 entry.

- The database (Room, on SQLite) in the same shape as the iOS models (database version 19), with migrations tested from the first version on. **Done** (#155): `android/store`, Room 3 on bundled SQLite, one table per iOS model, its shape pinned to the iOS `storedProperties` (`StoreShapeTest`); `RecordContents`, `ParentLinks`, `StayOnThePhone`; `RoomArchiveTarget` passes the importer's own tests. The section locks' data rules too (#156, `store.locks`). As on iOS, no link deletes what it points at: a record goes with what it holds only through one path (`RecordContents`), and each held record keeps its holder's id. What belongs to one phone (which copy a record is, since when a cycle is known, when a category was last locked anywhere) stays out of backups, as `DossierV3.stayOnThePhone` says.
- The unit of work: every save once, everything or nothing, change times kept by one writer, card numbers masked, "Anulează" for every step (`UndoReceipt`), deletions that take what a record holds. **Done** (#157): `UnitOfWork` and `Step`, `ChangeTimes`, `CycleTimes`, masking through `core.text` (#154: the card-number, IBAN and text rules, pinned by `shared/test-vectors/text/`), `UndoReceipt`, imports through `performPrivate`, launch's app-made steps in `LaunchData`.
- The catalog read from `shared/catalog/`, categories of one's own, the repair list (`DataRepairs`), the examples. **Done** except the examples: the catalog (#153, `android/catalog`, written by `CatalogExportTests`, with what a category of one's own and the household's deadlines are made of, #159); categories and the household's own deadlines (#159, `TemplateStore`, `CategorySwitches`, `HouseholdDeadlines`); the repair list (#158, all 31 steps in the iOS order, 9 ported, the others waiting on what Phase 3 brings). **The examples move to Phase 3**: iOS builds them through the actions, which come there.

### Phase 3: the engines (three or four agents) — done
**Done** on 26 November 2026, in pull requests #160 to #182: every engine below in `android/core`, `android/catalog` and `android/store`, each pinned by the iOS app's answers in `shared/test-vectors/`, with Android's words generated from the iOS String Catalogs (`core.wording`), the document catalog and the examples, loaded from the one household the iOS app declares (`shared/catalog/examples/`). What each left for later phases is in [HANDOFF.md](HANDOFF.md)'s Phase 3 entry.

Recurrence, reminder profiles and urgency, the attention list behind Urmează, box lines, readings and counters, history and the maintenance log, subscriptions and bills, readiness checks (*Pleci din țară*, *Vinzi mașina*, *Ai avut o daună*), search, and the wording (durations, money, Romanian plurals). Each proven by the shared test cases. The examples come here too (`ExampleDataService`, built through the actions), and each engine or action that lands ports the repair steps that wait on it (`DataRepairs.steps`, each naming what it waits for) with their iOS tests, in the same pull request. `ObligationActions` and `RecurrenceEngine` already exist (`:store`, `:catalog`): extend them, never a second copy.

### Phase 4: the screens (four or five agents, by tab)
The shell with its four tabs and one router, the binder grid, section pages and their pockets, a document's page, a deadline's page with *Editează* and *Am rezolvat*, the visit form, *Adaugă o secțiune*, the deadline form, Urmează, Caută, Settings and its pages, the backup screen, onboarding. This is the first phase where you can try something on the Pixel 6a: an internal test build that opens a binder exported from your iPhone.

### Phase 5: capture (three agents)
Taking a photo or a scan, finding and straightening the page, reading the text on the phone (question 1), the readers that turn text into values (the label tables, `LabelledLayout`, `BillReader`, the passport and ID card lines, policies, invoices, contracts), the review and filing, learning from what the person saved, and the optional AI key.

### Phase 6: what lives outside the app (three agents)
Reminders and their buttons, home screen widgets, receiving files shared from other apps (*De verificat*), locks with the fingerprint or the phone's screen lock, sealed PIN codes, covering the app in the recent-apps view, adding to Calendar, picking a contact.

### Phase 7: finish and release
An accessibility and "every size" pass, the break-it and framework reviews that iOS had, the Play listing in Romanian, the Data safety answers, the public pages in `site/` updated for Android in both languages, then Play's testing tracks before release.

## Parity, screen by screen

| iOS | Android | Same? |
| :--- | :--- | :--- |
| Four tabs: Dosar, Urmează, Adaugă, Caută | The same four, in a bottom navigation bar | Same |
| Binder grid, zoom into a box, drag to reorder | The same, with Android's shared-element transition for the zoom | Same |
| Section pages, pockets, *Adaugă…* menu, *Mută la…* | The same | Same |
| A document's page, *Trimite*, *Rotește* | The same; *Trimite* uses Android's share sheet | Same |
| Deadline page, *Editează*, *Am rezolvat*, *Gata*, snooze | The same | Same |
| Visit form, deadline form, *Adaugă o secțiune* | The same, from the same kinds and the same words | Same |
| Urmează, Caută | The same | Same |
| Settings and its pages | The same, except iCloud (see question 2) | Mostly |
| Backups (`.dosar`), with password | The same format, the same screens; long backups keep going in a foreground notification | Same |
| Capture: camera scan, photos, files, typing | The same four ways in; the text reader differs (question 1) | Mostly |
| The optional AI key (Gemini, OpenAI, Claude, compatible) | The same, the key kept in Android's Keystore on this phone only | Same |
| Apple's on-device model (tier 3) | None on the Pixel 6a (question 1) | Differs |
| Sharing from Mail or WhatsApp into *De verificat* | Android's share target: simpler, the app itself receives the file | Same for the person |
| Reminders, with *Am rezolvat* and *Amână* buttons | The same; Android may deliver them a few minutes late unless the person allows exact alarms, which a reminder at 09:00 doesn't need | Same for the person |
| Home Screen and Lock Screen widgets with *Gata* | Home screen widgets with *Gata*; Lock Screen widgets only where the phone offers them | Mostly |
| App icon badge with a count | Android launchers show a dot, and a count only on some phones | Differs |
| Face ID locks: the app and each category | The fingerprint (the Pixel 6a has no face unlock) or the phone's PIN, through Android's own prompt; same rules (locking travels inside a backup, opening stays on the phone) | Same |
| App-switcher cover | Hidden from the recent-apps view (Android 13 and later) without blocking screenshots | Same |
| *Pagină întreagă* screenshot | Android's own "Capture more" scrolling screenshot, never while something is locked | Same |
| iPhone search (Spotlight) | Android has no system search for an app's contents; search stays in Caută | Not possible |
| Siri and Shortcuts | Not in the first Android release; Android's equivalents are limited and change often | Later |
| iCloud sync | No iCloud on Android (question 2) | Differs |
| Adding to Calendar, picking a contact | Android's own calendar and contact pickers, with no permission | Same |

One thing to say plainly: **an iPhone and an Android phone in the same household can't share one binder live** under any of the options below. They move it with a `.dosar` copy, both ways.

## Four questions for you (answered: the recommendation each time)

### 1. Reading documents on the phone

What I found:
- **The Pixel 6a has no on-device language model.** Google's Gemini Nano runs on the Pixel 9 and later (and some Samsung phones), not on the 6a. So on your phone, Android reads documents with the text reader plus the rule-based readers (tiers 1 and 2, the same rules as iOS), and your AI key when you add one. That is already how an iPhone without Apple's model works.
- **Google's text reader, ML Kit, works offline but sends usage data to Google.** Its terms say it sends performance and usage metrics (device information, error codes, timings), even with the model built into the app; the pictures and text themselves stay on the phone. That breaks our rule of no SDK that talks to anyone, and the Play listing would have to say data is collected.

The options:
- **A. ML Kit, built into the app.** The best-known reader, the least work. Usage data goes to Google, and the Play listing says so.
- **B. An open-source reader that runs entirely on the phone** (the PaddleOCR models, run by ONNX Runtime). Nothing leaves the phone, the listing can say "no data collected", and it reads Romanian letters (ș, ț, ă, î, â). The app is about 15 to 25 MB larger and it is more work to set up.
- **C. Tesseract.** Nothing leaves the phone and it is small, but it reads phone photos of documents noticeably worse.

**My recommendation: B**, after a short side-by-side test of B against ML Kit on placeholder documents, before anything depends on it. If B reads clearly worse, I come back to you with the numbers. For the camera's page scanner, the same reasoning: our own camera screen that finds and straightens the page on the phone, not Google's scanner (which also needs Google Play services).

### 2. Keeping the binder somewhere other than the phone

There is no iCloud on Android, and there will never be servers of ours.

- **A. On the phone, with `.dosar` backups only, for the first Android release.** The person makes a backup when they want and keeps it where they like (Google Drive, a computer, an e-mail to themselves). Moving to a new Android phone with Android's own phone-to-phone transfer can bring the app's data along.
- **B. Later: the person's own Google Drive**, in a private app folder only the app can see, like iCloud on iOS. It needs signing into Google inside the app and takes a real sync engine (the iOS one took several waves). Still no server of ours.
- **C. Android's automatic cloud backup.** It keeps only 25 MB per app, too small for documents, so it would bring back a binder without its pictures. I'd leave it off.

**My recommendation: A now, and decide on B after the first Android release**, once you've seen how people use it.

### 3. How it looks and feels

The standing rule asks for an Apple-level finish. On Android I read that as the same care, not the same look.

- **A. Native Android (Material 3), done with the same checklist.** Springs for motion, the phone's "remove animations" setting respected, text that grows with the phone's font size, 48 dp touch targets, Android's icons matched to the iOS symbols, a real dark theme, the same calm copy. It feels like it belongs on the phone.
- **B. The iOS look on Android.** Familiar to someone who has both, but it feels foreign on Android and fights the system (back gesture, menus, sheets).
- **C. A look of our own** that is neither.

**My recommendation: A.** A smaller choice inside it: Android can colour an app after the wallpaper. I'd keep the app's own accent instead, so it looks like the same app on every phone.

### 4. How it's built and shipped

- **Language and screens:** Kotlin and Jetpack Compose (Android's own modern toolkit). No real alternative worth taking.
- **Database:** Room, on SQLite: Android's standard, with tested migrations. (SQLDelight is the other good choice; it gives no advantage here.)
- **Oldest Android supported:** **Android 11 (my recommendation)**, around nine in ten Android phones in use, and the version from which the fingerprint-or-PIN prompt and the per-use keys the locks need work the same everywhere. Android 9 reaches a few more phones at the cost of special cases in the locks; Android 12 is simpler still but leaves out more phones.
- **Distribution:** Google Play only. If your Play developer account is a personal one made after November 2023, Google asks for a closed test with at least 12 testers for 14 days before the app can go public; that fits Phase 7.
- **The app's identifier on Play**, which can never change once published: I'd use `com.ar.dosarcusina.app`, the same as the iPhone app's, instead of the old `com.dosarcusina`.
- **Play's Data safety form:** "No data collected, no data shared", as on iOS. That is only true with option B or C in question 1. A document read with the person's own AI key goes to the service they chose, at their request; I'll check how Play's current wording counts that before we fill in the form, and the form and the privacy page will say it plainly, as on iOS.

## What happens after you answer

1. Your answers go into [DECISIONS.md](DECISIONS.md).
2. Phase 0, then Phase 1 with several agents at once, each in its own branch with a pull request into `main` that I review and merge once every check passes.
3. [HANDOFF.md](HANDOFF.md) gets an entry at the end of each session, and this file says where the phases stand.
4. I use your Pixel 6a only when you say so, starting with Phase 4.
