# The `.dosar` container, both ways

Archives that prove each app reads the other's bytes: the ZIP container and the password format of [dosar-v3.md](../../schemas/dosar-v3.md), without the household inside (the golden exports in `shared/fixtures/` carry that). Both test suites read every file here on every pull request:

- the iOS tests, [ArchiveVectorsTests.swift](../../../ios/DosarCuSinaTests/ArchiveVectorsTests.swift);
- the Android tests, [ArchiveVectorsTest.kt](../../../android/archive/src/test/kotlin/com/ar/dosarcusina/archive/ArchiveVectorsTest.kt).

## The archives

| File | Made by | What it is |
| :--- | :--- | :--- |
| `ios-plain.zip` | the iOS app's `DosarZipEngine.Writer` | The entries below, as a plain ZIP. |
| `ios-password.dosar` | the iOS app's writer, through `ArchiveEncryption.EncryptingSink` | The same ZIP, protected with the password below: 600 000 rounds, chunks of 1 MiB, two chunks. |
| `android-plain.zip` | the Android app's `DosarZipEngine.Writer` | The same entries, as a plain ZIP. |
| `android-password.dosar` | the Android app's writer, through `ArchiveEncryption.EncryptingSink` | The same ZIP, protected the same way. |

The password of both protected files is the placeholder **`parolă-exemplu`** (with `ă`, U+0103). Typed with the `ă` as `a` and a combining breve (U+0306), it opens them too: the key is made from the password's composed form (NFC).

Each app checks that its own two files still open with everything in them, and that the other app's two do. With the password, each also checks the header (600 000 rounds, 1 MiB chunks), that the empty password and no password are told apart from a wrong one, and that a byte changed in the first chunk, the file cut after its first chunk, a header asking for no rounds and a header of version 2 are all refused (a wrong password for the first two, a damaged file for the others).

## The entries

Every archive holds the same five entries, in this order, each dated 25 November 2026, 10:00 UTC (a ZIP keeps the writer's local time, so dates aren't compared between the apps):

| Path | Contents | Kept as |
| :--- | :--- | :--- |
| `text/repeated.txt` | `Dosar cu Șină, vector de test.` and a line feed, 200 times, in UTF-8 | DEFLATE |
| `text/empty.txt` | nothing | STORE |
| `acte/` | a folder entry, which readers leave out | STORE |
| `acte/însemnare-ș.txt` | `Însemnare de probă: ș, ț, ă, î, â.` and a line feed, in UTF-8: a name and contents outside ASCII | STORE |
| `vault/pagini.bin` | 1 100 000 bytes: the SHA-256 of the ASCII text `pagina-0`, then of `pagina-1`, and so on, cut at 1 100 000 bytes | STORE (it doesn't compress) |

[`contents.sha256`](contents.sha256) lists what a reader finds, in the format `shasum -a 256` writes: each entry's SHA-256 and its path, in the order of the ZIP's directory, the folder left out. Both apps make the entries above and check that they match it.

## The archives both apps refuse

[`refused/`](refused) holds small archives crafted byte by byte, each one a case the iOS tests already cover. [`refused.tsv`](refused.tsv) lists each file, the kind of error both apps refuse it with (named as the iOS app names it, such as `overlappingEntries`), and what the archive does. An app refuses one when opening it, or reading every file in it to its end, fails with that kind.

## Making them again

Only when the format changes on purpose. The files are written once and committed; the protected ones differ every time they are written (the salt and the nonces are random), so a test never compares bytes, only what the files hold.

1. Android, from `android/`: `./gradlew :archive:test -PwriteArchiveVectors` writes `android-plain.zip`, `android-password.dosar`, `contents.sha256`, `refused.tsv` and `refused/`.
2. iOS: run `ArchiveVectorsTests` with `TEST_RUNNER_ARCHIVE_VECTORS_WRITE=1` in the environment (for example `TEST_RUNNER_ARCHIVE_VECTORS_WRITE=1 xcodebuild test … -only-testing:DosarCuSinaTests/ArchiveVectorsTests`), which writes `ios-plain.zip` and `ios-password.dosar`.
3. Run both suites without the switch, and commit what changed.
