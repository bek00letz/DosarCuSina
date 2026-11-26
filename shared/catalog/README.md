# The built-in catalog

The categories that ship with the app (Mașini, Locuințe, Acte and the rest), defined once in the iOS code ([`BuiltInTemplates`](../../ios/DosarCuSina/Services/Templates/BuiltInTemplates.swift)) and written here as data by an iOS test, so the Android app reads the same catalog and never keeps one of its own ([ANDROID_PLAN.md](../../docs/ANDROID_PLAN.md), "How parity is kept", item 1).

**Never edit these files by hand.** They are written by [`CatalogExportTests`](../../ios/DosarCuSinaTests/CatalogExportTests.swift); change the catalog in the iOS code and write them again.

## The files

| File | What it holds |
| :--- | :--- |
| [`templates.json`](templates.json) | Every built-in's definition, in the catalog's order. |
| [`catalog.json`](catalog.json) | What installing the built-ins reads that a backup doesn't carry. |
| [`keys.json`](keys.json) | The built-in field, deadline and category keys the code names. |
| [`ownCategories.json`](ownCategories.json) | What a category of one's own is made of besides the answers to its switches. |
| [`household.json`](household.json) | The household's own deadlines, which belong to no section. |
| [`subscriptions/subscriptions.json`](subscriptions/subscriptions.json) | What a subscription can be: its services, codes, groups and billing cycles. Written by [`SubscriptionCatalogExportTests`](../../ios/DosarCuSinaTests/SubscriptionCatalogExportTests.swift) (see below). |

All six are machine JSON, written by `MachineText` with their keys sorted, so a diff shows only what changed.

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

### `ownCategories.json`

What a category of one's own is made of besides the answers to its few questions (`CategorySwitches`: *Are acte*, *Are facturi și contracte*, *Are revizii sau lucrări* and how often, *Ține de…*, one box or one each). The rules that turn the answers into the category's pockets, behaviour, fields and deadlines are code, on both apps; the words and the parts they write are here.

- **`basePockets`:** the pockets every new category of one's own starts with (`CategorySwitches.basePockets`); the switches add theirs.
- **`counterSectionKey`:** the field section a counter goes in (`custom.counter`).
- **`counters`:** each way a service is counted, in `CategorySwitches.Counter`'s order (the order a category's service is read in): `counter` (its raw value, which names the service deadline `custom.service.<counter>`), `defaultEvery` (the interval it starts at: months, kilometres or hours), `field` (its counter field, none for a service by time) and `service` (its service deadline at `defaultEvery`, as a template's `blueprints` writes one). The interval the person types is laid into the deadline's `recurrence` and `firstDue` by the rule both apps share (`CategorySwitches.serviceBlueprint`).
- **`writtenBy`:** the test that writes the files.

### `household.json`

- **`blueprints`:** the household's own deadlines (`HouseholdRules.blueprints`), each as a template's `blueprints` writes one: today the rental income declaration (`household.rentalDeclaration`), made while the household has a tenancy (`HouseholdRules.reconcile`).
- **`writtenBy`:** the test that writes the files.

### `subscriptions/subscriptions.json`

What a subscription can be, declared once in the iOS code (`ServiceKind.services`, `SubscriptionGroup` and `BillingCycle` in [`ChoiceOptions.swift`](../../ios/DosarCuSina/Models/Fields/ChoiceOptions.swift), `SubscriptionCode` in [`SubscriptionFields.swift`](../../ios/DosarCuSina/Services/Subscriptions/SubscriptionFields.swift)), in a folder of its own so it is written and checked apart from the built-in catalog:

- **`services`:** in the order they are offered, each with its `key` (stored), `label` and `aliases` (what stored or typed text it is found by), its `group`, its `codes` (by name, most specific first: the only ones read, shown and asked), `isTiedToHome` (supplied at an address: the contract lives under the home), `sendsRegularBills` (one bill per billing cycle), `meter` (a `MeasurementKind`, or null) and `modelDescription` (what a language model is told it is).
- **`unspecifiedService`:** the service that says nothing about which contract a paper is: its codes are what any contract has, and it is never told apart from another service.
- **`codes`:** in the edit form's order, each with its `name`, `family` (`consumptionPoint`, `customer`, `contract`, `line`), `fieldKey` (the subscription's field that keeps it), `captureKey` (what capture reads it as), `weight` (how much an agreeing one says), `namesOnePoint` (a different one is a different contract), `homeFieldKeys` (a home's own fields for the same code), `comparedAs` (`compact`, or `nationalPhoneNumber`) and `editFormCondition` (when the edit form shows it, as a template writes a condition).
- **`groups`:** in the order subscriptions are listed under them, each its `key` and `label`; **`unspecifiedGroup`:** the group of a service that isn't known.
- **`billingCycles`:** in the order they are offered, each its `key`, `label`, `aliases` and `interval` (`every` and `unit`); **`unknownCycle`:** what a cycle that isn't known lasts.
- **`writtenBy`:** the test that writes the file.

[`SubscriptionCatalogExportTests`](../../ios/DosarCuSinaTests/SubscriptionCatalogExportTests.swift) writes it fresh or fails, by the same switch (`TEST_RUNNER_CATALOG_WRITE=1`, or `CATALOG_WRITE=1` in Xcode, running `SubscriptionCatalogExportTests`); a failed run on GitHub keeps it made afresh in `test-results` as `catalog/subscriptions/`. Android's `core` module copies it into its resources (the `subscriptionCatalogResources` task) and reads it into `SubscriptionCatalog.builtIn` ([`core.subscriptions`](../../android/core/src/main/kotlin/com/ar/dosarcusina/core/subscriptions)); every part must read whole, and no Android code tests for a named service.

## Fresh or failing

`CatalogExportTests` writes the five files again on every iOS test run and fails when what is committed differs, or when a JSON file here is written by nothing any more. A failed run on GitHub keeps them made afresh in its `test-results` artifact, as `catalog/` (`tests/run_tests.sh` passes the folder as `TEST_RUNNER_CATALOG_OUT`): copy them over this folder. Or write them on a Mac:

```sh
TEST_RUNNER_CATALOG_WRITE=1 xcodebuild test -project ios/DosarCuSina.xcodeproj -scheme DosarCuSina \
  -destination 'platform=iOS Simulator,name=<an installed iPhone>' \
  -only-testing:DosarCuSinaTests/CatalogExportTests CODE_SIGNING_ALLOWED=NO
```

(In Xcode, set `CATALOG_WRITE=1` in the scheme's environment and run `CatalogExportTests`.) Review the diff and commit it. A change to the catalog changes the golden archives too ([`../fixtures/golden/README.md`](../fixtures/golden/README.md)): bring both up to date in the same pull request.

## Who reads them

- **Android:** the `catalog` module ([`android/catalog`](../../android/catalog)) copies the five files into its resources as it is built (the `catalogResources` task), so the app carries this folder as it is, and reads them into `Catalog.builtIn`, with the archive's own codecs. Every part must read whole; a part the build can't read fails the build's tests, never the person's binder. The importer takes each built-in's definition from it (`BuiltIns`), and `BuiltInInstall` decides what installing the built-ins changes, as the iOS app's `TemplateStore.installBuiltIns` does. `CategorySwitches` makes a category of one's own from `ownCategories.json` (`Catalog.ownCategories`), and `HouseholdRules` the household's deadlines from `household.json` (`Catalog.household`).
- **iOS:** nothing reads them; the catalog is the code.

## Left for later

Words a shaped screen reads (`VisitShape`, `CompletionShape`, a pocket's words) are screen copy, not the catalog's data: they come with the screens in Phase 4, compared through the copy matrix ([COPY_MATRIX.md](../../docs/COPY_MATRIX.md)). So do capture's label tables (`CaptureKindProfile`), in a folder of their own under `shared/` when their phase comes. The travel rules and the countries are in [`shared/travel/`](../travel/).
