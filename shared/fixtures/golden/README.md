# Golden archives

Backups each app makes, committed so that the other app's tests can import them and check that nothing was lost. They prove the one rule of the Android port ([ANDROID_PLAN.md](../../../docs/ANDROID_PLAN.md)): a binder exported on one platform opens on the other with everything in it. The format is [dosar-v3.md](../../schemas/dosar-v3.md).

The hand-written fixtures beside this folder ([`../dosar-v3/household`](../dosar-v3/household), [`../dosar-v2/ios-export`](../dosar-v2/ios-export)) stay as they are: they pin the format as written by hand. These are what the apps' own writers make.

## What is here

| Path | What it is |
| :--- | :--- |
| [`ios/household.dosar`](ios/household.dosar) | A backup the iOS app wrote, without a password. |
| [`ios/household-password.dosar`](ios/household-password.dosar) | The same backup protected with a password, the placeholder in [`ios/README.md`](ios/README.md). Opened, it is the same archive. |
| [`ios/expected/`](ios/expected) | What both archives hold, unpacked: `manifest.json` and the nine `data/*.json` files exactly as written, and `vault.json`, every other file (pages, thumbnails, documents' files, photos) by its path and the SHA-256 of its bytes. |
| [`inputs/`](inputs) | The pictures and PDFs the iOS household files: a page kept as HEIC and one kept as JPEG, a thumbnail of each, a section's photo, two PDFs. Committed so the archives' bytes never depend on the encoder of the Mac that makes them. All of them are drawn shapes and placeholder text. |
| [`android/household.dosar`](android/household.dosar), [`android/household-password.dosar`](android/household-password.dosar), [`android/expected/`](android/expected) | The same for a backup the Android app wrote, laid out as `ios/` is, with the same placeholder password ([`android/README.md`](android/README.md)). |

## The iOS household

`GoldenHousehold`, in [`GoldenArchiveTests.swift`](../../../ios/DosarCuSinaTests/GoldenArchiveTests.swift), builds it through the app's own actions, as the App Store screenshots' household is built, never by writing the store directly; each step is the person's own, at a fixed moment. Placeholder data only (`B-123-ABC`, `VW Golf 2018`, `ENGIE Romania S.A.`, `nume@exemplu.ro`, the CNP `1800101990006`). It covers every record type the archive carries and the format's edges:

- every data file: categories, sections, deadlines, history, line items, firms, readings, documents and what capture learned;
- a section in a locked category (Sănătate), and a category of one's own (Bărci, counted in engine hours);
- secrets that must not be written: an electronic identity card's PIN and a secret row under Date importante;
- a card number in a document's text, masked to `•••• 1111`;
- calendar days, moments, money in lei and in euro, a snoozed deadline, a paused one, a reminder time;
- readings read and estimated, and a new counter;
- a page kept as HEIC and one kept as JPEG (named `.heic` and `.jpg`), thumbnails of both kinds, a PDF, a document of two pages with its framing, a replaced policy, a section's photo;
- a deadline of the person's own, a completed one, the household's rental declaration (a deadline with no section), a visit with line items, a rating and its invoice;
- what a newer version wrote and this one keeps as written: an import of a small archive from "version 9.0" brings a field value of an unknown type, unknown keys inside a value, a row, a recurrence, a reminder profile, a document's framing and a category's behaviour and fields, and a JPEG page named `.heic`, as archives were written before the 25 November rule.

## The Android household

The iOS golden household, brought into an empty Android binder and written out by the Android writer (`GoldenAndroidArchivesTest`, in `android/archive`). So the two apps' goldens hold the same household and each trip is checked whole: iOS → Android (Android's test compares what came in with `ios/expected/`), and iOS → Android → iOS (the iOS test imports `android/` and compares what it writes with `ios/expected/`). A household made by Android's own actions comes once Android has them (Phase 2 and later); until then this one covers every record type and edge the iOS one does. Today Android's data files are byte for byte iOS's; only the manifest's `platform` differs.

## Fresh or failing

`GoldenArchiveTests` exports the household again on every run and compares what it writes with `ios/expected/`, by contents, not bytes: the password's salt changes every time, and so do the ids the actions make and the moment each record was made. It leaves out only those: each id is compared by the place it takes (counted over the records in an order of their own contents, so a link still says which record it points at), `createdAt` and the manifest's `appVersion` are not compared, and the data files' checksums follow from the files, which are. Everything else must match, every vault file's SHA-256 included. It also checks that both committed archives unpack to `expected/`, and imports each of them into an empty binder and writes it out again, expecting every record back exactly as it was.

**Android's** are kept fresh the same way, by contents, not bytes, by `GoldenAndroidArchivesTest`: it writes the household again on every run and compares what it writes with `android/expected/`, every data file and the manifest as JSON and every vault file by its SHA-256 (the salt, and the entries' dates where the time zone moves them, may differ). Bring them up to date from `android/` with `./gradlew :archive:test -PwriteGoldenArchives`, or copy what a failed run left: locally in `android/archive/build/golden-archives/`, on GitHub in the failed `android-build-and-test` run's `android-golden-archives` artifact. As for iOS, review the diff of `expected/` and commit it with both archives.

For iOS: when the writer, the catalog or the household changes on purpose, bring them up to date and commit all three together. A pull request's failed `build-and-test` run already made them: its `test-results` artifact holds `golden-archives/`, laid out as `ios/` is (`tests/run_tests.sh` passes the folder as `TEST_RUNNER_GOLDEN_ARCHIVES_OUT`); copy `household.dosar`, `household-password.dosar` and `expected/` over `ios/`. Android's are made from the iOS household, so the same run made them afresh too, from the iOS ones it just made (`scripts/golden-android-from-ios.sh`), in `golden-archives-android/`: copy that folder over `android/` in the same commit, and the next run is green on both sides. Or make them on a Mac:

```sh
TEST_RUNNER_GOLDEN_ARCHIVES_WRITE=1 xcodebuild test -project ios/DosarCuSina.xcodeproj -scheme DosarCuSina \
  -destination 'platform=iOS Simulator,name=<an installed iPhone>' \
  -only-testing:DosarCuSinaTests/GoldenArchiveTests CODE_SIGNING_ALLOWED=NO
```

(In Xcode, set `GOLDEN_ARCHIVES_WRITE=1` in the scheme's environment and run `GoldenArchiveTests`.) Then make Android's from them with `scripts/golden-android-from-ios.sh shared/fixtures/golden/ios <out-dir>` and copy `<out-dir>` over `android/`. Review the diff of `expected/` before committing: it is what Android's tests will expect.

## Who reads them

- **Android**: `GoldenIosArchivesTest` (in `android/archive`) imports `ios/household.dosar` and `ios/household-password.dosar` into an empty binder and compares what came in, written out again as the archive's records, with `ios/expected/`, record by record and every vault file by its SHA-256. A difference fails unless it is on the test's written list of allowed ones (`Allowed`), each with why; today that list is empty.
- **iOS**: imports its own (above), and Android's: `AndroidGoldenArchiveTests` brings both `android/` archives into an empty binder, writes it out again and compares it with `ios/expected/` by the same canonical comparison, then checks every record against `android/expected/`.
- **Android** also imports its own, and checks they hold exactly what `ios/expected/` holds.
