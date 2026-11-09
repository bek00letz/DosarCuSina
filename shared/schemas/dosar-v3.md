# `.dosar` archive format, version 3

The household backup and transfer format shared by every platform. It is a
plain ZIP file (DEFLATE or STORE entries) with JSON inside, readable with
`java.util.zip` and `org.json` on Android and with any `unzip`.

- **File extension:** `.dosar`
- **Type identifier:** `com.ar.dosarcusina.dossier` (conforms to `public.zip-archive`)
- **MIME type:** `application/vnd.dosarcusina.dossier+zip`
- **JSON Schema:** [`dosar-v3.schema.json`](dosar-v3.schema.json)
- **Golden fixtures:** [`../fixtures/dosar-v3/household`](../fixtures/dosar-v3/household) (v3) and [`../fixtures/dosar-v2/ios-export`](../fixtures/dosar-v2/ios-export) (v2, still importable). Every implementation must import both.
- **With a password:** the same ZIP, encrypted whole; see [Password-protected archives](#password-protected-archives).

## Layout

| Path | Contents |
| :--- | :--- |
| `manifest.json` | Format, version, counts and checksums. Read first. |
| `data/templates.json` | Categories: built-in ones (with the household's preferences) and custom ones (in full). |
| `data/assets.json` | Assets and their field values. |
| `data/obligations.json` | Deadlines, recurrence and reminder profiles. |
| `data/history.json` | History entries: visits, repairs, purchases, inspections, completed obligations. |
| `data/service_items.json` | Line items of history entries, keyed by component. |
| `data/providers.json` | People and businesses, with trades and the assets they look after. |
| `data/measurements.json` | Meter readings, lab values, weights, odometer readings. |
| `data/attachments.json` | Document metadata. |
| `vault/<id>.<ext>` | An attachment's original file. |
| `vault/<id>/page-<n>.heic` | Scanned pages of an attachment, from 1. |
| `vault/<id>/thumbnail.heic` | An attachment's thumbnail. |
| `vault/photos/<assetId>.jpg` | An asset's photo. |
| `opis.pdf` | Optional printable table of contents. |

Every `data/*.json` file is a JSON array. Writers always write all eight data
files, even when empty. Readers treat a missing data file as an empty array.

## Value conventions

- **Identifiers:** UUID strings, written lowercase; compare case-insensitively.
- **Timestamps** (`createdAt`, `updatedAt`, `occurredAt`, `recordedAt`, `exportedAt`, `snoozedUntil`): ISO 8601 in UTC, such as `2026-03-01T07:30:00Z`. Writers write whole seconds; readers accept fractional seconds and offsets.
- **Calendar days** (`dueDate`, `cycleDueDate`, `documentDate`, date field values): `yyyy-MM-dd`, with no time zone. A day is the same day everywhere.
- **Month-days** (fixed yearly dates): `MM-dd`.
- **Money:** `{"amount": "175.50", "currency": "RON"}`. The amount is a decimal string with a dot; the currency is ISO 4217. Amounts in different currencies are never added together.
- **Optional values** are omitted rather than written as `null`. Readers accept either.
- **Enumerations** are lowercase-camel strings. A reader that meets an unknown value keeps the record and falls back: unknown field types read as `text`, unknown kinds read as the generic one (`note`, `other`, `custom`; an obligation's as `legal`, the loudest), unknown trades are kept as text. The value itself is kept as written and written back unchanged (see [Values from a newer version](#values-from-a-newer-version)).
- **Units** (a field's `unit`, a metric recurrence's `unit`, a measurement's `unit`) are keys, never display text. A reader shows its own label for each.

  | Key | Unit | Label in Romanian |
  | :--- | :--- | :--- |
  | `km` | kilometres | km |
  | `h` | engine hours | h |
  | `kwh` | kilowatt-hours | kWh |
  | `m3` | cubic metres | m³ |
  | `gcal` | gigacalories | Gcal |
  | `kg` | kilograms | kg |
  | `mgdl` | milligrams per decilitre | mg/dL |
  | `mmhg` | millimetres of mercury | mmHg |
  | `dpt` | dioptres | dpt |
  | `cm3` | cubic centimetres | cm³ |
  | `hp` | horsepower | CP |
  | `m2` | square metres | m² |
  | `months` | months | luni |
  | `shots` | coffees made by an espresso machine | cafele |

  - **Older archives** wrote the Romanian label instead (`m³`, `mc`, `kWh`, `Gcal`, `luni`, `cafele`, `CP`, `m²`, `cm³`). Readers match a unit against the keys and labels above ignoring case, diacritics and superscripts (`m³` is `m3`), and keep the key.
  - **A unit of the person's own** (a custom category's "ore motor") isn't in the table: it is written as typed, and read and shown as written.
  - **No unit** is an empty string for a measurement, and a missing key for a field.
  - Readers older than this table show a key as it is (`m3` instead of `m³`); the number and its unit are unchanged.

## Integrity

`manifest.checksums` maps every file in the archive except `manifest.json` to
the lowercase hex SHA-256 of its bytes. On import:

1. Every listed file must exist and match its checksum.
2. Every file in the archive (other than `manifest.json`) must be listed.
3. Every path an attachment or asset refers to must exist.

This detects damaged or incomplete archives. It is not a signature: anyone
can rewrite the manifest, so it says nothing about who made the archive.

Entry paths must be relative, use `/`, and contain no empty, `.` or `..`
components, no `\`, and no `:`. Readers enforce size limits; the iOS reader
accepts at most 20 000 entries, 128 MB per entry and 512 MB in total.

Archives are plain ZIP, never ZIP64: at most 65 535 entries and 4 GB. A
writer refuses a household larger than that rather than write a damaged
file; a reader refuses an archive marked as ZIP64. Entry dates run from 1980
to 2107; a writer puts an earlier or later date at the nearest end (the real
export time is `manifest.exportedAt`).

## `manifest.json`

```json
{
  "format": "com.ar.dosarcusina.dossier",
  "schemaVersion": 3,
  "appVersion": "1.0",
  "platform": "iOS",
  "exportedAt": "2026-03-02T08:00:00Z",
  "counts": { "templates": 2, "assets": 2, "obligations": 2, "historyEntries": 2,
              "serviceItems": 1, "providers": 2, "measurements": 1, "attachments": 3 },
  "checksums": { "data/assets.json": "e720…" }
}
```

A reader refuses a `schemaVersion` higher than it knows, with a message asking
to update the app, and imports version 2 through a converter.

## Records

### Template (`data/templates.json`)

`key`, `name`, `summary`?, `symbol` (SF Symbol name), `tint`
(`blue|orange|pink|brown|indigo|teal|purple|green|red|yellow|mint|cyan|gray`),
`heroStyle` (`vehicle|home|document|pet|standard`), `isBuiltIn`, `version`,
`homeOrder`, `isOnHome`, `isSensitive`, `sections`, `blueprints`,
`components`?, `pockets`?, `behavior`?, `createdAt`, `updatedAt`.

`pockets` lists the parts a section page shows. The values are
`upcoming|tenants|products|subscriptions|documents|history|people|money|keyFacts`,
always shown in that order. When the key is missing, readers use
`upcoming, documents, history, people, money, keyFacts`.

`behavior` says what the category does in the binder, so a custom category can
behave like a built-in one: `{"box": "wholeCategory", "listing": "byHolder", "role":
"personalDocument"}`. All keys are optional; a missing key, or a value a reader
doesn't know, reads as the default.

- **`box`:** `perSection` (one box per top-level section, the default), `wholeCategory` (one box for the category: Acte, Garanții, Abonamente) or `insideOther` (no box: its sections live inside another).
- **`listing`:** what the category's page lists: `plain` (the default), `byHolder`, `byWarranty` or `byMonthlyCost`.
- **`role`:** the part it plays for other categories: `holder` (people documents are filed under), `personalDocument`, `subscription` (ongoing contracts bills file into) or `home` (where contracts tied to an address live).
- **`parentPocket`:** the pocket of a parent's page its sections show in (`tenants`, `products`, `subscriptions`).
- **`addedOnlyUnderParent`:** its sections are only added under another section (a tenancy).
- **`visit`:** how its visits read and what they are: `{"title": "Am fost la service", "checklistTitle": "Ce s-a făcut", "providerTitle": "Service-ul", "kind": "maintenance", "trade": "mechanic"}`. `kind` is a history entry's kind, `trade` a provider's. Missing, it reads as a job done: "Am făcut o lucrare", "Ce s-a făcut", "Cine a lucrat", `repair`, `other`; a missing or unknown key inside reads as that one's.
- **`offerTitle`:** its option when adding a section, one thing rather than the category ("Mașină" for "Mașini"). Missing or empty, the category's `name`.
- **`shortlistOrder`:** its place, from 1, among the categories offered first when adding a section ("Cele mai des folosite"). Missing, it is offered with the others, in the binder's order.

Built-in keys: `vehicle`, `home`, `documents`, `pet`, `health`, `purchase`,
`subscription`, `other`, `bike`, `plants`, `tenancy`, `member`, `espresso`.

Keys from earlier builds:

- **`warranty`:** became `purchase`. Readers move such assets over and rename their fields (`warranty.purchaseDate` → `purchase.date`, `warranty.expiry` → `purchase.warrantyUntil`, other `warranty.*` → `purchase.*`).
- **`rental`:** retired. If assets still use it, readers keep it as a custom category. Custom keys
start with `custom.`. A built-in template always takes the reader's own
definition, whatever the archive says about it (`name`, `sections`, field
types, `blueprints`, `version`, `isBuiltIn`): a key that names a built-in is a
built-in. From the archive, a reader takes only the household preferences:
`homeOrder`, `isOnHome` and `isSensitive`, the last one only towards locked (a
category locked on the device stays locked). For a custom template on both
sides, a field that is `secret` or `isSensitive` on the device stays so.

- **Section:** `key`, `title`, `fields`.
- **Field:** `key`, `label`, `type`, `role`?, `isEssential`, `isSensitive`, `options`?, `unit`?, `placeholder`?, `defaultValue`?, `derivation`?, `appliesWhen`?, `footnote`?.
  - **`appliesWhen`:** `{"field": "document.variant", "oneOf": ["documentVariant.idCard.electronic"]}`. The field is shown and kept only while the asset's value is one of these keys; a reader drops a value whose field no longer applies.
  - **`footnote`:** one short line shown under the field.
  - **`defaultValue`:** a field value (see below), filled in when an asset is created and the field is empty. An example is `{"type": "number", "value": 24}` for warranty months.
  - **`derivation`:** `{"type": "addMonths", "date": "purchase.date", "months": "purchase.warrantyMonths"}`. The value is worked out again whenever one of its inputs changes, or while the field is empty. A value the person sets by hand stays until an input changes.
  - **`derivation` `validityAfterIssue`:** `{"type": "validityAfterIssue", "date": "document.issueDate"}`. A document's last valid day from its issue date, when its `document.type` and `document.variant` have a documented validity (today only `documentVariant.criminalRecord.judicial`: six months). Its inputs are the issue date, the type and the variant. A reader that doesn't know a derivation type ignores the derivation and keeps the value as stored.
  - **Options:** `[{"key": "fuel.diesel", "label": "Motorină", "aliases": ["Diesel"]}]`. Readers also accept a plain array of strings, from older definitions, and use each string as both key and label. An option may carry `appliesWhen` (same shape as above): it is offered only while that value matches, so a document's variants follow its type.
  - **Types:** `text`, `longText`, `number`, `year`, `money`, `date`, `expiryDate`, `toggle`, `choice`, `multiChoice`, `url`, `phone`, `email`, `address`, `plate`, `vin`, `microchip`, `iban`, `metric`, `secret`.
  - **`secret`:** a code kept hidden, such as an identity card's PIN. Its values are never written to an archive: writers leave them out, and readers ignore any they find and keep the ones already on the device for the same asset, in both import modes. A value sealed on the device (text starting with `sealed:v1:`) is a secret wherever it sits, so writers never write one under any field.
  - **Roles:** `identifier`, `subtitle`, `heroMetric`, `keyFact`, `documentNumber`, `holder`, `issuer`, `expiryDate`, `startDate`, `purchaseDate`, `purchasePrice`, `retailer`, `warrantyUntil`, `location`.
- **Component:** `key`, `name`, `group`, `synonyms`.
- **Blueprint:** `key`, `title`, `kind`, `recurrence`, `firstDue`, `reminders`, `reminderVariants`?, `appliesWhen`?, `estimatedCost`?, `isSuggested`, `note`?, `facts`?.
  - **`appliesWhen`:** `{"field": "subscription.cycle", "oneOf": ["billing.yearly"]}`. The blueprint is offered only when the asset's value is one of these keys.
  - **`facts`:** which of the section's fields hold this deadline's facts, by role: `{"insurer": "vehicle.cascoInsurer", "policyNumber": "vehicle.cascoPolicyNumber", "claimsPhone": "vehicle.cascoClaimsPhone"}`. A deadline's page and a claim checklist show these, so a car's CASCO never shows its RCA's policy. All keys are optional.

### Recurrence

```json
{"type": "none"}
{"type": "interval", "every": 2, "unit": "year", "anchor": "completion"}
{"type": "fixedDates", "dates": ["03-31", "09-30"]}
{"type": "metric", "every": 15000, "unit": "km", "fallbackEvery": 1, "fallbackUnit": "year"}
{"type": "legal", "rule": "vehicleITP"}
```

- **`unit`:** `day|week|month|year` for an interval and `fallbackUnit`; for a `metric` recurrence, the counter's unit key (see Units above), such as `km` or `h`.
- **`anchor`:** `dueDate` counts the next cycle from the previous due date; `completion` counts it from the day it was done.
- **Fixed dates:** the next cycle is the first listed date after the previous due date. 29 February becomes 28 February in common years, and month ends clamp (31 January plus one month is 28 or 29 February).
- **`vehicleITP`:** 6 months for cars in ridesharing or taxi use; otherwise 2 years while the car is at most 12 years old and 1 year after, counted from the inspection.

### First due date (`firstDue`)

```json
{"type": "field", "field": "document.expiry", "offsetDays": 0}
{"type": "afterInterval", "every": 1, "unit": "year"}
{"type": "nextFixedDate"}
{"type": "ask"}
```

### Reminder profile (`reminders`)

```json
{"leadDays": [30, 7, 0], "consequence": "legal", "graceDays": 0, "followUpAfterLapse": true}
```

- **`leadDays`:** days before the due date, largest first; `0` is the due day itself.
- **`consequence`:** `legal|financial|health|comfort`.
- **`graceDays`:** days of lateness that are still acceptable.
- **`followUpAfterLapse`:** one reminder the day after the due date if the obligation is still open, then nothing more.
  - **Default:** on for `legal` and `financial`, off otherwise. Readers apply this default when the key is missing.
  - **Per obligation:** the person can change it on each obligation.
- **`travelMarginDays`** (optional): how long before the due date the document stops being good for travel, in days, whole months counting as calendar months (180 is six months). Only a passport's profile has it (180). Leads then count back from that day, and the obligation is urgent from it on. Written only when it isn't 0; readers treat a missing key as 0.
- **`reminderVariants`:** `{"field": "document.type", "variants": {"Pașaport": {…profile…}}}`. It chooses a profile by an asset value.

### Asset (`data/assets.json`)

`id`, `templateKey`, `name`, `parentId`?, `symbolOverride`?, `tintOverride`?,
`notes`?, `values`, `customFacts`?, `photoPath`?, `isExample`, `createdAt`, `updatedAt`.

`customFacts` holds free rows under Date importante:
`[{"id": "…", "label": "Loc în port", "value": "Ponton 3", "isSensitive": false}]`.
A secret row (`"isSecret": true`, a code such as an alarm or Wi-Fi password)
is kept only on the device: writers leave it out, readers ignore any they
find and keep the device's own secret rows for the same asset.

`parentId` files the asset under another: a tenancy under its property, a
product under a home, a document under its holder. Deleting a parent never
deletes its children unless the person says so. A reader links parents with
the same rule as the app: an asset is never filed under itself or under
anything filed under it. A parent that would do that, or that is missing,
leaves the asset at the top level.

`values` maps field keys to typed values:

```json
{"type": "text", "value": "B-123-ABC"}
{"type": "number", "value": 142500}
{"type": "money", "amount": "350.00", "currency": "RON"}
{"type": "date", "value": "2027-03-31"}
{"type": "bool", "value": true}
{"type": "choices", "value": ["Căpușe", "Purici"]}
```

A reader skips a single value it can't read and keeps the rest of the asset.

**A bank card's number is never written.** A bank card (`document.type` `documentType.bankCard`) carries `document.cardNetwork` and `document.cardLastFour`, which holds four digits and nothing more. Writers write no card number in any value or `extractedText`; readers mask any they find (a run of 14 to 19 digits that starts like a card number and passes the Luhn check, or is printed in groups of four) to its last four digits after `••••`, and cut `document.cardLastFour` to its last four digits. A cazier keeps what it says, as printed, in `document.recordResult`.

**Choice values are option keys**, such as `fuel.diesel`, `vehicleUse.personal`, `documentType.passport` or `species.dog`, never display text. Single choices are `text` values and multiple choices are `choices` values. Labels come from the field's options, so they follow the reader's language.

**On import**, a choice value that isn't a key is matched against the options' labels and aliases, ignoring case and diacritics. This covers v2 backups and Android data that stored Romanian text. A match is stored as the key; text no option recognizes is kept as written.

Built-in option keys:

| Field | Keys |
| :--- | :--- |
| `vehicle.fuel` | `fuel.petrol`, `fuel.diesel`, `fuel.hybrid`, `fuel.plugInHybrid`, `fuel.electric`, `fuel.lpg` |
| `vehicle.usage` | `vehicleUse.personal`, `vehicleUse.commercial` |
| `document.type` | `documentType.idCard`, `documentType.passport`, `documentType.drivingLicence`, `documentType.euHealthCard`, `documentType.nationalHealthCard`, `documentType.greenCard`, `documentType.bankCard`, `documentType.eSignature`, `documentType.criminalRecord`, `documentType.other` |
| `document.cardNetwork` | `cardNetwork.visa`, `cardNetwork.mastercard`, `cardNetwork.maestro`, `cardNetwork.amex`, `cardNetwork.other` |
| `pet.species` | `species.cat`, `species.dog`, `species.other` |
| `health.bloodType` | `bloodType.0Positive`, `bloodType.0Negative`, `bloodType.aPositive`, `bloodType.aNegative`, `bloodType.bPositive`, `bloodType.bNegative`, `bloodType.abPositive`, `bloodType.abNegative` |
| `subscription.cycle` | `billing.monthly`, `billing.quarterly`, `billing.yearly` |

### Obligation (`data/obligations.json`)

`id`, `assetId`?, `title`, `notes`?, `blueprintKey`?, `kind`
(`legal|tax|insurance|health|renewal|payment|maintenance|routine`), `dueDate`,
`dueMetric`?, `reminders`, `reminderMinuteOfDay`?, `recurrence`,
`estimatedCost`?, `provider`?, `reference`?, `status`
(`active|paused|done|archived`), `snoozedUntil`?, `isExample`, `createdAt`,
`updatedAt`, `remindersCustomized`?.

- **`remindersCustomized`** (optional): `true` when the person set this deadline's reminders themselves. Written only when true; a missing key is `false`. A deadline that isn't customised takes its blueprint's profile for its asset's values again whenever a value that profile depends on changes (the `reminderVariants` field, such as a document's type or a pet's species); a customised one keeps its own.

**Household obligations** have no `assetId`. The one in use today is the yearly rental income declaration:

- **`blueprintKey`:** `household.rentalDeclaration`.
- **Due:** 25 May.
- **Lifecycle:** it exists exactly while at least one `tenancy` asset exists; readers recreate or remove it after import.

### History entry (`data/history.json`)

`id`, `assetId`?, `obligationId`?, `kind`
(`visit|repair|maintenance|inspection|purchase|payment|vaccination|treatment|note`),
`title`, `occurredAt`, `metricReading`?, `totalCost`?, `note`?, `rating`?
(1–5), `cycleDueDate`?, `nextDueDate`?, `previousStatus`?,
`previousDueMetric`?, `providerIds`, `isExample`, `reference`?, `updatedAt`?.

An entry with `cycleDueDate` records the completion of `obligationId`. Its
`previous*` values let the latest completion be undone.

- **`reference`** (optional): the number of the paper the entry records, as
  printed: a bill's invoice number. Within one subscription, a bill with the
  same `reference` is the same bill; without one on both, the same day and
  total are. Readers that don't know it keep the entry as it is.

### Line item (`data/service_items.json`)

`id`, `entryId`?, `componentKey`?, `name`, `group`?, `partBrandOrCode`?,
`partSerialNumber`?, `cost`?, `laborCost`?, `partsCost`?, `supplierId`?,
`batchOrTicket`?, `locationDetail`?, `daysInService`?, `warrantyMonths`?,
`notes`?, `isExample`, `updatedAt`?.

`componentKey` is a key from the asset's template components, or
`custom.<slug>` for free text. The slug is the text, lowercased, with no
diacritics, and words joined by `-`.

### Provider (`data/providers.json`)

`id`, `name`, `trades`, `phone`?, `email`?, `address`?, `notes`?,
`manualRating`? (1–5), `wouldCallAgain`?, `assetIds`, `isExample`,
`createdAt`, `updatedAt`, `taxID`?.

- **Trades:** `mechanic`, `tyreShop`, `inspectionStation`, `bodyShop`, `plumber`, `electrician`, `gasTechnician`, `boilerTechnician`, `hvacTechnician`, `handyman`, `vet`, `doctor`, `dentist`, `insuranceAgent`, `insurer`, `accountant`, `tenant`, `emergencyContact`, `other`. Any other string is kept as written.
- **Rating:** the shown rating is the average of the job ratings in `history.json`, or `manualRating` when no job is rated.
- **`taxID`:** the firm's tax ID (CUI), digits only, without `RO`. Two firms with the same `taxID` are the same firm.

### Measurement (`data/measurements.json`)

`id`, `assetId`?, `kind`
(`electricity|gas|coldWater|hotWater|thermalEnergy|biomarker|bloodPressure|bodyWeight|diopters|odometer|engineHours|cycles|custom`),
`name`, `value`, `secondaryValue`?, `unit`, `recordedAt`, `unitPrice`?,
`isSelfRead`, `referenceMin`?, `referenceMax`?, `source`?, `notes`?,
`isExample`, `updatedAt`?.

- **`unit`:** a unit key (see Units above), or `""` when the reading has none. Readings in the same unit form one series: a counter's readings are matched to its field and its metric deadlines by this key.

### Attachment (`data/attachments.json`)

`id`, `title`?, `fileName`, `kind`
(`invoice|receipt|policy|contract|certificate|report|identity|warranty|manual|prescription|photo|other`),
`contentType`, `byteCount`, `sha256`?, `path`?, `pagePaths`, `thumbnailPath`?,
`extractedText`?, `documentDate`?, `isArchived`, `supersededById`?,
`createdAt`, `isExample`, `assetId`?, `obligationId`?, `historyEntryId`?,
`serviceItemId`?, `measurementId`?, `providerId`?, `validUntil`?, `framing`?,
`updatedAt`?.

- **Fingerprint:** `sha256` is the hash of the original file, or of the page images joined in order when there is no original.
- **Replaced documents:** a replaced document is kept with `isArchived: true` and `supersededById` pointing to its replacement.
- **`validUntil`:** a calendar day, the last day the document itself is valid, as read when it was filed (a policy's end). Its deadline moving on later doesn't change it.
- **`framing`:** how the pages are shown; the page files stay as taken. `{ "version": 1, "pages": [ … ] }`, one entry per page in order (a page image, or a PDF's page), each optional: `crop`, the document's four corners in the photo (top-left, top-right, bottom-right, bottom-left) as fractions of its width and height from the top-left corner; `prefersWholePhoto`, the app's choice of the whole photo over the cut-out; `quarterTurns`, the app's guess of quarter turns clockwise (0–3) that put the page upright; and `choice`, what the person chose (`quarterTurns`, `showsWholePhoto`), which wins over both. A page is drawn cut out (with a perspective correction) when it has a `crop` and neither choice is the whole photo, then turned. A missing entry, or a missing `framing`, is the page as it is, whole and as taken. Keys a reader doesn't know are ignored.
- **`extractedText`:** what was read off the document, with any card number masked ("•••• 1111"); a reader masks any it finds the same way.

## Change times

Every record carries `updatedAt`, when it last changed: templates, assets,
obligations and providers always; history entries, line items, measurements
and attachments optionally. It moves when one of the record's own values or
links changes: its fields, the record it points to (`assetId`, `entryId`, …)
and the lists it keeps itself (a provider's `assetIds`, an entry's
`providerIds`). A record pointed at doesn't change when another record is
linked to it: an asset doesn't change when it gets a new history entry.
An attachment changes when one of its pages does.

A missing `updatedAt` (archives written before it was carried for history
entries, line items, measurements and attachments) is **unknown**: older
than any change, and the same for every reader. Writers leave it out for a
record whose change time they don't know.

## Import modes

Both modes write every record by one rule, whatever its type: a record whose
`id` (a template's `key`) isn't on the device is added; a record that is
there is replaced by the archive's copy only when the archive's `updatedAt` is
later. An unknown change time is older than any other; on a tie the device's
own copy stays. In both modes a timestamp later than the moment of import is
taken as now.

- **Replace:** removes everything, then writes the archive. It is all or nothing: a failure leaves the existing data untouched. Secrets the device keeps (PIN codes, secret rows) stay with their records, and locks stay on.
- **Merge:** keeps local data and takes the archive's newer copies. A replaced attachment takes the archive's pages and files too.

Records deleted on one side aren't deleted on the other: an archive carries
no deletions, so a merge brings back a record the device deleted.

## Values from a newer version

A newer writer can write values an older reader doesn't know. A reader keeps
what it can't read, raw, and writes it back unchanged; it never writes back a
smaller value in its place. It drops such a value only when the person sets a
new one for the same thing.

- **Field values:** a value of an unknown `type` is kept under its key.
- **Recurrence:** an unknown `type`, legal `rule`, `unit`, `anchor` or `fallbackUnit` is kept as written; the obligation behaves as one-off until the person picks a rule the reader knows.
- **Template sections, blueprints, components and custom facts:** each entry is read on its own. An entry the reader can't read is kept in its place and written back; one it can read with the same `key` (an `id` for a custom fact) replaces it. A secret custom fact (`"isSecret": true`, or any sealed text) is left out by writers and readers, read or not.
- **Fields:** an unknown `type`, `role`, `defaultValue`, `derivation` or `appliesWhen` is kept as written; the field reads as `text`, without the part it can't read.
- **Kinds** (`kind` of an obligation, a history entry, a measurement or an attachment) are kept as written.

Keys a reader doesn't know inside a record it reads are ignored.

## Password-protected archives

An archive can be protected with a password. The file keeps the `.dosar`
extension and type; its bytes are the plain ZIP above, encrypted whole. All
integers are big-endian.

| Bytes | Contents |
| :--- | :--- |
| 8 | `DOSARENC` (ASCII), which tells it from a ZIP |
| 1 | Version: `1` |
| 1 | Key derivation: `1` = PBKDF2-HMAC-SHA256 |
| 4 | Iterations (the iOS writer uses 600 000; readers accept 1 to 10 000 000) |
| 16 | Salt, random |
| 4 | Chunk size in bytes (the iOS writer uses 1 MiB) |
| 8 | Nonce prefix, random |
| rest | The ZIP in chunks of the chunk size (the last may be shorter, and is the only one when the ZIP fits in one), each encrypted with AES-256-GCM and followed by its 16-byte tag |

The 32-byte key is PBKDF2-HMAC-SHA256 of the password (UTF-8, Unicode
normalization form C) with the salt and the iterations. Chunk `i` (from 0)
uses the 12-byte nonce `prefix ‖ i` (4 bytes) and authenticates, as
additional data, the whole 42-byte header followed by one byte: `1` for the
last chunk and `0` for the others. A reader that fails to open any chunk
stops: the password is wrong or the file was changed, cut or reordered.
The password is never stored in the archive or on the device.

## Changes from version 2

- **Templates:** version 3 adds templates, providers, history entries and reminder profiles.
- **Field values:** asset fields are a typed `values` map, instead of fixed columns.
- **Completions:** completed events are history entries.
- **Contacts:** asset contacts are providers.
- **Data files:** `events.json` became `obligations.json`, `service_history.json` became `service_items.json` (linked to history entries), and `attachments_meta.json` became `attachments.json`.
