# Decisions

A dated log of product and architecture decisions, newest first. Each says what was decided and why. A newer decision can replace an older one: add a new entry that says so, and leave the old one in place.

To propose a change to a decision, open an issue with the **Proposal** template or a draft pull request. The owner decides.

---

## 2026-11-02

### Reminders you can trust
- **Decided:** every "done" and "amână" from outside the app (reminder buttons, the widget's *Gata*, Siri and Shortcuts) goes through one way in, `IntentEngine.perform`, built on the widget's guarded path. Reminders carry the due day of their cycle; an action for a cycle that has already closed, or one that can't say which cycle it was for, changes nothing. When a cycle closes, its reminders already shown are cleared from Notification Center. Every outside action ends with a pass of the app's one coordinator, which plans reminders and the widget again.
- **Why:** a reminder carried only the deadline, so tapping "Am rezolvat" on two reminders for the same RCA, or on an old one after it was done in the app, closed next year's cycle; and after a button, the old reminders still fired. The widget already had the right guard; the reminders used a weaker second path.
- **Decided:** a reminder button or widget tap that couldn't be saved is never dropped. It is shown calmly at the top of Urmează (*Nu s-a salvat*) until its cycle closes or the person hides it; a widget tap stays queued and is tried again. Siri says a failure at once.
- **Why:** the person saw "Gata" and moved on; a deadline that silently stays open breaks the app's promise.
- **Decided:** a deadline whose warnings had all passed before it became known gets one catch-up reminder at the next reminder time ("În 20 de zile: Carte de identitate"), in the same wording as every other reminder. Durations in reminders are worked out from the day they fire.
- **Why:** an identity card added 20 days before it expires, with leads of 90 and 30 days, got no reminder before it expired.
- **Decided:** when a household has more reminders than iOS keeps, the plan keeps every deadline's next reminder first, most consequential first, then the rest by time, and its last place goes to „Deschide Dosar cu Șină o clipă” / „Ca să-ți amintim în continuare de termene, deschide aplicația.”, the day before the first reminder that didn't fit. The owner chose this wording.
- **Why:** only the 60 soonest were kept, so a busy household lost a passport's warning months ahead, with nothing to say so.
- **Decided:** a background refresh (Background App Refresh, on the phone only, no network) applies waiting widget taps, plans reminders again and rewrites the widget snapshot. The owner agreed to it. iOS decides when it runs, so the "open the app" reminder stays.
- **Why:** reminders and the widget's list were planned only when the app was opened.
- **Decided:** a series counted from its due dates remembers its day of the month: each date is that day, or the month's last day when the month is shorter. The day is read from the obligation's own completions, so nothing new is stored; a date moved by hand starts a new series. A series that already drifted (31 January, 28 February, 28 March) finds its day again at its next completion.
- **Why:** a payment on the 31st became due on the 28th for good after February, because each date was worked out from the previous, shortened one.
- **Decided:** Siri, Shortcuts, widgets, reminders and Spotlight read one list of what may leave the app, which leaves examples out. Siri asks to unlock the phone first, and with the app lock on, Siri and Shortcuts open the app instead of answering.
- **Why:** Siri suggested example deadlines, and one rule in one place keeps every surface the same.
- **Decided:** deadlines that an old reminder may have closed twice (two completions a few days apart, the second closing a cycle still well ahead) are found by `LikelyDoubleCompletions` and left as they are. The coming repair list offers to undo the second one, only with the person's OK.
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
