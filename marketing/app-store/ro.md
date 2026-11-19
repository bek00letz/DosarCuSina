# App Store: textul în română

The listing in the app's language, ready to paste into App Store Connect (Romanian, the primary language). Every limit is App Store Connect's; the count beside each field is checked by `marketing/check-listing.py`. The words follow [docs/COPY_GUIDE.md](../../docs/COPY_GUIDE.md): the app speaks as „eu”, to „tu”, in sentence case, with no exclamation marks. Everything promised here is in version 1.0; iCloud sync isn't (it ships later, `DOSAR_SYNC_SHIPS_IN_RELEASE_BUILDS`), so the text doesn't promise it.

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
Nu ai nevoie de cont. Nu sunt reclame, nu urmăresc nimic din ce faci. Merge fără internet, iar ce pui în dosar stă pe telefonul tău. Actele și sănătatea pot sta în spatele Face ID. Faci o copie de siguranță cu parolă oricând vrei.

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
Prima versiune. Pune în dosar mașina, locuința, actele și animalele casei, și îți amintesc la timp de ce urmează.
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

## Confidențialitate (App Privacy)

- Data collection: **Data Not Collected** („Nu se colectează date”). The app has no account, no analytics, no server of ours. The binder stays on the phone (and later in the person's own iCloud, which Apple doesn't count as collection by the developer). A page the person chooses to read with their own AI key goes from their phone to the provider they chose, under their own account; the developer never receives it.
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

## Note pentru Apple (App Review Information)

App Review reads English; paste this into *Notes*. No sign-in is needed, so *Sign-in required* stays off.

```text
Dosar cu Șină is a household binder for Romanian paperwork (car inspection and insurance, passports, boiler checks, warranties, pets' vaccines) with reminders. The app is in Romanian. No account, no sign-in, no server: everything is stored on the device.

To see it filled in: on first launch, go through the short introduction and choose "Încarcă exemple" (load examples) on the last step. Later you can load or remove the examples in Setări (Settings) > Exemple. Examples are marked as such and never send notifications.

Reading documents: in the "Adaugă" tab, take a photo of a paper or pick a PDF. The text is read on the device (Vision and, where available, Apple's on-device model). The intro also offers a practice invoice to share into the app from the share sheet, which shows how the share extension works ("Arată-mi cum").

Optional AI key: Setări > Citire cu AI lets a person add their own key for Google Gemini, OpenAI, Anthropic Claude or an OpenAI-compatible service, to read difficult documents better. It is optional and never required; nothing is locked behind it. The key stays in the device's Keychain and is sent only to the provider the person chose, only when they choose to read a document with it. We provide no key and no account.

Face ID: the "Acte" (documents) and "Sănătate" (health) categories are protected with Face ID by default, as is the optional app lock (Setări > Protecție). On the simulator, use Features > Face ID > Matching Face.

Share extension: in another app (Mail, Files, Photos), tap Share and choose Dosar cu Șină. The file waits in Adaugă > "De verificat" (to review) until it is filed.

Notifications are asked for only after an explanation in the app, the first time a deadline needs a reminder. Widgets, Siri and Shortcuts are available ("Ce termene am?").

Contact: ar6development@gmail.com
```
