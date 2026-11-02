# Dosar cu Șină — product specification

This describes what is built today, from the code. When the code and this file disagree, the code wins and this file gets fixed. Decisions and their reasons live in [docs/DECISIONS.md](docs/DECISIONS.md). The first, Gemini-built specification is kept in [docs/archive/SPEC-v1.md](docs/archive/SPEC-v1.md) as a way back; it no longer describes the app.

UI terms are the app's real Romanian labels, with an English gloss the first time they appear.

## 1. Product principles

- **A documents binder, not a to-do app.** A *dosar cu șină* is the slotted folder Romanians keep their papers in. The app is that folder for rare-but-predictable life admin: the car's ITP and RCA, the boiler check, the passport, the cat's vaccine, the warranty on the washing machine. It opens on the binder, not on a list of deadlines.
- **Capture first.** The phone already has the photos, PDFs, mail and messages. The main way in is a photo or a document shared from another app; typing is the fallback.
- **Offline and private.** Everything works on the device, with no account and no network. Data stays on the phone. The only thing that ever leaves it is a page the person explicitly chooses to read with their own AI key.
- **Short and calm.** The list of what comes next stays short however much is tracked. Reminders arrive as early as the renewal needs, not earlier, and never nag.
- **Built for people who aren't tech-savvy** (aged 50–60 is the reference). Four labelled tabs, big targets, no horizontal scrolling, no hidden gestures needed, obvious buttons with verbs on them.
- **Free and complete without a key.** Nothing is behind a paywall, and nothing needs an AI key to work.
- **Sensible first run.** The app starts empty, with *Încarcă exemple* (load examples) for exploring. Examples are tagged, never notify, never reach widgets, and go away with one tap.

## 2. App structure

### 2.1 The shell

Four labelled tabs, always visible:

| Tab | Gloss | What it holds |
| :--- | :--- | :--- |
| **Dosar** | the binder | The grid of boxes. |
| **Urmează** | what's next | The short list of what needs attention. |
| **Adaugă** | add | Camera, photos, files, typing, and *De verificat* (to review): what other apps sent. |
| **Caută** | search | One field over the whole binder. |

Each tab has its own navigation stack, owned by the shell. Every place the app can open is an `AppRoute`, and every route, whether from a notification, a widget, a `dosarcusina://` link, Shortcuts or a search result, goes through one router (`ShellRouter`). Settings, *Adaugă o secțiune* (add a section) and the visit flow are sheets the shell presents; sheets never stack.

Onboarding runs once, is short and skippable: what the app is, an optional first photo, a practice share from another app (see 5.6), and examples or an empty start. It asks for no permission.

### 2.2 The binder grid (Dosar)

- **One box per thing the household looks after:** each car, home or pet gets its own box. Categories with many small records get one box each: *Acte* (documents), *Garanții* (warranties) and *Abonamente* (subscriptions). *Agendă* (people and firms) is always last. A final dashed box adds a section.
- **Nested records have no box of their own.** Tenancies live inside their home; household members and their documents live inside Acte; anything filed under another asset lives inside its parent.
- **One status line per box**, from the box status engine (4.5): *Totul e în regulă* (all good), or the single most pressing deadline and how far it is (*RCA · în 5 zile*). Status uses a symbol and a semantic colour, never colour alone. In a locked section the line names no deadline.
- **Opening a box zooms** out of the box with the system zoom transition; going back returns into it. The same screens pushed from elsewhere slide in.
- **Rearranging:** long-press and drag. VoiceOver and the context menu offer *Mută mai în față / în spate* (move earlier / later). The order is kept on this device; new boxes slot in next to their neighbours.
- **Layout:** two columns on iPhone, adaptive on iPad, one column at accessibility text sizes.
- **First run:** an empty state with *Adaugă primul lucru* (add the first thing) and *Încarcă exemple*.

### 2.3 Section pages

A section is the page of one asset. One vertical scroll: a hero, then the category's pockets.

**Heroes** follow the template's hero style: vehicle (plate, make, model, year, odometer), home (address and the meter-reading window), document (expiry and "valid until"), pet (photo, age, weight) and standard (name, identifier, next deadline).

**Pockets** are fixed parts of a page. A template declares which pockets it shows, and they always appear in one global order, so every page reads the same way:

1. *Urmează* — the next few deadlines (at most 3; the rest are in the tab).
2. *Chiriași* — tenancies filed under a property.
3. *Produse* — products filed under a home.
4. *Abonamente* — subscriptions filed under the asset.
5. *Acte* — documents.
6. *Istoric* — history: visits, repairs, purchases, and "last time" per component (*acum 18.200 km · 14 mar. 2025 · 420 lei*).
7. *Oameni* — the people and firms who look after it.
8. *Bani* — what it has cost, all time and in the last twelve months, per currency.
9. *Date importante* — key facts and free label–value rows (alarm code, Wi‑Fi, contract number), each one tap to copy or call.

Editing uses the design system's fields and asks before discarding changes. Fields that depend on another value (a document's variant on its type, the PIN codes on the electronic identity card) appear only while it matches. Deleting a section asks what happens to what is filed under it: keep those records on their own, or delete them too.

**Mută la…** (move to). Anything filed under something else (a document under a household member, a tenancy or a product under a home) moves from its page, and so does any subscription: between homes, under a home, or out to Abonamente (*În Abonamente, fără locuință*). It moves through the toolbar's *Mai multe* menu or the edit sheet. A short list offers the other parents of the same kind and, for a document, *O persoană nouă*. A document named after its holder ("Carte de identitate – Manole Corina") offers to take the new holder's name. The move is one save; the toast offers *Anulează*, which also removes a person made only for the move.

**A document's page** asks for its picture when it has none (*Adaugă poza actului*, through capture, which fills in what it reads), and shows its secret fields under *Coduri PIN* (see 7).

### 2.4 Category boxes and Agenda

- **Acte** groups documents by the household member they belong to, soonest expiry first, plus a group for documents not filed under anyone.
- **Adding a document for a person** (from Acte or the person's page) starts with the person chosen and three choices: *Fotografiază*, *Din poze* and *Scriu eu*. A photo goes through capture (5.4) and is filed as one of that person's documents whatever its kind. *Scriu eu* is one screen: the type in big rows; a variant only for types that have real ones (*Ce fel de cazier?* judiciar, fiscal or auto; card de debit or de credit; carte de identitate electronică (CEI) or fără cip; pașaport simplu electronic or temporar); a name that comes by itself, "<document> – <Surname Given names>", with *Schimbă*; the expiry with its reminder in plain words (*Expiră pe 30 iunie 2027. Te anunț cu 6 luni și cu două luni înainte.*); and *Salvează*. The reminder comes from the type's profile and can be changed on the deadline page. Both ways land on the document's page.
- **Garanții** groups products by whether their warranty still covers them.
- **Abonamente** lists every subscription, those under a home included, with what they cost a month: the price, or the last bill for a contract billed by use (amounts are never added across currencies). A subscription's page shows its bills in Istoric and, in Bani, *Ultima factură*, how it compares with the one before (*Cu 32,10 lei mai mult decât cea dinainte.*) and the average bill over the last year, one per currency.
- **Agendă** lists everyone the household relies on, grouped by trade or by section, best rated first, with the last job and its price, and real buttons to call or message. A provider's page shows their jobs, ratings and *Aș chema din nou* (would call again).

### 2.5 Urmează

A calm, short list built on the attention model (4.4):

- *Acum* (now): the few things that need the person, most consequential first.
- *Curând* (soon): the rest of the next month, one collapsed row per section.
- *Mai târziu* (later): a count that opens the full list.
- *Din timp*: calm notes with nothing due, today a bill that hasn't come (*Factura de la ENGIE n-a venit luna asta*), each opening its subscription (4.10).

Snoozed and paused items are counted, not listed. Tapping a deadline opens its page: when it is and why it matters, last time's price and who did it, the policy number and claims phone, what to bring (with what the binder already holds ticked), the actions (*Am rezolvat* — done, snooze, reschedule, pause, add to Calendar) and how it reminds.

### 2.6 Adaugă

Four big buttons: camera (document scanner), photos, files, and *Scriu eu* (I'll type it). A card teaches sharing from Mail or WhatsApp. *De verificat* lists what arrived from other apps, with a badge on the tab.

- *Scriu eu*: pick the section (or make one), then add a deadline, a visit or a document.
- *Am fost la service* (visit flow): one visit with many parts. Big check rows grouped by the template's components, each with an optional cost and brand; the date, the counter, the total and who did it; and an invoice photo that ticks the rows by itself. It saves once, then shows what changed with a way to take it back.
- *Adaugă o secțiune*: pick a ready-made category or describe one's own (*Altceva…*: name, symbol, pockets), fill only the essentials, then choose the deadlines to start with, each with its reminders said plainly (*Te anunț cu 30 de zile înainte*).

### 2.7 Caută

One field over sections, deadlines, history, components, people and the text read from scanned documents. It ignores case and diacritics (*polita* finds *poliță*), matches each word as the start of a word so Romanian endings still match, and needs every word to match. Results are grouped with matching words highlighted. Sensitive fields, secret fields and sensitive free facts are not indexed; results from locked sections show their title only.

### 2.8 Settings

Reminder time, app lock and section locks, which categories show on the binder, backup (export and import), the optional AI provider and its key, examples, storage and about. Settings can open scrolled to a section from a link.

## 3. Data model

SwiftData, one versioned schema (`DosarSchemaV2`) with a migration plan. The shapes follow CloudKit's rules from day one (every property optional or defaulted, every relationship optional, nothing unique) so iCloud sync can be added without reshaping. Complex values (field values, template sections, recurrence rules) are stored as JSON with sorted keys, the same encoding the `.dosar` archive uses. Every record has `isExample`.

| Model | What it is |
| :--- | :--- |
| `CategoryTemplate` | A category (Mașini, Locuințe, Acte…) and the household's preferences for it: order, whether it shows on the binder, whether it is locked. |
| `Asset` | Something the household looks after. Its details are field values described by its template. It can have a parent and children. |
| `Obligation` | Something to do by a date, once or on a schedule, with a reminder profile. |
| `HistoryEntry` | Something that happened: a visit, repair, purchase, inspection, payment, vaccination or a completed obligation. |
| `ServiceItem` | One line of a history entry, keyed to a component, with costs, brand, supplier and warranty. |
| `MeasurementLog` | A reading: odometer, meter index, weight, lab value. Readings are the source of truth for counters. |
| `Attachment`, `AttachmentPage` | A document: original file, scanned pages, thumbnail, fingerprint, extracted text. Replacing one archives the old and links them. |
| `Provider` | A person or firm, with trades, contact details, ratings and "would call again". |

### 3.1 Templates

Every category is one template engine. A `TemplateDefinition` declares sections of typed fields (text, number, year, money, date, expiry date, choice, multiple choice, phone, email, address, plate, VIN, microchip, IBAN, counter and more), field roles (identifier, hero metric, key fact, expiry date…), obligation blueprints, components for the maintenance log, pockets and a hero style.

- Built-in templates ship in the app (car, home, documents, pet, health, warranties, subscriptions, other, and starters hidden from the binder: bikes, plants, tenancies, household members, espresso machines). They are installed and upgraded by version; upgrades keep the household's preferences, and renamed or retired templates move their assets over so nothing disappears.
- Custom templates are the person's own and travel in archives in full.
- Choice values are stored as stable option keys, never as display text. Older stored text is migrated at launch.
- A field, and a choice option, can carry a condition (`appliesWhen`): it is offered only while another value matches. A document's variants are data on its type (`DocumentType.variants`), offered only for that type; a value that no longer fits is dropped on save.
- A `secret` field holds a code to keep hidden (see 7).
- When a derived field is given in the same change as its inputs (a contract's printed end beside its start and length), the given value is kept; it is worked out again only when an input changes alone.
- Legal cadences follow [shared/ROMANIAN_ADMINISTRATIVE_STANDARDS.md](shared/ROMANIAN_ADMINISTRATIVE_STANDARDS.md).

### 3.2 Parent and child

An asset can be filed under another: a tenancy under its property, a product under a home, a document under its holder. The engine refuses loops. A box's status includes what is filed under it. Moving to another parent of the same kind goes through `AssetActions.move` (one save, with `undoMove`).

### 3.3 Household members

A household member (template `member`) is a name only; no personal number is stored on the member. Personal documents are filed under the member they belong to, and Acte groups them that way. The member's obligations count towards Acte.

### 3.3a Subscriptions

A subscription (template `subscription`, keys in `SubscriptionFields`) is one ongoing contract: the provider, the service (*Gaz*, *Curent*, *Apă*, *Internet și TV*, *Telefon mobil*, *Alt abonament*; stored as `service.*` keys, `ServiceKind`), the price and billing cycle, the codes its bills quote (*Cod client*, *Număr contract*, and only for its service the POD, the CLC or the phone number; each one tap to copy), the start, the minimum period in months and when it ends (worked out from the two), *Plătesc prin debit direct* and *Ultima factură*. Gas, electricity, water and fixed internet or TV are filed under the home they supply (the home's *Abonamente* pocket); a mobile plan stands on its own. Its deadlines: the yearly renewal, the contract's end, *Se termină perioada minimă* (30 days before and on the day) and one *Factura de plătit*, which each bill moves to its own due date.

### 3.4 Obligations

An obligation is never copied to make the next cycle. Completing it writes a history entry and moves its due date forward; only the latest completion can be undone. Statuses: active, paused, done (a one-off that was completed) and archived. Snoozing hides it and its reminders until a date, then reminds once.

### 3.5 History, maintenance log and providers

Every asset type has a smart maintenance log. Line items point at the template's components (matched from free text and synonyms, without diacritics), so the history answers "when did I last change it" whatever the bill called it: when, how far the counter has moved since, what it cost, the supplier and who did it. With two or more past jobs it estimates the next one from the asset's own pace, and says it is an estimate.

A provider's rating is the average of their rated jobs, or the person's own rating when no job is rated.

## 4. Engines

All engines are pure where they can be (no database, no notification centre) and pinned by tests.

### 4.1 Obligation actions

`ObligationActions` is the only way to change an obligation: complete, undo, snooze, reschedule, pause, resume, archive, delete, change reminders, create from a blueprint. It is used by every screen, notification buttons, widgets and Shortcuts alike. Each call saves once; side effects follow from the save.

### 4.2 Recurrence

`RecurrenceEngine` works out first due dates from blueprints and the next due date after a completion:

- **none** — a one-off.
- **interval** — every N days, weeks, months or years, counted from the previous due date (payments, insurance) or from the day it was done (inspections, chores).
- **fixed dates** — the same calendar days each year (tax instalments, tyre changes).
- **metric** — every N units of a counter (service every 15 000 km), projected from the counter's recent pace, with a calendar fallback.
- **legal** — rules that need asset data, such as the car ITP cadence by age and use.

First dates come from a field on the asset (a document's expiry), one interval from today, the next fixed date, or the person. All calendar arithmetic handles month ends and 29 February.

### 4.3 Reminder profiles

Each obligation carries a profile: lead days, a consequence (legal, financial, health, comfort), grace days, and an optional follow-up. The lead time follows how hard the renewal is, not a fixed schedule:

| Obligation | Reminds |
| :--- | :--- |
| Rovinietă (road vignette) | 7 days before and on the day |
| Driving licence | 60 and 30 days before |
| Passport | 180 and 60 days before |
| Cat vaccine | 1 day before, with a week's grace |
| Dog rabies vaccine | 10 and 4 days before, legal, no grace |

Profiles can vary by a field value (document type, pet species). The person can change any profile.

**Follow-up after a lapse:** one reminder the day after the due date if it is still open, then silence. On by default for legal and financial items; the person can turn it on or off for any item.

Reminders fire at the person's chosen time of day (09:00 by default), keep the wall-clock time across daylight-saving changes, and stay within the system's limit on pending notifications. The last reminders for consequential items may break through Focus. Notification buttons *Am rezolvat* and *Amână 3 zile* (snooze 3 days) go through `ObligationActions`.

### 4.4 Attention model

`AttentionModel` ranks open obligations by consequence first, then by closeness, then by cost. Closeness can lift an item by a few consequence steps but an overdue chore never beats a legal deadline. Lateness within grace counts like "due soon", not like overdue. Each consequence has a maximum attention window (legal 30 days, financial 21, health 7, comfort 3), so a passport that reminds 180 days ahead only joins the list in the last month.

The digest has a capped *now* (5 items), a *soon* window grouped per asset (30 days), and *later* as counts. Overdue plus due today feed the app badge and widgets.

### 4.5 Box status

`BoxStatus` takes the obligations of a box (and of what is filed under it), ranks them exactly as Urmează does, and shows only the top one if it is inside its attention window. Distances read in the unit a person feels (4.9).

### 4.6 Readiness

`ObligationRequirements` lists what to bring for each built-in obligation (the papers an ITP station asks for, what a passport renewal needs) and whether the binder already holds each: a value on the asset, a current document of the right kind, or another obligation that must still be valid on the day. The obligation page shows it.

`ReadinessEngine` checks scenarios such as a trip abroad (inside or outside the EU, driving, with a pet), selling a vehicle or an insurance claim, and returns a checklist with problems first. The engine and its tests exist; no screen uses the scenarios yet.

### 4.7 Search

`SearchIndexBuilder` builds an in-memory index from the database, and `SearchEngine` matches and ranks it (2.7). Identifiers such as plates and IBANs are also searchable without separators.

### 4.8 Household rules

`HouseholdRules` keeps obligations that belong to the household rather than to one asset in step with the data. Today there is one: while at least one tenancy exists, the household files one *Declarația unică* (the annual income declaration) for rental income by 25 May. It has no asset, shows in Urmează but in no section, and is an example only while every tenancy is an example.

### 4.9 Wording

How far away something is reads in the unit a person feels, never rounded up: days under three weeks, then weeks, then months and weeks, then years and months (years only from three years). `DurationWording`, `DayCount` and `CalendarCount` are the one way to write these, with Romanian plural forms from the String Catalog.

### 4.10 Subscriptions and their bills

`SubscriptionMatcher` (pure) finds the subscription a bill or a contract belongs to. The codes decide first: a POD, a CLC or a phone number (one consumption point or one line, and a subscription with a different one is never the match), then the contract number, then the client code (which alone can't tell two homes apart, as one customer has one client code for several places). Without a code, the provider (and the service, when both are known) decides only inside one house: the home whose own POD, CLC or water code the document prints, or the only home. A new subscription goes under its house for gas, electricity, water and fixed internet or TV, and stands on its own for a mobile plan or anything else; with no home yet it stands on its own (and can be moved). When the house or the contract can't be told, nothing is guessed.

`BillHistory` (pure) reads a subscription's bills (its history's payments, not the completions of a deadline): the trend (the last bill, the difference from the one before in the same currency, the average over the last year per currency) and the missing bill. A bill is missing when one cycle after the last one (monthly unless the subscription says otherwise) has passed by more than ten days for a monthly bill (up to 30 for longer cycles) plus the provider's own usual delay (how late bills came before, at most 15 days). It is said for at most two missed cycles, then the note stops. `AttentionModel.missingBills` turns these into calm notes for utilities and phone plans that had a bill before, never for examples; a locked section's note names nothing. Notes never notify, never badge and never reach widgets.

## 5. Capture pipeline

`CaptureEngine` is the single way into the binder from a photo, scanned pages, a PDF, or pasted text. Every input goes through the same tiers, and the result is a draft: nothing is saved to the person's data until they confirm it.

### 5.1 Tiers

1. **Deterministic** — the machine-readable zone with its check digits, barcodes and QR codes, known invoice formats, checksums.
2. **Heuristic** — Romanian dates, amounts, labels and identifiers in the recognised text.
3. **On-device model** — Apple's on-device language model fills what patterns can't, when the device has it. Private and offline, on by default. Its answers are kept only if they are grounded in the recognised text.
4. **The person's AI provider (optional)** — only with their own key: when they tap "Citește mai bine cu …" on this document, or by itself after a weak phone reading when they turned on "Citește automat când nu sunt sigur". A full second opinion: it names the kind and reads every field. Only the first page, as prepared for reading, is sent. See 5.7 and 5.8.

**Preparing a photo.** Before a photo is read, `DocumentImageNormalizer` (the one preparation path) finds the document: a rectangle shaped like an ID-1 card (about 1.586 : 1) or a passport data page (about 1.42 : 1), or, when there is none or the rectangle is only a box printed on a larger page, Vision's document segmentation. The document is flattened, a card that comes out portrait is turned the way more text reads, and a small card is enlarged (up to three times) so small print is legible. The prepared image is what is read and what a cloud provider sees; the photo as taken is what is kept. Pages from the document scanner are already flat and are read as they are.

**The machine-readable zone's own pass.** The zone's band (the lines dense with `<` near the bottom) is cropped across the page, enlarged and read again without language correction; the reading whose check digits pass best is kept, and lines inside the band are never read as a printed label's value. Recognition's OCR-B confusions (O/0/Q, I/1/L, B/8, S/5, Z/2, G/6, and a `K` or `«` among fillers) are tried inside one field at a time, fewest swaps first and only where a character stands out from its neighbours, and a repair is kept only when exactly one combination passes the field's check digit (and the composite agrees). Two that pass are a guess: the field stays as read, unverified.

**One retry.** A reading with little text (fewer than about 20 letters), or an identity document without any of its main fields, is read once more with the page's best other view (a quarter turn, or the photo uncorrected, whichever a quick read finds more text in); the better reading is kept. If it is still poor, the review says "Poza e greu de citit. O poză nouă, dreaptă și fără reflexii, ajută."

Long PDFs are read up to their first 25 pages. Pages are read one pass at a time, and a failed pass doesn't lose the others. The same document captured twice is recognised by its fingerprint.

### 5.2 Per-kind field rules

`CaptureFieldRules` decides which fields belong on which kind of document and is applied after every tier, so no tier can put a field where it doesn't belong: only identity documents may carry personal fields (personal number, birth date, sex, nationality), and an ID card carries no line items or totals. For identity documents, the pattern tiers finding the essentials with good confidence makes the model unnecessary.

### 5.3 The label-layout reader

`LabelledLayout` reads documents printed as labels with values beside or under them (identity cards, licences, certificates). The labels are data, a table per document kind, so a new layout needs a table, not new reading code. Labels match as whole words in folded text (longer wordings win, so *prenume* is never read as *nume*).

Every recognised line keeps its position on the page (`TextLayout`). Fragments close together on one row join into one line ("03" "07" "1983" → "03 07 1983"; the gap threshold is relative to the text height). A label's value is the rest of its line, the nearest text to its right on the same row, or the nearest line below that overlaps the label's column, before the next label. A label's printed translation under it ("Nume" / "Surname") is skipped, and value lines stacked tightly in a column join ("CORINA" + "IOANA"). Without positions (pasted text, PDFs with a text layer) the next non-label line is read. The text shown under "Textul citit din document" follows the same layout: each label, then its value.

### 5.3a Bills and contracts

A bill (`utilityInvoice`) and a contract (`contract`, *Contract sau act adițional*) carry what ties them to their ongoing contract, read by `ContractReader` with one label table through `LabelledLayout`: the contract number, the client code, the POD and CLC (with the utility reader's patterns), the subscriber's mobile number (07…, written "0700 000 000"), and the service (a CLC means gas, a POD electricity, a mobile number a phone plan; otherwise the words that win clearly). A contract also gives its start, its minimum period (*24 de luni*, *2 ani*; one month to ten years), its end and its monthly price. The classifier knows a contract by its own words (*contract de furnizare*, *contract de abonament*, *act adițional*, *perioada minimă*, *perioadă contractuală*, *durata contractului*); what makes a page a bill instead is an amount to pay now (*total de plată*). A provider's bill reader never claims a page the classifier reads as a contract. When the end isn't printed, it is the start plus the length. A contract's start falls within the last 40 years or the next one, and its minimum period ends after it starts and within eleven years; the AI provider is asked for the same fields, the service as one of the stable keys.

### 5.4 Review and filing

The review screen shows what was read, where it could go, and the reminder it suggests. On confirm, `CaptureFiler` files everything through the engine as one unit of work (`UnitOfWork`): the section (`AssetActions`), the deadline (`ObligationActions`: complete the old cycle and move to the new date, or create it from the blueprint), who issued it (`ProviderActions`) and the document (`AttachmentActions`), all linked. Everything is kept, or nothing is: a failed save leaves the binder as it was, the review stays open with everything the person filled in, the document's pages stay ready for a retry, and the message says plainly what happened and what to do ("Telefonul nu mai are spațiu liber…"). Logging a visit with its invoice, completing a deadline with the new document, and editing a section with its photo work the same way.

**Bills and contracts** go to their subscription (4.10): the review suggests the one the codes find, a home (where a new one is made, or its matching one found), *Abonament nou* on its own for a phone plan, or nothing when it can't be told. Choosing a home in *Unde îl pun* means its subscription there; choosing a new home makes the home and the subscription in one save. A bill fills what the subscription doesn't have yet, sets *Ultima factură* when it is the newest, is logged in its history with its amount and number, and moves *Factura de plătit* to its own due date with its amount, unless the person turned off *Amintește-mi să o plătesc*, the subscription pays by direct debit (the review says so instead) or the date has passed. A bill kept without a place sets no reminder (the loose *Factură <furnizor>* deadline of earlier versions is disabled; the ones already made stay). A contract also brings its terms (the number, the start, the minimum period and its end, the price) and *Se termină perioada minimă*; the review says *Perioada minimă se termină pe … De atunci poți, de regulă, renunța fără penalități.* A period that already ended sets no deadline. When the person corrects the start or the length, the end follows them unless they set it themselves.

### 5.5 Identity documents

**Templates (`IdentityTemplates`).** One definition per known Romanian identity document: the electronic identity card (front, and back with a TD1 machine-readable zone), the older card (TD2, "SERIA XX NR …", validity as a range), the passport (TD3) and the EU driving licence (numbered fields, two sharing a row: 4a with 4c, 4b with 4d; 4d holds the personal number, which decides birth date and sex only with a valid control digit; categories printed in boxes are joined as "A, B, C"). Each template says how the document is recognised, each field's labels and format, an optional usual region on the card, and age rules. `IdentityDocumentReader` applies any template, so a new document means a new template, not new code. The health insurance card isn't included yet: its printed fields couldn't be confirmed against an official specimen.

**Confidence from checks (`CaptureConsistency`).** After all tiers, dates are checked against each other: a birth date is never also an issue, start or expiry date; an issue date is never in the future and, for identity cards and licences, never before the holder's 14th birthday; an expiry comes after the issue and birth dates. When two values break a rule, the less trusted goes, in `ReadingArbiter`'s order (5.8). The review marks "Verifică" only on values that failed a format or a check, that only the on-device model read, that an AI provider read alone without a check, or that two readers read differently (5.8).

**Plausible dates.** Each kind of document says, as data, when its dates can fall (`.within` rules in `CaptureConsistency`, identity windows in `IdentityTemplates.identityDates`): a birth date within the last 120 years and not in the future; an issue date not in the future and not before the birth date; on identity documents, an expiry between 2000 and 15 years from today (outside it the value is dropped), and an issue date within the last 15 years (older is possible only on a permanent card, so it is kept with "Verifică"). The windows are checked on every tier's answers before they are merged, so an impossible date (a passport "expiring in 1906") never pushes out a possible one, and again after all tiers. They also decide the century of two-digit years, in the machine-readable zone and on printed cards ("12.03.18-31.12.28", "12 IUN/JUN 31"): the candidate inside the window, the later one when both fit.

**Showing, naming and filing.** Everything read (personal number, series and number, birth date, sex, nationality, issuer, dates) is shown in the review, kept on the document and listed on its page with "Copiază", because people need it to fill in forms. The section's Face ID lock is the protection; these values never appear in search, widgets, notifications or exported file names. The document is named "Carte de identitate – Manole Corina Ioana" (surname first, as printed) and filed under the household member whose name matches (ignoring case, diacritics and name order), or under a new member named after the holder. When only the front of a card was read, the review offers to add the back; both are then read together, keeping what the person already corrected; where the checked zone on the back says otherwise, that field shows "Pe spatele actului scrie: …" with "Folosește-l". A new household member and their document are created in one save. Tapping the document's picture opens it full screen, with zoom. A capture started from a household member's documents is filed as one of their documents whatever its kind; one that isn't an identity document is named "<what it is> – <the person>".

### 5.6 Share extension and inbox

The share extension (`DosarCuSinaShare`) appears in the share sheet of Mail, WhatsApp, Photos and Files for photos, PDFs and text, including documents handed over as a link to a file. It copies what it receives into the share inbox in the App Group and confirms calmly. It never opens the database or reads the document. Photos shared together are the pages of one document; each PDF is its own. It accepts a limited number and size of files per share.

The app reads the inbox when it comes to the front and the moment the extension signals. Each item goes through the same capture and review as a photo taken in the app, and leaves the inbox once filed or dismissed.

The practice share (in onboarding and from the Adaugă card) sends a sample invoice with placeholder data through the real share sheet and the real extension, and shows how to move the app to the front of the share sheet.

### 5.7 Reading with the person's AI provider

**Providers (`AIProvider`, `AIProviderAdapters`).** Google Gemini (`gemini-3.8-flash`), OpenAI (`gpt-6-astra`), Anthropic Claude (`claude-opus-5-5`), and "Compatibil OpenAI": any service that speaks OpenAI's chat format at an address the person gives (OpenRouter, Mistral, LM Studio or Ollama on the home network). Each provider is one small adapter: its request, where the JSON is in its answer, a key test that reads nothing, and what its errors mean. The default models are defined once, in `AIProvider.defaultModel`.

**One configuration place (`AIProviderSettings`).** The chosen provider (Gemini until another is chosen), a model per provider (its default unless the person picks another), the compatible service's address (`https`, or `http` only to a server on the home network) and a key per provider in the Keychain. Settings → Inteligență artificială picks the provider, keeps its key and the compatible service's address, and tests them ("Testează"). Its "Model" row opens a picker: the recommended model, every model the key can use for reading (asked from the provider, newest first; speech, embedding and image-generation models left out by one shared list), or a name typed by hand. The recommended model is saved as "no choice", so it follows future updates.

**One contract.** The cloud tier (`CloudCaptureExtractor`) sends the first page and a strict JSON Schema (`CloudSchema`): first `documentKind`, one of the kinds the app knows, then every field any kind carries, built from the same definitions the app reads with (identity documents' template fields with their printed labels and formats, their machine-readable zone's lines, every other kind's `expectedKeys` in `CaptureFieldRules`). The phone's guess only orders the fields; it isn't told to the provider, so a wrong guess can't steer it.

**Whoever answered, the same checks (`CloudAnswerMapper`).** Every value the provider read is kept; what it is worth decides only whether it is marked. A value passing its own check (a CNP's control digit, a VIN's check digit, the machine-readable zone's check digits) is certain; one the phone's recognised text agrees with, or a date inside its plausibility window, needs no look; anything else is marked "Verifică". Being missing from the phone's text is never a reason to drop or demote it: the phone may have misread. Its dates go through the same windows, and a date outside them is dropped. How it ranks against the phone's reading is 5.8.

**Before sending, and when it fails.** The review names the provider before the tap: "Poza actului se trimite la <provider>, cu cheia ta." for identity documents, "Prima pagină se trimite la <provider>, cu cheia ta." otherwise, with a link to the provider's own data-use terms (nothing is claimed on their behalf). Settings shows the same link. A failed reading says why, in plain words: no internet, the key wasn't accepted, the key's requests are used up, the model isn't available, the service is busy or declined. Without a key nothing changes: reading stays on the phone.

**The button and the automatic reading.** "Citește mai bine cu <provider>" is offered whenever a provider is set up, whatever the phone read, until the provider has read the document. While it reads, the review stays on screen with "Citesc cu <provider>…" in the button's place; the new reading is merged into the review, keeping what the person changed meanwhile. Settings → Inteligență artificială has "Citește automat când nu sunt sigur" (off by default, shown once a provider is set up): with it on, the provider reads right after a weak phone reading, through the same path. A reading is weak (`ReadingArbiter.weaknesses`) when the kind's confidence is below 0.6; an identity document lacks one of its essentials (surname, document number, expiry); a value failed its own check (a CNP's or CUI's control digit, the zone's check digits) or a cross-check (dropped or marked by `CaptureConsistency`); little text was recognised; or only a provider's known format named the kind, without the classifier's support.

### 5.8 Deciding between readers

`ReadingArbiter` is the one place that decides, by evidence and not by the order the readers ran in. `FieldMerger` (within the phone's own readers), `CaptureConsistency` (rules between dates) and the AI's second opinion all ask it.

**The order, most trusted first.**
1. The person's own edits in the review: a value they typed or chose, the kind, the place, the title, the name and the reminder to pay. No later reading changes them: not the AI, not the zone on the back, not an automatic reading.
2. Checked values, from any reader: the machine-readable zone with valid check digits; then a value passing its own control digit (a CNP, and the birth date and sex it encodes; a VIN; a CUI) or a payment code in a known barcode format.
3. The AI provider, for values no check can prove.
4. The phone's patterns and labels (a provider's known format first).
5. Apple's on-device model.

Among the phone's own unprovable readings the more confident value wins (a model's clear answer beats a weak first-date guess); on a tie the order above decides. Two readers that agree reinforce each other.

**The kind.** The AI's kind replaces the phone's unless deterministic evidence backs the phone's: a machine-readable zone with valid check digits, a decoded payment barcode on a bill, or a provider's known format the classifier agrees with (`CaptureKindEvidence`). When the AI changes the kind, the phone's text is read again as that kind, so its values are the ones that kind carries, and then ranked against the AI's. Apple's on-device model may change the kind only when the classifier is unsure. "Altul" from the AI is no opinion.

**Disagreements in the review.** When readers disagree, the value kept is marked "Verifică" unless a check settles it, and the value not kept is shown beside it with "Folosește-l" (`CaptureReview.Field.alternatives`): "Pe telefon am citit: …" when the AI's value replaced the phone's, and, beside the person's own value, what a checked code or the AI read ("Pe spatele actului scrie: …", "În codul de jos al actului scrie: …", "Pe act scrie: …", "Gemini a citit: …"). The kind works the same way under the document's title ("Pe telefon părea: Factură de utilități"). Taking an alternative offers the replaced value back, so the person can switch again. Nothing is offered beside a checked value nobody edited. Everything that depends on the kind (routing, the blueprint, the reminder, the place, the title, the name) follows the kind shown through `CaptureReview.kindChanged`, except what the person chose themselves.

## 6. Side effects

`SideEffectsCoordinator` is the only path from saved data to anything outside the database. Views and actions never schedule anything themselves; they save, and the coordinator runs after the save (debounced), when preferences change, when the day changes and when the app becomes active.

- **Notifications** — `ReminderPlanner` (pure) works out every reminder that should be pending; `NotificationReconciler` makes the system match it, touching only its own identifiers. Notification permission is asked only after an in-app explanation or from Settings, never by a save on its own.
- **App badge** — overdue plus due today.
- **Widgets** (`DosarCuSinaWidgets`) — Home Screen (small, medium) and Lock Screen (inline, rectangular), drawn from a snapshot file in the App Group. Sensitive sections show a generic title and no *Gata* (done) button. *Gata* completes through `ObligationActions`: on iOS 27 inside the app; on iOS 26 the widget queues the request, hides the item at once, and the app applies it next time it runs, only if the obligation is still on the same cycle.
- **Spotlight** — the coordinator accepts indexers that rebuild after every pass. No Spotlight indexer is registered yet.
- **Example data** never notifies, never badges and never reaches widgets.

Integrations are optional, one tap, and asked in context: *Adaugă în Calendar* uses the system's event editor (no calendar permission), and contacts come from the system contact picker (no contacts permission). The app works fully without them. Siri and Shortcuts can list what needs attention and complete an obligation, through the same engine.

## 7. Security

- **Two independent locks:** an app lock (off by default) and per-section locks (Acte and Sănătate start locked; any category can be locked). Either can be on alone.
- **One unlock opens both** for the session, so the person is never asked twice in a row. The session closes after a minute in the background, or on demand.
- **A failed or cancelled unlock never ejects the person.** Only the locked part stays closed, calmly, with one button to try again.
- **The device passcode is the fallback** for Face ID, Touch ID or Optic ID.
- With the app lock on, the screen is hidden in the app switcher. Turning a lock off asks for Face ID first.
- Locked sections show nothing of what's inside: box lines, search results, widgets and notifications use generic wording.
- The optional AI keys, one per provider, are kept in the Keychain on this device only (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), are sent only in request headers, and can be tested and removed in Settings.
- **Secret fields** (`FieldType.secret`, the rules in `SecretFields`): the PIN codes of the electronic identity card, *PIN pentru autentificare* (4 digits) and *PIN pentru semnare* (6 digits), named as on the issuing authority's site. A code is sealed (AES-GCM) before it is saved, with a key kept in the Keychain on this device only, and shown masked. *Arată* and *Copiază* ask for Face ID or the passcode every time, even when the section is open, without opening or closing the session (`BiometricVaultManager.authenticateForReveal`). A shown code hides after 30 seconds or when the app leaves the screen; a copied one stays on this phone's clipboard for a minute. The edit sheet never shows a kept code: it offers *Schimbă* and *Scoate*. Secrets never reach search, widgets, notifications, the box status line, logs or `.dosar` archives. A bank card is never offered a PIN field.
- The database and documents use the system's file protection.

## 8. The `.dosar` archive

Backup and transfer use the `.dosar` v3 format, the cross-platform contract: a plain ZIP of JSON files plus the document files, with a manifest of SHA-256 checksums. Export goes through the share sheet; opening a `.dosar` file from Files, Mail or AirDrop goes to the import screen, which asks before anything is replaced. Import either merges (for records in both, the more recently edited wins) or replaces everything. Version 2 archives from the first app are still imported. Secret fields (PIN codes) are never written to an archive, and the backup screen says so; an import ignores any it finds and keeps the ones already on the phone.

The format, its JSON Schema and golden fixtures are in [shared/schemas/dosar-v3.md](shared/schemas/dosar-v3.md), [shared/schemas/dosar-v3.schema.json](shared/schemas/dosar-v3.schema.json) and [shared/fixtures](shared/fixtures). Every implementation must import both fixtures.

## 9. Localisation

- The app speaks Romanian. Romanian (`ro`) is the development language and the String Catalog's source language; dates and money are written the Romanian way (*1.250,50 lei*, *14 noiembrie 2026*) whatever the device region.
- Every user-facing string goes through the String Catalog. Counts use plural variations (Romanian *one / few / other*: *1 zi*, *2 zile*, *20 de zile*), never hand-written `count == 1` checks.
- Data from the person or from templates is shown verbatim, never translated.
- How the app writes is in [docs/COPY_GUIDE.md](docs/COPY_GUIDE.md).

## 10. Platform

iOS 26 and later, Swift 6, SwiftUI and SwiftData. Targets: the app, the widget extension, the share extension and the test target. The app, widgets and share extension share small handoff files through one App Group; the database stays in the app's own container.

## 11. Not built yet

- **iCloud sync** to the person's own private iCloud. The schema is ready for it; the store is local only today.
- **Android port.** Paused. The code under `android/` is from the first version and does not follow this spec. The `.dosar` format is the contract it will follow.
- **Partners.** Optional, privacy-first offers from vetted companies (an insurance broker, for example) on fair commission. See the decision log.
- **Household sharing** through iCloud.
- **Password-protected export.**
- **Spotlight indexing** (the hook exists) and **readiness scenarios on screen** (the engine exists).
- **Reminders app** integration. Not built; Calendar is.
