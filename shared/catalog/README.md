# The built-in catalog

The categories that ship with the app (Mașini, Locuințe, Acte and the rest), defined once in the iOS code ([`BuiltInTemplates`](../../ios/DosarCuSina/Services/Templates/BuiltInTemplates.swift)) and written here as data by an iOS test, so the Android app reads the same catalog and never keeps one of its own ([ANDROID_PLAN.md](../../docs/ANDROID_PLAN.md), "How parity is kept", item 1).

**Never edit these files by hand.** They are written by [`CatalogExportTests`](../../ios/DosarCuSinaTests/CatalogExportTests.swift); change the catalog in the iOS code and write them again.

## The files

| File | What it holds |
| :--- | :--- |
| [`templates.json`](templates.json) | Every built-in's definition, in the catalog's order. |
| [`catalog.json`](catalog.json) | What installing the built-ins reads that a backup doesn't carry. |
| [`keys.json`](keys.json) | The built-in field, deadline and category keys the code names. |

All three are machine JSON, written by `MachineText` with their keys sorted, so a diff shows only what changed.

### `templates.json`

A list with one entry per built-in category, in the catalog's order (`vehicle`, `home`, `documents`, `pet`, `health`, `purchase`, `subscription`, `other`, `bike`, `plants`, `tenancy`, `member`, `espresso`).

Each entry is the category exactly as a backup's `data/templates.json` writes it ([dosar-v3.md](../schemas/dosar-v3.md), "Template"), with the same keys and the same encodings, so one reader reads both: `key`, `name`, `summary`, `symbol`, `tint`, `heroStyle`, `isBuiltIn` (always true), `version`, `sections` (with their fields), `blueprints` (the deadlines, with their recurrence, first due date, reminder profile and its variants, facts and completion kind), `components`, `pockets` and `behavior` (its box, list, role, grouping, parent pocket, `mayBelongTo`, visit kind, offer wording and `singular`).

It leaves out what is the household's, not the catalog's: `homeOrder`, `isOnHome`, `isSensitive`, `boxGrouping`, `createdAt` and `updatedAt`. With those added, each entry is what [the iOS golden backup](../fixtures/golden/ios/expected/data/templates.json) holds for that category; Android's `CatalogTest` checks it.

### `catalog.json`

- **`builtInVersion`:** the catalog's version (`TemplateDefinition.builtInCatalogVersion`), every built-in's `version`. A binder whose built-ins come from a newer catalog is left as it is by an older build.
- **`categories`:** each built-in's key, in the catalog's order (the order new ones are installed in), with what a new install starts with: `isOnHomeByDefault` (shown on the binder) and `isSensitiveByDefault` (locked). The keys are `templates.json`'s, in the same order.
- **`replacedKeys`:** built-in keys of earlier catalogs and the key that replaced each (`warranty` → `purchase`). Installing the built-ins moves their sections over and removes the old category.
- **`replacedFieldKeys`:** the field keys renamed with them (`warranty.expiry` → `purchase.warrantyUntil`).
- **`retiredKeys`:** built-in keys of earlier catalogs that nothing replaced (`rental`). One with sections becomes a category of one's own, so nothing disappears; one without goes once the binder has all arrived.
- **`writtenBy`:** the test that writes the files.

### `keys.json`

- **`keys`:** by the Swift type that names them, each constant's name and its key: `VehicleFields`, `HomeFields`, `DocumentFields`, `MemberFields`, `PetFields`, `PurchaseFieldKeys` and `BuiltInBlueprints` ([`BuiltInFieldKeys.swift`](../../ios/DosarCuSina/Services/Templates/BuiltInFieldKeys.swift)), `SubscriptionFields` ([`SubscriptionFields.swift`](../../ios/DosarCuSina/Services/Subscriptions/SubscriptionFields.swift)) and `BuiltInTemplates.Key`, the categories' keys. The iOS test reads those files and fails when one declares a key `keys.json` doesn't list.
- **`writtenBy`:** the test that writes the files.

Android names the same constants in [`BuiltInKeys.kt`](../../android/catalog/src/main/kotlin/com/ar/dosarcusina/catalog/BuiltInKeys.kt): each object the Swift type of the same name, each constant its Swift name in capitals (`VehicleFields.POLICY_NUMBER`). `BuiltInKeysTest` checks them against `keys.json` both ways, and `CatalogTest` that every key names a field, deadline or category the catalog has.

## Fresh or failing

`CatalogExportTests` writes the three files again on every iOS test run and fails when what is committed differs, or when a JSON file here is written by nothing any more. A failed run on GitHub keeps them made afresh in its `test-results` artifact, as `catalog/` (`tests/run_tests.sh` passes the folder as `TEST_RUNNER_CATALOG_OUT`): copy them over this folder. Or write them on a Mac:

```sh
TEST_RUNNER_CATALOG_WRITE=1 xcodebuild test -project ios/DosarCuSina.xcodeproj -scheme DosarCuSina \
  -destination 'platform=iOS Simulator,name=<an installed iPhone>' \
  -only-testing:DosarCuSinaTests/CatalogExportTests CODE_SIGNING_ALLOWED=NO
```

(In Xcode, set `CATALOG_WRITE=1` in the scheme's environment and run `CatalogExportTests`.) Review the diff and commit it. A change to the catalog changes the golden archives too ([`../fixtures/golden/README.md`](../fixtures/golden/README.md)): bring both up to date in the same pull request.

## Who reads them

- **Android:** the `catalog` module ([`android/catalog`](../../android/catalog)) copies the three files into its resources as it is built (the `catalogResources` task), so the app carries this folder as it is, and reads them into `Catalog.builtIn`, with the archive's own codecs. Every part must read whole; a part the build can't read fails the build's tests, never the person's binder. The importer takes each built-in's definition from it (`BuiltIns`), and `BuiltInInstall` decides what installing the built-ins changes, as the iOS app's `TemplateStore.installBuiltIns` does.
- **iOS:** nothing reads them; the catalog is the code.

## Left for later

Words a shaped screen reads (`VisitShape`, `CompletionShape`, a pocket's words) are screen copy, not the catalog's data: they come with the screens in Phase 4, compared through the copy matrix ([COPY_MATRIX.md](../../docs/COPY_MATRIX.md)). So do capture's label tables (`CaptureKindProfile`), in a folder of their own under `shared/` when their phase comes. The travel rules and the countries are in [`shared/travel/`](../travel/).
