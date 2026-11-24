# App Store: textul în română

The listing in the app's language, ready to paste into App Store Connect (Romanian, the primary language). Every limit is App Store Connect's; the count beside each field is checked by `marketing/check-listing.py`. The words follow [docs/COPY_GUIDE.md](../../docs/COPY_GUIDE.md): the app speaks as „eu”, to „tu”, in sentence case, with no exclamation marks. Everything promised here is in version 1.0, iCloud sync included (DECISIONS, 2026-11-24).

## Nume (30)

```text
Dosar cu Șină
```

## Subtitlu (30)

```text
Actele și termenele casei
```

## Text promoțional (170)

```text
Ai grijă de ITP, RCA, pașaport, revizia centralei și vaccinul pisicii, toate într-un singur dosar pe telefon. Îți amintesc la timp, fără cont și fără internet.
```

## Descriere (4000)

```text
Dosarul cu șină de pe telefon: actele, termenele și facturile casei, cu amintiri la timp.

ITP-ul și RCA-ul mașinii, pașaportul, revizia centralei, polița PAD, vaccinul pisicii, garanția mașinii de spălat. Toate au o dată, și toate vin când nu te aștepți. Le pui o dată în dosar și îți amintesc de fiecare cât de devreme trebuie, nu mai devreme.

FOTOGRAFIEZI, EU CITESC
Faci o poză talonului, poliței sau facturii, sau o trimiți din Mail ori WhatsApp cu „Trimite”. Citesc pe telefon datele, sumele și numerele și îți arăt unde îl pun, înainte să salvez. Merge și cu PDF-uri.

URMEAZĂ: DOAR CE CONTEAZĂ
O listă scurtă cu ce urmează, oricât de multe ai în dosar. Când ai rezolvat, apeși „Am rezolvat” și trec la data următoare. ITP-ul ia data din raportul nou, polița din polița nouă.

O CUTIE PENTRU FIECARE
Mașina, locuința, oamenii casei cu actele lor, animalele, garanțiile, abonamentele. Fiecare are pagina ei: termenele, documentele, reviziile și reparațiile, cât ai cheltuit și cine s-a ocupat.

PLECI DIN ȚARĂ?
Îți spun ce acte îți trebuie pentru călătorie, pentru fiecare om și pentru mașină: buletinul sau pașaportul, cât mai e valabil, ce lipsește. La fel când vinzi mașina sau ai o daună.

AL TĂU, PE TELEFONUL TĂU
Nu ai nevoie de cont. Nu sunt reclame, nu urmăresc nimic din ce faci. Merge fără internet, iar ce pui în dosar stă pe telefonul tău și în iCloud-ul tău, ca să-l ai și pe iPad sau pe un telefon nou. Actele și sănătatea pot sta în spatele Face ID. Faci o copie de siguranță cu parolă oricând vrei.

ȘI MAI MULTE
• Caută în tot dosarul, și din căutarea iPhone-ului.
• Widgeturi pe ecranul principal și pe ecranul blocat.
• Siri și Scurtături: „Ce termene am?”
• Kilometrajul, indexul contoarelor și facturile, cu istoricul lor.
• Oamenii și firmele care au grijă de casă, cu telefonul la îndemână.

Opțional, dacă vrei, poți adăuga cheia ta de la un serviciu de AI (Google Gemini, OpenAI, Claude sau unul compatibil) ca să citesc mai bine documentele grele. Fără ea, totul merge la fel: citirea pe telefon, amintirile, widgeturile, copiile de siguranță.

E gratuită, fără abonament și fără nimic de cumpărat în aplicație. Codul aplicației e public, pe GitHub.
```

## Cuvinte-cheie (100)

App Store already searches the name and the subtitle, so the keywords add only words that aren't there.

```text
ITP,RCA,rovinietă,pașaport,buletin,garanție,revizie,centrală,CASCO,PAD,asigurare,factură,vaccin
```

## Ce e nou în 1.0 (4000)

```text
Prima versiune. Pune în dosar mașina, locuința, actele și animalele casei, și îți amintesc la timp de ce urmează. Dosarul te urmează pe iPad și pe un telefon nou, prin iCloud-ul tău.
```

## Adrese și contact

| Câmp | Valoare |
| :--- | :--- |
| Adresa de ajutor (Support URL) | https://bek00letz.github.io/DosarCuSina/ajutor/ |
| Politica de confidențialitate (Privacy Policy URL) | https://bek00letz.github.io/DosarCuSina/confidentialitate/ |
| Adresa de marketing (opțională) | https://bek00letz.github.io/DosarCuSina/ |
| E-mail de contact | ar6development@gmail.com |
| Drepturi (Copyright) | 2026 (numele proprietarului, cum apare în contul de dezvoltator) |
| Categorie principală | Productivitate (Productivity) |
| Categorie secundară | Finanțe sau Utilitare (alegerea proprietarului) |
| Preț | Gratuit |

## Antet și căutare (Header and Search Results)

App Store Connect › the version's page › *Header and Search Results*, shown in iOS 27 and iPadOS 27 and later. Both pictures have no words, so they need no translation; both keep the binder inside Apple's safe area, and the papers around it may be cut at the sides.

| Câmp | Fișier |
| :--- | :--- |
| Header (21:9) | [header/header-3840x1646.png](header/header-3840x1646.png) |
| Search Results (3:2) | [header/search-3840x2560.png](header/search-3840x2560.png) |

No video. Drawn by `marketing/header-art.swift`; after uploading, check them with App Store Connect's *Preview* on iPhone and iPad.

## Confidențialitate (App Privacy)

- Data collection: **Data Not Collected** („Nu se colectează date”). The app has no account, no analytics, no server of ours. The binder stays on the phone and, while sync is on, in the person's own private iCloud database, which the developer can't reach and Apple doesn't count as collection by the developer. A page the person chooses to read with their own AI key goes from their phone to the provider they chose, under their own account; the developer never receives it.
- Tracking: **No**.

## Vârsta (Age Rating)

Every answer in the questionnaire is **None / No**, which gives **4+**:

| Question | Answer |
| :--- | :--- |
| Violence (cartoon, realistic, prolonged, graphic) | None |
| Sexual content or nudity | None |
| Profanity or crude humour | None |
| Alcohol, tobacco or drugs | None |
| Mature or suggestive themes, horror or fear | None |
| Medical or treatment information | None (the app keeps the person's own check-up dates; it gives no medical advice) |
| Simulated gambling, contests | None |
| Unrestricted web access | No |
| User-generated content shared with others, messaging or chat | No |
| Advertising | No |
| Parental controls, age assurance | No |
| Made for Kids | No |

## Export compliance

Already answered in the app's Info.plist (`ITSAppUsesNonExemptEncryption` = NO): only the encryption iOS provides. `scripts/bundle-check.sh` checks it on every pull request.

## Pentru Apple (App Review Information)

What App Store Connect asks under *App Review Information*, field by field. App Review reads English, so the notes are in English.

| Field | Value |
| :--- | :--- |
| Sign-in required | Off: the app has no account and no sign-in, so there is no demo account. |
| Contact: first and last name, phone, e-mail | The owner's, typed in App Store Connect only (never written in this public repository); e-mail ar6development@gmail.com. |
| Notes | The block below. |
| Attachment | None needed: the examples and the practice invoice are inside the app. |

## Note pentru Apple (4000)

```text
Dosar cu Șină is a household binder for Romanian paperwork (car inspection and insurance, passports, boiler checks, warranties, pets' vaccines) with reminders. The app is in Romanian only. There is no account, no sign-in and no server of ours: everything is stored on the device.

THE TABS
Dosar = the binder, one box per thing you look after. Urmează = what is due next. Adaugă = add something (photo, PDF, shared files). Caută = search. Setări (Settings) is the button at the top right of Dosar.

TO SEE IT FILLED IN
1. On first launch, go through the short introduction and tap "Vreau să văd cu exemple" (show me with examples). Examples are marked "Exemplu" and never send notifications. They can be loaded or removed later in Setări > Exemple ("Încarcă exemple" / "Șterge exemplele").
2. Dosar: tap the car's box for its page (deadlines, documents, services, costs).
3. Urmează: tap a deadline, then "Am rezolvat" (done) to record it and move to the next date.
4. Adaugă: take a photo of any paper or pick a PDF. It is read on the device (Vision and, where available, Apple's on-device model), and the app shows where it will file it before saving. The introduction's "Arată-mi cum" (show me how) shares a practice invoice into the app through the share sheet.
5. Urmează, or a person's page: "Pleci din țară" (travelling abroad) checks the documents each traveller and the car need. A car's page also offers "Vinzi mașina" (selling the car) and "Ai avut o daună" (an insurance claim).

SHARE EXTENSION
In Mail, Files or Photos, tap Share and choose Dosar cu Șină. The file waits in Adaugă > "De verificat" (to review) until it is filed.

OPTIONAL AI PROVIDER (guidelines 5.1.1 and 5.1.2)
Setări > Citire cu AI lets a person add their own key for Google Gemini, OpenAI, Anthropic Claude or an OpenAI-compatible service, to read difficult documents better. It is never required and nothing is locked behind it; without a key everything works the same. Before a document leaves the phone the app asks ("Trimit poza la <provider>?", send the photo to <provider>?), unless the person turns on "Citește automat când nu sunt sigur" (read automatically when unsure), which is off by default; identity documents always ask. Only the document's first page is sent, directly from the device to the provider the person chose, under their own key. We receive nothing. The key stays in the device's Keychain. The privacy policy describes this.

PERMISSIONS
Camera: to photograph documents. Face ID: to open protected categories. Photos (add only): to save pages the person shares. Local network: only if the person chooses an AI service on their own network. Notifications: asked only after an explanation in the app, the first time a deadline needs a reminder.

FACE ID
"Acte" (documents) and "Sănătate" (health) are protected with Face ID by default; an optional app lock is in Setări > Protecție. On the simulator: Features > Face ID > Enrolled, then Matching Face when asked.

ALSO IN THE APP
Home and Lock Screen widgets; Siri and Shortcuts ("Ce termene am?", what deadlines do I have?); the iPhone's search; password-protected backups. iCloud sync (on by default, Setări > iCloud și copii de siguranță) keeps the binder in the person's own private iCloud database, so it appears on their iPad and a new phone; we have no server and can't see it. The examples never sync.

The health category stores the person's own check-up and vaccine dates; the app gives no medical advice. The app is free, with no in-app purchases, subscriptions or ads, and no tracking.

Contact: ar6development@gmail.com
```
