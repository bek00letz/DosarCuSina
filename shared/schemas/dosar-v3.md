# `.dosar` archive format, version 3

The household backup and transfer format shared by every platform. It is a
plain ZIP file (DEFLATE or STORE entries) with JSON inside, readable with
`java.util.zip` and `org.json` on Android and with any `unzip`.

- **File extension:** `.dosar`
- **Type identifier:** `com.ar.dosarcusina.dossier` (conforms to `public.zip-archive`)
- **MIME type:** `application/vnd.dosarcusina.dossier+zip`
- **JSON Schema:** [`dosar-v3.schema.json`](dosar-v3.schema.json)
- **Golden fixtures:** [`../fixtures/dosar-v3/household`](../fixtures/dosar-v3/household) (v3) and [`../fixtures/dosar-v2/ios-export`](../fixtures/dosar-v2/ios-export) (v2, still importable). Every implementation must import both.

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
- **Timestamps** (`createdAt`, `occurredAt`, `recordedAt`, `exportedAt`, `snoozedUntil`): ISO 8601 in UTC, such as `2026-03-01T07:30:00Z`. Readers accept fractional seconds and offsets.
- **Calendar days** (`dueDate`, `cycleDueDate`, `documentDate`, date field values): `yyyy-MM-dd`, with no time zone. A day is the same day everywhere.
- **Month-days** (fixed yearly dates): `MM-dd`.
- **Money:** `{"amount": "175.50", "currency": "RON"}`. The amount is a decimal string with a dot; the currency is ISO 4217. Amounts in different currencies are never added together.
- **Optional values** are omitted rather than written as `null`. Readers accept either.
- **Enumerations** are lowercase-camel strings. A reader that meets an unknown value keeps the record and falls back: unknown field types become `text`, unknown kinds become the generic one (`routine`, `note`, `other`), unknown trades are kept as text.

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
`components`?, `createdAt`, `updatedAt`.

Built-in keys: `vehicle`, `home`, `documents`, `pet`, `health`, `warranty`,
`subscription`, `other`, `bike`, `plants`, `rental`, `espresso`. Custom keys
start with `custom.`. For a built-in template, a reader keeps its own
definition unless the archive's `version` is higher, and always applies the
household preferences (`homeOrder`, `isOnHome`, `isSensitive`).

- **Section:** `key`, `title`, `fields`.
- **Field:** `key`, `label`, `type`, `role`?, `isEssential`, `isSensitive`, `options`?, `unit`?, `placeholder`?.
  - **Options:** `[{"key": "fuel.diesel", "label": "Motorină", "aliases": ["Diesel"]}]`. Readers also accept a plain array of strings, from older definitions, and use each string as both key and label.
  - **Types:** `text`, `longText`, `number`, `money`, `date`, `expiryDate`, `toggle`, `choice`, `multiChoice`, `url`, `phone`, `email`, `address`, `plate`, `vin`, `microchip`, `iban`, `metric`.
  - **Roles:** `identifier`, `subtitle`, `heroMetric`, `keyFact`, `documentNumber`, `holder`, `issuer`, `expiryDate`, `startDate`, `purchaseDate`, `purchasePrice`, `retailer`, `warrantyUntil`, `location`.
- **Component:** `key`, `name`, `group`, `synonyms`.
- **Blueprint:** `key`, `title`, `kind`, `recurrence`, `firstDue`, `reminders`, `reminderVariants`?, `estimatedCost`?, `isSuggested`, `note`?.

### Recurrence

```json
{"type": "none"}
{"type": "interval", "every": 2, "unit": "year", "anchor": "completion"}
{"type": "fixedDates", "dates": ["03-31", "09-30"]}
{"type": "metric", "every": 15000, "unit": "km", "fallbackEvery": 1, "fallbackUnit": "year"}
{"type": "legal", "rule": "vehicleITP"}
```

- **`unit`:** `day|week|month|year`.
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
- **`reminderVariants`:** `{"field": "document.type", "variants": {"Pașaport": {…profile…}}}`. It chooses a profile by an asset value.

### Asset (`data/assets.json`)

`id`, `templateKey`, `name`, `symbolOverride`?, `tintOverride`?, `notes`?,
`values`, `photoPath`?, `isExample`, `createdAt`, `updatedAt`.

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

**Choice values are option keys**, such as `fuel.diesel`, `vehicleUse.personal`, `documentType.passport` or `species.dog`, never display text. Single choices are `text` values and multiple choices are `choices` values. Labels come from the field's options, so they follow the reader's language.

**On import**, a choice value that isn't a key is matched against the options' labels and aliases, ignoring case and diacritics. This covers v2 backups and Android data that stored Romanian text. A match is stored as the key; text no option recognizes is kept as written.

Built-in option keys:

| Field | Keys |
| :--- | :--- |
| `vehicle.fuel` | `fuel.petrol`, `fuel.diesel`, `fuel.hybrid`, `fuel.plugInHybrid`, `fuel.electric`, `fuel.lpg` |
| `vehicle.usage` | `vehicleUse.personal`, `vehicleUse.commercial` |
| `document.type` | `documentType.idCard`, `documentType.passport`, `documentType.drivingLicence`, `documentType.euHealthCard`, `documentType.greenCard`, `documentType.bankCard`, `documentType.eSignature`, `documentType.criminalRecord`, `documentType.other` |
| `pet.species` | `species.cat`, `species.dog`, `species.other` |
| `health.bloodType` | `bloodType.0Positive`, `bloodType.0Negative`, `bloodType.aPositive`, `bloodType.aNegative`, `bloodType.bPositive`, `bloodType.bNegative`, `bloodType.abPositive`, `bloodType.abNegative` |
| `subscription.cycle` | `billing.monthly`, `billing.quarterly`, `billing.yearly` |

### Obligation (`data/obligations.json`)

`id`, `assetId`?, `title`, `notes`?, `blueprintKey`?, `kind`
(`legal|tax|insurance|health|renewal|payment|maintenance|routine`), `dueDate`,
`dueMetric`?, `reminders`, `reminderMinuteOfDay`?, `recurrence`,
`estimatedCost`?, `provider`?, `reference`?, `status`
(`active|paused|done|archived`), `snoozedUntil`?, `isExample`, `createdAt`,
`updatedAt`.

### History entry (`data/history.json`)

`id`, `assetId`?, `obligationId`?, `kind`
(`visit|repair|maintenance|inspection|purchase|payment|vaccination|treatment|note`),
`title`, `occurredAt`, `metricReading`?, `totalCost`?, `note`?, `rating`?
(1–5), `cycleDueDate`?, `nextDueDate`?, `previousStatus`?,
`previousDueMetric`?, `providerIds`, `isExample`.

An entry with `cycleDueDate` records the completion of `obligationId`. Its
`previous*` values let the latest completion be undone.

### Line item (`data/service_items.json`)

`id`, `entryId`?, `componentKey`?, `name`, `group`?, `partBrandOrCode`?,
`partSerialNumber`?, `cost`?, `laborCost`?, `partsCost`?, `supplierId`?,
`batchOrTicket`?, `locationDetail`?, `daysInService`?, `warrantyMonths`?,
`notes`?, `isExample`.

`componentKey` is a key from the asset's template components, or
`custom.<slug>` for free text. The slug is the text, lowercased, with no
diacritics, and words joined by `-`.

### Provider (`data/providers.json`)

`id`, `name`, `trades`, `phone`?, `email`?, `address`?, `notes`?,
`manualRating`? (1–5), `wouldCallAgain`?, `assetIds`, `isExample`,
`createdAt`, `updatedAt`.

- **Trades:** `mechanic`, `tyreShop`, `inspectionStation`, `bodyShop`, `plumber`, `electrician`, `gasTechnician`, `boilerTechnician`, `hvacTechnician`, `handyman`, `vet`, `doctor`, `dentist`, `insuranceAgent`, `accountant`, `tenant`, `emergencyContact`, `other`. Any other string is kept as written.
- **Rating:** the shown rating is the average of the job ratings in `history.json`, or `manualRating` when no job is rated.

### Measurement (`data/measurements.json`)

`id`, `assetId`?, `kind`
(`electricity|gas|coldWater|hotWater|thermalEnergy|biomarker|bloodPressure|bodyWeight|diopters|odometer|engineHours|cycles|custom`),
`name`, `value`, `secondaryValue`?, `unit`, `recordedAt`, `unitPrice`?,
`isSelfRead`, `referenceMin`?, `referenceMax`?, `source`?, `notes`?,
`isExample`.

### Attachment (`data/attachments.json`)

`id`, `title`?, `fileName`, `kind`
(`invoice|receipt|policy|contract|certificate|report|identity|warranty|manual|prescription|photo|other`),
`contentType`, `byteCount`, `sha256`?, `path`?, `pagePaths`, `thumbnailPath`?,
`extractedText`?, `documentDate`?, `isArchived`, `supersededById`?,
`createdAt`, `isExample`, `assetId`?, `obligationId`?, `historyEntryId`?,
`serviceItemId`?, `measurementId`?, `providerId`?.

- **Fingerprint:** `sha256` is the hash of the original file, or of the page images joined in order when there is no original.
- **Replaced documents:** a replaced document is kept with `isArchived: true` and `supersededById` pointing to its replacement.

## Import modes

- **Replace:** removes everything, then writes the archive. It is all or nothing: a failure leaves the existing data untouched.
- **Merge:** keeps local data. Templates, assets, obligations and providers update when the archive's `updatedAt` is newer. History entries, line items, measurements and attachments are added when their `id` is new.

## Changes from version 2

- **Templates:** version 3 adds templates, providers, history entries and reminder profiles.
- **Field values:** asset fields are a typed `values` map, instead of fixed columns.
- **Completions:** completed events are history entries.
- **Contacts:** asset contacts are providers.
- **Data files:** `events.json` became `obligations.json`, `service_history.json` became `service_items.json` (linked to history entries), and `attachments_meta.json` became `attachments.json`.
