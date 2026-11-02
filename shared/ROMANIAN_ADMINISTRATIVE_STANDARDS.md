# Standarde Administrative & Legale Românești — Dosar cu Șină
> **Statut**: Autoritar & Verificat (Ground Truth)  
> **Data ultimei verificări**: Noiembrie 2026  
> **Scop**: Ghid obligatoriu pentru toate componentele, presetările, calculele de cadență și șabloanele din aplicație. Previne implementarea unor legi abrogate, zvonuri sau termene incorecte.

---

## 1. Mobilitate, Auto & Regim Rutier

### 1.1 Rovinietă (Legea nr. 226/2023)
* **Prevederi actuale**: Începând cu 1 octombrie 2026, sistemul de tarifare a fost reformat conform normelor europene (Directiva Eurovinieta / PNRR):
  * **Durate valabile autoturisme ($\le 3.5\text{t}$)**: `1 zi`, `10 zile`, `30 zile`, `60 zile`, `12 luni`. *(Vechile durate de 7 zile și 90 zile au fost restructurate).*
  * **Criteriu ecologic**: Tarifele sunt diferențiate în funcție de clasa de poluare din talon: `Non-Euro` până la `Euro 6`, respectiv `Vehicul Electric`.
  * **Vehicule grele de marfă ($> 3.5\text{t}$)**: Trecute pe sistemul de taxare kilometrică electronică **TollRo**.
* **Tratament în aplicație**: Selector pentru norma de poluare a mașinii și preseturi pentru cele 5 durate oficiale.

### 1.2 Taxa de Pod (Peaj) Fetești–Cernavodă (A2) & Giurgeni–Vadu Oii (DN2A)
* **Prevederi actuale**: **ELIMINATĂ COMPLET** de la 1 octombrie 2026 prin Legea nr. 226/2023. Traversarea podurilor peste Dunăre pe A2 și DN2A este inclusă direct în Rovinietă și nu se mai plătește separat.
* **Tratament în aplicație**:
  * ❌ **NU implementați** cronometrul de 24h / regula orei 23:59 din ziua următoare.
  * ❌ **NU implementați** butonul de plată prin SMS la 8545.
  * ✅ Pentru treceri achiziționate anterior și neutilizate: notă informativă că utilizatorii pot solicita restituirea sumelor la CNAIR.

### 1.3 Inspecția Tehnică Periodică (ITP) — RNTR 1 / OUG nr. 195/2002
* **Periodicități legale**:
  * **Autoturisme noi (M1 uz personal)**: Prima inspecție la **3 ani** de la data primei înmatriculări.
  * **Autoturisme uz personal $\le 12$ ani**: La fiecare **2 ani**.
  * **Autoturisme uz personal $> 12$ ani**: La fiecare **1 an** (anual).
  * **Autoturisme Ridesharing (Uber, Bolt, etc.) / Taxi / Rent-a-car**: La fiecare **6 luni**.
  * **Autoutilitare N1 ($\le 3.5\text{t}$)**: La fiecare **1 an**, indiferent de vechimea vehiculului.
* **Efect juridic critic**: La data expirării ITP, **înmatricularea vehiculului se suspendă automat de drept** (art. 102 alin. 1 pct. 1 din OUG 195/2002). Circulația atrage amendă contravențională și reținerea certificatului și plăcuțelor.
* **Tratament în aplicație**:
  * Detector de vechime mașină (an fabricare) $\to$ propunere automată 3 ani / 2 ani / 1 an.
  * Comutator „Utilizare transport alternativ / Ridesharing / Taxi” $\to$ forțare automată cadență 6 luni.
  * Notificare critică Time-Sensitive la -7d, -1d și 0d („Înmatricularea se suspendă de drept la miezul nopții”).

---

## 2. Locuință, Utilități & Instalații Tehnice

### 2.1 Instalații de Gaze Naturale (Ordinul ANRE nr. 179/2015 și actualizări)
Legea distinge clar între două proceduri care nu trebuie confundate:
* **VIG (Verificarea Tehnică a Instalației de Gaze)**:
  * Obligatorie la maximum **2 ani**.
  * Cuprinde: etanșeitate conducte, funcționare robineți, verificare detectoare automate de gaz.
  * Executant: Operator economic autorizat **ANRE**.
* **RIG (Revizia Tehnică a Instalației de Gaze)**:
  * Obligatorie la maximum **10 ani**.
  * Cuprinde: probă de rezistență la presiune a conductelor (demontare contor) + toate operațiunile VIG.
  * Situații speciale: obligatorie după neutilizarea instalației mai mult de 6 luni sau după modificări structurale.
  * În anul 10, **RIG înlocuiește VIG-ul**.
* **Consecință nerespectare**: Distribuitorul de gaze sistează furnizarea (sigilare contor).

### 2.2 Centrala Termică de Apartament (ISCIR Prescripția Tehnică PT A1)
* **VTP (Verificarea Tehnică Periodică)**:
  * Obligatorie la maximum **2 ani**.
  * Cuprinde: analiză gaze arse, randament, funcționare supape de siguranță, tiraj coș.
  * Executant: Firmă autorizată **ISCIR** (eliberează livretul aparatului și proces-verbal).

### 2.3 Contoare de Apă / Apometre (BRML — Biroul Român de Metrologie Legală)
Conform Listei Oficiale a mijloacelor de măsurare supuse controlului metrologic legal:
* **Apometre apă rece**: valabilitate metrologică **7 ani**.
* **Apometre apă caldă**: valabilitate metrologică **4 ani**.
* **Consecință nerespectare**: Asociația de proprietari trece apartamentul la consum paușal.

### 2.4 Certificat de Performanță Energetică — CPE (Legea nr. 372/2005)
* **Valabilitate**: **10 ani** de la data emiterii.
* **Obligativitate**: Obligatoriu la vânzare (predare în original la notar) și la închiriere (copie atașată la contract și depusă la ANAF).
* **Încetare anticipată**: Se anulează dacă se efectuează renovări majore care modifică anvelopa termică.

---

## 3. Taxe Locale & Finanțe Publice (ANAF)

### 3.1 Impozite și Taxe Locale (Codul Fiscal — Legea nr. 227/2015)
Se aplică pentru clădiri, terenuri și mijloace de transport:
* **Rata I & Bonificație**: Scadență la **31 martie**.
  * Plata integrală până la 31 martie conferă o **bonificație de până la 10%** stabilită de Consiliul Local.
* **Rata a II-a**: Scadență la **30 septembrie**. După această dată curg majorări de întârziere zilnice.
* **Tratament în aplicație**: Reminder la 1 martie și 20 martie pentru obținerea discountului de 10%.

### 3.2 Declarația Unică — Formularul 212 (Codul Fiscal / ANAF)
* **Termen legal**: **25 mai** în fiecare an.
* **Aplicabilitate**: Venituri din chirii (contracte de locațiune), activități independente (PFA/PFI), dividende, dobânzi, tranzacții bursiere/crypto, stabilirea plafoanelor CASS (6, 12, 24 salarii minime brute).
* **Tratament în aplicație**: Cât timp există cel puțin un contract de închiriere (șablonul „Chiriași”, sub o locuință), gospodăria are o singură obligație anuală „Declarația unică pentru chirii”, scadentă pe 25 mai, cu remindere la 30 și 7 zile înainte și o revenire a doua zi dacă nu e bifată. Obligația aparține gospodăriei, nu unei proprietăți, și dispare când nu mai există chiriași.
* **Surse**: Codul fiscal (Legea nr. 227/2015), Titlul IV, Capitolul III „Venituri din cedarea folosinței bunurilor” (art. 83–84) și art. 120–122 (declarația unică); termenul de 25 mai este cel publicat de ANAF pentru formularul 212.

### 3.3 Contracte de închiriere (locuințe)
* **Contractul**: Date de început și sfârșit, chiria lunară, ziua de plată și garanția încasată.
* **La mutare și la plecare**: Indexurile contoarelor (apă, gaze, energie) se notează la intrarea și la ieșirea chiriașului, ca bază pentru decontul utilităților.
* **Tratament în aplicație**: Reminder pentru sfârșitul contractului cu 60 de zile înainte (timp pentru prelungire sau pentru alt chiriaș).

---

## 4. Acte Oficiale, Valabilitate & Proceduri Administrative

### 4.1 Cazier Judiciar (Legea nr. 290/2004)
* **Valabilitate legală**: Exact **6 luni** de la data eliberării.

### 4.2 Extras de Carte Funciară pentru Informare (ANCPI)
* **Valabilitate practică**: Codul de verificare electronică și acceptarea standard de către bănci, notari și autorități este de **30 de zile calendaristice**.

### 4.3 Viza de Flotant / Stabilirea Reședinței (OUG nr. 97/2005 / Legea nr. 162/2023)
* **Valabilitate**: Maximum **1 an (12 luni)**. După această perioadă își încetează efectele de drept.

### 4.4 Pașapoarte & Călătorii Non-UE
* **Regula celor 6 luni**: Majoritatea statelor non-UE (inclusiv Turcia, Egipt, Marea Britanie în anumite contexte, Emiratele Arabe, Asia) cer ca pașaportul să aibă o valabilitate de **minimum 6 luni** de la data preconizată a ieșirii din țara respectivă.
* **Tratament în aplicație**: Alertă la 6 luni înainte de expirarea efectivă a pașaportului („Pașaportul intră în zona restricționată pentru călătorii internaționale non-UE”).

---

## 5. Sănătate & Asigurări Sociale

### 5.1 Cardul European de Asigurări Sociale de Sănătate (CEASS)
* **Valabilitate standard**: **2 ani (24 luni)** de la data emiterii pentru asigurații din sistemul CNAS.

### 5.2 Concedii Medicale (OUG nr. 158/2005)
* **Predare la angajator**: Salariatul trebuie să depună certificatul de concediu medical până la data de **5 a lunii următoare** acordării concediului, pentru procesarea plății indemnizației.

### 5.3 Rețete Medicale Compensate / Gratuite (CNAS)
* **Afecțiuni acute**: Valabilitate de **3 până la 5 zile** (max. 48h–7d pentru urgențe/antibiotice).
* **Afecțiuni cronice**: Valabilitate de **30 de zile** (sau până la 90 de zile pentru scheme stabilizate).

---

## 6. Garanții & Bunuri de Folosință Îndelungată (OUG nr. 140/2021)

* **Garanția legală de conformitate**: 2 ani pentru bunuri noi, minimum 1 an pentru bunuri second-hand.
* **Extinderea garanției pe perioada service-ului**: Timpul de nefuncționare din momentul predării bunului în service până la restituirea lui funcțională **prelungește termenul de garanție cu numărul exact de zile petrecute în reparație** (art. 12 din OUG 140/2021).
* **Tratament în aplicație**: Câmpul `daysInService` din `ServiceItem` calculează automat noua dată extinsă de expirare a garanției bunului.
* **Șablonul „Garanții”**: Un produs pe înregistrare (magazin, data cumpărării, preț, bonul atașat). Garanția pornește implicit la 24 de luni, care se pot schimba. Data de sfârșit se calculează din data cumpărării și din numărul de luni. Reminderul vine cu 30 de zile înainte de sfârșitul garanției și întreabă dacă totul funcționează, pentru că atunci se mai poate reclama gratuit un defect.
* **Surse**: OUG nr. 140/2021 privind anumite aspecte referitoare la contractele de vânzare de bunuri (transpune Directiva (UE) 2019/771), art. 10 (răspunderea vânzătorului pentru lipsa de conformitate timp de 2 ani de la livrare) și art. 12 (prelungirea cu perioada de nefuncționare).
