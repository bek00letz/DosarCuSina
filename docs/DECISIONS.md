# Decisions

A dated log of product and architecture decisions, newest first. Each says what was decided and why. A newer decision can replace an older one: add a new entry that says so, and leave the old one in place.

To propose a change to a decision, open an issue with the **Proposal** template or a draft pull request. The owner decides.

---

## 2026-11-03

### The travel cut-off follows the document, and the usual reminders can come back
- **Decided (owner):** the travel cut-off always follows the document type, even on a deadline whose reminders the person set. The cut-off is a fact about the document, not a preference. The person's leads, consequence, grace and follow-up stay; only the travel margin (and so the day the leads count from) changes. It is the one rule, `DeadlineReminders`, so Editează, capture's filing and the repair list's travel cut-off step all do it; the repair step now also offers a marked deadline whose margin isn't its document's, and gives it only the margin. This answers the first "Open for the owner" in "A deadline's reminders follow its document" and replaces "a marked deadline keeps its reminders whatever the section becomes" there, for the margin only.
- **Decided (owner):** no separate reset button. On a deadline's page, *Când te anunț* offers "Revino la cele obișnuite" when the person set its reminders and they differ from what its document gives, with the usual ones in a sentence under it. The tap puts them back, clears `remindersCustomized` and says what they are in an undo toast. One action, `ObligationActions.restoreUsualReminders`, undoable through the step's receipt. This answers the second "Open for the owner".
- **Decided:** the mark means the reminders differ from the usual ones. Ticking exactly the usual ones back by hand clears it (`DeadlineReminders.isCustomized`), so the deadline follows its document again and the option isn't offered for reminders that are already the usual ones. A deadline not made from a category's blueprint has no usual ones: it stays marked when changed, and offers nothing.
- **Why:** a passport whose leads the person changed and that turned out to be an identity card kept counting from a cut-off it doesn't have; and once marked, a deadline had no way back to following its document.

### A deadline's reminders follow its document
- **Decided:** a deadline made from a blueprint reminds as the blueprint says for its section's values. When a value that profile depends on changes (a document's type, a pet's species: whatever the blueprint's `reminderVariants` reads), the deadline takes the new profile whole: leads, consequence, grace, follow-up and travel margin. One rule, `DeadlineReminders`, run by `AssetActions.update`, so Editează and capture's filing do the same thing. Changing an identity card to a passport gives it the passport's reminders and cut-off at once, and changing it back takes them away. A change the profile doesn't read (the expiry, the name) leaves the reminders alone.
- **Decided:** reminders the person set themselves stay. Changing a deadline's leads or its follow-up marks it (`Obligation.remindersCustomized`); a marked deadline keeps its reminders whatever the section becomes. It is stored, so the database is at version 5 (version 4 frozen, a lightweight stage and a test that opens a version 4 store), and it travels in backups.
- **Decided:** deadlines saved before version 5 are not marked: nobody knows which ones the person changed. Their reminders follow the next change of type or species, which is what that change asks for.
- **Decided:** the repair list's travel cut-off step is a check of the same rule. It offers a deadline that isn't marked and whose travel margin isn't its document's, either way (a passport saved before margins, or a document that stopped being a passport before reminders followed the type), and applying gives it what Editează would. This replaces "The person's grace and follow-up stay as they set them" in "A passport is good for travel until six months before it expires": the repair now gives the type's grace and follow-up too, because one path does both. The entry asks first and says when it will remind; it doesn't name the grace or the follow-up, which only change for a passport whose follow-up the person had turned off.
- **Open for the owner:** a marked deadline keeps its travel margin when its type changes, so a passport whose leads the person changed and that turns out to be an identity card still counts from a cut-off. The margin is never chosen by hand, so it could follow the type even for a marked deadline. Recommended: yes, keep the person's leads, grace and follow-up and let only the margin follow.
- **Open for the owner:** once marked, a deadline can't go back to following its document. A "Revino la cele obișnuite" on its reminder settings would clear the mark.
- **Why:** changing a document's type in Editează left its deadline with the old type's reminders and no travel cut-off; only the repair list noticed afterwards.

### Units are known by stable keys
- **Decided:** a reading, a number field, a counted deadline and capture say their unit with one type, `MeasurementUnit`: a stable key (`km`, `h`, `kwh`, `m3`, `gcal`, `kg`, `mgdl`, `mmhg`, `dpt`, `cm3`, `hp`, `m2`, `months`, `shots`) and a label shown to people ("km", "kWh", "m³", "CP", "luni", "cafele"). Code compares keys, never labels: readings are grouped by key, a counted deadline finds its counter by key, a lower kilometre reading asks by key.
- **Decided:** reading accepts every form the app has written: the key, the label (also in the app's language), capture's "mc" and the number reader's "m3", in any case, with or without superscripts. Older data and backups open as they are. A unit the person typed another way ("ore motor") is theirs and stays as written; it is not guessed into the catalog.
- **Decided:** a repair step that runs by itself rewrites stored readings, counted deadlines and the person's own categories to keys. It touches only the unit, in place, so nothing a newer version wrote is lost. Built-in categories get keys from the catalog (version 12). Backups write keys and read both forms (`dosar-v3.md`, Units).
- **Decided:** the type lives in the app (`Models/Values/MeasurementUnit.swift`), not in `ios/Shared` as the plan said: nothing outside the app shows a unit, and moving it there is one file when a widget needs one.
- **Why:** units were display text used as identity: capture's "mc" and a template's "m³" made two series of the same meter, and a translated label ("cafele") would have split a counter from its deadlines.

### One form for a new deadline, one flow for a new section
- **Decided:** a section's *Alt termen* and *Adaugă › Scriu eu* open the same `DeadlineForm`. A deadline of the person's own asks what it is, how important it is and whether it repeats; its kind comes from the importance (legal, payment, health, routine) and its reminders from that kind's default profile (`DeadlineChoice`). The fixed "a week before and on the day, financial" profile the section's sheet gave every deadline is gone. *Scriu eu*'s *Secțiune nouă* opens the binder's *Adaugă o secțiune* flow (category, essentials, deadlines) instead of a name-only form.
- **Open for the owner:** the importance starts on *Doar să nu uit*, as *Scriu eu* already did. Starting with nothing chosen would make the person pick every time.
- **Why:** the same "Plata asigurării" reminded differently depending on where it was typed, and read "Expiră în…" because every deadline from a section was a renewal.

### Rows give way by measuring, not by text size
- **Decided:** one layout, `DSAdaptiveStack`, puts a row's pieces side by side when they fit at their natural width and stacks them otherwise, at any text size and screen width. It replaces the `ViewThatFits` copies and the "accessibility size, so stack" checks in rows, value rows and button rows. Value buttons stack under each other when even they don't fit side by side. Status badges and chips wrap onto a second line instead of being cut off. The binder's grid still drops to one column at the accessibility sizes; that is a grid, not a row.
- **Decided:** tap sizes are tokens (`DS.Control`): 44 pt for anything tapped, and a test measures the DS buttons at every text size. A small action beside a row is `DSCompactButton`.
- **Why:** a size check stacked short rows that fitted and left long ones to clip at the sizes just below it.

### One way to fold text and find a keyword
- **Decided:** `RomanianText.fold` is the one fold (case, diacritics with both ş and ș, wide forms, no-break spaces, the typographic minus) for search, choices, component matching and capture. `CaptureText.containsWord` is the one keyword match for every capture reader and the classifier: folded, phrase-aware, never the middle of a word. Words of four letters or fewer match whole; longer ones may take a Romanian ending. A word whose longer forms mean something else is listed to match only whole (today "index", not "indexare").
- **Why:** three folds gave three answers, and substring matching read "neachitat" as "achitat", skipped "Control frâne" as a "cont" line and counted "indexare" as a meter index.

### Search keeps its own index, away from the main thread
- **Decided:** `SearchIndexer` holds the index, one per database, on a context of its own. It reads everything once; after each save it reads again only the records that save changed and those that show them. A category change, or a save that can't say what it changed, reads everything.
- **Why:** the screen rebuilt the whole index on the main thread after every save, so typing stuttered in a large binder.

### A restored backup is written away from the main thread
- **Decided:** the importer runs on a context made for it in a background task. `UnitOfWork.performPrivate` is the unit for such a context: one save at the end, everything rolled back on failure. It needs no bookkeeping because no one else has the context. Actions that save through `UnitOfWork.save` stay on the main actor's units. The main-thread import and the background one share one write path.
- **Why:** writing a large backup paused the screen.

### The share inbox has a version, and nothing in it is skipped silently
- **Decided:** each inbox manifest carries a version; one without reads as the first, a newer one is set aside. An item that can't be opened is moved aside once and shown as *Nu am putut deschide* with *Șterge*, never skipped on every look. The practice invoice is known by the fingerprint the app leaves before showing the share sheet (valid one hour), not by its file name; the name check is kept, unused, as the way back.
- **Why:** an item the app couldn't read stayed invisible in the inbox forever, and a practice file renamed on the way became a real document.

### Motion and the delayed spinner are shared with the extensions
- **Decided:** `DS.Motion`, `dsAnimation` and `DSDelayedProgress` live in `ios/Shared`, so the share sheet uses the app's springs and waits the same time before a spinner. A steady sweep (the skeleton's shimmer) and the short confirmation dwell are tokens too.
- **Why:** the share sheet had its own spring, ease-out curve, spinner delay and auto-close.

### First-version code nothing uses is deleted, not moved
- **Decided:** the day-count cadence heuristic, the `.annual` interval, the calculator's own day difference, the cover, bonus-malus and component catalogs, and the PDF parse and thumbnail helpers are deleted. Nothing referenced them, so nothing is being replaced; the history keeps them. `ios/Legacy/` is unchanged.
- **Open for the owner:** the agreed fix list said "move to Legacy, ask before deleting". If you want them kept there, they come back from the commit in one step.
- **Why:** a second copy nobody uses is the one a later change picks by mistake.

### A passport is good for travel until six months before it expires
- **Decided (owner):** only passports have a travel cut-off: six months before the printed expiry. Many countries refuse entry with less left, and 6 months covers every country's rule, including those that ask for 3. It is fixed: no per-country option, no setting. ID cards are valid for travel until they expire; driving licences, certificates and every other document keep their plain expiry, with no "bun de călătorit" line, no earlier reminders and no earlier urgency.
- **Decided:** it is data on the document type, not a passport case in code: `DocumentType.travelMargins` gives the passport type (and so every variant of it) 180 days, as whole calendar months; no other type has one and there is no default. The catalog's passport profile takes it from there (`ReminderProfile.travelMarginDays`), the deadline keeps it (database version 4, `Obligation.travelMarginDays`) and the one urgency rule carries it (`UrgencyRule.travelMarginDays`, in the widget snapshot too).
- **Decided:** what the cut-off changes, all from that one number:
  - the page and the document's hero show both dates, "Expiră pe …" and "Bun de călătorit până pe …" ("A fost bun de călătorit până pe …" once it has passed);
  - reminders count back from the cut-off: 3 months before it and on the day, so 9 and 6 months before the printed expiry. They say how long it is still good for travel; the follow-up after it lapses stays the day after it expires;
  - from the cut-off on, the passport is in *Acum* and amber, through `UrgencyRule`; *Curând* is what the rule calls upcoming, so the month before the cut-off lists it there;
  - the trip check outside the EU asks for the passport to be good for travel until the trip ends (the same cut-off).
- **Decided:** a passport deadline saved before the cut-off existed gets it from the repair list, with the owner's OK ("„Pașaport” e bun de călătorit doar până pe …, cu 6 luni înainte să expire. Schimb când te anunț?"). The person's grace and follow-up stay as they set them.
- **Why:** a passport that reminded 6 months before its expiry reminded on the very day it stopped being any good for most trips abroad, and stayed calm until its last month.

### Counts of one are words
- **Decided (owner):** a count of one is written as a word, two and up as digits: "o zi", "o săptămână", "o lună", "un an"; "2 luni", "20 de zile". It lives in the String Catalogs' plural "one" variants (`Shared.xcstrings` and the app's), so "Cu o lună înainte", "Peste o zi", "întârziat cu o zi", "un document" read naturally. "În" before a duration is written in one place, `DurationWording.inside`, which joins it as Romanian does: "într-o lună", "într-un an".
- **Why:** "1 lună" reads like a form; people say "o lună". The digit form stays where it helps to compare (two and up).

### A home keeps its two policies apart
- **Decided (owner):** a home keeps its mandatory policy (PAD) and its optional one apart, like a car's RCA and CASCO: separate insurer, policy number and claims phone for each. PAD keeps the fields a home had; the optional policy has its own (`HomeFields.optional…`). Each deadline names its own (`BlueprintFacts`), so capture files a policy into its cover's set and each deadline page and claim checklist shows its own policy. Built-in catalog version 11.
- **Decided:** the repair list moves what an earlier version kept together, with the owner's OK: when a policy filed on the home that carries the number, or the one deadline running, says it is the optional policy, it offers to move it there; when the cover can't be told, it asks the owner to check ("Verifică asigurarea de la …"), and "Lasă așa" keeps it as PAD's.
- **Why:** with one set, a PAD and an optional policy from different insurers overwrote each other, and a claim call could go to the wrong insurer.

### The owner's answers
These were open in the entries below; they are settled, and pinned by `SettledDecisionsTests`.
- **The consequence cap on *Acum* stays.** A deadline that reminds months ahead (an ID card, three) is amber and in *Acum* only within its consequence's window (a month for legal). The one exception is the passport's travel cut-off above, which is the document's real end for travel. *Why:* "Urmează stays short"; what isn't urgent yet is still reminded.
- **Due today is amber everywhere; red only when late past grace.** *Why:* the day itself still leaves time to act; red means it is already late.
- **Month reminders fire on the same day of the month** ("Cu 6 luni înainte" on the 12th for a due day on the 12th), even when that is a few days earlier or later than a count of days. *Why:* the reminder then says exactly what its setting says.
- **A due day is the last valid day, as papers print it.** `DueDayValidity.dueDayIsLastValidDay` stays true: "valabilă până la 12.08.2027" covers 12 August. *Why:* that is how Romanian policies and identity cards are written.
- **An expired RCA or ITP read from a photo gets no overdue deadline**; it is kept as history (`ObligationBlueprint.isWorthScheduling`). Only a document that must be renewed by law (an identity card that expired) still gets one. *Why:* last year's policy or inspection is a record of what was, not something to do; the current one is what matters.
- **Counts of one in words, and separate home policies**: see their entries above.

### One undo for every action; deleting from Istoric is separate
- **Decided:** every action the person can take back returns an undo receipt, made by its own unit of work: the records it created, and every stored property of the records it changed or deleted, read from the store just before it saves. "Anulează" puts all of it back in one unit of work, as if the step never happened (change times included), and refuses when any of those records changed again since, so it never overwrites something newer. The three earlier undo paths (the visit's, the completion's, the move's) are gone.
- **Decided (owner):** the three earlier undo paths stay deleted, not kept disabled; git history is the way back. An owner-approved exception to "keep a way back".
- **Decided:** a receipt covers the whole step the person took: an action inside a filing is undone with the filing. Undoing a filing that kept a new photo removes that photo too; the visit's "Anulează vizita" already did.
- **Decided:** receipts live in memory, only while the toast offers them. No database change.
- **Decided:** deleting a record from Istoric is not undo. Its line items and the reading it recorded go; the documents filed with it stay in the binder; a completion moves its deadline back only when it's the latest one, judged by the cycle it closed (a completion dated in the past still counts), and an older one leaves the deadline alone. The confirmation says which, with the date.
- **Decided (owner):** deleting a visit or a completion from Istoric takes the reading it recorded with it, and the value on the section follows the readings left.
- **Why:** each undo path forgot something different: undoing "Gata" left a mistyped reading, undoing a visit found its reading by matching numbers, a move's undo knew nothing about a document's other fields, and a completion dated in the past couldn't be undone at all ("Poți anula doar ultima bifare"). Deleting an old completion went through the same undo, so it was refused, and the dialog promised a date change that didn't happen.
- **Open (owner, until sync is designed):** undo also restores the records' change times; when sync comes, an undone step may need a fresh change time so other devices take it.

### Who the app is for
- **Decided:** this replaces "the reference user is aged 50–60 and not tech-savvy" (below, kept as it was). The app is for everyone who keeps papers, deadlines and the people who help with them. It must be just as usable by someone in their 50s or 60s who isn't at ease with phones: that person is the test case for every screen, not the whole audience.
- **Why:** reading the old line as "the app is for older people" leads to designs that talk down or leave out what everyone else needs. Designing for everyone, then checking each screen against the person who finds phones hardest, keeps both.

### What a kind of document means, written once
- **Decided:** every kind of captured document has one entry in `CaptureKindProfile`: its category, its deadline (a real blueprint of the catalog; for a policy, the one its cover names), the field that dates it, how it is kept (`DocumentKind`, `DocumentType`), the issuer's trade, the fields it carries (the AI provider is asked for exactly these), whether it opens the visit form, and its title (a personal document takes its type's name). Routing, the field rules, the review and the filer read it; capture has no names of its own for categories, deadlines or trades any more.
- **Decided:** how early a deadline reminds comes only from its blueprint (or the kind's default profile). Capture's own lead times are gone, so a passport reminds as the catalog says, wherever it is added (since "A passport is good for travel until six months before it expires": 3 months before its travel cut-off, and on it).
- **Decided:** saving a review follows one plan (`CaptureFilingPlan`), worked out once: where the values land, the deadline made or moved, how early it reminds and who issued it. The review's "Când te anunț" line reads the plan and the filer carries it out, so the line names a reminder exactly when saving makes one, and otherwise says why not (no place chosen, paid by direct debit, the day passed, the category keeps no such deadline, a later one already there).
- **Decided:** a deadline whose day has passed is still made only for something that must be renewed by law (an identity card that expired); a warranty, a minimum period, a bill or a policy that ended is only history (`ObligationBlueprint.isWorthScheduling`). *Answered:* no, it doesn't (see "The owner's answers").
- **Decided:** the cover of a policy is a choice with stable keys (`coverage.rca`, `.casco`, `.pad`, `.home`), read once with whole words, offered as a choice in the review and asked of the AI provider. A policy of the kind "Poliță de asigurare" is CASCO, PAD or a home's optional one; RCA is a kind of its own.
- **Decided:** a home's optional (facultative) insurance is a deadline of its own, `home.insurance`, renewed yearly. Before, such a policy was kept with no deadline while the review promised a reminder. *Answered:* yes, a home keeps them apart (see "A home keeps its two policies apart").
- **Decided:** an insurer that issued a policy becomes a firm in Agendă (`ProviderTrade.insurer`), like a mechanic or a vet. Utilities and shops still don't.
- **Decided:** a field that drives a deadline (a contract's end, a warranty's end) makes that deadline when it gets a value and the section has none from it, by the same rule.
- **Why:** the same facts about a kind were written in six places that disagreed: the router named deadlines and trades that matched nothing in the catalog, a non-PAD home policy was promised a reminder that saving never made, and the preview's lead times weren't the ones the deadline got.

### Facts by role
- **Decided:** a blueprint names the fields that hold its facts (`BlueprintFacts`: insurer, policy number, claims phone). The deadline page, the claim checklist and capture's filing read them through it. A CASCO deadline shows CASCO's policy number and claims phone, an ITP shows none.
- **Decided:** field and deadline keys that code reads come from constants (`VehicleFields`, `HomeFields`, `DocumentFields`, `BuiltInBlueprints` and the rest), never typed text.
- **Why:** the deadline page matched any field whose name ended in "policyNumber", so a CASCO page could show the RCA's number.

### What a category does is data
- **Decided:** a category says what it does (`CategoryBehavior`): its box on the grid (one per section, one for the category, or none), what its page lists (plainly, by person, by warranty, by monthly cost), its part (a person, personal documents, a subscription, a home) and the pocket of a parent it shows in. It is stored on the category and travels in the archive. The grid, the category page, the pockets, the hero, settings and capture ask it; none of them names a built-in.
- **Why:** 98 places tested a built-in's key, so a category of the person's own could never behave like Acte or Garanții. The add-section menu's wording, the visit wording and one refresh query still name built-ins (listed in the architecture exceptions).

### What a due day means
- **Decided for now:** the due day is the last valid day, the way policies and identity cards print it ("valabilă până la 12.08.2027" covers 12 August). It is decided in one place, `DueDayValidity.dueDayIsLastValidDay`, which every validity check uses ("Ce-ți trebuie", the readiness checks).
- **Answered:** the last valid day stays (see "The owner's answers"). Flipping the one constant would change every check.
- **Why:** one check treated a deadline due on the day as still valid and another as expired.

### Firms keep their CUI; database version 3
- **Decided:** a firm keeps its tax ID (`Provider.taxID`, digits only, without RO). `findOrCreate` finds a firm by its CUI first, then by its name when that firm has no other CUI. Two firms with the same CUI are the same firm; the repair list offers to merge them.
- **Decided:** the database is at version 3: the CUI, what a category does (`CategoryTemplate.behaviorData`) and the last day a filed paper is valid as read when it was filed (`Attachment.validUntil`), all optional. Version 2 is frozen in `Models/Schema/Versions/`, with a lightweight stage and a test that opens a version 2 store. A filed policy shows the end it was read with; last year's policy no longer shows next year's date.
- **Decided:** the repair list offers, with the owner's OK: a CASCO policy's facts kept in a car's RCA fields move to CASCO's; a home policy kept without its deadline gets "Adaugă termenul" on the day the policy says it ends.

### One urgency, one way to say how long
- **Decided:** how urgent a deadline is comes from one rule, `UrgencyRule`, read from its reminder profile: it needs the person from the day its first reminder goes out, never earlier than its consequence's window (legal a month, financial 21 days, health 7, comfort 3), and lateness within its grace days is calm. Urmează's *Acum*, the binder's boxes, a section's badges and hero, expiry fields, the deadline page, the widget, the app badge, Siri and reminders take that result and only draw it: red when late past grace, amber when it needs the person (due today included), calm otherwise. A date on a page (an expiry, a warranty's end) is as urgent as the deadline it drives; a date with no deadline only on the day and after. The rule lives in `ios/Shared`, so the widget runs the same code, and the widget snapshot carries each deadline's rule.
- **Decided:** a reminder's lead of a whole number of months (30 days each, a year 365) is calendar months: it fires on the same day of the month, so the reminder reads exactly what its settings say ("Cu 6 luni înainte", "În 6 luni: Pașaport"). Other leads are days. Leads and counts are written with plural forms ("Cu 7 zile înainte"), like every other count; a count of one is a word since "Counts of one are words" ("Cu o lună înainte").
- **Decided:** one duration wording, `DurationWording`, with two styles: how far a day is (calendar-accurate, never rounded up) and a reminder's lead. One short "when": *azi*, *mâine*, *în 5 zile*, *întârziat cu 2 zile* within grace, *depășit de 3 zile* past it. Every counted string has plural variations, and `scripts/plural-check.py` checks that after every build.
- **Why:** six urgency rules and three duration wordings disagreed. An RCA 20 days out was "Acum" in Urmează and calm on the car's page; a cat vaccine 2 days late within grace was calm in the app and red on the widget, whose count ignored grace; a passport's 6-month lead read "6 luni" on its page and "5 luni și 3 săptămâni" in its reminder, because a lead counted in days fell a few days short of six calendar months.
- **Answered (owner):** all three stay as built: the consequence cap, today in amber, month leads on the same day of the month (see "The owner's answers"). A passport is now amber from its travel cut-off instead (see its entry).

### One number reader, the Romanian way
- **Decided (owner):** every number the app reads, from a document or from a field, goes through one reader, `RomanianNumber`, told what the number is: money, a count, a meter index (or another measured value) or kilometres. A comma is the decimal mark and a dot groups thousands ("1.250,50"); a number with both marks takes the last one as the decimal mark ("1,250.50" too). Kilometres and counts are whole, so "45,724 km" and "45.724 km" are both 45724. Money or a meter index with one mark and exactly three digits after it follows the Romanian rule ("3,750" lei is 3,75; "Index nou: 12.345" is 12345) and, from a document, is marked "Verifică". Anything that can't be read one way only ("-", ".", "12-5", "5²", "12 km" as money) is refused with a message in the field, never read as 0 or cut short.
- **Decided:** the app writes numbers, money and dates in one locale, Romanian, whatever the phone's region or number format (`Locale.dosarDefault`, injected once at the root). Archives and stored JSON keep the machine form ("1250.5"), read with `RomanianNumber.canonical`.
- **Why:** five readers disagreed: "45,724" was 45724 to one and 45,724 to another, a gas index "12.345" lost its thousands, "86,420 km" became 420, and "3,750" lei became 3.750 lei. A field that writes in one convention and reads in another turned a car's 45.724 km into 457.

### Counter readings: one way in, and a lower reading asks
- **Decided:** every reading (the edit form, the visit form, "Gata", capture, examples) is recorded by one path, `HouseholdMutations.recordReading` (`AssetActions.recordReading` on its own), with where it came from: read by the person, from a document, or estimated. A document's reading is dated by the document.
- **Decided (owner):** a counter reading lower than one recorded before it asks: "Kilometrajul e mai mic decât ultima dată. Corectez citirea veche?" "Corectează citirea veche" (yes) removes the higher earlier readings (and the same number on the visit that logged them) and keeps the new one; "Lasă citirea veche" (no) keeps the new one aside, in the list but not counted. "Anulează" goes back to the form to fix the number; nothing is saved before an answer.
- **Decided:** an estimate is only a greyed placeholder in the visit form ("Cifra gri e doar o estimare"); it is never stored. The hero value (the kilometres on the section) is always worked out from the readings, and undoing "Gata" or a visit takes back the reading it recorded.
- **Decided:** every rate and projection reads one cleaned series, `ReadingSeries`: the longest run of readings that never goes down, in date order, the earlier ones winning a tie. A reading that breaks the order is skipped and flagged, never a reason to stop projecting.
- **Why:** the visit form saved its rounded-up guess as a real reading; the next real one then looked like a drop, and one drop switched off every kilometre-based projection for good. A second rate calculator had no check at all.

### The repair list
- **Decided (owner):** data an earlier version saved wrongly is repaired only with the owner's OK. `DataRepairs` is an ordered registry of idempotent steps with stored ids; detection runs after the built-in categories are installed at launch and after every import. What it finds is one short list in Settings (*Date de verificat*) and one calm prompt when there is something new ("Am găsit date de verificat", "Arată-mi" or "Mai târziu"). Each entry says in plain words what looks wrong and what the repair does ("Kilometrajul la VW Golf pare greșit: 457 km. Corectez la 45.724?"), and is applied or left as it is one by one, or all of one kind; "Lasă așa" is remembered on the phone. Applying runs in one unit of work.
- **Decided:** a step that changes only how a value is stored, never what it says, runs by itself (choice values stored as text become option keys, the old `ChoiceMigration`).
- **Decided:** the steps today, in order: choice keys; deadlines from a first-version copy (a blueprint-less running deadline whose title and kind match one of its category's blueprints gets that blueprint and its rule, such as the legal ITP rule); documents moved with their old links; visits saved without their invoice; firms kept twice; deadlines an old reminder closed twice; counter readings 10 or more times off both neighbours, or equal to the reading before them divided by a power of ten; round-hundred visit readings above the next reading (the old estimate); a hero value that differs from its readings.
- **Why:** repairs were scattered (a migration inside the template store, functions nothing called), and the owner's own car shows 457 km for 45.724.

### Values from a newer version
- **Decided:** one rule for stored values this build can't read: keep them raw, behave as the loudest case, never write back a downgraded value. An unknown field value is kept as stored and written back unchanged; an unknown consequence or kind of deadline reads as legal (the loudest) and stays stored as it was until the person changes it.
- **Why:** an unreadable value was dropped on the next save, and an unknown consequence read as "comfort", so a legal deadline from a newer build would have lost its urgent reminders.

### Only the system's encryption
- **Decided:** the app uses only the encryption Apple's frameworks provide (CryptoKit for backup passwords and sealed codes, the Keychain, file protection, HTTPS). The app's Info.plist says so (`ITSAppUsesNonExemptEncryption` is `NO`), so App Store Connect doesn't ask about export compliance on every upload.
- **Why:** this kind of encryption is exempt from export documentation, and the owner has no plans for any other kind. Adding a custom or non-standard algorithm would change the answer and need the owner's OK first.

### A due day is written as the day it is
- **Decided:** every date the app writes goes through `DosarFormat`, which lives in `ios/Shared` with `CalendarDay` and `Locale.dosarDefault` so the widget writes dates the same way. A `CalendarDay` (a due day, an expiry) is written straight from its year, month and day, never turned into a `Date` first. A `Date` (when a visit happened) is written in the time zone of the calendar the days are counted in. Both use the Gregorian calendar, whatever the phone is set to.
- **Why:** due days were turned into midnight in the calendar the days are counted in, then written in the phone's own time zone. Whenever the two differed (the tests' Bucharest calendar on GitHub's UTC Mac, a calendar kept from before the phone changed time zone) the date read a day early. Tests run in UTC on GitHub, and the runner's time zone is never set to Bucharest to hide it.

## 2026-11-02

### Rules are checked, not remembered
- **Decided:** every pull request and every push to `main` runs three checks: `privacy-check`, `architecture-check` and `build-and-test`. The architecture check turns the one-path rules in AGENTS.md into patterns with a plain message each (save through `UnitOfWork`, errors through `SaveFailure`, springs from `DS.Motion`, side effects through `SideEffectsCoordinator`, no built-in category key in a view, and the rest). Code that broke a rule before it existed is listed in `scripts/architecture-exceptions.txt`; that list only shrinks. A fixed line must be removed, and a new line or a higher count needs the owner's OK, given as the `architecture-exception` label on the pull request.
- **Why:** the review found that the shared helpers already existed and were bypassed: nothing but the privacy check ran on a pull request, and three people's agents contribute. A rule only a reader remembers drifts; a check that names the right helper keeps every contributor on it, and a list that only shrinks turns the old debt into a to-do list instead of a permission.
- **Decided:** the build runs on GitHub's `xcode-27` Mac image (generally available since October 2026, free at its standard size for public repositories), not on the older `macos-26` image, whose newest Xcode is 26.6. The tests run on whatever iPhone simulator the image has with the newest iOS, found by `tests/run_tests.sh`, never a fixed device.
- **Why:** the app builds against the iOS 27 SDK (`IntentExecutionTargets` for widgets), which only Xcode 27 has; a fixed device name breaks the day GitHub updates the image.

### The lock and backups
- **Decided:** the app lock and the app-switcher cover live in a window of their own, above every window of the app. A sheet, a full-screen flow or an alert left open stays under them. Links, notification taps and opened backups wait until the app is unlocked.
- **Why:** this is how the system's own apps hide their content: nothing drawn later can end up on top, whatever presents it. Closing and reopening sheets instead would lose what the person was typing and would need every screen to take part.
- **Decided:** the app-switcher picture is covered whenever the app lock is on, or a section lock is on and the session is open.
- **Why:** a locked section can only be on screen while the session is open, and section locks alone are the default, so the cover follows whichever lock could have something on screen.
- **Decided:** exporting a backup and "Înlocuiește tot" ask for Face ID or the passcode every time, whenever any lock is on.
- **Why:** a backup holds everything the locks protect, and replacing everything can't be undone; turning a lock off already asked.
- **Decided:** a backup can have a password. With one, the whole file is encrypted (PBKDF2-HMAC-SHA256 with 600 000 iterations, AES-256-GCM in 1 MiB chunks) and can't be opened without it. The password is at least 8 characters, typed twice, never kept, and the screen says plainly that a forgotten one can't be recovered. Without one, the backup is an ordinary file, as before.
- **Why:** a backup travels: iCloud Drive, e-mail, another phone. A password keeps CNPs and document photos unreadable wherever the file ends up, while people who keep it somewhere safe aren't forced to remember one. The format is open and documented, so Android can read it.
- **Decided:** the sheet before every backup says what the copy contains, the identity documents included, lock or no lock.
- **Why:** with no lock on, nothing else would stop to say so; it costs no extra tap, because the password sheet opens anyway.
- **Decided:** an archive never changes what the app defines. Built-in categories always take the app's definition (fields, field types, reminders, version); an archive brings only their order, visibility and lock. A lock is never made weaker by an import, sections are filed by the same rule as "Mută la…", no timestamp is later than now, and the app puts back any built-in that differs from its own at launch.
- **Why:** the person's records belong to them and travel; what a PIN field is, or whether Acte is locked, belongs to the app and to the person's own choices on this phone.
- **Decided:** restoring with "Înlocuiește tot" keeps the PIN codes this phone already has for the same records, like a merge.
- **Why:** this decision log promises it; a backup never carries codes, so the phone's own are the only ones that can come through a restore.
- **Decided:** a sealed value is recognised by its own form, wherever it sits and whatever its template says. Every exit (search, archives, widgets, notifications, the box line) leaves it out, and every display shows only the mask.
- **Why:** one rule that doesn't depend on each exit remembering, or on a template being what it should be.

### Search, copying and codes
- **Decided:** text read off a document filed in a locked section is never searchable, whatever its kind, and no thirteen-digit number (the shape of a CNP) is ever indexed, wherever it was typed or read. Recent searches keep neither a CNP-shaped query nor one that found something locked.
- **Why:** a criminal record certificate or a bank letter carries a CNP as much as an identity card does; the kind a document was given can be wrong. A misread CNP is still personal, so the rule is its shape, not its checksum. A thirteen-digit invoice number is the rare price.
- **Decided:** a personal value (read off an identity document, a sensitive field, anything from a locked section) or a code is copied to this phone's clipboard only, and leaves it after a minute.
- **Why:** the same reason PINs already did: the clipboard is shared with the person's other devices and read by other apps.
- **Decided:** a row under Date importante can be a "Cod secret": sealed like a PIN, masked, shown or copied after Face ID, kept out of search and backups. A row whose label names a code ("Parolă Wi-Fi", "Cod alarmă", "Interfon") starts as a secret; "Cod client" or "Cod POD" don't.
- **Why:** people keep these codes in the binder. Reusing the PIN rules gives them a safe place without a new kind of screen.

### A database that can't open yet
- **Decided:** before the phone's first unlock after a restart, the app waits for the unlock and opens the database then, instead of showing recovery. The recovery screen offers only what it does, tells a full phone apart, and never shows the system's error text.
- **Why:** nothing is wrong with the database then; it only can't be read until the phone is unlocked. A screen that offers recovery should offer only what the app can do.

### One filer, one document in one place, and steps that can't swallow each other
- **Decided:** a unit of work never waits. `UnitOfWork.perform` takes synchronous work only; whatever a step needs that takes time (a capture's pages, Face ID) is gathered before it opens. What another screen left unsaved is saved before a unit opens, so a rollback takes back only the unit's own changes. Actions never roll back on their own.
- **Why:** a unit belonged to the whole database context, so while a filing waited, another screen's save joined it and was undone with it when the filing failed. A unit that can't wait can't be joined: nothing else runs on the main actor while it is open. Separate contexts per unit were weighed and not chosen: screens hold the main context's records, and moving each across contexts is a second, error-prone path.
- **Decided:** `CaptureFiler` is the only filer for a captured document, with three intents: the review, "Am rezolvat" with the new document, and a visit with its invoice. All three write the values read, the provider and the document the same way, and one rule (`renew`) decides what a new document's date does to a deadline. A new RCA policy through "Am rezolvat" updates the car's policy details. `ObligationCompletion` and the visit's own filing were removed rather than kept disabled: they were the second and third save paths this replaces, and the parameterised duplicate-photo test pins the new one.
- **Decided:** capture names a document with one typed reference, `CapturedDocumentRef`: pages waiting in capture's store (with this capture's own claim) or a document the binder already keeps. Each capture holds its own claim; the pages go when no capture holds them. A capture whose pages are gone stops and says so; it never saves without its document. Sharing the same photo twice files the second one with the same document (it moves there).
- **Decided:** a kept document that moves belongs to its new place only: its links to the old place's deadline, history entry and firm are replaced, its archived state stays as it was, and it takes what was read now (kind, text, date, title). Undoing a visit puts a moved invoice back where it was instead of deleting it. Moving a document out of a locked section, or writing captured values into an existing locked section, asks for Face ID or the passcode first; a new section reveals nothing, so it doesn't ask.
- **Why:** three save paths wrote the same document three ways; the visit path silently dropped an invoice that was already in the binder, and moved documents kept links to their old place.
- **Decided:** a capture lives in a `CaptureSession` owned by what presents it. Closing the sheet (swiped down, closed or saved) cancels whatever is still reading, so a request to the AI provider not yet sent is never sent, and lets go of its pages.
- **Decided (owner):** with "Citește automat când nu sunt sigur" on, a page is sent by itself only when the phone is sure it is not an identity document (no machine-readable zone, no CNP-shaped number, no identity words, no identity kind among the readings) and the capture isn't headed for a locked section or a person's documents. In every other case the review asks once for that document, naming the provider ("Trimit poza la Gemini?"), with the provider's terms link; nothing is sent before yes. Bills, policies and contracts still read by themselves.
- **Why:** a weak reading is often a glared ID card the phone didn't recognise as one, so "the kind isn't identity" isn't enough to send it.
- **Decided:** who issued a document or did a job is found with one lookup, `ProviderActions.findOrCreate`: the firm already kept under the same name before a new one, for the filer and the visit form alike. Firms don't keep their CUI yet, so it doesn't decide the match today; matching it first needs a new database version. Firms kept twice are merged only through the repair list (`CaptureRepairs.mergeDuplicateProviders`).
- **Decided:** correcting the kind reads the page again as that kind. `CaptureEngine.reinterpret(_:as:)` reads the stored text with that kind's patterns and labels, merges the models' answers through `ReadingArbiter` and keeps only the fields the kind carries; the AI's change of kind and the person's own correction both use it. The person's edits stay, the kind they chose stays through later readings, and the review lists the kind's expected fields that weren't read so they can be added. This extends "A corrected kind brings what depends on it" (below).
- **Why:** an RCA policy corrected from a bill kept the bill's fields and couldn't get its expiry.
- **Decided (owner):** examples become the person's. Only the example loader makes examples; nothing real inherits the mark. When the person adds something of their own (a deadline, a document, a history entry, a reading, a section) to an example, the app asks "Păstrezi „VW Golf” ca a ta?" (the possessive agrees with the category's noun: mașina, locuința, persoana are feminine; the rest read "al tău"). Yes makes that example and everything in it theirs; removing examples never touches it again. No leaves the example as it was and saves nothing. Removing examples keeps an example that already holds something of the person's, and makes it theirs.
- **Why:** a real deadline added to the example car never reminded and was deleted with the examples.
- **Decided (owner):** data already affected is repaired only with the owner's OK. `CaptureRepairs` finds candidates (documents moved with old links, visits saved without their invoice) and repairs only what is approved, idempotently. The repair list that asks comes with the numbers session.

### Reminders you can trust
- **Decided:** every "done" and "amână" from outside the app (reminder buttons, the widget's *Gata*, Siri and Shortcuts) goes through one way in, `IntentEngine.perform`, built on the widget's guarded path. Reminders carry the due day of their cycle; an action for a cycle that has already closed, or one that can't say which cycle it was for, changes nothing. When a cycle closes, its reminders already shown are cleared from Notification Center. Every outside action ends with a pass of the app's one coordinator, which plans reminders and the widget again.
- **Why:** a reminder carried only the deadline, so tapping "Am rezolvat" on two reminders for the same RCA, or on an old one after it was done in the app, closed next year's cycle; and after a button, the old reminders still fired. The widget already had the right guard; the reminders used a weaker second path.
- **Decided:** a reminder button or widget tap that couldn't be saved is never dropped. It is shown calmly at the top of Urmează (*Nu s-a salvat*) until its cycle closes or the person hides it; a widget tap stays queued and is tried again. Siri says a failure at once.
- **Why:** the person saw "Gata" and moved on; a deadline that silently stays open breaks the app's promise.
- **Decided:** a deadline whose warnings had all passed before it became known gets one catch-up reminder at the next reminder time (the same day if it's still before it, otherwise the next morning), in the same wording as every other reminder: "În 20 de zile: Carte de identitate". The owner chose both. Durations in reminders are worked out from the day they fire.
- **Why:** an identity card added 20 days before it expires, with leads of 90 and 30 days, got no reminder before it expired.
- **Decided:** when a household has more reminders than iOS keeps, the plan keeps every deadline's next reminder first, most consequential first, then the rest by time, and its last place goes to „Deschide Dosar cu Șină o clipă” / „Ca să-ți amintim în continuare de termene, deschide aplicația.”, the day before the first reminder that didn't fit. The owner chose this wording.
- **Why:** only the 60 soonest were kept, so a busy household lost a passport's warning months ahead, with nothing to say so.
- **Decided:** a background refresh (Background App Refresh, on the phone only, no network) applies waiting widget taps, plans reminders again and rewrites the widget snapshot. The owner agreed to it. iOS decides when it runs, so the "open the app" reminder stays.
- **Why:** reminders and the widget's list were planned only when the app was opened.
- **Decided:** a series counted from its due dates remembers its day of the month: each date is that day, or the month's last day when the month is shorter. The day is read from the obligation's own completions, so nothing new is stored; a date moved by hand starts a new series. A series that already drifted (31 January, 28 February, 28 March) finds its day again at its next completion.
- **Why:** a payment on the 31st became due on the 28th for good after February, because each date was worked out from the previous, shortened one.
- **Decided:** Siri, Shortcuts, widgets, reminders and Spotlight read one list of what may leave the app, which leaves examples out. Siri asks to unlock the phone first, and with the app lock on, Siri and Shortcuts open the app instead of answering.
- **Why:** Siri suggested example deadlines, and one rule in one place keeps every surface the same.
- **Decided:** deadlines that an old reminder may have closed twice (the two latest completions a few days apart, closing consecutive cycles, the second still well ahead) are found by `LikelyDoubleCompletions.find` and left as they are. The coming repair list offers to undo the second one with `LikelyDoubleCompletions.undoSecond`, only with the person's OK; running it again changes nothing.
- **Why:** such a cycle can't be told apart with certainty from one paid early.

### Bills and contracts belong to their subscription
- **Decided:** an ongoing contract is one record, a subscription. The first bill or contract from a provider makes it; later bills and contracts find it by the codes they print (a POD, a CLC or the phone number first, then the contract number, then the client code) and file under it. Without a code, the provider decides only inside one house; two homes with the same provider never merge, and when the house can't be told the person picks. One engine decides, `SubscriptionMatcher`, and the review's place ("Unde îl pun") is the one way to change its answer.
- **Why:** each month's bill made a new, unrelated "Factură ENGIE" deadline, so nothing knew it was the same contract, and the codes that identify it were already on every bill.
- **Decided:** gas, electricity, water and fixed internet or TV live under the home they supply; a mobile plan lives in Abonamente, like a streaming service. "Mută la…" moves any subscription between homes and Abonamente.
- **Why:** these contracts are tied to an address and each home has its own; a phone contract follows the person. Phone contracts are among the most valuable to track for their costly minimum period.
- **Decided:** a bill is logged in its subscription's history with what it came to, sets "Ultima factură" when it is the newest, and moves the subscription's one "Factura de plătit" deadline to its own due date. With "Plătesc prin debit direct" on, no reminder to pay is made. A bill kept without a place sets no reminder: the loose "Factură <furnizor>" deadline is disabled (kept in the code, not called). Loose ones made before stay as they are; nothing is migrated without the person.
- **Why:** the payment reminder belongs to the contract and to the real due date on the paper; a reminder for something the bank pays by itself is noise.
- **Decided:** contracts are their own kind of document ("Contract sau act adițional"). What they say (the provider, the service, the contract number, the start, the minimum period and its end, the monthly price, the phone number) goes on the subscription, and the end of the minimum period becomes "Se termină perioada minimă", a month before and on the day. Its note says, without promising: "De regulă, de la această dată poți renunța fără penalități, anunțând cu cel mult o lună înainte. E cel mai bun moment să ceri o ofertă mai bună." A minimum period that already ended sets no deadline.
- **Why:** under EU rules (the electronic communications code, art. 105) a fixed term that ends continues indefinitely and can be left with at most a month's notice and no penalty; that day is the best moment to renegotiate. "De regulă" because contracts for energy and other services can differ.
- **Decided:** a bill that hasn't come well past when it usually does (one cycle after the last one, plus ten days for a monthly bill and the provider's usual delay) shows as a calm note in Urmează, under "Din timp": "Factura de la ENGIE n-a venit luna asta". Only for utilities and phone plans that had a bill before; never a notification, never on the badge or in widgets; it stops after two missed cycles.
- **Why:** a missing bill often means it went to an old email or the address changed, and late fees follow; but it is never urgent, so it must not sound like an alarm.

### Reading by evidence: the AI provider as a second opinion
- **Decided:** this replaces the rule in "What a cloud provider's answer is worth" (below, kept as it was). Readers are ranked by evidence in one place, `ReadingArbiter`, not by which ran first. The order: the person's own edits in the review (values, the kind, the place, the title and the name); then checked values from any reader (the machine-readable zone's check digits, a CNP, VIN or CUI control digit, a payment code in a known barcode format); then the AI provider; then the phone's patterns and labels; then Apple's on-device model.
- **Decided:** the AI provider reads the whole page as a full second opinion: it names the kind and every field. Its kind replaces the phone's unless the phone's rests on deterministic evidence (a checked zone, a decoded payment barcode, a provider's known format the classifier agrees with). A value it reads that isn't in the text the phone recognised is kept, marked "Verifică" unless it passes its own check or agrees with the phone; a value outside its plausibility window is still dropped.
- **Decided:** what a reader read differently is shown beside the value kept, with "Folosește-l", never applied by itself: "Pe telefon am citit: …", "Pe telefon părea: <kind>", "<provider> a citit: …", "Pe spatele actului scrie: …". One mechanism for all of them. A disagreement between readers marks the field "Verifică" unless a check settles it.
- **Decided:** "Citește mai bine cu <provider>" is offered whenever a provider is set up, whatever the phone read; for identity documents the line naming the provider and linking its terms stays. A new setting, "Citește automat când nu sunt sigur", off by default, has the provider read right after a weak phone reading: an unsure kind, an identity document without its essentials, a value that failed its check or a cross-check, little text, or a kind only a provider's format named.
- **Why:** a confident wrong reading on the phone (an RCA policy taken for a bill) used to hide the button, stop the model from changing the kind, and grade the model's correct answer against the phone's misread text. The more expensive reading the person chose to pay for must always be able to do better; only checks and the person themselves outrank it.

### Number fields change only while the person types
- **Decided:** a number or money field turns text into a value only while the person is typing in it. Showing a stored value never feeds back into it.
- **Why:** the field read its own formatted text back into the value, and a format and a read under different number conventions compounded: a car's 45.724 km became 457 after one edit. Rounding rules or a longer field would only have hidden it.

### A corrected kind brings what depends on it
- **Decided:** when the person changes a document's kind in the review, its deadline, place, title, name and reminder to pay follow the new kind, unless they already chose those themselves. Routing and the blueprint are worked out again from the new kind.
- **Why:** an RCA policy read as a bill and corrected by hand was saved without its expiry deadline: the kind changed, but nothing that depends on it did.

### Bill readers claim only bills
- **Decided:** a provider's known bill format (Digi, ENGIE, E.ON…) names the kind only when the classifier agrees or isn't sure, and providers are matched as whole words.
- **Why:** an RCA policy mentioning a word inside a provider's name was read as a Digi bill. A specialised reader is strong evidence for its own kind, not for every page that happens to share a word.

### Each car policy keeps its own details
- **Decided:** RCA and CASCO each have their own insurer, policy number and claims phone on the vehicle ("Telefon daune RCA", "Telefon daune CASCO"). A policy whose cover can't be told isn't written into either. Built-in catalog version 7.
- **Why:** a CASCO policy filled the RCA fields, so the number to call after an accident was the wrong one.

### Bill lines: only real lines, and the person can fix them
- **Decided:** line items ("Ce s-a făcut") belong only on service invoices, receipts, veterinary records and unknown documents. A line is kept only when it reads like one: short, with letters, and with an amount or a known part. In the review each line can be corrected or removed, a line added, or all removed.
- **Why:** a CASCO policy's terms came through as dozens of "lines", and there was no way to remove them before saving.

### A photo already in the binder moves to where it's added now
- **Decided:** filing a photo that's already kept moves the existing document to the new place, with what was read, instead of refusing or keeping two copies.
- **Why:** "Adaugă poza actului" with a photo added before saved nothing; the person had no way to know why.

### Adding a document for a person, photo first
- **Decided:** adding a document from a household member starts with three choices, the person already chosen: "Fotografiază", "Din poze", "Scriu eu". A photo goes through capture and becomes one of that person's documents whatever its kind. "Scriu eu" is one screen: the type in big rows, a variant only where the type has real ones, a name that comes by itself ("Cazier judiciar – Manole Corina"), the expiry with its reminder said plainly, and "Salvează". There is no separate deadlines step: the reminder comes from the type's profile and can be changed on the deadline page. Both land on the document's page, which asks for the picture when there is none.
- **Why:** the old way asked for a name the type already gave, then a deadlines step, and only then let the person add the picture. The picture is what people have in hand, and every extra step is a place to give up.
- **Decided:** variants are data on the document type (cazier judiciar, fiscal or auto; card de debit or de credit; carte de identitate electronică or fără cip; pașaport simplu electronic or temporar), offered through a condition on the field and its options, never as special cases in screens. A value that no longer fits its type is dropped on save.
- **Why:** one source of truth for what a document can be, which the add flow, the edit sheet, the naming and the PIN rule all read.

### "Mută la…"
- **Decided:** anything filed under something else (a document under a person, a tenancy or a product under a home) can move to another parent of the same kind from its page, through the toolbar menu or the edit sheet; a document can also go to a new person. A document named after its holder offers to take the new holder's name. The move is one save and the toast takes it back.
- **Why:** the only way before was to delete and add it again, losing its deadline, history and pictures.

### Secret fields (PIN codes)
- **Decided:** a new field type, `secret`, for codes such as the two PINs of the electronic identity card. It is sealed before saving with a key kept in the phone's Keychain (this device only), shown masked, and shown or copied only after Face ID or the passcode, every time, even when the section is open. A shown code hides after 30 seconds or when the app leaves the screen; a copied one leaves the clipboard after a minute and isn't shared with other devices. It never reaches search, widgets, notifications, the box status line, logs or `.dosar` archives; the backup screen says so, and a restored or merged backup keeps whatever codes the phone already has.
- **Why:** people forget these codes, and the card is blocked after a few wrong tries. Unlike the rest of an identity document, a PIN is never needed to fill in a form, so it can afford a prompt every time; a code that left the phone in a backup or a search index would defeat the point. A code moved to another phone with the database can't be opened there, and says so.
- **Decided:** the fields are named as the issuing authority names them, "PIN pentru autentificare" (4 digits) and "PIN pentru semnare" (6 digits), and apply only to the electronic identity card.
- **Decided:** a bank card is never offered a PIN field.
- **Why:** bank card terms forbid writing the PIN down; keeping it would put the person in breach of their card contract.

### AI providers: bring your own key, several providers, one contract
- **Decided:** the optional cloud reading is a provider layer, not Gemini wired in. The person picks Google Gemini, OpenAI, Anthropic Claude or any OpenAI-compatible service (OpenRouter, Mistral, LM Studio or Ollama on the home network) and brings their own key, one per provider, kept only in this phone's Keychain and sent only in request headers. Every provider gets the same request (the page and the document kind's fields as a JSON Schema, from the definitions the app reads with) and its answer goes through the same grounding and checks. The default model per provider is defined in one place and can be changed in Settings. Without a key nothing changes.
- **Why:** people already pay for, or trust, different services, and some run a model at home. One contract keeps the checks identical whoever answers, and a new provider is one small adapter, not a second reading path.

### What a cloud provider's answer is worth
- **Decided:** a value from a cloud provider is kept as read only when it appears in the text recognised on the phone or passes its own check (a CNP's control digit, a VIN's check digit, the machine-readable zone's check digits, a date inside its plausibility window). Anything else is a candidate marked "Verifică" and never replaces a checked value. The provider runs only when the person taps "Citește mai bine cu …"; for identity documents the review first says "Poza actului se trimite la <provider>, cu cheia ta." and links to the provider's own data-use terms. The app doesn't summarise those terms: it links to them.
- **Why:** a model reading a glared photo can be confidently wrong, and an identity document's values end up on forms. The phone's own reading and the documents' check digits are the evidence; the model only helps find what they can confirm. Linking avoids claims that may not hold for every person (Google's terms, for example, treat free keys differently in the European Economic Area).

### Plausible dates per document kind
- **Decided:** each kind of document says, as data, when its dates can fall. A birth date is within the last 120 years and not in the future. An issue date is not in the future and not before the birth date. On identity documents an expiry is between 2000 and 15 years from today (outside: dropped), and an issue date more than 15 years ago is kept only with "Verifică" (permanent cards). The same windows decide the century of two-digit years, in the machine-readable zone and on printed cards.
- **Why:** library photos are angled, glared and blurred, and a misread digit made a passport "expire in 1906". A fixed century rule can't tell a 1952 birth from a 2052 expiry; the window for each date can. Checking every tier's dates before they are merged keeps an impossible date from pushing out a possible one.

### Back of the card vs the person's edits
- **Decided:** when the back of an identity card is added after the person corrected a value by hand, their correction stays. Where the checked machine-readable zone disagrees, the field shows what the back says, with a button to use it.
- **Why:** the person is the final authority on their own data, but a checked value they may have mistyped against deserves to be seen.

### Collaboration
- **Decided:** collaborators work on their own branches and open pull requests into `main`, which the owner reviews and approves. Security problems are reported through GitHub's private vulnerability reporting. The privacy check is versioned in the repository and runs both before each commit and on every pull request.
- **Why:** the repository is public and two collaborators with their own AI agents are joining. The knowledge they need has to be in the repository, and the protection against leaks can't depend on one person's local setup.

### Distances read in the unit a person feels
- **Decided:** how far away something is reads as days under three weeks, then weeks, then months and weeks, then years and months. Leftovers are dropped, never rounded up.
- **Why:** "87 de zile" hides that something is under three months away. Rounding up would show more time than there is.

### Identity documents
- **Decided:** everything read from an identity document (CNP, series and number, birth date and so on) is shown and can be copied. The section's Face ID lock is the protection. It never appears in search, widgets or notifications.
- **Why:** people need these values to fill in forms; hiding them behind extra taps would defeat the binder. The lock protects the section; the places that show content without the lock never get it.
- **Decided:** documents are named "<document> – <Surname Given names>" and filed under the household member they belong to.
- **Why:** one person usually keeps the papers for the whole household.
- **Decided:** known Romanian documents (the new and the old identity card, the passport, the EU driving licence) are read with per-document templates and cross-checks. The person is asked only about doubtful values.
- **Why:** these layouts are fixed and well known, so they can be read reliably; asking about every field would make capture slower than typing.

### Widgets and examples
- **Decided:** widgets never show example data, and examples never notify.
- **Why:** examples are for exploring. A reminder or a widget about a made-up car would be confusing and would erode trust in real reminders.

### Choice values
- **Decided:** choice values are stored as stable keys, not as display text.
- **Why:** display text changes with wording and language; keys keep stored data, archives and rules stable.

### Face ID
- **Decided:** the app lock and the section locks are independent. A failed unlock never ejects the person. The device passcode is the fallback.
- **Why:** people protect different things in different ways. Being thrown out of the app after a failed Face ID is startling and loses their place.

### The share sheet is the main door
- **Decided:** onboarding includes a real practice share and shows how to move the app to the front of the share sheet.
- **Why:** most documents already arrive in Mail or WhatsApp, and many people don't know apps can hand things to each other, or can't find the app at the end of the share row.

### Integrations
- **Decided:** the app works fully without Calendar, Reminders or Contacts, which are optional one-tap extras. Permissions are asked in context. Notification permission is asked only after an in-app explanation or from Settings.
- **Why:** a permission prompt with no context gets refused, and a refused notification permission is hard to undo. Nothing essential should depend on a permission.

### Structure
- **Decided:** four tabs (Dosar, Urmează, Adaugă, Caută). The binder is a grid of boxes, each with one status line. A section shows fixed pockets in one global order. Agenda is a box.
- **Why:** labelled tabs and one predictable page layout are easy to learn, and one status line per box answers "is everything fine?" at a glance.

### Audience
- **Decided:** the reference user is aged 50–60 and not tech-savvy. No horizontal scrolling, no small pull tabs, labelled tabs, big targets, obvious affordances.
- **Why:** these are the people who keep the household's papers and who struggle most with apps built for power users.

### Follow-up after a lapse
- **Decided:** an optional single reminder the day after something lapsed. On by default for legal and financial items; the person can turn it on or off for any item.
- **Why:** a missed legal or financial deadline gets worse every day, so one nudge is worth it. More than one would nag.

### Reminder profiles
- **Decided:** the lead time follows how hard the renewal is. Rovinietă: 7 days before and on the day. Driving licence: 60 and 30 days. Cat vaccine: 1 day, with grace. Dog rabies vaccine: 10 and 4 days, legal, no grace.
- **Why:** a fixed "30 days before" is too early for a vignette bought in a minute and too late for a passport appointment. Reminding when action is actually needed keeps reminders trusted.

### Capture first
- **Decided:** the phone already has calendar, contacts, photos and notes. The app connects them to real-life events, and the main input is a photo or a document shared from another app.
- **Why:** typing details into forms is the main reason people give up on apps like this. The documents already exist; the app should read them.

### Product centre
- **Decided:** the app is a documents binder (*dosar cu șină*) for rare-but-predictable life admin, not a reminders or to-do app. It opens on the binder, not on a list of deadlines.
- **Why:** the value is having everything about the car, the home or the passport in one place when it's needed. Reminders follow from that, not the other way round.
- **Decided:** a smart maintenance log per component (when, how many km ago, cost, supplier, who did it) for every asset type.
- **Why:** "when did I last change it, and who did it" is the question people actually ask, and it applies to cars, boilers and bikes alike.
- **Decided:** people and providers with star ratings; key facts in one tap; purchase information; readiness checks (for example, the passport before a trip).
- **Why:** the binder should answer the next practical question, too: who to call, what number to quote, whether everything is in order before a trip.

## 2026-11-01

### Overhaul
- **Decided:** a full "framework, not patch" overhaul instead of incremental fixes, built in waves by coordinated agents.
- **Why:** the first version had one 90-field model and hand-built screens per category; fixing it piece by piece would have kept that structure. A template engine and single paths fix the cause.
- **Decided:** minimum iOS 26, Swift 6.
- **Why:** the app isn't released yet, so there are no older devices to support, and the newer APIs (on-device model, current SwiftUI and SwiftData) remove a lot of workarounds.

### Android and the archive format
- **Decided:** Android is paused, but `.dosar` export and import stay cross-platform, with a written specification and golden fixtures in `shared/`.
- **Why:** one platform done well first. Keeping the format portable means a future Android version can read the same backups without reshaping anything.

### Categories
- **Decided:** categories are one template engine, and the mainstays (car, home, documents, pets) must feel premium.
- **Why:** one engine means every category gets the same reminders, history, search and archive support; the mainstays are what most people use, so they get purpose-built heroes.

### First run
- **Decided:** the first run is empty, with "Explore with examples". Example data is tagged and removable.
- **Why:** seeding fake data into someone's binder mixes it with theirs. Examples on request let people explore, then start clean.

### Face ID
- **Decided:** Face ID is optional, per section, plus an app lock.
- **Why:** most of the binder (the car, the boiler) needs no lock and should open instantly; identity and health papers do.

### Urmează stays short
- **Decided:** the Urmează list must stay short as data grows (the attention model).
- **Why:** a list that grows with every tracked item becomes noise and stops being read.

---

## Decided, not built yet

### Partner offers
- **Decided:** optional partner offers (an insurance broker, vetted companies) on fair commission, privacy-first: the catalog is downloaded anonymously and matched on the device, data is shared only on an explicit tap per request, paid placements are labelled, and they never override the person's own rated providers.
- **Why:** it can help people renew insurance or find a trusted tradesperson and fund the free app, without trading their data or their trust.

### Household sharing
- **Decided:** household sharing through iCloud.
- **Why:** papers are often kept by two people; sharing through their own iCloud keeps the no-servers promise.
