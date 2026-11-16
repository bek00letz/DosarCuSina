# Copy guide

How the app talks. Short, plain Romanian, like a calm person who knows the rules.

## Words with one meaning

Each of these means one thing everywhere: the app, the widgets, the share sheet, notifications, Siri and Shortcuts, VoiceOver's labels and hints, onboarding and Settings. A word that does two jobs makes the person stop and wonder which one this is. The architecture check refuses the button words where they don't belong (`anuleaza-outside-undo`, `gata-outside-done`, `de-verificat-outside-inbox`).

| Word | What it means | Where | Not |
| :--- | :--- | :--- | :--- |
| **Gata** | A deadline is done, now, in one tap. | A chore's button on its page and in Urmează (`CompletionShape.actionTitle`), the widget's button, Siri's answer after it („Gata, am bifat-o.”). | Closing („Închide”) or saving („Salvează”). |
| **Am rezolvat** | Closing a deadline whose kind asks something first: it opens the sheet. „Am rezolvat…” in a menu or as VoiceOver's action (`menuTitle`). | The deadline's page, Urmează's swipe and menu (one entry, `CompletionEntry`), the reminder's button. | „Gata” for a kind that asks. |
| **Închide** | Close a sheet, a page or a viewer; nothing else happens, because nothing is waiting to be kept. | Setări, the full-screen pages, *Când te anunț*, the share sheet once something arrived, „Scriu eu”'s list. | „Gata”. |
| **Salvează** | Keep what was typed in a form or an editor, and close it. | Every editor's confirming button: *Editează* on a section, a document, a person or firm, a row under *Date importante*, a bill line. | „Gata”. |
| **Renunță** | Leave a sheet, a flow or a question without doing what it offers. „Renunți la modificări?” asks first when something typed would be lost. | `DSCancelButton`, a dialog's cancel, the Face ID prompt's cancel, the share sheet while it copies. A deletion's question cancels with „Păstrează”. | „Anulează”. |
| **Anulează** | Take back the step just taken. | Only the undo toast (`DSToast.undo`); „Anulează vizita” where the step is a visit just saved. | Cancelling anything („Renunță”), stopping a snooze („Nu mai amâna”). |
| **De verificat** | What other apps sent, waiting to be filed: the share inbox. | Adaugă › *De verificat*, the share sheet's and the notice's „Te așteaptă la De verificat”, an item's *Șterge din De verificat*. | The repair list, a checklist, the review's notices. |
| **De corectat** | What an earlier version saved wrongly, each with *Corectează* and *Lasă așa*: the repair list. | Setări › *De corectat* („Nimic de corectat”, „Un lucru de corectat”, „3 lucruri de corectat”), its prompt („Am găsit ceva de corectat”). | „Date de verificat”. |
| **Verifică** | Look again at a value read off a paper. | The review: „Verifică actul”, „Verifică ce e marcat”, the *Verifică* mark beside a value; a value read again („Verifică-le mai jos”). In an error, the plain verb in its next step („Verifică dacă ai copiat-o întreagă”). | A title or a mark for anything else: a checklist's outcome is „Merită o privire”, more notices are „Mai sunt 2 observații”. |
| **Secțiune** | One thing in the binder: a car, a home, a person, a document. | *Adaugă o secțiune*, a section's page, „Secțiunea e protejată” on one that is locked. | A kind of thing. |
| **Categorie** | A kind of section (Mașini, Locuințe, Acte), built in or the person's own; what a lock protects. | *Categorii protejate*, Setări › *Ecranul Dosar*, *Alte categorii* in *Adaugă o secțiune*. | „Secțiune” for a kind („Secțiuni protejate”, „Alte secțiuni gata făcute”). |
| **Copie de siguranță** | The one file with the whole binder (a backup); „copia” once it is named. | Setări › *iCloud și copii de siguranță*, *Fă o copie de siguranță*, *Pune înapoi o copie*, every error about one. | „Copie de rezervă”, „arhivă”, „backup”. |
| **Arhivă** | A document put away, kept for reference. | *Mută în arhivă*, *Arhivat*, *Arhivate*. | A backup. |
| **Vizită** | Going to someone who looks at it: the service, the doctor, the vet. | *Am fost la service*, *Am fost la medic*, *Am fost la veterinar*, *Salvează vizita*, „Vizita e în istoric.” | A tradesperson's job or a repair. |
| **Lucrare** | A job someone did on a home, or on something of one's own that goes by time. | *Am chemat un meseriaș*, *Ce s-a lucrat*, *Salvează lucrarea*, „Lucrarea e în istoric.” | A visit. |
| **Reparație** | Something bought, taken to be fixed. | *Am dus la reparat*, *Ce s-a reparat*, *Salvează reparația*. | A job on a home. |
| **Revizie** | A machine's regular upkeep: a car's (*Revizie periodică*), an espresso machine's. | *Am făcut o revizie*, *Salvează revizia*, *Are revizii sau lucrări*. | A doctor's check-up („control”). |

Words a shaped screen says (the visit form, „Am rezolvat”, the deadline form, a section page's pockets and the full lists behind „Vezi tot”, adding a section, the form for a category of one's own, the capture review, the photo kept on request, a record's page in Istoric) come from its kind's description, never from the screen; [COPY_MATRIX.md](COPY_MATRIX.md) lists them for every category. Words about vehicles („km”, „kilometraj”, „piese”, „marcă”, „ulei”, „bord”) appear only in a vehicle's kind, a doctor's and a vet's („medic”, „veterinar”, „vaccin”, „analize”, „rețetă”) only in health and pets.

A paper is named for what it is: *Raportul ITP*, *Polița nouă*, *Carnetul de sănătate*, *Procesul-verbal*, *Rezultatele*, not „dovada” or „actul” where the deadline knows which. What is said about it agrees with its noun: „O păstrez în dosar.” for *Chitanța*, „Îl păstrez în dosar.” for *Rezultatul*, „Le păstrez în dosar.” for *Rezultatele*, „Din el iau data următoare.” for *Raportul ITP*. Work done at home asks no service's invoice. What a paper says is on it or in it, as its noun says: „Pe factură scrie”, „Pe card scrie”, „În contract scrie”, „În poliță scrie”, „În certificat scrie”, never „pe” before a booklet, a contract or a certificate. No two sentences on one form open the same way: the purpose says what the photo is for („Din ea iau data următoare.”), the example which paper („Cea primită de la asigurător sau de la broker.”).

A new section is named as one thing, never as its category: „Mașina”, „Produsul”, „Fișa medicală”, not „Mașini”, „Garanții”, „Sănătate”. A section's Acte names the papers its category keeps („Scanează talonul, polița sau raportul ITP și le găsești aici.”), not a list that fits only some. A completion's page in Istoric speaks of what it was: a policy names *Asigurătorul*, a tax *Cui ai plătit*, upkeep at home *Cine s-a ocupat*, never the vet or the service for a chore.

## Basics

- **Sentence case** for everything: titles, buttons, tabs, menus. „Adaugă o mașină”, not „Adaugă O Mașină”.
- **No exclamation marks.** Not for success, not for warnings.
- **No jargon.** Say what it does, not what it is. „Copie de siguranță”, not „arhivă .dosar”. „Cheia ta Google”, not „BYOK”. Official abbreviations people already use (ITP, RCA, CASCO, VTP) are fine.
- **Second person, singular, informal** („tu”): „Adaugă”, „Poți schimba”, „Ai scris”.
- **Verbs on buttons**, naming the result: „Salvează”, „Marchează ca rezolvat”, „Șterge activul”. Never „OK” or „Da” when a verb fits.
- **Short.** One idea per sentence. If a footnote needs two sentences, the screen needs a redesign.

## Punctuation and formatting

- Romanian quotes: „așa”. Apostrophe: ’. En dash for ranges and asides: 9–17, 2 – 3 zile. Ellipsis character: … (not three dots), only for things still in progress („Se încarcă…”) and for a menu item that asks something before anything is done („Am rezolvat…”, „Altă zi…”).
- Diacritics always: ș and ț with comma below (not ş/ţ with cedilla), ă, â, î.
- Numbers, money and dates go through format styles so they follow the locale: 1.250,50 lei, 14 noiembrie 2026. Money in lei is written in lei, never „RON” (`Money.formatted`), and a whole number of lei is counted as Romanian counts it, from the String Catalog's plural forms: „1 leu”, „2 lei”, „19 lei”, „20 de lei”, „101 lei”, „1.250 de lei”; with decimals it is always „lei” („1,50 lei”). Never build them with `String(format:)`.
- Plurals go through the String Catalog. Romanian has three forms: „o zi”, „2 zile”, „20 de zile”. A count of one is a word („o lună”, „un an”, „un document”), two and up are digits. „În” before a duration joins „o” and „un”: „într-o lună”, „într-un an” (`DurationWording.inside`). Never write `count == 1 ? … : …` by hand.

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
- Message: why it's worth adding, in one sentence. „Adaugă mașina și îți amintim de ITP, RCA și rovinietă la timp.”
- Button: the action. „Adaugă o mașină”.

## Confirmations

Prefer an undo toast over an „Ești sigur?” dialog whenever the action can be reversed. Ask first only for things that can't be undone, and name the consequence: „Activul și toate documentele lui vor fi șterse de pe acest telefon.”

## Placeholders and examples

Use placeholder data only: B-123-ABC, VW Golf 2018, ENGIE Romania S.A., nume@exemplu.ro. Never real names, plates, phone numbers or personal identification numbers.

## In code

- Pass string literals straight to `Text`, `Button`, `Label` (they're localized automatically). Add a `comment:` when a word could be read two ways.
- Types that carry user-facing text use `LocalizedStringResource`, not `String`.
- Data from the person or from templates (asset names, option titles) is shown with `Text(verbatim:)` or a `String` value, never translated.
