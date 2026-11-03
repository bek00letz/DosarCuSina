# Copy guide

How the app talks. Short, plain Romanian, like a calm person who knows the rules.

## Basics

- **Sentence case** for everything: titles, buttons, tabs, menus. „Adaugă o mașină”, not „Adaugă O Mașină”.
- **No exclamation marks.** Not for success, not for warnings.
- **No jargon.** Say what it does, not what it is. „Copie de rezervă”, not „arhivă .dosar”. „Cheia ta Google”, not „BYOK”. Official abbreviations people already use (ITP, RCA, CASCO, VTP) are fine.
- **Second person, singular, informal** („tu”): „Adaugă”, „Poți schimba”, „Ai scris”.
- **Verbs on buttons**, naming the result: „Salvează”, „Marchează ca rezolvat”, „Șterge activul”. Never „OK” or „Da” when a verb fits.
- **Short.** One idea per sentence. If a footnote needs two sentences, the screen needs a redesign.

## Punctuation and formatting

- Romanian quotes: „așa”. Apostrophe: ’. En dash for ranges and asides: 9–17, 2 – 3 zile. Ellipsis character: … (not three dots), only for things still in progress („Se încarcă…”).
- Diacritics always: ș and ț with comma below (not ş/ţ with cedilla), ă, â, î.
- Numbers, money and dates go through format styles so they follow the locale: 1.250,50 lei, 14 noiembrie 2026. Never build them with `String(format:)`.
- Plurals go through the String Catalog. Romanian has three forms: „o zi”, „2 zile”, „20 de zile”. A count of one is a word („o lună”, „un an”, „un document”), two and up are digits. „În” before a duration joins „o” and „un”: „într-o lună”, „într-un an” (`DurationWording.inside`). Never write `count == 1 ? … : …` by hand.

## Errors

Every error says **what happened** and **what to do next**, in that order. No codes, no blame, no „A apărut o eroare”.

| Instead of | Write |
| :--- | :--- |
| Eroare la import. | Arhiva nu s-a putut deschide. Fișierul pare incomplet. Exportă-l din nou și încearcă iar. |
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
