# Copy matrix

What each shaped screen says to each category, generated from the kinds' descriptions: the visit form from `VisitShape` laid over the category (`VisitForm`), „Gata” and „Am rezolvat” from `CompletionShape`. Every built-in category is here, and one category of one's own per combination of its switches. Reviews walk every category through it.

Don't edit it by hand: `CopyMatrixTests` writes it and fails when it is out of date. To bring it up to date, run `TEST_RUNNER_COPY_MATRIX_WRITE=1 ./tests/run_tests.sh` and commit the diff. Sample values: 3 rows, 1.250 RON, 3 mai 2027.

## The visit form

### What every kind shares

| Where | Words |
| :--- | :--- |
| Details | Detalii · Data |
| Where the photo comes from | Alege din poze · Din Fișiere · Renunță |
| A row of one's own | Scoate rândul |
| A firm already rated | Notă 4,5 din 5 |
| Not saved | Nu s-a salvat · Poza nu s-a putut deschide. Încearcă din nou. |
| A section that has gone | Secțiunea nu mai există — Poate a fost ștearsă. Închide și alege alta. |
| A link to a visit where the category has none | Aici nu se notează vizite — Pe pagina secțiunii găsești ce poți adăuga. |

### Mașini (`vehicle`) · `service`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am fost la service |
| „Scriu eu”'s card | Am fost la service — Ce s-a făcut, cât a costat, cine a lucrat. |
| The paper's card | Atașează factura — Bifez singur ce scrie pe ea și trec sumele. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am bifat 3 rânduri de pe factură. Verifică-le. / Nu am găsit rânduri de bifat. Bifează de mână. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți bifa și de mână. |
| Already in the binder | Factura e deja în dosar |
| What was done: the checklist | Ce s-a făcut — Atinge ce s-a făcut. Prețul și marca sunt opționale. |
| Its rows | Frâne: Plăcuțe frână față, Plăcuțe frână spate, Discuri frână față, Discuri frână spate, Lichid de frână · Motor: Ulei și filtru de ulei, Distribuție (curea sau lanț), Bujii, Lichid de răcire, Curea de accesorii · Filtre: Filtru de aer, Filtru de habitaclu, Filtru de combustibil · Transmisie: Ambreiaj, Ulei cutie de viteze · Suspensie: Amortizoare · Roți: Anvelope de vară, Anvelope de iarnă, Geometrie roți, Echilibrare roți · Electric: Baterie · Caroserie: Ștergătoare · Climatizare: Încărcare aer condiționat |
| A ticked row asks | Cât a costat, Marcă sau cod (Opțional) · Ultima dată: martie 2026 |
| Rows of one's own | Altceva — Ce nu e în listă. · Ce s-a făcut, Cât a costat · Adaugă altceva |
| The counter | Kilometraj — Cifra gri e doar o estimare. Scrie cifra de la bord, dacă o știi. |
| What it cost | Total plătit — Piesele adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Service-ul — Nume / Altcineva, „Service Exemplu SRL” — Cum a lucrat? |
| Before it can save | Bifează ce s-a făcut sau scrie totalul ca să poți salva. |
| The button | Salvează vizita |
| The toast | Vizita e în istoric. Anulează |

### Locuințe (`home`) · `job`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am chemat un meseriaș |
| „Scriu eu”'s card | Am chemat un meseriaș — Ce s-a lucrat, cine a lucrat, cât a costat. |
| The paper's card | Atașează factura — Bifez singur ce scrie pe ea și trec sumele. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am bifat 3 rânduri de pe factură. Verifică-le. / Nu am găsit rânduri de bifat. Bifează de mână. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți bifa și de mână. |
| Already in the binder | Factura e deja în dosar |
| What was done: the checklist | Ce s-a lucrat — Atinge ce s-a lucrat. Prețul e opțional. |
| Its rows | Încălzire: Centrală termică, Revizie centrală, Calorifere · Instalații sanitare: Robinete și baterii, Boiler electric, Rezervor și WC, Filtru de apă · Gaze: Detector de gaz · Bucătărie: Hotă, Aragaz · Climatizare: Filtre aer condiționat · Electric: Tablou electric · Tâmplărie: Garnituri geamuri |
| A ticked row asks | Cât a costat · Ultima dată: martie 2026 |
| Rows of one's own | Altceva — Ce nu e în listă. · Ce s-a lucrat, Cât a costat · Adaugă altceva |
| What it cost | Cât a costat — Rândurile adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Cine a lucrat — Nume / Altcineva, „Instalator Exemplu SRL” — Cum a lucrat? |
| Before it can save | Bifează ce s-a lucrat sau scrie cât a costat ca să poți salva. |
| The button | Salvează lucrarea |
| The toast | Lucrarea e în istoric. Anulează |

### Acte (`documents`) · `none`

No visits: offered nowhere, and Istoric adds nothing by hand.

### Animale (`pet`) · `vet`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am fost la veterinar |
| „Scriu eu”'s card | Am fost la veterinar — Ce i s-a făcut, la cine, fișa sau rețeta. |
| The paper's card | Atașează fișa sau rețeta — Sau carnetul de vaccinări. Bifez singur ce găsesc scris. |
| Where the photo comes from | Atașează o hârtie de la veterinar: Fotografiază hârtia |
| While it is read | Citesc hârtia… |
| Read | Hârtia e atașată (Am citit hârtia, photo not kept) — Am bifat 3 rânduri de pe hârtie. Verifică-le. / Nu am găsit rânduri de bifat. Bifează de mână. |
| Not read | Hârtia nu s-a citit — Încearcă o poză mai clară. Poți bifa și de mână. |
| Already in the binder | (only the same document, said nothing) |
| What was done: the checklist | Ce i s-a făcut — Atinge ce i s-a făcut. Prețul e opțional. |
| Its rows | Vaccinuri: Vaccin antirabic, Vaccin anual · Paraziți: Deparazitare internă, Deparazitare externă · Îngrijire: Detartraj, Toaletaj · Tratamente: Tratament |
| A ticked row asks | Cât a costat · Ultima dată: martie 2026 |
| Rows of one's own | Altceva — Ce nu e în listă. · Ce i s-a făcut, Cât a costat · Adaugă altceva |
| What it cost | Cât a costat — Dacă ai plătit ceva. — Rândurile adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Veterinarul — Nume / Altcineva, „Cabinet Veterinar Exemplu” — Cum a fost? |
| Before it can save | (saves with its day alone) |
| The button | Salvează vizita |
| The toast | Vizita e în istoric. Anulează |

### Sănătate (`health`) · `doctor`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am fost la medic |
| „Scriu eu”'s card | Am fost la medic — La cine, pentru ce, rețeta sau analizele. |
| The paper's card | Atașează rețeta sau analizele — Sau biletul de trimitere. Le păstrez cu vizita. |
| Where the photo comes from | Atașează o hârtie de la medic: Fotografiază hârtia |
| While it is read | Citesc hârtia… |
| Read | Hârtia e atașată (Am citit hârtia, photo not kept) — Am trecut data, suma și numele de pe ea. Verifică-le. / Am trecut data, suma și numele de pe ea. Verifică-le. |
| Not read | Hârtia nu s-a citit — Încearcă o poză mai clară. Poți scrie și de mână. |
| Already in the binder | (only the same document, said nothing) |
| A note | Pentru ce — Un control, o durere, o trimitere… |
| What it cost | Cât a costat — Dacă ai plătit ceva. — Rândurile adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Medicul sau clinica — Nume / Altcineva, „Clinica Exemplu” — Cum a fost? |
| Before it can save | (saves with its day alone) |
| The button | Salvează vizita |
| The toast | Vizita e în istoric. Anulează |

### Garanții (`purchase`) · `repair`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am dus la reparat |
| „Scriu eu”'s card | Am dus la reparat — Ce s-a reparat, unde, cât a costat. |
| The paper's card | Atașează factura — O păstrez și trec data și suma de pe ea. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am trecut data, suma și numele de pe ea. Verifică-le. / Am trecut data, suma și numele de pe ea. Verifică-le. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți scrie și de mână. |
| Already in the binder | Factura e deja în dosar |
| A note | Ce s-a reparat — Ecranul, bateria, un buton… |
| The warranty, under the date | Era în garanție, până pe 3 mai 2027. / Garanția se terminase pe 3 mai 2027. |
| What it cost | Cât a costat — Lasă gol dacă a fost gratuită. — Rândurile adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Cine a reparat — Nume / Altcineva, „Atelier Exemplu SRL” — Cum a lucrat? |
| Before it can save | Scrie ce s-a reparat sau cât a costat ca să poți salva. |
| The button | Salvează reparația |
| The toast | Reparația e în istoric. Anulează |

### Abonamente (`subscription`) · `none`

No visits: offered nowhere, and Istoric adds nothing by hand.

### Altele (`other`) · `job`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am chemat un meseriaș |
| „Scriu eu”'s card | Am chemat un meseriaș — Ce s-a lucrat, cine a lucrat, cât a costat. |
| The paper's card | Atașează factura — Trec singur rândurile și sumele de pe ea. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am trecut 3 rânduri de pe factură. Verifică-le. / Nu am găsit rânduri pe ea. Scrie-le de mână. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți scrie și de mână. |
| Already in the binder | Factura e deja în dosar |
| Rows of one's own | Ce s-a lucrat — Câte un rând pentru fiecare lucrare. Prețul e opțional. · Ce s-a lucrat, Cât a costat · Adaugă un rând |
| What it cost | Cât a costat — Rândurile adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Cine a lucrat — Nume / Altcineva, „Instalator Exemplu SRL” — Cum a lucrat? |
| Before it can save | Scrie ce s-a lucrat sau cât a costat ca să poți salva. |
| The button | Salvează lucrarea |
| The toast | Lucrarea e în istoric. Anulează |

### Biciclete (`bike`) · `service`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am fost la service |
| „Scriu eu”'s card | Am fost la service — Ce s-a făcut, cât a costat, cine a lucrat. |
| The paper's card | Atașează factura — Bifez singur ce scrie pe ea și trec sumele. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am bifat 3 rânduri de pe factură. Verifică-le. / Nu am găsit rânduri de bifat. Bifează de mână. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți bifa și de mână. |
| Already in the binder | Factura e deja în dosar |
| What was done: the checklist | Ce s-a făcut — Atinge ce s-a făcut. Prețul și marca sunt opționale. |
| Its rows | Transmisie: Lanț, Casetă · Frâne: Plăcuțe de frână · Suspensie: Service furcă · Roți: Anvelope |
| A ticked row asks | Cât a costat, Marcă sau cod (Opțional) · Ultima dată: martie 2026 |
| Rows of one's own | Altceva — Ce nu e în listă. · Ce s-a făcut, Cât a costat · Adaugă altceva |
| The counter | Kilometri parcurși — Cifra gri e doar o estimare. Scrie cifra de la bord, dacă o știi. |
| What it cost | Total plătit — Piesele adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Service-ul — Nume / Altcineva, „Service Exemplu SRL” — Cum a lucrat? |
| Before it can save | Bifează ce s-a făcut sau scrie totalul ca să poți salva. |
| The button | Salvează vizita |
| The toast | Vizita e în istoric. Anulează |

### Plante (`plants`) · `note`

No visits: offered nowhere. Istoric takes a dated note, „Adaugă o notă”.

### Chiriași (`tenancy`) · `none`

No visits: offered nowhere, and Istoric adds nothing by hand.

### Membri ai familiei (`member`) · `none`

No visits: offered nowhere, and Istoric adds nothing by hand.

### Espressoare (`espresso`) · `upkeep`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am făcut o revizie |
| „Scriu eu”'s card | Am făcut o revizie — Ce s-a făcut și cât a costat, dacă a costat. |
| What was done: the checklist | Ce s-a făcut — Atinge ce s-a făcut. Prețul e opțional. |
| Its rows | Întreținere: Decalcifiere, Garnitură grup, Filtru de apă |
| A ticked row asks | Cât a costat · Ultima dată: martie 2026 |
| Rows of one's own | Altceva — Ce nu e în listă. · Ce s-a făcut, Cât a costat · Adaugă altceva |
| What it cost | Cât a costat — Dacă a costat ceva. — Rândurile adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Before it can save | Bifează ce s-a făcut ca să poți salva. |
| The button | Salvează revizia |
| The toast | Revizia e în istoric. Anulează |

### A ta: cu acte, fără facturi, fără revizii · `none`

No visits: offered nowhere, and Istoric adds nothing by hand.

### A ta: cu acte, fără facturi, revizii după timp · `job`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am chemat un meseriaș |
| „Scriu eu”'s card | Am chemat un meseriaș — Ce s-a lucrat, cine a lucrat, cât a costat. |
| The paper's card | Atașează factura — Trec singur rândurile și sumele de pe ea. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am trecut 3 rânduri de pe factură. Verifică-le. / Nu am găsit rânduri pe ea. Scrie-le de mână. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți scrie și de mână. |
| Already in the binder | Factura e deja în dosar |
| Rows of one's own | Ce s-a lucrat — Câte un rând pentru fiecare lucrare. Prețul e opțional. · Ce s-a lucrat, Cât a costat · Adaugă un rând |
| What it cost | Cât a costat — Rândurile adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Cine a lucrat — Nume / Altcineva, „Instalator Exemplu SRL” — Cum a lucrat? |
| Before it can save | Scrie ce s-a lucrat sau cât a costat ca să poți salva. |
| The button | Salvează lucrarea |
| The toast | Lucrarea e în istoric. Anulează |

### A ta: cu acte, fără facturi, revizii după kilometri · `service`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am fost la service |
| „Scriu eu”'s card | Am fost la service — Ce s-a făcut, cât a costat, cine a lucrat. |
| The paper's card | Atașează factura — Trec singur rândurile și sumele de pe ea. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am trecut 3 rânduri de pe factură. Verifică-le. / Nu am găsit rânduri pe ea. Scrie-le de mână. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți scrie și de mână. |
| Already in the binder | Factura e deja în dosar |
| Rows of one's own | Ce s-a făcut — Câte un rând pentru fiecare lucrare. Prețul e opțional. · Ce s-a făcut, Cât a costat · Adaugă un rând |
| The counter | Kilometraj — Cifra gri e doar o estimare. Scrie cifra de la bord, dacă o știi. |
| What it cost | Total plătit — Piesele adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Service-ul — Nume / Altcineva, „Service Exemplu SRL” — Cum a lucrat? |
| Before it can save | Scrie ce s-a făcut sau totalul ca să poți salva. |
| The button | Salvează vizita |
| The toast | Vizita e în istoric. Anulează |

### A ta: cu acte, fără facturi, revizii după ore · `service`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am fost la service |
| „Scriu eu”'s card | Am fost la service — Ce s-a făcut, cât a costat, cine a lucrat. |
| The paper's card | Atașează factura — Trec singur rândurile și sumele de pe ea. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am trecut 3 rânduri de pe factură. Verifică-le. / Nu am găsit rânduri pe ea. Scrie-le de mână. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți scrie și de mână. |
| Already in the binder | Factura e deja în dosar |
| Rows of one's own | Ce s-a făcut — Câte un rând pentru fiecare lucrare. Prețul e opțional. · Ce s-a făcut, Cât a costat · Adaugă un rând |
| The counter | Ore de motor — Cifra gri e doar o estimare. Scrie cifra de la bord, dacă o știi. |
| What it cost | Total plătit — Piesele adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Service-ul — Nume / Altcineva, „Service Exemplu SRL” — Cum a lucrat? |
| Before it can save | Scrie ce s-a făcut sau totalul ca să poți salva. |
| The button | Salvează vizita |
| The toast | Vizita e în istoric. Anulează |

### A ta: cu acte, cu facturi, fără revizii · `none`

No visits: offered nowhere, and Istoric adds nothing by hand.

### A ta: cu acte, cu facturi, revizii după timp · `job`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am chemat un meseriaș |
| „Scriu eu”'s card | Am chemat un meseriaș — Ce s-a lucrat, cine a lucrat, cât a costat. |
| The paper's card | Atașează factura — Trec singur rândurile și sumele de pe ea. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am trecut 3 rânduri de pe factură. Verifică-le. / Nu am găsit rânduri pe ea. Scrie-le de mână. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți scrie și de mână. |
| Already in the binder | Factura e deja în dosar |
| Rows of one's own | Ce s-a lucrat — Câte un rând pentru fiecare lucrare. Prețul e opțional. · Ce s-a lucrat, Cât a costat · Adaugă un rând |
| What it cost | Cât a costat — Rândurile adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Cine a lucrat — Nume / Altcineva, „Instalator Exemplu SRL” — Cum a lucrat? |
| Before it can save | Scrie ce s-a lucrat sau cât a costat ca să poți salva. |
| The button | Salvează lucrarea |
| The toast | Lucrarea e în istoric. Anulează |

### A ta: cu acte, cu facturi, revizii după kilometri · `service`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am fost la service |
| „Scriu eu”'s card | Am fost la service — Ce s-a făcut, cât a costat, cine a lucrat. |
| The paper's card | Atașează factura — Trec singur rândurile și sumele de pe ea. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am trecut 3 rânduri de pe factură. Verifică-le. / Nu am găsit rânduri pe ea. Scrie-le de mână. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți scrie și de mână. |
| Already in the binder | Factura e deja în dosar |
| Rows of one's own | Ce s-a făcut — Câte un rând pentru fiecare lucrare. Prețul e opțional. · Ce s-a făcut, Cât a costat · Adaugă un rând |
| The counter | Kilometraj — Cifra gri e doar o estimare. Scrie cifra de la bord, dacă o știi. |
| What it cost | Total plătit — Piesele adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Service-ul — Nume / Altcineva, „Service Exemplu SRL” — Cum a lucrat? |
| Before it can save | Scrie ce s-a făcut sau totalul ca să poți salva. |
| The button | Salvează vizita |
| The toast | Vizita e în istoric. Anulează |

### A ta: cu acte, cu facturi, revizii după ore · `service`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am fost la service |
| „Scriu eu”'s card | Am fost la service — Ce s-a făcut, cât a costat, cine a lucrat. |
| The paper's card | Atașează factura — Trec singur rândurile și sumele de pe ea. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am trecut 3 rânduri de pe factură. Verifică-le. / Nu am găsit rânduri pe ea. Scrie-le de mână. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți scrie și de mână. |
| Already in the binder | Factura e deja în dosar |
| Rows of one's own | Ce s-a făcut — Câte un rând pentru fiecare lucrare. Prețul e opțional. · Ce s-a făcut, Cât a costat · Adaugă un rând |
| The counter | Ore de motor — Cifra gri e doar o estimare. Scrie cifra de la bord, dacă o știi. |
| What it cost | Total plătit — Piesele adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Service-ul — Nume / Altcineva, „Service Exemplu SRL” — Cum a lucrat? |
| Before it can save | Scrie ce s-a făcut sau totalul ca să poți salva. |
| The button | Salvează vizita |
| The toast | Vizita e în istoric. Anulează |

### A ta: fără acte, fără facturi, fără revizii · `none`

No visits: offered nowhere, and Istoric adds nothing by hand.

### A ta: fără acte, fără facturi, revizii după timp · `job`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am chemat un meseriaș |
| „Scriu eu”'s card | Am chemat un meseriaș — Ce s-a lucrat, cine a lucrat, cât a costat. |
| The paper's card | Atașează factura — Trec singur rândurile și sumele de pe ea. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am trecut 3 rânduri de pe factură. Verifică-le. / Nu am găsit rânduri pe ea. Scrie-le de mână. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți scrie și de mână. |
| Already in the binder | Factura e deja în dosar |
| Rows of one's own | Ce s-a lucrat — Câte un rând pentru fiecare lucrare. Prețul e opțional. · Ce s-a lucrat, Cât a costat · Adaugă un rând |
| What it cost | Cât a costat — Rândurile adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Cine a lucrat — Nume / Altcineva, „Instalator Exemplu SRL” — Cum a lucrat? |
| Before it can save | Scrie ce s-a lucrat sau cât a costat ca să poți salva. |
| The button | Salvează lucrarea |
| The toast | Lucrarea e în istoric. Anulează |

### A ta: fără acte, fără facturi, revizii după kilometri · `service`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am fost la service |
| „Scriu eu”'s card | Am fost la service — Ce s-a făcut, cât a costat, cine a lucrat. |
| The paper's card | Atașează factura — Trec singur rândurile și sumele de pe ea. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am trecut 3 rânduri de pe factură. Verifică-le. / Nu am găsit rânduri pe ea. Scrie-le de mână. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți scrie și de mână. |
| Already in the binder | Factura e deja în dosar |
| Rows of one's own | Ce s-a făcut — Câte un rând pentru fiecare lucrare. Prețul e opțional. · Ce s-a făcut, Cât a costat · Adaugă un rând |
| The counter | Kilometraj — Cifra gri e doar o estimare. Scrie cifra de la bord, dacă o știi. |
| What it cost | Total plătit — Piesele adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Service-ul — Nume / Altcineva, „Service Exemplu SRL” — Cum a lucrat? |
| Before it can save | Scrie ce s-a făcut sau totalul ca să poți salva. |
| The button | Salvează vizita |
| The toast | Vizita e în istoric. Anulează |

### A ta: fără acte, fără facturi, revizii după ore · `service`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am fost la service |
| „Scriu eu”'s card | Am fost la service — Ce s-a făcut, cât a costat, cine a lucrat. |
| The paper's card | Atașează factura — Trec singur rândurile și sumele de pe ea. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am trecut 3 rânduri de pe factură. Verifică-le. / Nu am găsit rânduri pe ea. Scrie-le de mână. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți scrie și de mână. |
| Already in the binder | Factura e deja în dosar |
| Rows of one's own | Ce s-a făcut — Câte un rând pentru fiecare lucrare. Prețul e opțional. · Ce s-a făcut, Cât a costat · Adaugă un rând |
| The counter | Ore de motor — Cifra gri e doar o estimare. Scrie cifra de la bord, dacă o știi. |
| What it cost | Total plătit — Piesele adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Service-ul — Nume / Altcineva, „Service Exemplu SRL” — Cum a lucrat? |
| Before it can save | Scrie ce s-a făcut sau totalul ca să poți salva. |
| The button | Salvează vizita |
| The toast | Vizita e în istoric. Anulează |

### A ta: fără acte, cu facturi, fără revizii · `none`

No visits: offered nowhere, and Istoric adds nothing by hand.

### A ta: fără acte, cu facturi, revizii după timp · `job`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am chemat un meseriaș |
| „Scriu eu”'s card | Am chemat un meseriaș — Ce s-a lucrat, cine a lucrat, cât a costat. |
| The paper's card | Atașează factura — Trec singur rândurile și sumele de pe ea. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am trecut 3 rânduri de pe factură. Verifică-le. / Nu am găsit rânduri pe ea. Scrie-le de mână. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți scrie și de mână. |
| Already in the binder | Factura e deja în dosar |
| Rows of one's own | Ce s-a lucrat — Câte un rând pentru fiecare lucrare. Prețul e opțional. · Ce s-a lucrat, Cât a costat · Adaugă un rând |
| What it cost | Cât a costat — Rândurile adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Cine a lucrat — Nume / Altcineva, „Instalator Exemplu SRL” — Cum a lucrat? |
| Before it can save | Scrie ce s-a lucrat sau cât a costat ca să poți salva. |
| The button | Salvează lucrarea |
| The toast | Lucrarea e în istoric. Anulează |

### A ta: fără acte, cu facturi, revizii după kilometri · `service`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am fost la service |
| „Scriu eu”'s card | Am fost la service — Ce s-a făcut, cât a costat, cine a lucrat. |
| The paper's card | Atașează factura — Trec singur rândurile și sumele de pe ea. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am trecut 3 rânduri de pe factură. Verifică-le. / Nu am găsit rânduri pe ea. Scrie-le de mână. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți scrie și de mână. |
| Already in the binder | Factura e deja în dosar |
| Rows of one's own | Ce s-a făcut — Câte un rând pentru fiecare lucrare. Prețul e opțional. · Ce s-a făcut, Cât a costat · Adaugă un rând |
| The counter | Kilometraj — Cifra gri e doar o estimare. Scrie cifra de la bord, dacă o știi. |
| What it cost | Total plătit — Piesele adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Service-ul — Nume / Altcineva, „Service Exemplu SRL” — Cum a lucrat? |
| Before it can save | Scrie ce s-a făcut sau totalul ca să poți salva. |
| The button | Salvează vizita |
| The toast | Vizita e în istoric. Anulează |

### A ta: fără acte, cu facturi, revizii după ore · `service`

| Where | Words |
| :--- | :--- |
| Its title, in the page's „Adaugă…” and Istoric | Am fost la service |
| „Scriu eu”'s card | Am fost la service — Ce s-a făcut, cât a costat, cine a lucrat. |
| The paper's card | Atașează factura — Trec singur rândurile și sumele de pe ea. |
| Where the photo comes from | Atașează factura: Fotografiază factura |
| While it is read | Citesc factura… |
| Read | Factura e atașată (Am citit factura, photo not kept) — Am trecut 3 rânduri de pe factură. Verifică-le. / Nu am găsit rânduri pe ea. Scrie-le de mână. |
| Not read | Factura nu s-a citit — Încearcă o poză mai clară. Poți scrie și de mână. |
| Already in the binder | Factura e deja în dosar |
| Rows of one's own | Ce s-a făcut — Câte un rând pentru fiecare lucrare. Prețul e opțional. · Ce s-a făcut, Cât a costat · Adaugă un rând |
| The counter | Ore de motor — Cifra gri e doar o estimare. Scrie cifra de la bord, dacă o știi. |
| What it cost | Total plătit — Piesele adună 1.250 RON. Lasă gol dacă ăsta e totalul. |
| Who did it | Service-ul — Nume / Altcineva, „Service Exemplu SRL” — Cum a lucrat? |
| Before it can save | Scrie ce s-a făcut sau totalul ca să poți salva. |
| The button | Salvează vizita |
| The toast | Vizita e în istoric. Anulează |

## „Gata” and „Am rezolvat”

### Mașini (`vehicle`)

| Where | Words |
| :--- | :--- |
| ITP (legal) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Dovada (Opțional. Din ea iau data următoare.) — Fotografiază dovada: Raportul, certificatul sau chitanța. |
| RCA (insurance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Polița nouă (Opțional. Din ea iau data următoare.) — Fotografiază polița: Din ea iau numărul, asigurătorul și data. |
| Rovinietă (legal) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Dovada (Opțional. Din ea iau data următoare.) — Fotografiază dovada: Raportul, certificatul sau chitanța. |
| Revizie periodică (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat.; the counter |
| Schimb de anvelope (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat.; the counter |
| CASCO (insurance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Polița nouă (Opțional. Din ea iau data următoare.) — Fotografiază polița: Din ea iau numărul, asigurătorul și data. |
| Trusă medicală și stingător (legal) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Dovada (Opțional. Din ea iau data următoare.) — Fotografiază dovada: Raportul, certificatul sau chitanța. |

### Locuințe (`home`)

| Where | Words |
| :--- | :--- |
| Verificare centrală (VTP) (legal) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Dovada (Opțional. Din ea iau data următoare.) — Fotografiază dovada: Raportul, certificatul sau chitanța. |
| Verificare instalație de gaze (legal) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Dovada (Opțional. Din ea iau data următoare.) — Fotografiază dovada: Raportul, certificatul sau chitanța. |
| Revizie instalație de gaze (legal) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Dovada (Opțional. Din ea iau data următoare.) — Fotografiază dovada: Raportul, certificatul sau chitanța. |
| Asigurare obligatorie (PAD) (insurance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Polița nouă (Opțional. Din ea iau data următoare.) — Fotografiază polița: Din ea iau numărul, asigurătorul și data. |
| Asigurare facultativă (insurance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Polița nouă (Opțional. Din ea iau data următoare.) — Fotografiază polița: Din ea iau numărul, asigurătorul și data. |
| Impozit pe clădire (tax) | Am rezolvat / Am rezolvat… — Când; Cât ai plătit; Chitanța (Opțional. Îl păstrez în dosar.) — Fotografiază chitanța: Sau dovada plății din aplicația băncii. |
| Curățare coș de fum (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat. |

### Acte (`documents`)

| Where | Words |
| :--- | :--- |
| Reînnoire (renewal) | Am rezolvat / Am rezolvat… — Când; Actul nou (Opțional. Din el iau data la care expiră.) — Fotografiază actul nou: Partea cu data la care expiră.; the new expiry |

### Animale (`pet`)

| Where | Words |
| :--- | :--- |
| Vaccin antirabic (legal) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Dovada (Opțional. Din ea iau data următoare.) — Fotografiază dovada: Raportul, certificatul sau chitanța. |
| Vaccin anual (health) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Rezultatul (Opțional. Îl păstrez în dosar.) — Fotografiază rezultatul: Analizele, rețeta sau carnetul de vaccinări.; a note |
| Deparazitare internă (health) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Rezultatul (Opțional. Îl păstrez în dosar.) — Fotografiază rezultatul: Analizele, rețeta sau carnetul de vaccinări.; a note |
| Deparazitare externă (health) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Rezultatul (Opțional. Îl păstrez în dosar.) — Fotografiază rezultatul: Analizele, rețeta sau carnetul de vaccinări.; a note |
| Toaletaj (routine) | Gata / Gata — nothing: done today, „Adaugă o notă” after |

### Sănătate (`health`)

| Where | Words |
| :--- | :--- |
| Analize anuale (health) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Rezultatul (Opțional. Îl păstrez în dosar.) — Fotografiază rezultatul: Analizele, rețeta sau carnetul de vaccinări.; a note |
| Control stomatologic (health) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Rezultatul (Opțional. Îl păstrez în dosar.) — Fotografiază rezultatul: Analizele, rețeta sau carnetul de vaccinări.; a note |
| Rapel antitetanos (health) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Rezultatul (Opțional. Îl păstrez în dosar.) — Fotografiază rezultatul: Analizele, rețeta sau carnetul de vaccinări.; a note |
| Vaccin antigripal (health) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Rezultatul (Opțional. Îl păstrez în dosar.) — Fotografiază rezultatul: Analizele, rețeta sau carnetul de vaccinări.; a note |
| Card european de sănătate (renewal) | Am rezolvat / Am rezolvat… — Când; Actul nou (Opțional. Din el iau data la care expiră.) — Fotografiază actul nou: Partea cu data la care expiră.; the new expiry |

### Garanții (`purchase`)

| Where | Words |
| :--- | :--- |
| Garanția se termină (renewal) | Am rezolvat / Am rezolvat… — Când; Actul nou (Opțional. Din el iau data la care expiră.) — Fotografiază actul nou: Partea cu data la care expiră.; the new expiry |

### Abonamente (`subscription`)

| Where | Words |
| :--- | :--- |
| Reînnoire anuală (payment) | Am rezolvat / Am rezolvat… — Când; Cât ai plătit; Factura (Opțional. O trec în istoric.) — Fotografiază factura: Cea pe care ai plătit-o. |
| Se termină contractul (renewal) | Am rezolvat / Am rezolvat… — Când; Actul nou (Opțional. Din el iau data la care expiră.) — Fotografiază actul nou: Partea cu data la care expiră.; the new expiry |
| Se termină perioada minimă (renewal) | Am rezolvat / Am rezolvat… — Când; Actul nou (Opțional. Din el iau data la care expiră.) — Fotografiază actul nou: Partea cu data la care expiră.; the new expiry |
| Factura de plătit (payment) | Am rezolvat / Am rezolvat… — Când; Cât ai plătit; Factura (Opțional. O trec în istoric.) — Fotografiază factura: Cea pe care ai plătit-o. |

### Biciclete (`bike`)

| Where | Words |
| :--- | :--- |
| Curățare și ungere lanț (routine) | Gata / Gata — nothing: done today, „Adaugă o notă” after |
| Verificare plăcuțe de frână (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat.; the counter |
| Schimb lanț (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat.; the counter |
| Service suspensie (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat.; the counter |

### Plante (`plants`)

| Where | Words |
| :--- | :--- |
| Udat (routine) | Gata / Gata — nothing: done today, „Adaugă o notă” after |
| Fertilizat (routine) | Gata / Gata — nothing: done today, „Adaugă o notă” after |
| Schimbat ghiveciul (routine) | Gata / Gata — nothing: done today, „Adaugă o notă” after |

### Chiriași (`tenancy`)

| Where | Words |
| :--- | :--- |
| Se termină contractul de închiriere (renewal) | Am rezolvat / Am rezolvat… — Când; Actul nou (Opțional. Din el iau data la care expiră.) — Fotografiază actul nou: Partea cu data la care expiră.; the new expiry |

### Espressoare (`espresso`)

| Where | Words |
| :--- | :--- |
| Curățare grup (routine) | Gata / Gata — nothing: done today, „Adaugă o notă” after |
| Decalcifiere (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat.; the counter |
| Schimb filtru de apă (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat.; the counter |

### A ta: cu acte, fără facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Revizie periodică (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat. |

### A ta: cu acte, fără facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Revizie periodică (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat.; the counter |

### A ta: cu acte, fără facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Revizie periodică (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat.; the counter |

### A ta: cu acte, cu facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Revizie periodică (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat. |

### A ta: cu acte, cu facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Revizie periodică (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat.; the counter |

### A ta: cu acte, cu facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Revizie periodică (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat.; the counter |

### A ta: fără acte, fără facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Revizie periodică (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat. |

### A ta: fără acte, fără facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Revizie periodică (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat.; the counter |

### A ta: fără acte, fără facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Revizie periodică (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat.; the counter |

### A ta: fără acte, cu facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Revizie periodică (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat. |

### A ta: fără acte, cu facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Revizie periodică (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat.; the counter |

### A ta: fără acte, cu facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Revizie periodică (maintenance) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service sau de la cel care a lucrat.; the counter |
