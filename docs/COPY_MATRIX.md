# Copy matrix

What each shaped screen says to each category, generated from the kinds' descriptions: the visit form from `VisitShape` laid over the category (`VisitForm`), „Gata” and „Am rezolvat” from each deadline's `CompletionKind`, the deadline form and a record's page in Istoric (`HistoryEntryShape`), a section page's pockets, adding a section, the capture review by document kind (`CaptureKindProfile`), „Pleci din țară” by citizenship (`TravelRules`), „Vinzi mașina” and „Ai avut o daună” (`ReadinessEngine`), and Abonamente by service (`ServiceKind`). Every built-in category is here, and one category of one's own per combination of its switches. Reviews walk every category through it.

Don't edit it by hand: `CopyMatrixTests` writes it and fails when it is out of date. To bring it up to date, run `TEST_RUNNER_COPY_MATRIX_WRITE=1 ./tests/run_tests.sh` and commit the diff. Sample values: 3 rows, 1.250 de lei, 3 mai 2027. Lei are counted: 1 leu · 2 lei · 19 lei · 20 de lei · 101 lei · 1,50 lei. So are counted units: 1 cafea · 2 cafele · 20 de cafele · 1.250 de cafele · 1 lună · 24 de luni · 10.000 km.

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
| The counter | Kilometraj — Cifra gri e doar o estimare. Scrie kilometrajul, dacă îl știi. |
| What it cost | Total plătit — Piesele adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| What it cost | Cât a costat — Rândurile adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| What it cost | Cât a costat — Dacă ai plătit ceva. — Rândurile adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| What it cost | Cât a costat — Dacă ai plătit ceva. |
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
| What it cost | Cât a costat — Lasă gol dacă a fost gratuită. |
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
| What it cost | Cât a costat — Rândurile adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| The counter | Kilometri parcurși — Cifra gri e doar o estimare. Scrie kilometrajul, dacă îl știi. |
| What it cost | Total plătit — Piesele adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| What it cost | Cât a costat — Dacă a costat ceva. — Rândurile adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| What it cost | Cât a costat — Rândurile adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| The counter | Kilometraj — Cifra gri e doar o estimare. Scrie kilometrajul, dacă îl știi. |
| What it cost | Total plătit — Rândurile adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| The counter | Ore de motor — Cifra gri e doar o estimare. Scrie orele de pe contor, dacă le știi. |
| What it cost | Total plătit — Rândurile adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| What it cost | Cât a costat — Rândurile adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| The counter | Kilometraj — Cifra gri e doar o estimare. Scrie kilometrajul, dacă îl știi. |
| What it cost | Total plătit — Rândurile adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| The counter | Ore de motor — Cifra gri e doar o estimare. Scrie orele de pe contor, dacă le știi. |
| What it cost | Total plătit — Rândurile adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| What it cost | Cât a costat — Rândurile adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| The counter | Kilometraj — Cifra gri e doar o estimare. Scrie kilometrajul, dacă îl știi. |
| What it cost | Total plătit — Rândurile adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| The counter | Ore de motor — Cifra gri e doar o estimare. Scrie orele de pe contor, dacă le știi. |
| What it cost | Total plătit — Rândurile adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| What it cost | Cât a costat — Rândurile adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| The counter | Kilometraj — Cifra gri e doar o estimare. Scrie kilometrajul, dacă îl știi. |
| What it cost | Total plătit — Rândurile adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
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
| The counter | Ore de motor — Cifra gri e doar o estimare. Scrie orele de pe contor, dacă le știi. |
| What it cost | Total plătit — Rândurile adună 1.250 de lei. Dacă e totalul, lasă câmpul gol. |
| Who did it | Service-ul — Nume / Altcineva, „Service Exemplu SRL” — Cum a lucrat? |
| Before it can save | Scrie ce s-a făcut sau totalul ca să poți salva. |
| The button | Salvează vizita |
| The toast | Vizita e în istoric. Anulează |

## „Gata” and „Am rezolvat”

### What every deadline shares

| Where | Words |
| :--- | :--- |
| Its title | Am rezolvat: ITP |
| Where the photo comes from | Alege din poze · Din Fișiere · Renunță · Alege altă poză |
| Not read | Încearcă o poză mai clară, de aproape și fără umbre. |
| A bill read | Am citit factura — O trec în istoricul „Gaze”. |
| Read, with its next date | Următorul termen: 3 mai 2027. |
| What it cost last time | Data trecută: 1.250 de lei. |
| The button | Salvează |
| Not saved | Nu s-a salvat · Poza nu s-a putut deschide. Încearcă din nou. |
| A new end before today, under its field | Alege o zi de după azi. Data aceasta a trecut deja. |
| Closed meanwhile (a reminder, the widget, another device) | Nu s-a salvat — Termenul a fost bifat între timp, dintr-o notificare, din widget sau de pe alt dispozitiv. N-am salvat nimic, iar următorul termen a rămas cum era. |
| The toast | ITP: gata. Următorul termen e pe 3 mai 2027. / ITP: gata. Anulează |

### The household's own (`HouseholdRules`)

| Where | Words |
| :--- | :--- |
| Declarația unică pentru chirii (`rentalDeclaration`) | Am rezolvat / Am rezolvat… — Când; Cât ai plătit; Recipisa (Opțional. O păstrez în dosar.) — Fotografiază recipisa: Dovada că ai depus declarația, din Spațiul Privat Virtual. [Citesc recipisa… / Am citit recipisa / Recipisa nu s-a citit] |

### Mașini (`vehicle`)

| Where | Words |
| :--- | :--- |
| ITP (`itp`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Raportul ITP (Opțional. Din el iau data următoare.) — Fotografiază raportul ITP: Cel primit la stație, cu data următoarei inspecții. [Citesc raportul ITP… / Am citit raportul ITP / Raportul ITP nu s-a citit / Nu am găsit o dată nouă pe el. Îl păstrez oricum.] |
| RCA (`policy`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Polița nouă (Opțional. Din ea iau data următoare.) — Fotografiază polița nouă: Cea primită de la asigurător sau de la broker. [Citesc polița nouă… / Am citit polița nouă / Polița nouă nu s-a citit / Nu am găsit o dată nouă pe ea. O păstrez oricum.] |
| Rovinietă (`vignette`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Rovinieta (Opțional. Din ea iau data următoare.) — Fotografiază rovinieta: Chitanța sau confirmarea primită pe e-mail. [Citesc rovinieta… / Am citit rovinieta / Rovinieta nu s-a citit / Nu am găsit o dată nouă pe ea. O păstrez oricum.] |
| Revizie periodică (`vehicleService`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service-ul care a lucrat. [Citesc factura… / Am citit factura / Factura nu s-a citit]; Kilometraj |
| Schimb de anvelope (`tyreChange`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la vulcanizare. [Citesc factura… / Am citit factura / Factura nu s-a citit]; Kilometraj |
| CASCO (`policy`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Polița nouă (Opțional. Din ea iau data următoare.) — Fotografiază polița nouă: Cea primită de la asigurător sau de la broker. [Citesc polița nouă… / Am citit polița nouă / Polița nouă nu s-a citit / Nu am găsit o dată nouă pe ea. O păstrez oricum.] |
| Trusă medicală și stingător (`safetyKit`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Expiră pe — De aici încep să-ți amintesc din nou. |

### Locuințe (`home`)

| Where | Words |
| :--- | :--- |
| Verificare centrală (VTP) (`boilerCheck`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Procesul-verbal (Opțional. Din el iau data următoare.) — Fotografiază procesul-verbal: De la firma autorizată ISCIR care a verificat centrala. [Citesc procesul-verbal… / Am citit procesul-verbal / Procesul-verbal nu s-a citit / Nu am găsit o dată nouă pe el. Îl păstrez oricum.] |
| Verificare instalație de gaze (`gasCheck`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Procesul-verbal (Opțional. Din el iau data următoare.) — Fotografiază procesul-verbal: De la firma autorizată care a verificat instalația. [Citesc procesul-verbal… / Am citit procesul-verbal / Procesul-verbal nu s-a citit / Nu am găsit o dată nouă pe el. Îl păstrez oricum.] |
| Revizie instalație de gaze (`gasCheck`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Procesul-verbal (Opțional. Din el iau data următoare.) — Fotografiază procesul-verbal: De la firma autorizată care a verificat instalația. [Citesc procesul-verbal… / Am citit procesul-verbal / Procesul-verbal nu s-a citit / Nu am găsit o dată nouă pe el. Îl păstrez oricum.] |
| Asigurare obligatorie (PAD) (`policy`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Polița nouă (Opțional. Din ea iau data următoare.) — Fotografiază polița nouă: Cea primită de la asigurător sau de la broker. [Citesc polița nouă… / Am citit polița nouă / Polița nouă nu s-a citit / Nu am găsit o dată nouă pe ea. O păstrez oricum.] |
| Asigurare facultativă (`policy`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Polița nouă (Opțional. Din ea iau data următoare.) — Fotografiază polița nouă: Cea primită de la asigurător sau de la broker. [Citesc polița nouă… / Am citit polița nouă / Polița nouă nu s-a citit / Nu am găsit o dată nouă pe ea. O păstrez oricum.] |
| Impozit pe clădire (`buildingTax`) | Am rezolvat / Am rezolvat… — Când; Cât ai plătit; Chitanța (Opțional. O păstrez în dosar.) — Fotografiază chitanța: Sau dovada plății din aplicația băncii. [Citesc chitanța… / Am citit chitanța / Chitanța nu s-a citit] |
| Curățare coș de fum (`chimneySweep`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la firma care a curățat coșul. [Citesc factura… / Am citit factura / Factura nu s-a citit] |

### Acte (`documents`)

| Where | Words |
| :--- | :--- |
| Reînnoire (`documentReplaced`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Închid termenul și trec actul acesta ca expirat. Actul nou are altă serie și alt număr, așa că îl adaugi separat, cu poza lui. Once closed: „Ai reînnoit actul” — Cel nou are altă serie și alt număr: adaugă-l ca act nou, cu poza lui. Pe acesta îl poți păstra sau șterge. [Adaugă actul nou · Șterge actul vechi] · the toast's Vezi actul · the badge Expirat |

### Animale (`pet`)

| Where | Words |
| :--- | :--- |
| Vaccin antirabic (`petVaccine`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Carnetul de sănătate (Opțional. Din el iau data următoare.) — Fotografiază carnetul: Pagina cu vaccinul și data rapelului. [Citesc carnetul de sănătate… / Am citit carnetul de sănătate / Carnetul de sănătate nu s-a citit / Nu am găsit o dată nouă pe el. Îl păstrez oricum.] |
| Vaccin anual (`petVaccine`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Carnetul de sănătate (Opțional. Din el iau data următoare.) — Fotografiază carnetul: Pagina cu vaccinul și data rapelului. [Citesc carnetul de sănătate… / Am citit carnetul de sănătate / Carnetul de sănătate nu s-a citit / Nu am găsit o dată nouă pe el. Îl păstrez oricum.] |
| Deparazitare internă (`doneAtHome`) | Am rezolvat / Am rezolvat… — Când; Cât a costat |
| Deparazitare externă (`doneAtHome`) | Am rezolvat / Am rezolvat… — Când; Cât a costat |
| Toaletaj (`chore`) | Gata / Gata — nothing: done today, „Adaugă o notă” after |

### Sănătate (`health`)

| Where | Words |
| :--- | :--- |
| Analize anuale (`checkup`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Rezultatele (Opțional. Le păstrez în dosar.) — Fotografiază rezultatele: Buletinul de analize, de la laborator. [Citesc rezultatele… / Am citit rezultatele / Rezultatele nu s-au citit]; Notă — Ce a spus medicul, ce urmează. |
| Control stomatologic (`dentist`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Notă — Ce s-a făcut, ce urmează. |
| Rapel antitetanos (`vaccine`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Adeverința de vaccinare (Opțional. O păstrez în dosar.) — Fotografiază adeverința: Sau pagina din carnetul de vaccinări. [Citesc adeverința de vaccinare… / Am citit adeverința de vaccinare / Adeverința de vaccinare nu s-a citit] |
| Vaccin antigripal (`vaccine`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Adeverința de vaccinare (Opțional. O păstrez în dosar.) — Fotografiază adeverința: Sau pagina din carnetul de vaccinări. [Citesc adeverința de vaccinare… / Am citit adeverința de vaccinare / Adeverința de vaccinare nu s-a citit] |
| Card european de sănătate (`newHealthCard`) | Am rezolvat / Am rezolvat… — Când; Cardul nou (Opțional. Din el iau data la care expiră.) — Fotografiază cardul nou: Fața, cu data la care expiră. [Citesc cardul nou… / Am citit cardul nou / Cardul nou nu s-a citit / Nu am găsit o dată nouă pe el. Îl păstrez oricum.]; Expiră pe — De aici încep să-ți amintesc din nou. |

### Garanții (`purchase`)

| Where | Words |
| :--- | :--- |
| Garanția se termină (`acknowledged`) | Gata / Gata — nothing: done today, „Adaugă o notă” after |

### Abonamente (`subscription`)

| Where | Words |
| :--- | :--- |
| Reînnoire anuală (`bill`) | Am rezolvat / Am rezolvat… — Când; Cât ai plătit; Factura (Opțional. O trec în istoric.) — Fotografiază factura: Cea pe care ai plătit-o. [Citesc factura… / Am citit factura / Factura nu s-a citit] |
| Se termină contractul (`newContract`) | Am rezolvat / Am rezolvat… — Când; Contractul nou (Opțional. Din el iau data la care se termină.) — Fotografiază contractul nou: Pagina cu perioada contractului. [Citesc contractul nou… / Am citit contractul nou / Contractul nou nu s-a citit / Nu am găsit o dată nouă pe el. Îl păstrez oricum.]; Se termină pe — De aici încep să-ți amintesc din nou. |
| Se termină perioada minimă (`acknowledged`) | Gata / Gata — nothing: done today, „Adaugă o notă” after |
| Factura de plătit (`bill`) | Am rezolvat / Am rezolvat… — Când; Cât ai plătit; Factura (Opțional. O trec în istoric.) — Fotografiază factura: Cea pe care ai plătit-o. [Citesc factura… / Am citit factura / Factura nu s-a citit] |

### Biciclete (`bike`)

| Where | Words |
| :--- | :--- |
| Curățare și ungere lanț (`chore`) | Gata / Gata — nothing: done today, „Adaugă o notă” after |
| Verificare plăcuțe de frână (`bikeService`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service, dacă ai dus-o acolo. [Citesc factura… / Am citit factura / Factura nu s-a citit]; Kilometri parcurși |
| Schimb lanț (`bikeService`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service, dacă ai dus-o acolo. [Citesc factura… / Am citit factura / Factura nu s-a citit]; Kilometri parcurși |
| Service suspensie (`bikeService`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la service, dacă ai dus-o acolo. [Citesc factura… / Am citit factura / Factura nu s-a citit]; Kilometri parcurși |

### Plante (`plants`)

| Where | Words |
| :--- | :--- |
| Udat (`chore`) | Gata / Gata — nothing: done today, „Adaugă o notă” after |
| Fertilizat (`chore`) | Gata / Gata — nothing: done today, „Adaugă o notă” after |
| Schimbat ghiveciul (`chore`) | Gata / Gata — nothing: done today, „Adaugă o notă” after |

### Chiriași (`tenancy`)

| Where | Words |
| :--- | :--- |
| Se termină contractul de închiriere (`newLease`) | Am rezolvat / Am rezolvat… — Când; Contractul nou (Opțional. Din el iau data la care se termină.) — Fotografiază contractul nou: Pagina cu perioada închirierii. [Citesc contractul nou… / Am citit contractul nou / Contractul nou nu s-a citit / Nu am găsit o dată nouă pe el. Îl păstrez oricum.]; Se termină pe — De aici încep să-ți amintesc din nou. |

### Espressoare (`espresso`)

| Where | Words |
| :--- | :--- |
| Curățare grup (`chore`) | Gata / Gata — nothing: done today, „Adaugă o notă” after |
| Decalcifiere (`doneAtHome`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Cafele făcute |
| Schimb filtru de apă (`doneAtHome`) | Am rezolvat / Am rezolvat… — Când; Cât a costat |

### A ta: cu acte, fără facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Revizie periodică (`ownService`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la cel care a lucrat. [Citesc factura… / Am citit factura / Factura nu s-a citit] |

### A ta: cu acte, fără facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Revizie periodică (`ownService`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la cel care a lucrat. [Citesc factura… / Am citit factura / Factura nu s-a citit]; Kilometraj |

### A ta: cu acte, fără facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Revizie periodică (`ownService`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la cel care a lucrat. [Citesc factura… / Am citit factura / Factura nu s-a citit]; Ore de motor |

### A ta: cu acte, cu facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Revizie periodică (`ownService`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la cel care a lucrat. [Citesc factura… / Am citit factura / Factura nu s-a citit] |

### A ta: cu acte, cu facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Revizie periodică (`ownService`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la cel care a lucrat. [Citesc factura… / Am citit factura / Factura nu s-a citit]; Kilometraj |

### A ta: cu acte, cu facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Revizie periodică (`ownService`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la cel care a lucrat. [Citesc factura… / Am citit factura / Factura nu s-a citit]; Ore de motor |

### A ta: fără acte, fără facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Revizie periodică (`ownService`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la cel care a lucrat. [Citesc factura… / Am citit factura / Factura nu s-a citit] |

### A ta: fără acte, fără facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Revizie periodică (`ownService`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la cel care a lucrat. [Citesc factura… / Am citit factura / Factura nu s-a citit]; Kilometraj |

### A ta: fără acte, fără facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Revizie periodică (`ownService`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la cel care a lucrat. [Citesc factura… / Am citit factura / Factura nu s-a citit]; Ore de motor |

### A ta: fără acte, cu facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Revizie periodică (`ownService`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la cel care a lucrat. [Citesc factura… / Am citit factura / Factura nu s-a citit] |

### A ta: fără acte, cu facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Revizie periodică (`ownService`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la cel care a lucrat. [Citesc factura… / Am citit factura / Factura nu s-a citit]; Kilometraj |

### A ta: fără acte, cu facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Revizie periodică (`ownService`) | Am rezolvat / Am rezolvat… — Când; Cât a costat; Factura (Opțional. O păstrez în istoric.) — Fotografiază factura: De la cel care a lucrat. [Citesc factura… / Am citit factura / Factura nu s-a citit]; Ore de motor |

## Adding a deadline

### What every category shares

| Where | Words |
| :--- | :--- |
| Its title | Un termen |
| Which deadline | Ce termen |
| A deadline of one's own | Alt termen — Scrii tu ce e. |
| Its fields | Ce trebuie făcut („O verificare, o plată, o programare”) · Cât de important e: Obligatoriu prin lege, Ține de bani, Ține de sănătate, Doar să nu uit · Se repetă |
| When | Când e termenul — Data |
| The button | Salvează termenul |
| Not saved | Nu s-a salvat |
| Saved | Am adăugat termenul „ITP”. Te anunț cu o lună și cu 7 zile înainte și în ziua termenului. |

### Mașini (`vehicle`)

| Where | Words |
| :--- | :--- |
| ITP | Fără ITP valabil, înmatricularea se suspendă. — Te anunț cu o lună și cu 7 zile înainte. — on its page: Cum cere legea pentru ITP, după vârsta mașinii și cum o folosești. |
| RCA | Cere oferte cu o lună înainte, prețurile diferă mult. — Te anunț cu o lună și cu 7 zile înainte și în ziua termenului. — on its page: În fiecare an, de la data termenului. |
| Rovinietă | Te anunț cu 7 zile înainte și în ziua termenului. — on its page: La fiecare 12 luni, de la data la care l-ai făcut. |
| Revizie periodică | Te anunț cu 14 zile și cu o zi înainte. — on its page: La fiecare 15.000 km sau în fiecare an, ce vine mai întâi. |
| Schimb de anvelope | Te anunț cu 14 zile înainte. — on its page: În fiecare an, pe 15 aprilie și pe 1 noiembrie. |
| CASCO | Te anunț cu o lună și cu 7 zile înainte și în ziua termenului. — on its page: În fiecare an, de la data termenului. |
| Trusă medicală și stingător | Data expirării e pe ambalaj. — Te anunț cu 14 zile înainte și în ziua termenului. — on its page: Nu se repetă. |

### Locuințe (`home`)

| Where | Words |
| :--- | :--- |
| Verificare centrală (VTP) | Obligatorie la cel mult 2 ani, făcută de o firmă autorizată ISCIR. — Te anunț cu o lună și cu 7 zile înainte. — on its page: La fiecare 2 ani, de la data la care l-ai făcut. |
| Verificare instalație de gaze | Te anunț cu o lună și cu 7 zile înainte. — on its page: La fiecare 2 ani, de la data la care l-ai făcut. |
| Revizie instalație de gaze | Te anunț cu 2 luni și cu o lună înainte. — on its page: La fiecare 10 ani, de la data la care l-ai făcut. |
| Asigurare obligatorie (PAD) | Te anunț cu o lună și cu 7 zile înainte și în ziua termenului. — on its page: În fiecare an, de la data termenului. |
| Asigurare facultativă | Te anunț cu o lună și cu 7 zile înainte și în ziua termenului. — on its page: În fiecare an, de la data termenului. |
| Impozit pe clădire | Plata integrală până la 31 martie poate aduce o reducere. — Te anunț cu 14 zile și cu o zi înainte. — on its page: În fiecare an, pe 31 martie și pe 30 septembrie. |
| Curățare coș de fum | Te anunț cu 14 zile înainte și în ziua termenului. — on its page: În fiecare an, de la data la care l-ai făcut. |

### Acte (`documents`)

| Where | Words |
| :--- | :--- |
| Reînnoire | Programările durează. Pentru pașaport, multe țări cer 6 luni de valabilitate. — Te anunț cu 3 luni și cu o lună înainte. — on its page: Nu se repetă. |

### Animale (`pet`)

| Where | Words |
| :--- | :--- |
| Vaccin antirabic | Obligatoriu și cerut la trecerea graniței. — Te anunț cu o zi înainte. — on its page: În fiecare an, de la data la care l-ai făcut. |
| Vaccin anual | Te anunț cu o zi înainte. — on its page: În fiecare an, de la data la care l-ai făcut. |
| Deparazitare internă | Te anunț cu o zi înainte și în ziua termenului. — on its page: La fiecare 3 luni, de la data la care l-ai făcut. |
| Deparazitare externă | Te anunț cu o zi înainte și în ziua termenului. — on its page: În fiecare lună, de la data la care l-ai făcut. |
| Toaletaj | Te anunț cu 2 zile înainte. — on its page: La fiecare 6 săptămâni, de la data la care l-ai făcut. |

### Sănătate (`health`)

| Where | Words |
| :--- | :--- |
| Analize anuale | Te anunț cu 14 zile înainte și în ziua termenului. — on its page: În fiecare an, de la data la care l-ai făcut. |
| Control stomatologic | Te anunț cu 7 zile înainte și în ziua termenului. — on its page: La fiecare 6 luni, de la data la care l-ai făcut. |
| Rapel antitetanos | Te anunț cu o lună înainte și în ziua termenului. — on its page: La fiecare 10 ani, de la data la care l-ai făcut. |
| Vaccin antigripal | Te anunț cu 7 zile înainte și în ziua termenului. — on its page: În fiecare an, pe 15 octombrie. |
| Card european de sănătate | Te anunț cu o lună și cu 7 zile înainte. — on its page: La fiecare 2 ani, de la data la care l-ai făcut. |

### Garanții (`purchase`)

| Where | Words |
| :--- | :--- |
| Garanția se termină | Funcționează totul bine? Acum mai poți reclama gratuit un defect. — Te anunț cu o lună înainte. — on its page: Nu se repetă. |

### Abonamente (`subscription`)

| Where | Words |
| :--- | :--- |
| Reînnoire anuală | Decide dacă îl mai vrei înainte să se plătească singur. — Te anunț cu 14 zile înainte. — on its page: În fiecare an, de la data termenului. |
| Se termină contractul | De obicei prețul crește după. E momentul să ceri o ofertă mai bună. — Te anunț cu o lună înainte. — on its page: Nu se repetă. |
| Se termină perioada minimă | De regulă, de la această dată poți renunța fără penalități, iar contractul se încheie la cel mult o lună după ce anunți. E cel mai bun moment să ceri o ofertă mai bună. — Te anunț cu o lună înainte și în ziua termenului. — on its page: Nu se repetă. |
| Factura de plătit | Data vine de pe ultima factură citită. — Te anunț cu 2 zile înainte și în ziua termenului. — on its page: Nu se repetă. |

### Altele (`other`)

No usual deadlines: only „Alt termen”.

### Biciclete (`bike`)

| Where | Words |
| :--- | :--- |
| Curățare și ungere lanț | Te anunț în ziua termenului. — on its page: La fiecare 150 km sau în fiecare lună, ce vine mai întâi. |
| Verificare plăcuțe de frână | Te anunț cu 3 zile înainte și în ziua termenului. — on its page: La fiecare 1.000 km sau la fiecare 6 luni, ce vine mai întâi. |
| Schimb lanț | Te anunț cu 7 zile înainte și în ziua termenului. — on its page: La fiecare 2.000 km sau în fiecare an, ce vine mai întâi. |
| Service suspensie | Te anunț cu 7 zile înainte. — on its page: În fiecare an, de la data la care l-ai făcut. |

### Plante (`plants`)

| Where | Words |
| :--- | :--- |
| Udat | Te anunț în ziua termenului. — on its page: La fiecare 7 zile, de la data la care l-ai făcut. |
| Fertilizat | Te anunț în ziua termenului. — on its page: În fiecare lună, de la data la care l-ai făcut. |
| Schimbat ghiveciul | Te anunț cu 7 zile înainte. — on its page: La fiecare 2 ani, de la data la care l-ai făcut. |

### Chiriași (`tenancy`)

| Where | Words |
| :--- | :--- |
| Se termină contractul de închiriere | Timp să vorbiți despre prelungire sau să cauți alt chiriaș. — Te anunț cu 2 luni înainte. — on its page: Nu se repetă. |

### Membri ai familiei (`member`)

No usual deadlines: only „Alt termen”.

### Espressoare (`espresso`)

| Where | Words |
| :--- | :--- |
| Curățare grup | Te anunț în ziua termenului. — on its page: La fiecare 100 de cafele sau la fiecare 2 săptămâni, ce vine mai întâi. |
| Decalcifiere | Te anunț cu 3 zile înainte și în ziua termenului. — on its page: La fiecare 300 de cafele sau la fiecare 2 luni, ce vine mai întâi. |
| Schimb filtru de apă | Te anunț cu 3 zile înainte și în ziua termenului. — on its page: La fiecare 2 luni, de la data la care l-ai făcut. |

### A ta: cu acte, fără facturi, fără revizii

No usual deadlines: only „Alt termen”.

### A ta: cu acte, fără facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Revizie periodică | În fiecare an, de la data la care l-ai făcut. — Te anunț cu 14 zile și cu o zi înainte. — on its page: În fiecare an, de la data la care l-ai făcut. |

### A ta: cu acte, fără facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Revizie periodică | La fiecare 10.000 km sau în fiecare an, ce vine mai întâi. — Te anunț cu 14 zile și cu o zi înainte. — on its page: La fiecare 10.000 km sau în fiecare an, ce vine mai întâi. |

### A ta: cu acte, fără facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Revizie periodică | La fiecare 100 h sau în fiecare an, ce vine mai întâi. — Te anunț cu 14 zile și cu o zi înainte. — on its page: La fiecare 100 h sau în fiecare an, ce vine mai întâi. |

### A ta: cu acte, cu facturi, fără revizii

No usual deadlines: only „Alt termen”.

### A ta: cu acte, cu facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Revizie periodică | În fiecare an, de la data la care l-ai făcut. — Te anunț cu 14 zile și cu o zi înainte. — on its page: În fiecare an, de la data la care l-ai făcut. |

### A ta: cu acte, cu facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Revizie periodică | La fiecare 10.000 km sau în fiecare an, ce vine mai întâi. — Te anunț cu 14 zile și cu o zi înainte. — on its page: La fiecare 10.000 km sau în fiecare an, ce vine mai întâi. |

### A ta: cu acte, cu facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Revizie periodică | La fiecare 100 h sau în fiecare an, ce vine mai întâi. — Te anunț cu 14 zile și cu o zi înainte. — on its page: La fiecare 100 h sau în fiecare an, ce vine mai întâi. |

### A ta: fără acte, fără facturi, fără revizii

No usual deadlines: only „Alt termen”.

### A ta: fără acte, fără facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Revizie periodică | În fiecare an, de la data la care l-ai făcut. — Te anunț cu 14 zile și cu o zi înainte. — on its page: În fiecare an, de la data la care l-ai făcut. |

### A ta: fără acte, fără facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Revizie periodică | La fiecare 10.000 km sau în fiecare an, ce vine mai întâi. — Te anunț cu 14 zile și cu o zi înainte. — on its page: La fiecare 10.000 km sau în fiecare an, ce vine mai întâi. |

### A ta: fără acte, fără facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Revizie periodică | La fiecare 100 h sau în fiecare an, ce vine mai întâi. — Te anunț cu 14 zile și cu o zi înainte. — on its page: La fiecare 100 h sau în fiecare an, ce vine mai întâi. |

### A ta: fără acte, cu facturi, fără revizii

No usual deadlines: only „Alt termen”.

### A ta: fără acte, cu facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Revizie periodică | În fiecare an, de la data la care l-ai făcut. — Te anunț cu 14 zile și cu o zi înainte. — on its page: În fiecare an, de la data la care l-ai făcut. |

### A ta: fără acte, cu facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Revizie periodică | La fiecare 10.000 km sau în fiecare an, ce vine mai întâi. — Te anunț cu 14 zile și cu o zi înainte. — on its page: La fiecare 10.000 km sau în fiecare an, ce vine mai întâi. |

### A ta: fără acte, cu facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Revizie periodică | La fiecare 100 h sau în fiecare an, ce vine mai întâi. — Te anunț cu 14 zile și cu o zi înainte. — on its page: La fiecare 100 h sau în fiecare an, ce vine mai întâi. |

## A record in Istoric

### What every record shares

| Where | Words |
| :--- | :--- |
| Notes | Note · Schimbă nota · Adaugă o notă |
| Under the stars, when someone did it | Nota intră în stelele celui care a lucrat. |
| Deleting | Șterge din istoric — Ștergi „Revizie” din istoric? Șterge / Păstrează |
| What deleting does | Termenul revine la 3 mai 2027, ca și cum nu l-ai fi rezolvat. Se șterge și citirea de 45.724 km notată aici. Ce ai atașat rămâne în dosar. |

### Mașini (`vehicle`)

| Where | Words |
| :--- | :--- |
| Vizită la service (`maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? · Nr. 0001 · deleting: Piesele și prețurile notate aici se șterg de pe acest telefon. |
| ITP (`check`, stored as `inspection`) | Ce s-a verificat · Cine a verificat · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| RCA (`policy`, stored as `payment`) | Ce acoperă · Asigurătorul · no rating · Polița nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Rovinietă (`purchase`, stored as `purchase`) | Ce ai cumpărat · De unde · no rating · Factura nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Revizie periodică (`job`, stored as `maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Schimb de anvelope (`job`, stored as `maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| CASCO (`policy`, stored as `payment`) | Ce acoperă · Asigurătorul · no rating · Polița nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Trusă medicală și stingător (`purchase`, stored as `purchase`) | Ce ai cumpărat · De unde · no rating · Factura nr. 0001 · deleting: Termenul rămâne cum e acum. |

### Locuințe (`home`)

| Where | Words |
| :--- | :--- |
| Lucrare (`repair`) | Ce s-a lucrat · Cine a lucrat · Cum a lucrat? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Verificare centrală (VTP) (`check`, stored as `inspection`) | Ce s-a verificat · Cine a verificat · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Verificare instalație de gaze (`check`, stored as `inspection`) | Ce s-a verificat · Cine a verificat · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Revizie instalație de gaze (`check`, stored as `inspection`) | Ce s-a verificat · Cine a verificat · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Asigurare obligatorie (PAD) (`policy`, stored as `payment`) | Ce acoperă · Asigurătorul · no rating · Polița nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Asigurare facultativă (`policy`, stored as `payment`) | Ce acoperă · Asigurătorul · no rating · Polița nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Impozit pe clădire (`tax`, stored as `payment`) | Ce ai plătit · Cui ai plătit · no rating · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Curățare coș de fum (`job`, stored as `maintenance`) | Ce s-a lucrat · Cine a lucrat · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### Acte (`documents`)

| Where | Words |
| :--- | :--- |
| Reînnoire (`renewal`, stored as `note`) | Ce s-a făcut · Cine l-a emis · no rating · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### Animale (`pet`)

| Where | Words |
| :--- | :--- |
| Vizită la veterinar (`visit`) | Ce i s-a făcut · Veterinarul · Cum a fost? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Vaccin antirabic (`vaccination`, stored as `vaccination`) | Ce i s-a făcut · Veterinarul · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Vaccin anual (`vaccination`, stored as `vaccination`) | Ce i s-a făcut · Veterinarul · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Deparazitare internă (`atHome`, stored as `maintenance`) | Ce i s-a făcut · Cine s-a ocupat · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Deparazitare externă (`atHome`, stored as `maintenance`) | Ce i s-a făcut · Cine s-a ocupat · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Toaletaj (`atHome`, stored as `maintenance`) | Ce i s-a făcut · Cine s-a ocupat · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### Sănătate (`health`)

| Where | Words |
| :--- | :--- |
| Vizită la medic (`visit`) | Ce s-a făcut · Medicul sau clinica · Cum a fost? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Analize anuale (`care`, stored as `treatment`) | Ce s-a făcut · Medicul sau clinica · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Control stomatologic (`care`, stored as `treatment`) | Ce s-a făcut · Medicul sau clinica · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Rapel antitetanos (`vaccination`, stored as `vaccination`) | Ce s-a făcut · Medicul sau clinica · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Vaccin antigripal (`vaccination`, stored as `vaccination`) | Ce s-a făcut · Medicul sau clinica · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Card european de sănătate (`renewal`, stored as `note`) | Ce s-a făcut · Cine l-a emis · no rating · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### Garanții (`purchase`)

| Where | Words |
| :--- | :--- |
| Reparație (`repair`) | Ce s-a reparat · Cine a reparat · Cum a lucrat? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Garanția se termină (`acknowledged`, stored as `note`) | Ce ai notat · names no one · no rating · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### Abonamente (`subscription`)

| Where | Words |
| :--- | :--- |
| Reînnoire anuală (`bill`, stored as `payment`) | Ce cuprinde · Cui ai plătit · no rating · Factura nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Se termină contractul (`renewal`, stored as `note`) | Ce s-a făcut · Cu cine l-ai semnat · no rating · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Se termină perioada minimă (`acknowledged`, stored as `note`) | Ce ai notat · names no one · no rating · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Factura de plătit (`bill`, stored as `payment`) | Ce cuprinde · Cui ai plătit · no rating · Factura nr. 0001 · deleting: Termenul rămâne cum e acum. |

### Altele (`other`)

| Where | Words |
| :--- | :--- |
| Lucrare (`repair`) | Ce s-a lucrat · Cine a lucrat · Cum a lucrat? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |

### Biciclete (`bike`)

| Where | Words |
| :--- | :--- |
| Vizită la service (`maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? · Nr. 0001 · deleting: Piesele și prețurile notate aici se șterg de pe acest telefon. |
| Curățare și ungere lanț (`atHome`, stored as `maintenance`) | Ce s-a făcut · Cine s-a ocupat · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Verificare plăcuțe de frână (`job`, stored as `maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Schimb lanț (`job`, stored as `maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Service suspensie (`job`, stored as `maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### Plante (`plants`)

| Where | Words |
| :--- | :--- |
| Notă (`note`) | Ce ai notat · names no one · no rating · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Udat (`atHome`, stored as `maintenance`) | Ce s-a făcut · Cine s-a ocupat · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Fertilizat (`atHome`, stored as `maintenance`) | Ce s-a făcut · Cine s-a ocupat · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Schimbat ghiveciul (`atHome`, stored as `maintenance`) | Ce s-a făcut · Cine s-a ocupat · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### Chiriași (`tenancy`)

| Where | Words |
| :--- | :--- |
| Se termină contractul de închiriere (`renewal`, stored as `note`) | Ce s-a făcut · Cu cine l-ai semnat · no rating · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### Espressoare (`espresso`)

| Where | Words |
| :--- | :--- |
| Revizie (`maintenance`) | Ce s-a făcut · Cine a lucrat · Cum a fost? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Curățare grup (`atHome`, stored as `maintenance`) | Ce s-a făcut · Cine s-a ocupat · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Decalcifiere (`atHome`, stored as `maintenance`) | Ce s-a făcut · Cine s-a ocupat · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |
| Schimb filtru de apă (`atHome`, stored as `maintenance`) | Ce s-a făcut · Cine s-a ocupat · Cum a fost? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### A ta: cu acte, fără facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Lucrare (`repair`) | Ce s-a lucrat · Cine a lucrat · Cum a lucrat? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Revizie periodică (`job`, stored as `maintenance`) | Ce s-a lucrat · Cine a lucrat · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### A ta: cu acte, fără facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Vizită la service (`maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Revizie periodică (`job`, stored as `maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### A ta: cu acte, fără facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Vizită la service (`maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Revizie periodică (`job`, stored as `maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### A ta: cu acte, cu facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Lucrare (`repair`) | Ce s-a lucrat · Cine a lucrat · Cum a lucrat? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Revizie periodică (`job`, stored as `maintenance`) | Ce s-a lucrat · Cine a lucrat · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### A ta: cu acte, cu facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Vizită la service (`maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Revizie periodică (`job`, stored as `maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### A ta: cu acte, cu facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Vizită la service (`maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Revizie periodică (`job`, stored as `maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### A ta: fără acte, fără facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Lucrare (`repair`) | Ce s-a lucrat · Cine a lucrat · Cum a lucrat? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Revizie periodică (`job`, stored as `maintenance`) | Ce s-a lucrat · Cine a lucrat · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### A ta: fără acte, fără facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Vizită la service (`maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Revizie periodică (`job`, stored as `maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### A ta: fără acte, fără facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Vizită la service (`maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Revizie periodică (`job`, stored as `maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### A ta: fără acte, cu facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Lucrare (`repair`) | Ce s-a lucrat · Cine a lucrat · Cum a lucrat? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Revizie periodică (`job`, stored as `maintenance`) | Ce s-a lucrat · Cine a lucrat · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### A ta: fără acte, cu facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Vizită la service (`maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Revizie periodică (`job`, stored as `maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

### A ta: fără acte, cu facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Vizită la service (`maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? · Nr. 0001 · deleting: Ce ai notat aici se șterge de pe acest telefon. |
| Revizie periodică (`job`, stored as `maintenance`) | Ce s-a făcut · Service-ul · Cum a lucrat? (only when someone did it) · Nr. 0001 · deleting: Termenul rămâne cum e acum. |

## The section page's pockets

What a section's page says in its pockets and its „Adaugă…” menu while it holds nothing yet: each pocket's line from `SectionPocket.emptyLine` (Istoric's and Oameni's from the category's visit kind, `VisitKind.pocketWords`), what it adds from `PocketAddition.title`. An empty pocket folds into „Adaugă…” (`SectionPageLayout.foldsEmptyPockets`); its line shows with the way back, or while the person adds to it right there.

### What every page shares

| Where | Words |
| :--- | :--- |
| The menu's row | Adaugă… |
| A pocket named after a category of one's own (a car's „Anvelope”) | Nimic din „Anvelope” trecut aici. — Adaugă în „Anvelope” |
| A section filed under the page | până la 3 mai 2027 / garanție până la 3 mai 2027 |
| A paper in Acte | Expiră pe 3 mai 2027 / A expirat pe 3 mai 2027 / Din 3 mai 2027 |
| A person's „Adaugă un document” (capture decides; a checklist's or the Acte box's files an act) | Un document nou: Fotografiază — Eu văd ce document e. Pentru un act care expiră, îți amintesc la timp. · Din poze — O poză cu documentul, făcută mai demult. · Din Fișiere — Un PDF sau o poză păstrată în Fișiere. · Scriu eu — Pentru un act: alegi ce act e și până când e valabil. / Un act nou: Fotografiază — Fotografiezi actul, iar eu completez ce act e, datele și când expiră. · Din poze — O poză cu actul, făcută mai demult. · Din Fișiere — Un PDF sau o poză păstrată în Fișiere. · Scriu eu — Alegi ce act e și până când e valabil. |
| A paper with no title of its own | Factură, Bon, Poliță, Contract, Certificat, Raport, Act de identitate, Certificat de garanție, Manual, Rețetă, Poză, Document |
| Bani's rows | Pe lună · Ultima factură · În medie, pe factură · În ultimul an · În total · Preț de cumpărare |
| The full lists („Vezi tot”; empty, each says its pocket's line) | Termene · Ultima dată · Tot istoricul · Acte personale · Documente · Arhivate (its line under it is the category's) · Adaugă |
| The full list's suggestions (off, `ObligationListScreen.offersSuggestionRows`) | Poți adăuga — Sugestii pentru „Golful”. Le poți schimba oricând. · Alt termen · Când e următoarea dată pentru „ITP”? Data — De exemplu, data până la care e valabil actul de acum. |

### Mașini (`vehicle`)

| Where | Words |
| :--- | :--- |
| Its visits | `service` |
| Its pockets, in order | Urmează · Acte · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un document (Acte) · Am fost la service (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Acte, empty | Niciun document. Scanează talonul, polița sau raportul ITP și le găsești aici. — Adaugă un document |
| Istoric, empty | Nimic notat încă. După fiecare service, notează aici ce s-a făcut, cât a costat și cine a lucrat. — Am fost la service |
| Oameni, empty | Nimeni încă. Adaugă service-ul sau mecanicul și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, ca talonul, polița sau raportul ITP, păstrate pentru orice eventualitate. |

### Locuințe (`home`)

| Where | Words |
| :--- | :--- |
| Its visits | `job` |
| Its pockets, in order | Urmează · Chiriași · Produse · Abonamente · Plante · Acte · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un chiriaș (Chiriași) · Adaugă un produs (Produse) · Adaugă un abonament (Abonamente) · Adaugă un document (Acte) · Am chemat un meseriaș (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Chiriași, empty | Niciun chiriaș. Adaugă contractul și îți spun când se termină. — Adaugă un chiriaș |
| Produse, empty | Niciun produs. Adaugă aragazul sau centrala și ții minte garanția. — Adaugă un produs |
| Abonamente, empty | Niciun abonament trecut aici. — Adaugă un abonament |
| Plante, empty (not offered until the household keeps them) | Nicio plantă trecută aici. Adaug-o și îți amintesc de udat. — Adaugă o plantă |
| Acte, empty | Niciun document. Scanează polița și o găsești aici. — Adaugă un document |
| Istoric, empty | Nimic notat încă. Când vine un meseriaș, notează aici ce a lucrat, cât a costat și cine a fost. — Am chemat un meseriaș |
| Oameni, empty | Nimeni încă. Adaugă meseriașii la care apelezi și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, ca polița, păstrate pentru orice eventualitate. |

### Acte (`documents`)

| Where | Words |
| :--- | :--- |
| Its visits | `none` |
| Its pockets, in order | Urmează · Acte · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un document (Acte) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Acte, empty | Niciun document. Scanează un act și îl găsești aici. — Adaugă un document |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, păstrate pentru orice eventualitate. |

### Animale (`pet`)

| Where | Words |
| :--- | :--- |
| Its visits | `vet` |
| Its pockets, in order | Urmează · Acte · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un document (Acte) · Am fost la veterinar (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Acte, empty | Niciun document. Scanează un act și îl găsești aici. — Adaugă un document |
| Istoric, empty | Nicio vizită notată încă. După o vizită la veterinar, notează aici ce i s-a făcut, la cine și fișa sau rețeta. — Am fost la veterinar |
| Oameni, empty | Nimeni încă. Adaugă veterinarul și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, păstrate pentru orice eventualitate. |

### Sănătate (`health`)

| Where | Words |
| :--- | :--- |
| Its visits | `doctor` |
| Its pockets, in order | Urmează · Acte · Istoric · Oameni · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un document (Acte) · Am fost la medic (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Acte, empty | Niciun document. Scanează buletinul de analize și îl găsești aici. — Adaugă un document |
| Istoric, empty | Nicio vizită notată încă. După o vizită la medic, notează aici la cine, pentru ce și rețeta sau analizele. — Am fost la medic |
| Oameni, empty | Nimeni încă. Adaugă medicul de familie sau clinica și ai numărul la îndemână. — Adaugă o persoană |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, ca buletinul de analize, păstrate pentru orice eventualitate. |

### Garanții (`purchase`)

| Where | Words |
| :--- | :--- |
| Its visits | `repair` |
| Its pockets, in order | Urmează · Acte · Istoric · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un document (Acte) · Am dus la reparat (Istoric) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Acte, empty | Niciun document. Scanează bonul sau certificatul de garanție și le găsești aici. — Adaugă un document |
| Istoric, empty | Nicio reparație notată încă. După una, notează aici ce s-a reparat, unde și cât a costat. — Am dus la reparat |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, ca bonul sau certificatul de garanție, păstrate pentru orice eventualitate. |

### Abonamente (`subscription`)

| Where | Words |
| :--- | :--- |
| Its visits | `none` |
| Its pockets, in order | Urmează · Acte · Istoric · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un document (Acte) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Acte, empty | Niciun document. Scanează contractul și îl găsești aici. — Adaugă un document |
| Istoric, empty (not drawn until it holds something) | Nimic în istoric încă. Aici apare ce rezolvi la termen, cu data și cât a costat. |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, ca contractul, păstrate pentru orice eventualitate. |

### Altele (`other`)

| Where | Words |
| :--- | :--- |
| Its visits | `job` |
| Its pockets, in order | Urmează · Acte · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un document (Acte) · Am chemat un meseriaș (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Acte, empty | Niciun document. Scanează un act și îl găsești aici. — Adaugă un document |
| Istoric, empty | Nimic notat încă. Când vine un meseriaș, notează aici ce a lucrat, cât a costat și cine a fost. — Am chemat un meseriaș |
| Oameni, empty | Nimeni încă. Adaugă meseriașii la care apelezi și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, păstrate pentru orice eventualitate. |

### Biciclete (`bike`)

| Where | Words |
| :--- | :--- |
| Its visits | `service` |
| Its pockets, in order | Urmează · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Am fost la service (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Istoric, empty | Nimic notat încă. După fiecare service, notează aici ce s-a făcut, cât a costat și cine a lucrat. — Am fost la service |
| Oameni, empty | Nimeni încă. Adaugă service-ul sau mecanicul și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |

### Plante (`plants`)

| Where | Words |
| :--- | :--- |
| Its visits | `note` |
| Its pockets, in order | Urmează · Istoric · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă o notă (Istoric) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Istoric, empty | Nimic notat încă. Notează aici ce observi, cu data: un boboc nou, o mutare la lumină. — Adaugă o notă |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |

### Chiriași (`tenancy`)

| Where | Words |
| :--- | :--- |
| Its visits | `none` |
| Its pockets, in order | Urmează · Acte · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un document (Acte) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Acte, empty | Niciun document. Scanează un act și îl găsești aici. — Adaugă un document |
| Oameni, empty | Nimeni încă. Adaugă pe cine suni când e nevoie și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, păstrate pentru orice eventualitate. |

### Membri ai familiei (`member`)

| Where | Words |
| :--- | :--- |
| Its visits | `none` |
| Its pockets, in order | Urmează · Acte · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un document (Acte) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Acte, empty | Niciun document. Scanează un act și îl găsești aici. — Adaugă un document |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, păstrate pentru orice eventualitate. |

### Espressoare (`espresso`)

| Where | Words |
| :--- | :--- |
| Its visits | `upkeep` |
| Its pockets, in order | Urmează · Istoric · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Am făcut o revizie (Istoric) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Istoric, empty | Nicio revizie notată încă. După una, notează aici ce s-a făcut și cât a costat, dacă a costat. — Am făcut o revizie |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |

### A ta: cu acte, fără facturi, fără revizii

| Where | Words |
| :--- | :--- |
| Its visits | `none` |
| Its pockets, in order | Urmează · Acte · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un document (Acte) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Acte, empty | Niciun document. Scanează un act și îl găsești aici. — Adaugă un document |
| Istoric, empty (not drawn until it holds something) | Nimic în istoric încă. Aici apare ce rezolvi la termen, cu data și cât a costat. |
| Oameni, empty | Nimeni încă. Adaugă pe cine suni când e nevoie și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, păstrate pentru orice eventualitate. |

### A ta: cu acte, fără facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Its visits | `job` |
| Its pockets, in order | Urmează · Acte · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un document (Acte) · Am chemat un meseriaș (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Acte, empty | Niciun document. Scanează un act și îl găsești aici. — Adaugă un document |
| Istoric, empty | Nimic notat încă. Când vine un meseriaș, notează aici ce a lucrat, cât a costat și cine a fost. — Am chemat un meseriaș |
| Oameni, empty | Nimeni încă. Adaugă meseriașii la care apelezi și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, păstrate pentru orice eventualitate. |

### A ta: cu acte, fără facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Its visits | `service` |
| Its pockets, in order | Urmează · Acte · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un document (Acte) · Am fost la service (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Acte, empty | Niciun document. Scanează un act și îl găsești aici. — Adaugă un document |
| Istoric, empty | Nimic notat încă. După fiecare service, notează aici ce s-a făcut, cât a costat și cine a lucrat. — Am fost la service |
| Oameni, empty | Nimeni încă. Adaugă service-ul sau mecanicul și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, păstrate pentru orice eventualitate. |

### A ta: cu acte, fără facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Its visits | `service` |
| Its pockets, in order | Urmează · Acte · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un document (Acte) · Am fost la service (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Acte, empty | Niciun document. Scanează un act și îl găsești aici. — Adaugă un document |
| Istoric, empty | Nimic notat încă. După fiecare service, notează aici ce s-a făcut, cât a costat și cine a lucrat. — Am fost la service |
| Oameni, empty | Nimeni încă. Adaugă service-ul sau mecanicul și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, păstrate pentru orice eventualitate. |

### A ta: cu acte, cu facturi, fără revizii

| Where | Words |
| :--- | :--- |
| Its visits | `none` |
| Its pockets, in order | Urmează · Abonamente · Acte · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un abonament (Abonamente) · Adaugă un document (Acte) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Abonamente, empty | Niciun abonament trecut aici. — Adaugă un abonament |
| Acte, empty | Niciun document. Scanează un act și îl găsești aici. — Adaugă un document |
| Istoric, empty (not drawn until it holds something) | Nimic în istoric încă. Aici apare ce rezolvi la termen, cu data și cât a costat. |
| Oameni, empty | Nimeni încă. Adaugă pe cine suni când e nevoie și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, păstrate pentru orice eventualitate. |

### A ta: cu acte, cu facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Its visits | `job` |
| Its pockets, in order | Urmează · Abonamente · Acte · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un abonament (Abonamente) · Adaugă un document (Acte) · Am chemat un meseriaș (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Abonamente, empty | Niciun abonament trecut aici. — Adaugă un abonament |
| Acte, empty | Niciun document. Scanează un act și îl găsești aici. — Adaugă un document |
| Istoric, empty | Nimic notat încă. Când vine un meseriaș, notează aici ce a lucrat, cât a costat și cine a fost. — Am chemat un meseriaș |
| Oameni, empty | Nimeni încă. Adaugă meseriașii la care apelezi și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, păstrate pentru orice eventualitate. |

### A ta: cu acte, cu facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Its visits | `service` |
| Its pockets, in order | Urmează · Abonamente · Acte · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un abonament (Abonamente) · Adaugă un document (Acte) · Am fost la service (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Abonamente, empty | Niciun abonament trecut aici. — Adaugă un abonament |
| Acte, empty | Niciun document. Scanează un act și îl găsești aici. — Adaugă un document |
| Istoric, empty | Nimic notat încă. După fiecare service, notează aici ce s-a făcut, cât a costat și cine a lucrat. — Am fost la service |
| Oameni, empty | Nimeni încă. Adaugă service-ul sau mecanicul și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, păstrate pentru orice eventualitate. |

### A ta: cu acte, cu facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Its visits | `service` |
| Its pockets, in order | Urmează · Abonamente · Acte · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un abonament (Abonamente) · Adaugă un document (Acte) · Am fost la service (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Abonamente, empty | Niciun abonament trecut aici. — Adaugă un abonament |
| Acte, empty | Niciun document. Scanează un act și îl găsești aici. — Adaugă un document |
| Istoric, empty | Nimic notat încă. După fiecare service, notează aici ce s-a făcut, cât a costat și cine a lucrat. — Am fost la service |
| Oameni, empty | Nimeni încă. Adaugă service-ul sau mecanicul și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |
| Acte's full list, under the archived | Arhivate — Acte vechi, păstrate pentru orice eventualitate. |

### A ta: fără acte, fără facturi, fără revizii

| Where | Words |
| :--- | :--- |
| Its visits | `none` |
| Its pockets, in order | Urmează · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Istoric, empty (not drawn until it holds something) | Nimic în istoric încă. Aici apare ce rezolvi la termen, cu data și cât a costat. |
| Oameni, empty | Nimeni încă. Adaugă pe cine suni când e nevoie și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |

### A ta: fără acte, fără facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Its visits | `job` |
| Its pockets, in order | Urmează · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Am chemat un meseriaș (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Istoric, empty | Nimic notat încă. Când vine un meseriaș, notează aici ce a lucrat, cât a costat și cine a fost. — Am chemat un meseriaș |
| Oameni, empty | Nimeni încă. Adaugă meseriașii la care apelezi și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |

### A ta: fără acte, fără facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Its visits | `service` |
| Its pockets, in order | Urmează · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Am fost la service (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Istoric, empty | Nimic notat încă. După fiecare service, notează aici ce s-a făcut, cât a costat și cine a lucrat. — Am fost la service |
| Oameni, empty | Nimeni încă. Adaugă service-ul sau mecanicul și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |

### A ta: fără acte, fără facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Its visits | `service` |
| Its pockets, in order | Urmează · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Am fost la service (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Istoric, empty | Nimic notat încă. După fiecare service, notează aici ce s-a făcut, cât a costat și cine a lucrat. — Am fost la service |
| Oameni, empty | Nimeni încă. Adaugă service-ul sau mecanicul și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |

### A ta: fără acte, cu facturi, fără revizii

| Where | Words |
| :--- | :--- |
| Its visits | `none` |
| Its pockets, in order | Urmează · Abonamente · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un abonament (Abonamente) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Abonamente, empty | Niciun abonament trecut aici. — Adaugă un abonament |
| Istoric, empty (not drawn until it holds something) | Nimic în istoric încă. Aici apare ce rezolvi la termen, cu data și cât a costat. |
| Oameni, empty | Nimeni încă. Adaugă pe cine suni când e nevoie și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |

### A ta: fără acte, cu facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Its visits | `job` |
| Its pockets, in order | Urmează · Abonamente · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un abonament (Abonamente) · Am chemat un meseriaș (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Abonamente, empty | Niciun abonament trecut aici. — Adaugă un abonament |
| Istoric, empty | Nimic notat încă. Când vine un meseriaș, notează aici ce a lucrat, cât a costat și cine a fost. — Am chemat un meseriaș |
| Oameni, empty | Nimeni încă. Adaugă meseriașii la care apelezi și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |

### A ta: fără acte, cu facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Its visits | `service` |
| Its pockets, in order | Urmează · Abonamente · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un abonament (Abonamente) · Am fost la service (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Abonamente, empty | Niciun abonament trecut aici. — Adaugă un abonament |
| Istoric, empty | Nimic notat încă. După fiecare service, notează aici ce s-a făcut, cât a costat și cine a lucrat. — Am fost la service |
| Oameni, empty | Nimeni încă. Adaugă service-ul sau mecanicul și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |

### A ta: fără acte, cu facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Its visits | `service` |
| Its pockets, in order | Urmează · Abonamente · Istoric · Oameni · Bani · Date importante |
| „Adaugă…” on an empty page | Adaugă un termen (Urmează) · Adaugă un abonament (Abonamente) · Am fost la service (Istoric) · Adaugă o persoană (Oameni) · Adaugă un rând (Date importante) |
| Urmează, empty | Niciun termen. Adaugă unul și îți amintesc la timp. — Adaugă un termen |
| Abonamente, empty | Niciun abonament trecut aici. — Adaugă un abonament |
| Istoric, empty | Nimic notat încă. După fiecare service, notează aici ce s-a făcut, cât a costat și cine a lucrat. — Am fost la service |
| Oameni, empty | Nimeni încă. Adaugă service-ul sau mecanicul și ai numărul la îndemână. — Adaugă o persoană |
| Bani, empty (not drawn until it holds something) | Nicio sumă notată încă. Când notezi ceva cu preț, apare aici. |
| Date importante, empty | Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN. — Adaugă un rând |

## Adding a section

### What every category shares

| Where | Words |
| :--- | :--- |
| The catalog's title | Ce adaugi? |
| Its groups | Cele mai des folosite · Alte categorii |
| A category of one's own | Altceva… — Îi dai tu un nume și alegi ce ține minte. |
| Its step (its questions are `CustomCategoryForm`'s) | Categorie nouă — Continuă |
| The first version's step (off, `CustomSectionStep.offersPocketList`) | Cum se numește, „Barca, Rulota, Pianul” · Ce ține minte: Urmează: Termene, cu amintiri din timp. · Acte: Poze și PDF-uri cu actele și facturile. · Istoric: Ce s-a făcut, când și cât a costat. · Oameni: Cine are grijă de el, cu telefonul lui. · Bani: Cât ai cheltuit pe el. · Date importante: Coduri, numere și tot ce cauți des. · Produse: Lucruri cumpărate, cu garanția lor. · Abonamente: Ce plătești lunar sau anual. |
| The essentials' title | Ce trebuie știut |
| The deadlines' title | Termene — Alege ce vrei să-ți amintesc. Datele le poți schimba oricând. |
| A ticked deadline asks | Următoarea dată |
| Finishing without a category | Alege mai întâi ce vrei să adaugi. |

### Mașini (`vehicle`)

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Mașină — ITP, RCA, rovinietă și revizii, cu kilometrajul la zi. · in „Cele mai des folosite” |
| The essentials' header | Mașini |
| The name, before anything is typed | Nume, „Mașina” |
| Under the name | Cum vrei să apară în dosar, de exemplu „Golful”. |
| What it asks | Număr de înmatriculare · Marcă · Model · An de fabricație · Kilometraj |
| The essentials' button | Continuă |
| A deadline: ITP | Te anunț cu o lună și cu 7 zile înainte. / Fără ITP valabil, înmatricularea se suspendă. — (unticked, its date asked) |
| A deadline: RCA | Te anunț cu o lună și cu 7 zile înainte și în ziua termenului. / Cere oferte cu o lună înainte, prețurile diferă mult. — (unticked, its date asked) |
| A deadline: Rovinietă | Te anunț cu 7 zile înainte și în ziua termenului. — (unticked, its date asked) |
| A deadline: Revizie periodică | Te anunț cu 14 zile și cu o zi înainte. — (ticked) |
| A deadline: Schimb de anvelope | Te anunț cu 14 zile înainte. — (ticked) |
| A deadline: CASCO | Te anunț cu o lună și cu 7 zile înainte și în ziua termenului. — (unticked, its date asked) |
| A deadline: Trusă medicală și stingător | Te anunț cu 14 zile înainte și în ziua termenului. / Data expirării e pe ambalaj. — (unticked, its date asked) |
| Under the deadlines | Pe cele care cer o dată le poți adăuga și mai târziu, din pagina secțiunii sau dintr-o poză a actului. |
| The deadlines' button | Adaugă în dosar |

### Locuințe (`home`)

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Casă sau apartament — Centrală, gaze, asigurare, impozit și contoare. · in „Cele mai des folosite” |
| The essentials' header | Locuințe |
| The name, before anything is typed | Nume, „Locuința” |
| Under the name | Cum vrei să apară în dosar, de exemplu „Apartamentul”. |
| What it asks | Adresă |
| The essentials' button | Continuă |
| A deadline: Verificare centrală (VTP) | Te anunț cu o lună și cu 7 zile înainte. / Obligatorie la cel mult 2 ani, făcută de o firmă autorizată ISCIR. — (unticked, its date asked) |
| A deadline: Verificare instalație de gaze | Te anunț cu o lună și cu 7 zile înainte. — (unticked, its date asked) |
| A deadline: Revizie instalație de gaze | Te anunț cu 2 luni și cu o lună înainte. — (unticked, its date asked) |
| A deadline: Asigurare obligatorie (PAD) | Te anunț cu o lună și cu 7 zile înainte și în ziua termenului. — (unticked, its date asked) |
| A deadline: Asigurare facultativă | Te anunț cu o lună și cu 7 zile înainte și în ziua termenului. — (unticked, its date asked) |
| A deadline: Impozit pe clădire | Te anunț cu 14 zile și cu o zi înainte. / Plata integrală până la 31 martie poate aduce o reducere. — (ticked) |
| A deadline: Curățare coș de fum | Te anunț cu 14 zile înainte și în ziua termenului. — (unticked, its date asked) |
| Under the deadlines | Pe cele care cer o dată le poți adăuga și mai târziu, din pagina secțiunii sau dintr-o poză a actului. |
| The deadlines' button | Adaugă în dosar |

### Acte (`documents`)

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Un act (buletin, pașaport, permis) — Buletin, pașaport, permis, cu reînnoirea din timp. · in „Alte categorii” |
| The essentials' header | Acte |
| The name, before anything is typed | Nume, „Actul” |
| Under the name | Cum vrei să apară în dosar, de exemplu „Buletinul”. |
| What it asks | Tip · Valabil până la |
| Whose it is (added on its own, with people in the binder) | Al cui este — Actele stau grupate pe persoane. |
| The essentials' button | Continuă |
| A deadline: Reînnoire | Te anunț cu 3 luni și cu o lună înainte. / Programările durează. Pentru pașaport, multe țări cer 6 luni de valabilitate. — (unticked, its date asked) |
| Under the deadlines | Pe cele care cer o dată le poți adăuga și mai târziu, din pagina secțiunii sau dintr-o poză a actului. |
| The deadlines' button | Adaugă în dosar |

### Animale (`pet`)

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Animal de companie — Vaccinuri, deparazitări, greutate și veterinar. · in „Cele mai des folosite” |
| The essentials' header | Animale |
| The name, before anything is typed | Nume, „Animalul” |
| Under the name | Cum vrei să apară în dosar, de exemplu „PawPaw”. |
| What it asks | Specie · Data nașterii |
| The essentials' button | Continuă |
| A deadline: Vaccin antirabic | Te anunț cu o zi înainte. / Obligatoriu și cerut la trecerea graniței. — (unticked, its date asked) |
| A deadline: Vaccin anual | Te anunț cu o zi înainte. — (unticked, its date asked) |
| A deadline: Deparazitare internă | Te anunț cu o zi înainte și în ziua termenului. — (ticked) |
| A deadline: Deparazitare externă | Te anunț cu o zi înainte și în ziua termenului. — (ticked) |
| A deadline: Toaletaj | Te anunț cu 2 zile înainte. — (unticked) |
| Under the deadlines | Pe cele care cer o dată le poți adăuga și mai târziu, din pagina secțiunii sau dintr-o poză a actului. |
| The deadlines' button | Adaugă în dosar |

### Sănătate (`health`)

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Sănătate — Analize, controale, vaccinuri și date de urgență. · in „Alte categorii” |
| The essentials' header | Sănătate |
| The name, before anything is typed | Nume, „Fișa medicală” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | (nothing) — Detaliile le completezi oricând din pagina secțiunii, cu Editează. |
| The essentials' button | Continuă |
| A deadline: Analize anuale | Te anunț cu 14 zile înainte și în ziua termenului. — (ticked) |
| A deadline: Control stomatologic | Te anunț cu 7 zile înainte și în ziua termenului. — (ticked) |
| A deadline: Rapel antitetanos | Te anunț cu o lună înainte și în ziua termenului. — (unticked, its date asked) |
| A deadline: Vaccin antigripal | Te anunț cu 7 zile înainte și în ziua termenului. — (unticked) |
| A deadline: Card european de sănătate | Te anunț cu o lună și cu 7 zile înainte. — (unticked, its date asked) |
| Under the deadlines | Pe cele care cer o dată le poți adăuga și mai târziu, din pagina secțiunii. |
| The deadlines' button | Adaugă în dosar |

### Garanții (`purchase`)

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Produs cu garanție — Ce ai cumpărat, cât a costat și până când e în garanție. · in „Cele mai des folosite” |
| The essentials' header | Garanții |
| The name, before anything is typed | Nume, „Produsul” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | Magazin · Data cumpărării · Preț |
| The essentials' button | Continuă |
| A deadline: Garanția se termină | Te anunț cu o lună înainte. / Funcționează totul bine? Acum mai poți reclama gratuit un defect. — (unticked, its date asked) |
| Under the deadlines | Pe cele care cer o dată le poți adăuga și mai târziu, din pagina secțiunii sau dintr-o poză a actului. |
| The deadlines' button | Adaugă în dosar |

### Abonamente (`subscription`)

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Abonament — Telefon, internet, gaze și curent: facturile și contractele lor. · in „Cele mai des folosite” |
| The essentials' header | Abonamente |
| The name, before anything is typed | Nume, „Abonamentul” |
| Under the name | Cum vrei să apară în dosar, de exemplu „Internetul”. |
| What it asks | Furnizor · Preț · Se plătește |
| Where it goes (added on its own, with some in the binder) | Locuința — Apare și pe pagina locuinței. Poți schimba oricând, cu „Mută la…”. |
| The essentials' button | Continuă |
| A deadline: Reînnoire anuală | Te anunț cu 14 zile înainte. / Decide dacă îl mai vrei înainte să se plătească singur. — (offered only when Se plătește is „Anual”) |
| A deadline: Se termină contractul | Te anunț cu o lună înainte. / De obicei prețul crește după. E momentul să ceri o ofertă mai bună. — (unticked, its date asked) |
| A deadline: Se termină perioada minimă | Te anunț cu o lună înainte și în ziua termenului. / De regulă, de la această dată poți renunța fără penalități, iar contractul se încheie la cel mult o lună după ce anunți. E cel mai bun moment să ceri o ofertă mai bună. — (unticked, its date asked) |
| A deadline: Factura de plătit | Te anunț cu 2 zile înainte și în ziua termenului. / Data vine de pe ultima factură citită. — (unticked, its date asked) |
| Under the deadlines | Pe cele care cer o dată le poți adăuga și mai târziu, din pagina secțiunii sau dintr-o poză a actului. |
| The deadlines' button | Adaugă în dosar |

### Altele (`other`)

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Altele — Orice altceva, cu scadențele tale. · in „Alte categorii” |
| The essentials' header | Altele |
| The name, before anything is typed | Nume, „Obiectul” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | (nothing) — Detaliile le completezi oricând din pagina secțiunii, cu Editează. |
| The essentials' button | Adaugă în dosar |

### Biciclete (`bike`)

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Biciclete — Lanț, frâne și service, după kilometri. · in „Alte categorii” |
| The essentials' header | Biciclete |
| The name, before anything is typed | Nume, „Bicicleta” |
| Under the name | Cum vrei să apară în dosar, de exemplu „Bicicleta de oraș”. |
| What it asks | Marcă · Kilometri parcurși |
| The essentials' button | Continuă |
| A deadline: Curățare și ungere lanț | Te anunț în ziua termenului. — (ticked) |
| A deadline: Verificare plăcuțe de frână | Te anunț cu 3 zile înainte și în ziua termenului. — (ticked) |
| A deadline: Schimb lanț | Te anunț cu 7 zile înainte și în ziua termenului. — (ticked) |
| A deadline: Service suspensie | Te anunț cu 7 zile înainte. — (unticked) |
| The deadlines' button | Adaugă în dosar |

### Plante (`plants`)

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Plante — Udat, fertilizat și schimbat ghiveciul. · in „Alte categorii” |
| The essentials' header | Plante |
| The name, before anything is typed | Nume, „Planta” |
| Under the name | Cum vrei să apară în dosar, de exemplu „Ficusul din sufragerie”. |
| What it asks | Specie |
| Where it goes (added on its own, with some in the binder) | Locuința — Apare și pe pagina locuinței. Poți schimba oricând, cu „Mută la…”. |
| The essentials' button | Continuă |
| A deadline: Udat | Te anunț în ziua termenului. — (ticked) |
| A deadline: Fertilizat | Te anunț în ziua termenului. — (ticked) |
| A deadline: Schimbat ghiveciul | Te anunț cu 7 zile înainte. — (unticked) |
| The deadlines' button | Adaugă în dosar |

### Chiriași (`tenancy`)

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Chiriași — Contractul, chiria, garanția și indexurile la mutare. · (not offered: added from its parent section's page) |
| The essentials' header | Chiriași |
| The name, before anything is typed | Nume, „Chiriașul” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | Început contract · Sfârșit contract · Chirie lunară |
| The essentials' button | Continuă |
| A deadline: Se termină contractul de închiriere | Te anunț cu 2 luni înainte. / Timp să vorbiți despre prelungire sau să cauți alt chiriaș. — (unticked, its date asked) |
| Under the deadlines | Pe cele care cer o dată le poți adăuga și mai târziu, din pagina secțiunii. |
| The deadlines' button | Adaugă în dosar |

### Membri ai familiei (`member`)

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Actele unei persoane — Actele fiecărei persoane, la un loc. · in „Cele mai des folosite” |
| The essentials' header | Membri ai familiei |
| The name, before anything is typed | Nume, „Persoana” |
| Under the name | Cum vrei să apară în dosar, de exemplu „Mama”. |
| What it asks | (nothing) — Detaliile le completezi oricând din pagina secțiunii, cu Editează. |
| The essentials' button | Adaugă în dosar |

### Espressoare (`espresso`)

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Espressoare — Curățare, decalcifiere și filtre, după numărul de cafele. · in „Alte categorii” |
| The essentials' header | Espressoare |
| The name, before anything is typed | Nume, „Espressorul” |
| Under the name | Cum vrei să apară în dosar, de exemplu „Espressorul din bucătărie”. |
| What it asks | Marcă |
| The essentials' button | Continuă |
| A deadline: Curățare grup | Te anunț în ziua termenului. — (ticked) |
| A deadline: Decalcifiere | Te anunț cu 3 zile înainte și în ziua termenului. — (ticked) |
| A deadline: Schimb filtru de apă | Te anunț cu 3 zile înainte și în ziua termenului. — (ticked) |
| The deadlines' button | Adaugă în dosar |

### A ta: cu acte, fără facturi, fără revizii

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Barca · in „Alte categorii” |
| The essentials' header | Barca |
| The name, before anything is typed | Nume, „Barca” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | (nothing) |
| The essentials' button | Adaugă în dosar |

### A ta: cu acte, fără facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Barca · in „Alte categorii” |
| The essentials' header | Barca |
| The name, before anything is typed | Nume, „Barca” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | (nothing) |
| The essentials' button | Continuă |
| A deadline: Revizie periodică | Te anunț cu 14 zile și cu o zi înainte. / În fiecare an, de la data la care l-ai făcut. — (ticked) |
| The deadlines' button | Adaugă în dosar |

### A ta: cu acte, fără facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Barca · in „Alte categorii” |
| The essentials' header | Barca |
| The name, before anything is typed | Nume, „Barca” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | Kilometraj |
| The essentials' button | Continuă |
| A deadline: Revizie periodică | Te anunț cu 14 zile și cu o zi înainte. / La fiecare 10.000 km sau în fiecare an, ce vine mai întâi. — (ticked) |
| The deadlines' button | Adaugă în dosar |

### A ta: cu acte, fără facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Barca · in „Alte categorii” |
| The essentials' header | Barca |
| The name, before anything is typed | Nume, „Barca” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | Ore de motor |
| The essentials' button | Continuă |
| A deadline: Revizie periodică | Te anunț cu 14 zile și cu o zi înainte. / La fiecare 100 h sau în fiecare an, ce vine mai întâi. — (ticked) |
| The deadlines' button | Adaugă în dosar |

### A ta: cu acte, cu facturi, fără revizii

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Barca · in „Alte categorii” |
| The essentials' header | Barca |
| The name, before anything is typed | Nume, „Barca” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | (nothing) |
| The essentials' button | Adaugă în dosar |

### A ta: cu acte, cu facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Barca · in „Alte categorii” |
| The essentials' header | Barca |
| The name, before anything is typed | Nume, „Barca” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | (nothing) |
| The essentials' button | Continuă |
| A deadline: Revizie periodică | Te anunț cu 14 zile și cu o zi înainte. / În fiecare an, de la data la care l-ai făcut. — (ticked) |
| The deadlines' button | Adaugă în dosar |

### A ta: cu acte, cu facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Barca · in „Alte categorii” |
| The essentials' header | Barca |
| The name, before anything is typed | Nume, „Barca” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | Kilometraj |
| The essentials' button | Continuă |
| A deadline: Revizie periodică | Te anunț cu 14 zile și cu o zi înainte. / La fiecare 10.000 km sau în fiecare an, ce vine mai întâi. — (ticked) |
| The deadlines' button | Adaugă în dosar |

### A ta: cu acte, cu facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Barca · in „Alte categorii” |
| The essentials' header | Barca |
| The name, before anything is typed | Nume, „Barca” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | Ore de motor |
| The essentials' button | Continuă |
| A deadline: Revizie periodică | Te anunț cu 14 zile și cu o zi înainte. / La fiecare 100 h sau în fiecare an, ce vine mai întâi. — (ticked) |
| The deadlines' button | Adaugă în dosar |

### A ta: fără acte, fără facturi, fără revizii

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Barca · in „Alte categorii” |
| The essentials' header | Barca |
| The name, before anything is typed | Nume, „Barca” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | (nothing) |
| The essentials' button | Adaugă în dosar |

### A ta: fără acte, fără facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Barca · in „Alte categorii” |
| The essentials' header | Barca |
| The name, before anything is typed | Nume, „Barca” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | (nothing) |
| The essentials' button | Continuă |
| A deadline: Revizie periodică | Te anunț cu 14 zile și cu o zi înainte. / În fiecare an, de la data la care l-ai făcut. — (ticked) |
| The deadlines' button | Adaugă în dosar |

### A ta: fără acte, fără facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Barca · in „Alte categorii” |
| The essentials' header | Barca |
| The name, before anything is typed | Nume, „Barca” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | Kilometraj |
| The essentials' button | Continuă |
| A deadline: Revizie periodică | Te anunț cu 14 zile și cu o zi înainte. / La fiecare 10.000 km sau în fiecare an, ce vine mai întâi. — (ticked) |
| The deadlines' button | Adaugă în dosar |

### A ta: fără acte, fără facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Barca · in „Alte categorii” |
| The essentials' header | Barca |
| The name, before anything is typed | Nume, „Barca” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | Ore de motor |
| The essentials' button | Continuă |
| A deadline: Revizie periodică | Te anunț cu 14 zile și cu o zi înainte. / La fiecare 100 h sau în fiecare an, ce vine mai întâi. — (ticked) |
| The deadlines' button | Adaugă în dosar |

### A ta: fără acte, cu facturi, fără revizii

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Barca · in „Alte categorii” |
| The essentials' header | Barca |
| The name, before anything is typed | Nume, „Barca” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | (nothing) |
| The essentials' button | Adaugă în dosar |

### A ta: fără acte, cu facturi, revizii după timp

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Barca · in „Alte categorii” |
| The essentials' header | Barca |
| The name, before anything is typed | Nume, „Barca” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | (nothing) |
| The essentials' button | Continuă |
| A deadline: Revizie periodică | Te anunț cu 14 zile și cu o zi înainte. / În fiecare an, de la data la care l-ai făcut. — (ticked) |
| The deadlines' button | Adaugă în dosar |

### A ta: fără acte, cu facturi, revizii după kilometri

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Barca · in „Alte categorii” |
| The essentials' header | Barca |
| The name, before anything is typed | Nume, „Barca” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | Kilometraj |
| The essentials' button | Continuă |
| A deadline: Revizie periodică | Te anunț cu 14 zile și cu o zi înainte. / La fiecare 10.000 km sau în fiecare an, ce vine mai întâi. — (ticked) |
| The deadlines' button | Adaugă în dosar |

### A ta: fără acte, cu facturi, revizii după ore

| Where | Words |
| :--- | :--- |
| Its option in the catalog | Barca · in „Alte categorii” |
| The essentials' header | Barca |
| The name, before anything is typed | Nume, „Barca” |
| Under the name | Cum vrei să apară în dosar. |
| What it asks | Ore de motor |
| The essentials' button | Continuă |
| A deadline: Revizie periodică | Te anunț cu 14 zile și cu o zi înainte. / La fiecare 100 h sau în fiecare an, ce vine mai întâi. — (ticked) |
| The deadlines' button | Adaugă în dosar |

## A category of one's own

What `CustomCategoryForm` asks when a category of one's own is made („Altceva…”) or changed in Setări, from `CustomCategoryWording` and each counter's words (`CategorySwitches.Counter`). Its name is what one of its sections is called (`TemplateDefinition.sectionName`), so a new section's name before anything is typed is the category's own; no gender is guessed from it.

### What every category of one's own shares

| Where | Words |
| :--- | :--- |
| Its name | Cum se numește, „Barca, Rulota, Pianul” · Simbol |
| What it keeps | Ce ține minte — Are acte: Poze și PDF-uri: acte, contracte, garanții. · Are facturi și contracte: Abonamente cu facturile lor, ca la o locuință: curent, internet, loc de parcare. · Are revizii sau lucrări: Le notezi în istoric și îți amintesc din timp, ca la mașină. |
| How the service counts (VoiceOver) | Revizia se face |
| How often, not a whole number | Scrie un număr întreg, mai mare ca zero. |
| Ține de… | Ține de… — Nimic · O locuință — Fiecare apare și pe pagina celei de care ține și se adaugă și de acolo. (Ține de) |
| Its boxes | Pe ecranul Dosar — Câte o cutie pentru fiecare: Ca la mașini: fiecare are cutia ei. · O cutie pentru toate: Ca la plante: toate stau la un loc. |
| Its line in Setări | Acte / Acte · Facturi și contracte · Revizii după kilometri |

### What its service counts by

| Where | Words |
| :--- | :--- |
| `yearly` | După timp — Fără contor, de obicei o dată pe an: un pian, o centrală. · La câte luni? — Îți amintesc din timp de fiecare revizie. · in Setări: Revizii după timp |
| `kilometres` | După kilometri — Ții kilometrajul la zi: o rulotă, o motocicletă. · La câți km? — Sau o dată pe an, ce vine întâi. · in Setări: Revizii după kilometri |
| `engineHours` | După orele de motor — Ții orele la zi: o barcă, un generator. · La câte ore? — Sau o dată pe an, ce vine întâi. · in Setări: Revizii după ore |

## The capture review

What the review says to each kind of document, from the kind's description (`CaptureKindProfile`: its title, its noun and the pronoun it takes, what its day means) and what saving does (`CaptureFilingPlan`, said by `CaptureReminderPreview`). Samples: nothing in the binder, read on 2 noiembrie 2026, its day on 10 iunie 2027 or, passed, 10 mai 2026.

### What every kind shares

| Where | Words |
| :--- | :--- |
| The screen | Verifică actul · Salvează · Nu s-a salvat |
| From De verificat | Mai târziu · Șterge din De verificat · Ce ai schimbat nu se salvează. Actul rămâne în De verificat. |
| The thumbnail (VoiceOver) | Vezi actul mare — Se deschide pe tot ecranul. Poți mări sau roti pagina. |
| Its kind | Nu e asta? Schimbă · Ce act e · Pe telefon părea: Pașaport · Codul de jos al actului arată: Pașaport |
| How it was read | Citit pe telefon. Nimic n-a plecat de aici. / Citit pe telefon, cu Apple Intelligence. / Citit și cu Gemini, cu cheia ta. |
| The photo's frame | Am păstrat doar actul, fără ce e în jur. Folosește poza întreagă / Se păstrează poza întreagă. Doar actul |
| Where it goes | Alege alta · Verifică: Adresa locului de consum seamănă cu cea a locuinței, dar nu e chiar aceeași. / Adresa locului de consum nu e cea a locuinței. · a home's policy: Adresa din poliță seamănă cu cea a locuinței, dar nu e chiar aceeași. / Adresa din poliță nu e cea a locuinței. |
| Kept in no section | Doar păstrez actul — Îl găsești în Caută. |
| Filed under a section | Actul stă la actele acestei persoane. / La abonamentul „Gaze Apartament” / Abonament nou aici: Gaze Apartament / Abonament la Apartament |
| A new section | Persoană nouă: Exemplu Ion — Se adaugă în Acte când salvezi. / Abonament nou: Gaze Apartament / Secțiune nouă în Mașini — Se creează când salvezi. / Se creează când salvezi, cu abonamentul „Gaze Apartament”. |
| A new section's name | Numele persoanei / Numele abonamentului / Numele locuinței / Numele secțiunii noi |
| A section that has gone | Secțiune ștearsă |
| The place picker | Doar păstrez actul — Fără secțiune; îl găsești în Caută. · Persoană nouă — Actele stau grupate pe persoane. · Secțiune nouă în „Mașini” — Completezi ce trebuie, apoi pun actul acolo. · Altă secțiune… — Toate secțiunile din dosar. |
| The place picker, every section | Toate secțiunile · Secțiune nouă — Alegi ce fel de secțiune, apoi pun actul acolo. · Ce fel de secțiune · Exemplu · La abonamentul de aici, sau unul nou · Ales · Închide |
| When it reminds | Când te anunț · Schimbă ziua (Arată ziua de pe act, ca s-o poți schimba.) · Poți schimba după, pe pagina termenului. |
| More notices | Mai e o observație / Mai sunt 2 observații |
| The same photo | Ai mai adăugat poza asta — Dacă salvezi, o pun la locul ales, împreună cu ce am citit. Vezi unde e acum |
| The card's back | Fotografiază spatele · Alege din poze · Citesc și spatele… · Nu am putut citi spatele · Poza nu s-a putut deschide. Încearcă din nou. |
| The code didn't read | Verifică numărul și datele — Codul de jos al actului nu s-a citit sigur. |
| The provider didn't read it | Google Gemini nu a citit actul |
| Hard to read | Poza e greu de citit — O poză nouă, dreaptă și fără reflexii, ajută. |
| A long PDF | Am citit primele 10 pagini — E un document lung. Se păstrează tot, cu toate paginile. |
| Sending the photo | Trimit poza la Google Gemini? Nu sunt sigur ce am citit. Google Gemini poate citi actul mai bine, cu cheia ta. Fără un da, poza rămâne pe telefon. · Trimite poza / Nu, rămâne pe telefon · Cum folosește Google Gemini ce trimiți |
| Reading it again | Citește mai bine cu Gemini · Citesc cu Gemini… |
| What was read | Ce am citit — Verifică ce e marcat. · Numele actului · Nu am găsit pe act: Adaugă: Total |
| Where a value came from | Din act: „Total de plată 245,30” (Citit din: Total de plată 245,30) |
| Another reader's value | Pe telefon am citit: 123456 / Gemini a citit: 123456 / Modelul tău a citit: 123456 · Folosește-l (Folosește: Pe telefon am citit: 123456) |
| A photo kept only on request: a bank card | Poza cardului — Păstrează și poza cardului — Păstrez doar banca, tipul cardului, ultimele 4 cifre și data expirării. Poza și numărul întreg nu se păstrează. / Poza arată numărul întreg al cardului. O păstrez în dosar, protejată ca restul actelor. |
| A photo kept only on request: a page with a card's number | Poza actului — Păstrează și poza actului — Poza arată numărul întreg al unui card, așa că nu o păstrez. Păstrez ce am citit pe act, cu numărul cardului ascuns. / Poza arată numărul întreg al unui card. O păstrez în dosar, protejată ca restul actelor. |

### Pașaport (`passport`)

| Where | Words |
| :--- | :--- |
| Its title | Pașaport |
| Where it goes: the summary's heading and the picker's title | Unde îl pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Acte — Se creează când salvezi. — field „Numele secțiunii noi” |
| What its day means | Expiră pe 3 mai 2027. |
| When it reminds, its day to come | Expiră pe 10 iunie 2027. Bun de călătorit până pe 10 decembrie. Te anunț cu 3 luni înainte de ultima zi bună de călătorit și în ziua aceea. |
| Its place not chosen yet | Expiră pe 10 iunie 2027. Alege unde îl pui ca să te anunț din timp. |
| Its day passed | A expirat pe 10 mai. A fost bun de călătorit până pe 10 noiembrie 2025. Data a trecut, așa că termenul apare de acum în Urmează. |
| Nothing read off it | Nu am găsit date în pașaport. Îl păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | În pașaport scrie: 123456 |
| What its machine-readable code says | În codul de jos al actului scrie: 123456 |
| Under „Citește mai bine” | Poza actului se trimite la Google Gemini, cu cheia ta. |

### Carte de identitate (`identityCard`)

| Where | Words |
| :--- | :--- |
| Its title | Carte de identitate |
| Where it goes: the summary's heading and the picker's title | Unde o pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Acte — Se creează când salvezi. — field „Numele secțiunii noi” |
| What its day means | Expiră pe 3 mai 2027. |
| When it reminds, its day to come | Expiră pe 10 iunie 2027. Te anunț cu 3 luni și cu o lună înainte. |
| Its place not chosen yet | Expiră pe 10 iunie 2027. Alege unde o pui ca să te anunț din timp. |
| Its day passed | A expirat pe 10 mai. Data a trecut, așa că termenul apare de acum în Urmează. |
| Nothing read off it | Nu am găsit date pe cartea de identitate. O păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | Pe cartea de identitate scrie: 123456 |
| What its machine-readable code says | Pe spatele actului scrie: 123456 |
| Its back | Ai și o poză cu spatele? Acolo e codul care confirmă datele. |
| Under „Citește mai bine” | Poza actului se trimite la Google Gemini, cu cheia ta. |

### Permis de ședere (`residencePermit`)

| Where | Words |
| :--- | :--- |
| Its title | Permis de ședere |
| Where it goes: the summary's heading and the picker's title | Unde îl pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Acte — Se creează când salvezi. — field „Numele secțiunii noi” |
| What its day means | Expiră pe 3 mai 2027. |
| When it reminds, its day to come | Expiră pe 10 iunie 2027. Te anunț cu 3 luni și cu 45 de zile înainte. |
| Its place not chosen yet | Expiră pe 10 iunie 2027. Alege unde îl pui ca să te anunț din timp. |
| Its day passed | A expirat pe 10 mai. Data a trecut, așa că termenul apare de acum în Urmează. |
| Nothing read off it | Nu am găsit date pe permisul de ședere. Îl păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | Pe permisul de ședere scrie: 123456 |
| What its machine-readable code says | Pe spatele actului scrie: 123456 |
| Its back | Ai și o poză cu spatele? Acolo e codul care confirmă datele. |
| Under „Citește mai bine” | Poza actului se trimite la Google Gemini, cu cheia ta. |

### Permis de conducere (`drivingLicence`)

| Where | Words |
| :--- | :--- |
| Its title | Permis de conducere |
| Where it goes: the summary's heading and the picker's title | Unde îl pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Acte — Se creează când salvezi. — field „Numele secțiunii noi” |
| What its day means | Expiră pe 3 mai 2027. |
| When it reminds, its day to come | Expiră pe 10 iunie 2027. Te anunț cu 2 luni și cu o lună înainte. |
| Its place not chosen yet | Expiră pe 10 iunie 2027. Alege unde îl pui ca să te anunț din timp. |
| Its day passed | A expirat pe 10 mai. Data a trecut, așa că termenul apare de acum în Urmează. |
| Nothing read off it | Nu am găsit date pe permisul de conducere. Îl păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | Pe permisul de conducere scrie: 123456 |
| What its machine-readable code says | În codul de jos al actului scrie: 123456 |
| Under „Citește mai bine” | Poza actului se trimite la Google Gemini, cu cheia ta. |

### Cazier (`criminalRecord`)

| Where | Words |
| :--- | :--- |
| Its title | Cazier |
| Where it goes: the summary's heading and the picker's title | Unde îl pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Acte — Se creează când salvezi. — field „Numele secțiunii noi” |
| What its day means | Expiră pe 3 mai 2027. |
| When it reminds, its day to come | Expiră pe 10 iunie 2027. Te anunț cu 7 zile înainte și în ziua termenului. |
| Its place not chosen yet | Expiră pe 10 iunie 2027. Alege unde îl pui ca să te anunț din timp. |
| Its day passed | A expirat pe 10 mai. Data a trecut, așa că nu îți mai amintesc. |
| Nothing read off it | Nu am găsit date în cazier. Îl păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | În cazier scrie: 123456 |
| Under „Citește mai bine” | Poza actului se trimite la Google Gemini, cu cheia ta. |

### Card european de sănătate (`healthInsuranceCard`)

| Where | Words |
| :--- | :--- |
| Its title | Card european de sănătate |
| Where it goes: the summary's heading and the picker's title | Unde îl pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Acte — Se creează când salvezi. — field „Numele secțiunii noi” |
| What its day means | Expiră pe 3 mai 2027. |
| When it reminds, its day to come | Expiră pe 10 iunie 2027. Te anunț cu o lună și cu 7 zile înainte. |
| Its place not chosen yet | Expiră pe 10 iunie 2027. Alege unde îl pui ca să te anunț din timp. |
| Its day passed | A expirat pe 10 mai. Data a trecut, așa că nu îți mai amintesc. |
| Nothing read off it | Nu am găsit date pe cardul de sănătate. Îl păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | Pe cardul de sănătate scrie: 123456 |
| Under „Citește mai bine” | Poza actului se trimite la Google Gemini, cu cheia ta. |

### Card bancar (`bankCard`)

| Where | Words |
| :--- | :--- |
| Its title | Card bancar |
| Where it goes: the summary's heading and the picker's title | Unde îl pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Acte — Se creează când salvezi. — field „Numele secțiunii noi” |
| What its day means | Expiră pe 3 mai 2027. |
| When it reminds, its day to come | Expiră pe 10 iunie 2027. Te anunț cu o lună înainte și în ziua termenului. |
| Its place not chosen yet | Expiră pe 10 iunie 2027. Alege unde îl pui ca să te anunț din timp. |
| Its day passed | A expirat pe 10 mai. Data a trecut, așa că nu îți mai amintesc. |
| Nothing read off it | Nu am găsit date pe cardul bancar. Îl păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | Pe cardul bancar scrie: 123456 |
| Under „Citește mai bine” | Cardurile bancare se citesc doar pe telefon. |

### Carte verde (`greenCard`)

| Where | Words |
| :--- | :--- |
| Its title | Carte verde |
| Where it goes: the summary's heading and the picker's title | Unde o pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Acte — Se creează când salvezi. — field „Numele secțiunii noi” |
| What its day means | Expiră pe 3 mai 2027. |
| When it reminds, its day to come | Expiră pe 10 iunie 2027. Te anunț cu o lună și cu 7 zile înainte. |
| Its place not chosen yet | Expiră pe 10 iunie 2027. Alege unde o pui ca să te anunț din timp. |
| Its day passed | A expirat pe 10 mai. Data a trecut, așa că termenul apare de acum în Urmează. |
| Nothing read off it | Nu am găsit date pe cartea verde. O păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | Pe cartea verde scrie: 123456 |
| Under „Citește mai bine” | Poza actului se trimite la Google Gemini, cu cheia ta. |

### Semnătură electronică (`electronicSignature`)

| Where | Words |
| :--- | :--- |
| Its title | Semnătură electronică |
| Where it goes: the summary's heading and the picker's title | Unde o pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Acte — Se creează când salvezi. — field „Numele secțiunii noi” |
| What its day means | Expiră pe 3 mai 2027. |
| When it reminds, its day to come | Expiră pe 10 iunie 2027. Te anunț cu o lună și cu 7 zile înainte. |
| Its place not chosen yet | Expiră pe 10 iunie 2027. Alege unde o pui ca să te anunț din timp. |
| Its day passed | A expirat pe 10 mai. Data a trecut, așa că nu îți mai amintesc. |
| Nothing read off it | Nu am găsit date în certificat. O păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | În certificat scrie: 123456 |
| Under „Citește mai bine” | Poza actului se trimite la Google Gemini, cu cheia ta. |

### Talon (certificat de înmatriculare) (`vehicleRegistration`)

| Where | Words |
| :--- | :--- |
| Its title | Talon (certificat de înmatriculare) |
| Where it goes: the summary's heading and the picker's title | Unde îl pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Mașini — Se creează când salvezi. — field „Numele secțiunii noi” |
| When it reminds | (sets no deadline: no reminder line) |
| Nothing read off it | Nu am găsit date în talon. Îl păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | În talon scrie: 123456 |
| Under „Citește mai bine” | Prima pagină se trimite la Google Gemini, cu cheia ta. |

### Poliță RCA (`rcaPolicy`)

| Where | Words |
| :--- | :--- |
| Its title | Poliță RCA |
| Where it goes: the summary's heading and the picker's title | Unde o pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Mașini — Se creează când salvezi. — field „Numele secțiunii noi” |
| What its day means | Expiră pe 3 mai 2027. |
| When it reminds, its day to come | Expiră pe 10 iunie 2027. Te anunț cu o lună și cu 7 zile înainte și în ziua termenului. |
| Its place not chosen yet | Expiră pe 10 iunie 2027. Alege unde o pui ca să te anunț din timp. |
| Its day passed | A expirat pe 10 mai. Data a trecut, așa că nu îți mai amintesc. |
| Its bonus-malus class | Clasa bonus-malus o păstrez la Exemplu Ion: e a celui asigurat, nu a mașinii. / Clasa bonus-malus n-o păstrez: în poliță nu scrie cine e asiguratul. / Clasa bonus-malus n-o păstrez: Exemplu Ion nu e printre persoanele din dosar. Adaugă persoana și citește polița din nou. |
| Nothing read off it | Nu am găsit date în poliță. O păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | În poliță scrie: 123456 |
| Under „Citește mai bine” | Prima pagină se trimite la Google Gemini, cu cheia ta. |

### Poliță de asigurare (`insurancePolicy`)

| Where | Words |
| :--- | :--- |
| Its title | Poliță de asigurare |
| Where it goes: the summary's heading and the picker's title | Unde o pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Locuințe — Se creează când salvezi. — field „Numele secțiunii noi” |
| What its day means | Expiră pe 3 mai 2027. |
| When it reminds, its day to come | Expiră pe 10 iunie 2027. Te anunț cu o lună și cu 7 zile înainte și în ziua termenului. |
| Its place not chosen yet | Expiră pe 10 iunie 2027. Alege unde o pui ca să te anunț din timp. |
| Its day passed | A expirat pe 10 mai. Data a trecut, așa că nu îți mai amintesc. |
| Nothing read off it | Nu am găsit date în poliță. O păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | În poliță scrie: 123456 |
| Under „Citește mai bine” | Prima pagină se trimite la Google Gemini, cu cheia ta. |

### Factură de utilități (`utilityInvoice`)

| Where | Words |
| :--- | :--- |
| Its title | Factură de utilități |
| Where it goes: the summary's heading and the picker's title | Unde o pun |
| Where it goes, with nothing in the binder | Abonament nou: Gaz – ENGIE Romania S.A. — Se creează când salvezi. — field „Numele abonamentului” |
| What its day means | De plătit până pe 3 mai 2027. |
| When it reminds, its day to come | De plătit până pe 10 iunie 2027. Te anunț cu 2 zile înainte și în ziua termenului. |
| Its place not chosen yet | De plătit până pe 10 iunie 2027. Alege abonamentul ei ca să îți amintesc s-o plătești. |
| Its day passed | Era de plătit până pe 10 mai. Data a trecut, așa că nu îți mai amintesc. |
| Reminded to pay it | Amintește-mi să o plătesc |
| The bank pays it | Se plătește prin debit direct — Pe factură scrie: „Plata se face prin debit direct”. Dacă e așa, nu îți mai amintesc să plătești facturile. |
| Its meter index | Indexul 12.345 m³ se trece la „Gaze Apartament”. / Indexul estimat 12.345 m³ se trece la „Gaze Apartament”. Se socotește până vine citirea reală. / Indexul 12.345 m³ e deja trecut la „Gaze Apartament”. / Indexul nu-l trec: nu știu dacă e de gaze, de curent sau de apă. |
| Nothing read off it | Nu am găsit date pe factură. O păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | Pe factură scrie: 123456 |
| Under „Citește mai bine” | Prima pagină se trimite la Google Gemini, cu cheia ta. |

### Contract sau act adițional (`contract`)

| Where | Words |
| :--- | :--- |
| Its title | Contract sau act adițional |
| Where it goes: the summary's heading and the picker's title | Unde îl pun |
| Where it goes, with nothing in the binder | Abonament nou: Gaz – ENGIE Romania S.A. — Se creează când salvezi. — field „Numele abonamentului” |
| What its day means | Perioada minimă se termină pe 3 mai 2027. De atunci poți, de regulă, renunța fără penalități. |
| When it reminds, its day to come | Perioada minimă se termină pe 10 iunie 2027. De atunci poți, de regulă, renunța fără penalități. Te anunț cu o lună înainte și în ziua termenului. |
| Its place not chosen yet | Perioada minimă se termină pe 10 iunie 2027. De atunci poți, de regulă, renunța fără penalități. Alege unde îl pui ca să te anunț din timp. |
| Its day passed | Perioada minimă s-a terminat pe 10 mai. De atunci poți, de regulă, renunța fără penalități. Contractul se încheie la cel mult o lună după ce anunți. |
| The bank pays it | Se plătește prin debit direct — În contract scrie: „Plata se face prin debit direct”. Dacă e așa, nu îți mai amintesc să plătești facturile. |
| Its meter index | Indexul 12.345 m³ se trece la „Gaze Apartament”. / Indexul estimat 12.345 m³ se trece la „Gaze Apartament”. Se socotește până vine citirea reală. / Indexul 12.345 m³ e deja trecut la „Gaze Apartament”. / Indexul nu-l trec: nu știu dacă e de gaze, de curent sau de apă. |
| Nothing read off it | Nu am găsit date în contract. Îl păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | În contract scrie: 123456 |
| Under „Citește mai bine” | Prima pagină se trimite la Google Gemini, cu cheia ta. |

### Factură de service (`serviceInvoice`)

| Where | Words |
| :--- | :--- |
| Its title | Factură de service |
| Where it goes: the summary's heading and the picker's title | Unde o pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Mașini — Se creează când salvezi. — field „Numele secțiunii noi” |
| When it reminds | (sets no deadline: no reminder line) |
| Nothing read off it | Nu am găsit date pe factură. O păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | Pe factură scrie: 123456 |
| Under „Citește mai bine” | Prima pagină se trimite la Google Gemini, cu cheia ta. |

### Bon fiscal (`fiscalReceipt`)

| Where | Words |
| :--- | :--- |
| Its title | Bon fiscal |
| Where it goes: the summary's heading and the picker's title | Unde îl pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Garanții — Se creează când salvezi. — field „Numele secțiunii noi” |
| What its day means | Garanția se termină pe 3 mai 2027. |
| When it reminds, its day to come | Garanția se termină pe 10 iunie 2027. Te anunț cu o lună înainte. |
| Its place not chosen yet | Garanția se termină pe 10 iunie 2027. Alege unde îl pui ca să te anunț din timp. |
| Its day passed | Garanția s-a terminat pe 10 mai. Data a trecut, așa că nu îți mai amintesc. |
| Nothing read off it | Nu am găsit date pe bon. Îl păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | Pe bon scrie: 123456 |
| Under „Citește mai bine” | Prima pagină se trimite la Google Gemini, cu cheia ta. |

### Certificat de garanție (`warrantyCertificate`)

| Where | Words |
| :--- | :--- |
| Its title | Certificat de garanție |
| Where it goes: the summary's heading and the picker's title | Unde îl pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Garanții — Se creează când salvezi. — field „Numele secțiunii noi” |
| What its day means | Garanția se termină pe 3 mai 2027. |
| When it reminds, its day to come | Garanția se termină pe 10 iunie 2027. Te anunț cu o lună înainte. |
| Its place not chosen yet | Garanția se termină pe 10 iunie 2027. Alege unde îl pui ca să te anunț din timp. |
| Its day passed | Garanția s-a terminat pe 10 mai. Data a trecut, așa că nu îți mai amintesc. |
| Nothing read off it | Nu am găsit date în certificat. Îl păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | În certificat scrie: 123456 |
| Under „Citește mai bine” | Prima pagină se trimite la Google Gemini, cu cheia ta. |

### Raport ITP (`itpReport`)

| Where | Words |
| :--- | :--- |
| Its title | Raport ITP |
| Where it goes: the summary's heading and the picker's title | Unde îl pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Mașini — Se creează când salvezi. — field „Numele secțiunii noi” |
| What its day means | ITP-ul e valabil până pe 3 mai 2027. |
| When it reminds, its day to come | ITP-ul e valabil până pe 10 iunie 2027. Te anunț cu o lună și cu 7 zile înainte. |
| Its place not chosen yet | ITP-ul e valabil până pe 10 iunie 2027. Alege unde îl pui ca să te anunț din timp. |
| Its day passed | ITP-ul a fost valabil până pe 10 mai. Data a trecut, așa că nu îți mai amintesc. |
| Nothing read off it | Nu am găsit date în raport. Îl păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | În raport scrie: 123456 |
| Under „Citește mai bine” | Prima pagină se trimite la Google Gemini, cu cheia ta. |

### Fișă de la veterinar (`veterinaryRecord`)

| Where | Words |
| :--- | :--- |
| Its title | Fișă de la veterinar |
| Where it goes: the summary's heading and the picker's title | Unde o pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Animale — Se creează când salvezi. — field „Numele secțiunii noi” |
| What its day means | Următoarea doză e pe 3 mai 2027. |
| When it reminds, its day to come | Următoarea doză e pe 10 iunie 2027. Te anunț cu o zi înainte. |
| Its place not chosen yet | Următoarea doză e pe 10 iunie 2027. Alege unde o pui ca să te anunț din timp. |
| Its day passed | Următoarea doză era pe 10 mai. Data a trecut, așa că nu îți mai amintesc. |
| Nothing read off it | Nu am găsit date în fișă. O păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | În fișă scrie: 123456 |
| Under „Citește mai bine” | Prima pagină se trimite la Google Gemini, cu cheia ta. |

### Buletin de analize (`medicalResult`)

| Where | Words |
| :--- | :--- |
| Its title | Buletin de analize |
| Where it goes: the summary's heading and the picker's title | Unde îl pun |
| Where it goes, with nothing in the binder | Secțiune nouă în Sănătate — Se creează când salvezi. — field „Numele secțiunii noi” |
| When it reminds | (sets no deadline: no reminder line) |
| Nothing read off it | Nu am găsit date pe buletinul de analize. Îl păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | Pe buletinul de analize scrie: 123456 |
| Under „Citește mai bine” | Prima pagină se trimite la Google Gemini, cu cheia ta. |

### Alt document (`other`)

| Where | Words |
| :--- | :--- |
| Its title | Alt document |
| Where it goes: the summary's heading and the picker's title | Unde îl pun |
| Where it goes, with nothing in the binder | Doar păstrez actul — Îl găsești în Caută. |
| When it reminds | (sets no deadline: no reminder line) |
| Nothing read off it | Nu am găsit date pe document. Îl păstrez oricum, cu numele de mai sus. |
| A value that passed its check digit | Pe document scrie: 123456 |
| Under „Citește mai bine” | Prima pagină se trimite la Google Gemini, cu cheia ta. |

## Pleci din țară

What the trip check asks of each traveller, by the group their citizenship falls in (`Citizenship.Group`: read from the person, else from their documents; never assumed) and where they go, from `TravelRules` and `TravelWording`. Sample day: 3 mai 2027.

### `freeMovement`

| Where | Words |
| :--- | :--- |
| În Uniunea Europeană („Cetățenilor UE le ajunge cartea de identitate sau pașaportul, valabile până te întorci.”) | Carte de identitate sau pașaport — Nu sunt în dosar. Adaugă unul dintre ele cu o poză și verific până când e valabil. · Card european de sănătate |
| În afara UE („Ai nevoie de pașaport, bun de călătorit până te întorci.”) | Pașaport — Nu e în dosar. În afara UE ai nevoie de pașaport. Adaugă-l cu o poză și verific până când e bun. · Viza pentru țara în care mergi — Unele țări cer viză sau o autorizație de călătorie, după cetățenie. Verifică ce cere țara înainte de plecare. |

### `thirdCountry`

| Where | Words |
| :--- | :--- |
| În Uniunea Europeană („Cetățenilor UE le ajunge cartea de identitate sau pașaportul, valabile până te întorci.”) | Pașaport — Nu e în dosar. Fără cetățenie europeană, ai nevoie de pașaport și în UE. Adaugă-l cu o poză și verific până când e valabil. · Permis de ședere — Nu e în dosar. Fără el nu poți intra înapoi în țară. Adaugă-l cu o poză și verific până când e valabil. · Card european de sănătate |
| În afara UE („Ai nevoie de pașaport, bun de călătorit până te întorci.”) | Pașaport — Nu e în dosar. În afara UE ai nevoie de pașaport. Adaugă-l cu o poză și verific până când e bun. · Permis de ședere — Nu e în dosar. Fără el nu poți intra înapoi în țară. Adaugă-l cu o poză și verific până când e valabil. · Viza pentru țara în care mergi — Unele țări cer viză sau o autorizație de călătorie, după cetățenie. Verifică ce cere țara înainte de plecare. |

### `unknown`

| Where | Words |
| :--- | :--- |
| În Uniunea Europeană („Cetățenilor UE le ajunge cartea de identitate sau pașaportul, valabile până te întorci.”) | Cetățenia — Spune-mi ce cetățenie are, ca să știu ce acte îi trebuie. · Card european de sănătate |
| În afara UE („Ai nevoie de pașaport, bun de călătorit până te întorci.”) | Cetățenia — Spune-mi ce cetățenie are, ca să știu ce acte îi trebuie. · Pașaport — Nu e în dosar. În afara UE ai nevoie de pașaport. Adaugă-l cu o poză și verific până când e bun. · Viza pentru țara în care mergi — Unele țări cer viză sau o autorizație de călătorie, după cetățenie. Verifică ce cere țara înainte de plecare. |

### What each need says

| Where | Words |
| :--- | :--- |
| `identity` · Carte de identitate | Valabilă până pe 3 mai 2027. Ajunge pentru toată UE. / Expiră pe 3 mai 2027, înainte să te întorci. Fă-ți alta sau ia un pașaport valabil. |
| `identity` · Pașaport | Valabil până pe 3 mai 2027. În UE ajunge și pașaportul. / Valabil până pe 3 mai 2027. Ia-l pe el: cartea de identitate nu mai e valabilă la întoarcere. / Expiră pe 3 mai 2027, înainte să te întorci. Fă-ți altul sau ia o carte de identitate valabilă. |
| `passport` · Pașaport | Valabil până pe 3 mai 2027. / Expiră pe 3 mai 2027, înainte să te întorci. Fă-ți altul înainte de plecare. |
| `passport` (travel cut-off) · Pașaport | Bun de călătorit până pe 3 mai 2027, după ce te întorci. / Bun de călătorit doar până pe 3 mai 2027. Expiră pe 3 mai 2027, iar multe țări nu primesc un pașaport atât de aproape de expirare. Fă-ți altul înainte de plecare. |
| `residencePermit` · Permis de ședere | Valabil până pe 3 mai 2027. Ia-l cu tine: îți trebuie ca să intri înapoi în țară. / Expiră pe 3 mai 2027, înainte să te întorci. Cere prelungirea cu cel puțin 30 de zile înainte să expire. |
| A document with no expiry | Nu știu până când e valabil. Adaugă data de expirare. |
| Documents filed under no one, no citizenship | Cetățenia — Nu știu ce cetățenie are titularul. Mută actele la persoana lor și spune-mi ce cetățenie are. |

## Vinzi mașina și Ai avut o daună

Every check of each checklist, group by group, from `ReadinessEngine`, with its outcome in brackets (an optional check, `ReadinessNeed.optional`, reads „Opțional”). Sample day: 3 mai 2027.

### Vinzi mașina · nothing in the binder

| Where | Words |
| :--- | :--- |
| Pentru cumpărător | Cartea de identitate a vehiculului (CIV) (Nu e în dosar) — Adaugă-o înainte de vânzare. O găsești pe talon. · Serie de șasiu (VIN) (Nu e în dosar) — Adaugă-o înainte de vânzare. O găsești pe talon. · ITP (Nu e în dosar) — Nu e în dosar. Cumpărătorul are nevoie de ITP valabil ca să înmatriculeze mașina. · RCA (Nu e în dosar) — Nu e în dosar. Cumpărătorul poate cere să-l vadă. · Istoric de service (Opțional) — Un istoric complet crește încrederea și prețul. Adaugă reviziile pe care le știi. · Facturi de service (Opțional) — Dacă le ai, arată cumpărătorului cum a fost îngrijită mașina. · Certificatul de înmatriculare (talonul) — Originalul îl dai cumpărătorului. · Contractul de vânzare-cumpărare — Semnat de amândoi, câte un exemplar pentru tine, pentru cumpărător și pentru primărie. · Cartea ta de identitate — Pentru contract și la primărie. |
| De achitat înainte | Impozitul pe mașină, plătit pe tot anul — Primăria îți dă certificatul fiscal pentru vânzare doar fără datorii. · Amenzile neplătite — Tot pentru certificatul fiscal. Le vezi pe ghiseul.ro. · Leasing sau credit pe mașină — Dacă mașina e încă în leasing sau garanție la bancă, o vinzi doar după ce e achitată. |
| După vânzare | Scoate mașina de pe numele tău la primărie — La biroul de taxe locale, cu contractul. Altfel plătești impozit pe ea mai departe. |

### Vinzi mașina · everything in the binder

| Where | Words |
| :--- | :--- |
| Pentru cumpărător | Cartea de identitate a vehiculului (CIV) (Pregătit) — Seria e în dosar. Originalul îl dai cumpărătorului. · Serie de șasiu (VIN) (Pregătit) — E în dosar, pentru contract. · ITP (Pregătit) — Valabil până pe 10 ianuarie 2028. Cumpărătorul are nevoie de el ca să înmatriculeze mașina. · RCA (Pregătit) — Valabil până pe 10 ianuarie 2028. Nu trece la cumpărător: el își face polița lui. · Istoric de service (Pregătit) — 3 intrări de arătat cumpărătorului. · Facturi de service (Pregătit) — Sunt facturi în dosar. · Certificatul de înmatriculare (talonul) — Originalul îl dai cumpărătorului. · Contractul de vânzare-cumpărare — Semnat de amândoi, câte un exemplar pentru tine, pentru cumpărător și pentru primărie. · Cartea ta de identitate — Pentru contract și la primărie. |
| De achitat înainte | Impozitul pe mașină, plătit pe tot anul — Primăria îți dă certificatul fiscal pentru vânzare doar fără datorii. · Amenzile neplătite — Tot pentru certificatul fiscal. Le vezi pe ghiseul.ro. · Leasing sau credit pe mașină — Dacă mașina e încă în leasing sau garanție la bancă, o vinzi doar după ce e achitată. |
| După vânzare | Scoate mașina de pe numele tău la primărie — La biroul de taxe locale, cu contractul. Altfel plătești impozit pe ea mai departe. · Reziliază RCA — Cu contractul de vânzare, la asigurător. Primești înapoi banii pe lunile rămase. |

### Ai avut o daună · a car, nothing in the binder

| Where | Words |
| :--- | :--- |
| Polița | Număr poliță (Nu e în dosar) — Îl cere asigurătorul la primul telefon. E scris pe poliță. · Telefon pentru daune (Nu e în dosar) — E pe poliță sau pe site-ul asigurătorului. Adaugă-l ca să suni dintr-o atingere. · Valabilitatea poliței (Nu e în dosar) — Nu știu până când e valabilă. Adaugă termenul poliței. · Polița (Opțional) — Fă o poză poliței, ca s-o ai la îndemână. |
| Ce fotografiezi | Mașinile, cu numerele la vedere — Din față, din spate și din lateral, înainte să le mutați. · Fiecare avarie — De aproape și de departe, ca să se vadă unde e. · Locul — Indicatoare, marcaje, urme pe carosabil. · Actele celuilalt șofer — Talonul, permisul și polița RCA, dacă e și altă mașină. · Constatarea amiabilă — După ce o semnați amândoi. Dacă nu vă înțelegeți, mergi la Poliție. |
| Acte de avut la îndemână | Permisul de conducere și cartea de identitate — Ale celui care conducea. · Talonul și cartea de identitate a mașinii — Le cere asigurătorul la constatare. · Constatarea amiabilă sau procesul-verbal de la poliție — Originalul, nu doar poza. |

### Ai avut o daună · a car, everything in the binder

| Where | Words |
| :--- | :--- |
| Polița | Valabilitatea poliței (Pregătit) — Valabilă până pe 10 ianuarie 2028. · Polița (Pregătit) — E în dosar, cu poză. |
| Ce fotografiezi | Mașinile, cu numerele la vedere — Din față, din spate și din lateral, înainte să le mutați. · Fiecare avarie — De aproape și de departe, ca să se vadă unde e. · Locul — Indicatoare, marcaje, urme pe carosabil. · Actele celuilalt șofer — Talonul, permisul și polița RCA, dacă e și altă mașină. · Constatarea amiabilă — După ce o semnați amândoi. Dacă nu vă înțelegeți, mergi la Poliție. |
| Acte de avut la îndemână | Permisul de conducere și cartea de identitate — Ale celui care conducea. · Talonul și cartea de identitate a mașinii — Le cere asigurătorul la constatare. · Constatarea amiabilă sau procesul-verbal de la poliție — Originalul, nu doar poza. |

### Ai avut o daună · a home, nothing in the binder

| Where | Words |
| :--- | :--- |
| Polița | Număr poliță (Nu e în dosar) — Îl cere asigurătorul la primul telefon. E scris pe poliță. · Telefon pentru daune (Nu e în dosar) — E pe poliță sau pe site-ul asigurătorului. Adaugă-l ca să suni dintr-o atingere. · Valabilitatea poliței (Nu e în dosar) — Nu știu până când e valabilă. Adaugă termenul poliței. · Polița (Opțional) — Fă o poză poliței, ca s-o ai la îndemână. |
| Ce fotografiezi | Fiecare zonă afectată — Întâi de departe, apoi avariile de aproape. · De unde a pornit — Țeava, acoperișul, geamul sau peretele. · Lucrurile stricate — Înainte să arunci ceva, cu bonurile dacă le ai. |
| Acte de avut la îndemână | Cartea de identitate — A celui care are polița. · Actul de proprietate — Contractul sau extrasul de carte funciară. · Procesul-verbal, dacă a venit cineva — De la pompieri, poliție sau administratorul blocului. |

## Abonamente by service

What a subscription says by what it is (`ServiceKind.Service`): the group it is listed under, which the person can change in its edit form; the codes its papers are identified by, the only ones its edit form shows and the review offers (`SubscriptionCode`). A subscription whose service isn't chosen yet is asked „Cod client” and „Număr contract”.

### What every subscription shares

| Where | Words |
| :--- | :--- |
| The groups of Abonamente, in order | Utilități · Internet și telefon · Transport · Aplicații și streaming · Altele |
| Moving one to another group | Grup în Abonamente — Se alege după serviciu. Îl poți muta în alt grup. |
| „Se plătește” | Săptămânal · Lunar · Trimestrial · Anual |
| A bill that hasn't come, by cycle | Factura de la ENGIE n-a venit săptămâna asta / Factura de la ENGIE n-a venit luna asta / Factura de la ENGIE n-a venit încă / Factura de la ENGIE n-a venit încă |

### Gaz (`service.gas`)

| Where | Words |
| :--- | :--- |
| Its group | Utilități |
| Its codes (edit form, review) | Cod loc de consum gaze (CLC) („Poate apărea și ca POD gaz. E pe factura de gaze.”) · Cod client · Număr contract |
| Where a new one goes | Under the home it supplies |

### Curent (`service.electricity`)

| Where | Words |
| :--- | :--- |
| Its group | Utilități |
| Its codes (edit form, review) | Cod loc de consum (POD) („Începe cu RO. E pe factura de curent.”) · Cod client · Număr contract |
| Where a new one goes | Under the home it supplies |

### Apă (`service.water`)

| Where | Words |
| :--- | :--- |
| Its group | Utilități |
| Its codes (edit form, review) | Cod loc de consum („E pe factură, lângă codul de client.”) · Cod client · Număr contract |
| Where a new one goes | Under the home it supplies |

### Căldură (`service.heating`)

| Where | Words |
| :--- | :--- |
| Its group | Utilități |
| Its codes (edit form, review) | Cod loc de consum („E pe factură, lângă codul de client.”) · Cod client · Număr contract |
| Where a new one goes | Under the home it supplies |

### Salubritate (`service.sanitation`)

| Where | Words |
| :--- | :--- |
| Its group | Utilități |
| Its codes (edit form, review) | Cod client · Număr contract |
| Where a new one goes | Under the home it supplies |

### Internet și TV (`service.internetTV`)

| Where | Words |
| :--- | :--- |
| Its group | Internet și telefon |
| Its codes (edit form, review) | Cod client · Număr contract · Cont de facturare („E pe factură, uneori în locul codului de client.”) |
| Where a new one goes | Under the home it supplies |

### Telefon mobil (`service.mobile`)

| Where | Words |
| :--- | :--- |
| Its group | Internet și telefon |
| Its codes (edit form, review) | Număr de telefon · Cod client · Număr contract · Cont de facturare („E pe factură, uneori în locul codului de client.”) |
| Where a new one goes | On its own, in Abonamente |

### Transport (`service.transport`)

| Where | Words |
| :--- | :--- |
| Its group | Transport |
| Its codes (edit form, review) | Cod client · Număr contract |
| Where a new one goes | On its own, in Abonamente |

### Aplicație sau streaming (`service.streaming`)

| Where | Words |
| :--- | :--- |
| Its group | Aplicații și streaming |
| Its codes (edit form, review) | None |
| Where a new one goes | On its own, in Abonamente |

### Alt abonament (`service.other`)

| Where | Words |
| :--- | :--- |
| Its group | Altele |
| Its codes (edit form, review) | Cod client · Număr contract |
| Where a new one goes | On its own, in Abonamente |
