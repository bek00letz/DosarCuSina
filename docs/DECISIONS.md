# Decisions

A dated log of product and architecture decisions, newest first. Each says what was decided and why. A newer decision can replace an older one: add a new entry that says so, and leave the old one in place.

To propose a change to a decision, open an issue with the **Proposal** template or a draft pull request. The owner decides.

---

## 2026-11-02

### Reading by evidence: the AI provider as a second opinion
- **Decided:** this replaces the rule in "What a cloud provider's answer is worth" (below, kept as it was). Readers are ranked by evidence in one place, `ReadingArbiter`, not by which ran first. The order: the person's own edits in the review (values, the kind, the place, the title and the name); then checked values from any reader (the machine-readable zone's check digits, a CNP, VIN or CUI control digit, a payment code in a known barcode format); then the AI provider; then the phone's patterns and labels; then Apple's on-device model.
- **Decided:** the AI provider reads the whole page as a full second opinion: it names the kind and every field. Its kind replaces the phone's unless the phone's rests on deterministic evidence (a checked zone, a decoded payment barcode, a provider's known format the classifier agrees with). A value it reads that isn't in the text the phone recognised is kept, marked "Verifică" unless it passes its own check or agrees with the phone; a value outside its plausibility window is still dropped.
- **Decided:** what a reader read differently is shown beside the value kept, with "Folosește-l", never applied by itself: "Pe telefon am citit: …", "Pe telefon părea: <kind>", "<provider> a citit: …", "Pe spatele actului scrie: …". One mechanism for all of them. A disagreement between readers marks the field "Verifică" unless a check settles it.
- **Decided:** "Citește mai bine cu <provider>" is offered whenever a provider is set up, whatever the phone read; for identity documents the line naming the provider and linking its terms stays. A new setting, "Citește automat când nu sunt sigur", off by default, has the provider read right after a weak phone reading: an unsure kind, an identity document without its essentials, a value that failed its check or a cross-check, little text, or a kind only a provider's format named.
- **Why:** a confident wrong reading on the phone (an RCA policy taken for a bill) used to hide the button, stop the model from changing the kind, and grade the model's correct answer against the phone's misread text. The more expensive reading the person chose to pay for must always be able to do better; only checks and the person themselves outrank it.

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
