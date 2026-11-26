# What a traveller carries

The trip check's rules (*Pleci din țară*), the countries a person can be a citizen of and the document types' travel data, defined once in the iOS code ([`TravelRules`](../../ios/DosarCuSina/Services/Readiness/TravelRules.swift), [`Citizenship`](../../ios/DosarCuSina/Models/Fields/Citizenship.swift), [`DocumentType`](../../ios/DosarCuSina/Models/Fields/ChoiceOptions.swift)) and written here as data by an iOS test, so the Android app checks a trip by the same rules and never names a country, a document rule or a key of its own ([ANDROID_PLAN.md](../../docs/ANDROID_PLAN.md), "How parity is kept", item 1).

**Never edit these files by hand.** They are written by [`TravelExportTests`](../../ios/DosarCuSinaTests/TravelExportTests.swift); change the rules in the iOS code and write them again.

## The files

All three are machine JSON, written by `MachineText` with their keys sorted, so a diff shows only what changed.

### `rules.json`

- **`groups`** and **`regions`:** the citizenship groups (`Citizenship.Group`: `freeMovement`, `thirdCountry`, `unknown`) and the regions a trip goes to (`TripPlan.Region`: `europeanUnion`, `moldovaAndWesternBalkans`, `outsideEU`), by their raw values.
- **`byGroup`:** for each group and region, what a traveller carries, in the order the check lists it. Each requirement is its `need` (`identity`, `passport`, `residencePermit`), the document types that meet it (`accepted`, the first preferred and the one a check asks to add), whether a passport counts only until its travel cut-off (`countsTravelCutoff`) and how many months after the trip it must still be valid (`monthsValidAfterReturn`).
- **`identityCards`:** where a region's countries take a citizenship's identity card instead (by ISO code), the requirement they set and the rule's `source`.
- **`healthCardRegions`** and **`visaRegions`:** where the European health card is checked, and where everyone is reminded to look up the visa rules.
- **`petRabiesWaitDays`:** the days a first rabies vaccine takes before it counts for crossing a border.
- **`reads`:** every key the readiness checks read (fields, deadlines, categories, document types, the kinds of deadline and document, a deadline's fact roles), by the Swift constant that names it, in `shared/catalog/keys.json`'s shape. Android's `TravelDataTest` checks them against `keys.json`.
- **`writtenBy`:** the test that writes the files.

### `countries.json`

- **`options`:** the choice a person's citizenship field offers, in its order (by Romanian name, „Fără cetățenie (apatrid)” last): each country's key (`country.` and its ISO 3166-1 code), its Romanian name (`label`), what documents print for it (`printedCode`, `otherCodes`, and in `aliases` how a Romanian document says it), and whether its citizens move freely in the EU (`movesFreely`). They are the catalog's `member.citizenship` options; `TravelDataTest` checks that.
- **`keyPrefix`**, **`stateless`** and **`statelessCodes`:** how a country's key is made, the key of having no citizenship, and the codes documents print for it.
- **`freeMovement`:** the EU's 27, the other EEA states and Switzerland, by code.

### `documents.json`

- **`typeField`** and **`variantField`:** the fields that hold a personal document's type and its variant.
- **`types`:** each document type's key, name and other spellings (as the catalog's `document.type` options), and its `travelMarginDays` (a passport: 180, six calendar months before its expiry it stops being good for travel).
- **`variants`:** each variant's type, key, whether it `travels` at all (the simple identity card doesn't) and the last day it is good for travel whatever its printed expiry (`travelEnds`: an identity card without a chip, 2 August 2031).

## Fresh or failing

`TravelExportTests` writes the three files again on every iOS test run and fails when what is committed differs, or when a JSON file here is written by nothing any more. A failed run on GitHub keeps them made afresh in its `test-results` artifact, as `travel/` (`tests/run_tests.sh` passes the folder as `TEST_RUNNER_TRAVEL_OUT`): copy them over this folder. Or write them on a Mac:

```sh
TEST_RUNNER_TRAVEL_WRITE=1 xcodebuild test -project ios/DosarCuSina.xcodeproj -scheme DosarCuSina \
  -destination 'platform=iOS Simulator,name=<an installed iPhone>' \
  -only-testing:DosarCuSinaTests/TravelExportTests CODE_SIGNING_ALLOWED=NO
```

(In Xcode, set `TRAVEL_WRITE=1` in the scheme's environment and run `TravelExportTests`.) Review the diff and commit it.

## Who reads them

- **Android:** the `core` module copies the three files into its resources as it is built (the `travelResources` task) and reads them into `TravelData.builtIn` (`com.ar.dosarcusina.core.readiness`), which the readiness engine reads. Every part must read whole; a part the build can't read fails the build's tests, never the person's binder.
- **iOS:** nothing reads them; the rules are the code.

The checks' answers are pinned separately, in [`shared/test-vectors/readiness/`](../test-vectors/readiness/) (`ReadinessVectorsTests`).
