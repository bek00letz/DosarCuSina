# Copy guide

How the app talks. Short, plain Romanian, like a calm person who knows the rules.

## Words with one meaning

Each of these means one thing everywhere: the app, the widgets, the share sheet, notifications, Siri and Shortcuts, VoiceOver's labels and hints, onboarding and Settings. A word that does two jobs makes the person stop and wonder which one this is. The architecture check refuses the button words where they don't belong (`anuleaza-outside-undo`, `gata-outside-done`, `de-verificat-outside-inbox`).

| Word | What it means | Where | Not |
| :--- | :--- | :--- | :--- |
| **Gata** | A deadline is done, now, in one tap. | A chore's button on its page and in Urmează (`CompletionShape.actionTitle`), the widget's button, Siri's answer after it („Gata, l-am bifat.”). | Closing („Închide”) or saving („Salvează”). |
| **Am rezolvat** | Closing a deadline whose kind asks something first: it opens the sheet. „Am rezolvat…” in a menu or as VoiceOver's action (`menuTitle`). | The deadline's page, Urmează's swipe and menu (one entry, `CompletionEntry`), the reminder's button. | „Gata” for a kind that asks. |
| **Închide** | Close a sheet, a page or a viewer; nothing else happens, because nothing is waiting to be kept. | Setări, the full-screen pages, *Când te anunț*, the share sheet once something arrived, „Scriu eu”'s list. | „Gata”. |
| **Salvează** | Keep what was typed in a form or an editor, and close it. | Every editor's confirming button: *Editează* on a section, a document, a person or firm, a row under *Date importante*, a bill line. | „Gata”. |
| **Renunță** | Leave a sheet, a flow or a question without doing what it offers. „Renunți la modificări?” asks first when something typed would be lost. | `DSCancelButton`, a dialog's cancel, the Face ID prompt's cancel, the share sheet while it copies. A deletion's question cancels with „Păstrează”. | „Anulează”. |
| **Anulează** | Take back the step just taken. | Only the undo toast (`DSToast.undo`); „Anulează vizita” where the step is a visit just saved. | Cancelling anything („Renunță”), stopping a snooze („Nu mai amâna”). |
| **De verificat** | What other apps sent, waiting to be filed: the share inbox. | Adaugă › *De verificat*, the share sheet's and the notice's „Te așteaptă la De verificat”, an item's *Șterge din De verificat*. | The repair list, a checklist, the review's notices. |
| **De corectat** | What an earlier version saved wrongly, each with *Corectează* and *Lasă așa*: the repair list. | Setări › *De corectat* („Nimic de corectat”, „Un lucru de corectat”, „3 lucruri de corectat”), its prompt („Am găsit ceva de corectat”). | „Date de verificat”. |
| **Verifică** | Look again at a value read off a paper. | The review: „Verifică documentul”, „Verifică ce e marcat”, the *Verifică* mark beside a value; a value read again („Verifică-le mai jos”). In an error, the plain verb in its next step („Verifică dacă ai copiat-o întreagă”). | A title or a mark for anything else: a checklist's outcome is „Merită o privire”, more notices are „Mai sunt 2 observații”. |
| **Secțiune** | One thing in the binder: a car, a home, a person, a document. | *Adaugă o secțiune*, a section's page, „Secțiunea e protejată” on one that is locked. | A kind of thing. |
| **Categorie** | A kind of section (Mașini, Locuințe, Acte), built in or the person's own; what a lock protects. | *Categorii protejate*, Setări › *Ecranul Dosar*, *Alte categorii* in *Adaugă o secțiune*. | „Secțiune” for a kind („Secțiuni protejate”, „Alte secțiuni gata făcute”). |
| **Copie de siguranță** | The one file with the whole binder (a backup); „copia” once it is named. | Setări › *iCloud și copii de siguranță*, *Fă o copie de siguranță*, *Pune înapoi o copie*, every error about one. | „Copie de rezervă”, „arhivă”, „backup”. |
| **Arhivă** | A document put away, kept for reference. | *Mută în arhivă*, *Arhivat*, *Arhivate*. | A backup. |
| **Document** | Any paper kept in the binder: an act, a diploma, a contract, an invoice. | Every Acte's button and menu item, „Adaugă un document” (`PocketWording.addDocument`); a person's page has only that one, and capture decides whether the paper is one of their acts. | „Adaugă un act” on a button: a diploma is a document, not an act. |
| **Act** | A personal or official document with its holder and, usually, an expiry: an identity card, a passport, a licence. | The Acte category and pocket, „Un act nou”, a checklist's missing passport, a personal document's own page and flow. | A button that adds any paper, and anything capture, Adaugă or onboarding say of a paper they don't know yet: „Verifică documentul”, „Fotografiază un document”, „Citesc documentul…” (the `act-for-any-paper` check). |
| **Termen** | A deadline, anywhere the app speaks: on its screens, in the widget, in notifications, to Siri and in Shortcuts. „Termen protejat”, „Ai un termen mâine”, „Ce termene am”; a reminder says until when („Mașina · până pe 14 noiembrie”). | Everywhere a deadline is named. | „Obligație”, „scadență”, „scadent” (the `one-word-for-a-deadline` check). A bill's own label („Data scadenței”) is only read by capture. |
| **Opțional** | A checklist's check that is worth having and never required (`ReadinessNeed.optional`): it says so beside its title, in a neutral tone, and invites („Dacă le ai, …”). | Service history and invoices for a sale, the European health card for a trip, the policy's photo for a claim. | A warning tone, „Nu e în dosar”, or a count of what is missing. |
| **Notificări** | Settings' switch for everything the app sends to this phone: reminders, the badge, the share's notice. | Setări › *Notificări*, once iOS allows them; „Notificările sunt oprite” with „Pornește-le” where reminders are set up. | iOS's own permission, which the phone's Settings keep. |
| **Vizită** | Going to someone who looks at it: the service, the doctor, the vet. | *Am fost la service*, *Am fost la medic*, *Am fost la veterinar*, *Salvează vizita*, „Vizita e în istoric.” | A tradesperson's job or a repair. |
| **Lucrare** | A job someone did on a home, or on something of one's own that goes by time. | *Am chemat un meseriaș*, *Ce s-a lucrat*, *Salvează lucrarea*, „Lucrarea e în istoric.” | A visit. |
| **Reparație** | Something bought, taken to be fixed. | *Am dus la reparat*, *Ce s-a reparat*, *Salvează reparația*. | A job on a home. |
| **Revizie** | A machine's regular upkeep: a car's (*Revizie periodică*), an espresso machine's. | *Am făcut o revizie*, *Salvează revizia*, *Are revizii sau lucrări*. | A doctor's check-up („control”). |

Words a shaped screen says (the visit form, „Am rezolvat”, the deadline form, a section page's pockets and the full lists behind „Vezi tot”, adding a section, the form for a category of one's own, the capture review, the photo kept on request, a record's page in Istoric) come from its kind's description, never from the screen; [COPY_MATRIX.md](COPY_MATRIX.md) lists them for every category. Words about vehicles („km”, „kilometraj”, „piese”, „marcă”, „ulei”, „bord”) appear only in a vehicle's kind, a doctor's and a vet's („medic”, „veterinar”, „vaccin”, „analize”, „rețetă”) only in health and pets.

A paper is named for what it is: *Raportul ITP*, *Polița nouă*, *Carnetul de sănătate*, *Procesul-verbal*, *Rezultatele*, not „dovada” or „actul” where the deadline knows which. What is said about it agrees with its noun: „O păstrez în dosar.” for *Chitanța*, „Îl păstrez în dosar.” for *Rezultatul*, „Le păstrez în dosar.” for *Rezultatele*, „Din el iau data următoare.” for *Raportul ITP*. Work done at home asks no service's invoice. What a paper says is on it or in it, as its noun says: „Pe factură scrie”, „Pe card scrie”, „În contract scrie”, „În poliță scrie”, „În certificat scrie”, never „pe” before a booklet, a contract or a certificate. No two sentences on one form open the same way: the purpose says what the photo is for („Din ea iau data următoare.”), the example which paper („Cea primită de la asigurător sau de la broker.”).

A new section is named as one thing, never as its category: „Mașina”, „Produsul”, „Fișa medicală”, not „Mașini”, „Garanții”, „Sănătate”. A section's Acte names the papers its category keeps („Scanează talonul, polița sau raportul ITP și le găsești aici.”), not a list that fits only some. A completion's page in Istoric speaks of what it was: a policy names *Asigurătorul*, a tax *Cui ai plătit*, upkeep at home *Cine s-a ocupat*, never the vet or the service for a chore. Who a renewed paper comes from is said as the paper declares it (`CompletionShape.Paper.origin`): a document is issued („Cine l-a emis”), a contract or a lease signed („Cu cine l-ai semnat”). A paper's line agrees with any paper and with its day: „Expiră pe…”, „A expirat pe…” (`PocketWording.validity`, `validityLabel`), in Acte, on a person's documents, on a paper's page and in a document's hero, never „Valabil până la” under „Polița” or for a card that expired years ago. What a deadline repeats from is said of no noun, so it fits a rovinietă bought as well as an ITP done: „De la data rezolvării”, „Următorul e la 3 zile după rezolvare.” A paper that gave nothing says so („Nu am găsit pe ea data, suma sau numele.”); one that gave some names only those. A category is offered as one thing in *Adaugă o secțiune* („Bicicletă”, „Plantă”, „Espressor”), never by its plural name.

## Basics

- **Sentence case** for everything: titles, buttons, tabs, menus. „Adaugă o mașină”, not „Adaugă O Mașină”.
- **No exclamation marks.** Not for success, not for warnings.
- **No jargon.** Say what it does, not what it is. „Copie de siguranță”, not „arhivă .dosar”. „Cheia ta Google”, not „BYOK”. Official abbreviations people already use (ITP, RCA, CASCO, VTP) are fine.
- **Second person, singular, informal** („tu”): „Adaugă”, „Poți schimba”, „Ai scris”.
- **The app speaks as one, „eu”**: „Te anunț”, „Îți amintesc”, „O păstrez”, „Bifez singur”, „țin minte”. Never „noi” („îți amintim”, „îți spunem”, „Folosim Face ID”), in an empty line, in what iOS shows when the app asks for a permission (`INFOPLIST_KEY_…`: „Cer Face ID ca să deschid…”), or anywhere else, and never of itself in the third person („Aplicația are nevoie…”). `ReleaseReadinessTests` checks the permissions' words.
- **Words that agree with a gender** („Dacă o păstrezi”) are said only of what declares one (a built-in's `CategoryBehavior.singular`, a paper's noun). A category of one's own has none, so what every section's page says is worded without one: *Bani*'s total is „În total”, never „De când îl ai”; a category's name is never treated as a plural („Secțiunile din „Barca”…”).
- **A day already passed is said as passed**: „A expirat pe 10 mai.”, „Era de plătit până pe…”, and never promises a reminder before it („Te anunț … înainte”); it says what happens instead („Data a trecut, așa că termenul apare de acum în Urmează.”).
- **Verbs on buttons**, naming the result: „Salvează”, „Marchează ca rezolvat”, „Șterge secțiunea”. Never „OK”, „Da” or „Nu” when a verb fits: a dialog closes with „Închide” and leaves with „Renunță”. A section is a „secțiune”, never „un activ”.
- **The iPhone's settings are „Configurări”**, as iOS names the app in Romanian: „Le pornești din Configurări, la Notificări.”
- **Short.** One idea per sentence. If a footnote needs two sentences, the screen needs a redesign.

## Punctuation and formatting

- Romanian quotes: „așa”. Apostrophe: ’. En dash for ranges and asides: 9–17, 2 – 3 zile. Ellipsis character: … (not three dots), only for things still in progress („Se încarcă…”) and for a menu item that asks something before anything is done („Am rezolvat…”, „Altă zi…”).
- Diacritics always: ș and ț with comma below (not ş/ţ with cedilla), ă, â, î.
- Numbers, money and dates go through format styles so they follow the locale: 1.250,50 lei, 14 noiembrie 2026. Money in lei is written in lei, never „RON” (`Money.formatted`), and a whole number of lei is counted as Romanian counts it, from the String Catalog's plural forms: „1 leu”, „2 lei”, „19 lei”, „20 de lei”, „101 lei”, „1.250 de lei”; with decimals it is always „lei” („1,50 lei”). Never build them with `String(format:)`.
- A number is written the app's way whatever the phone's region („10.000”, never „10,000”): `RomanianNumber.format`, `MeasurementUnit.written`, `Money`, never an integer put straight into a sentence that is kept. A count in a `String(localized:)` or a `LocalizedStringResource(…)` passes the app's locale, `locale: .dosarDefault` (after `table:`, before `comment:`), or it is written in the phone's region; a `Text` takes the screen's, which is the app's. `scripts/plural-check.py` fails a string with a number that doesn't. A number and its unit stay on one line, with a no-break space („45.724 km”, „20 de lei”, between „de” and the unit too). A unit's symbol follows the number as it is („10.000 km”, „12,5 m³”); a counted word is counted like the leu, from the String Catalog's plural forms (`MeasurementUnit.written`): „1 cafea”, „2 cafele”, „20 de cafele”, „1.250 de cafele”, „24 de luni”. From 20 on, „de” always stands between a number and what it counts; `scripts/plural-check.py` fails a catalog entry whose „other” form leaves it out, and `CopyMatrixTests` a matrix that shows one.
- What can be worked out is said when it is shown, never stored as words: a service's note is its rule (`ObligationBlueprint.shownNote`), so it follows an edit and the app's number format.
- Plurals go through the String Catalog. Romanian has three forms: „o zi”, „2 zile”, „20 de zile”. A count of one is a word („o lună”, „un an”, „un document”), two and up are digits. „În” before a duration joins „o” and „un”: „într-o lună”, „într-un an” (`DurationWording.inside`). Never write `count == 1 ? … : …` by hand.

## Advice in a situation

A checklist's advice says where to go and what to bring, as the law and the insurer ask: after a minor crash with no one hurt, a joint report („constatarea amiabilă”), and „Dacă nu vă înțelegeți, mergi la Poliție”, never „sună la Poliție” or 112, which is for an emergency (someone hurt) and can be fined otherwise. `CopyMatrixTests` checks the situations' words for it.

## Errors

Every error says **what happened** and **what to do next**, in that order. No codes, no blame, no „A apărut o eroare”.

| Instead of | Write |
| :--- | :--- |
| Eroare la import. | Copia de siguranță nu s-a deschis. Fișierul pare incomplet. Fă copia din nou și încearcă iar. |
| Câmp invalid. | Seria de șasiu are 17 caractere. Ai scris 15. |
| Cheie API invalidă (401). | Google nu a acceptat cheia. Verifică dacă ai copiat-o întreagă. |
| Fără conexiune. | Nu ești conectat la internet. Scanarea locală merge în continuare. |

Field messages appear under the field, after the person leaves it. Write them as a fix, not a verdict: „Scrie suma doar cu cifre, de exemplu 1.250,50.”

## Empty states

Say what will live here and offer the one action that fills it.

- Title: what's missing, plainly. „Nicio mașină încă”.
- Message: why it's worth adding, in one sentence. „Adaugă mașina și îți amintesc de ITP, RCA și rovinietă la timp.”
- Button: the action. „Adaugă o mașină”.

## Confirmations

Prefer an undo toast over an „Ești sigur?” dialog whenever the action can be reversed. Ask first only for things that can't be undone, and name the consequence: „Secțiunea și toate documentele ei se șterg de pe acest telefon.”

## Placeholders and examples

Use placeholder data only: B-123-ABC, VW Golf 2018, ENGIE Romania S.A., nume@exemplu.ro. Never real names, plates, phone numbers or personal identification numbers.

## In code

- Pass string literals straight to `Text`, `Button`, `Label` (they're localized automatically). Add a `comment:` when a word could be read two ways.
- Types that carry user-facing text use `LocalizedStringResource`, not `String`.
- Data from the person or from templates (asset names, option titles) is shown with `Text(verbatim:)` or a `String` value, never translated.
