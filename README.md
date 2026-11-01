# 📁 Dosar cu Șină

> Manager local-first pentru active, documente, garanții și scadențe administrative, configurat conform cerințelor și termenelor legale din România.
Aplicația rulează complet pe dispozitiv (SwiftData pe iOS / Room pe Android), sincronizată opțional prin iCloud / Google Drive privat, fără backend extern și fără tracking.

---

## 🌟 Caracteristici Cheie

### 1. Monitorizare pe 8 categorii predefinite
Fiecărui bun sau domeniu îi sunt asociate reguli de viață, scadențe conforme cu legislația românească și jurnale de telemetrie:
- 🏠 **Casă & Utilități**: Termene VTP centrală termică (ISCIR 2 ani), verificare instalație gaze (VIG 2 ani / RIG 10 ani), apometre (BRML rece 7 ani / caldă 4 ani), poliță PAD, ferestre de autocitire contoare.
- 🚗 **Auto**: Calcul ITP în funcție de vechimea vehiculului, alerte RCA și rovinietă (conform Legii 226/2023), jurnal de service și consum.
- 🩺 **Sănătate & Familie**: Profil medical de urgență (ICE), grupă sanguină & Rh, alergii, afecțiuni cronice, medic de familie, pașaport implant dentar cu numerotare FDI (lot/serie), card european CEASS (24 luni), rețete și buletine de analize.
- 🐾 **Animale de Companie (Pet)**: Rasă, microcip ISO 15 cifre (prefix 642 România), număr pașaport UE, grafic evoluție greutate, cadențe deparazitare internă/externă (Milbemax, Bravecto) și vaccin antirabic cu regulă de frontieră de 21 de zile.
- 🪪 **Documente & Identitate**: Carte de identitate, pașaport simplu electronic cu alertă timpurie la 6 luni (-180 zile) pentru restricții de călătorie non-UE, permis de conducere, semnătură electronică calificată și cazier judiciar.
- 🛡️ **Garanții & Bunuri**: Electrocasnice, unelte și electronice, S/N, IMEI, bon fiscal scanat, alertă automată „Ultima Șansă” cu 30 de zile înainte de expirarea garanției de 2 ani, prelungire automată a garanției legale cu zilele petrecute în reparație (`daysInService` per OUG nr. 140/2021).
- 💳 **Abonamente & Contracte**: Servicii digitale și telecom, cicluri de facturare, alertă cu 48h/24h înainte de conversia perioadelor de probă (Free Trials), alertă de retenție la expirarea contractelor minime pe 24 de luni.
- 🧩 **Active Personalizate & Landlord Hub**: Șabloane gata de utilizat pentru Proprietari / Chirii (chiriaș, garanție, contract ANAF, termen Declarația Unică Formular 212 la 25 mai, apometre chiriaș), Prosumator Solar, Bicicletă / E-Bike și Echipamente Cafea de Specialitate.

### 2. Cele 4 Coloane Universale (Universal Pillars)
Fiecare activ implementează cei 4 piloni arhitecturali:
1. **Identitate & Specificații Personalizate**: Metadata puternic tipizate, câmpuri dinamice nelimitate pe 10 tipuri (`DynamicField`) și legătură directă cu specialiști din agendă via `ContactsUI`.
2. **Motor de Scadențe & Obligații**: Evenimente recurente și punctuale (`LifecycleEvent`), alerte Time-Sensitive la praguri critice, rollover automat la bifare („Am rezolvat”) direct din ecranul de blocare, sincronizare bidirecțională cu Apple Calendar și Apple Reminders prin `EventKit`.
3. **Jurnale Istorice Duble**:
   - `ServiceItem`: Intervenții discrete și piese de schimb, cu analiză comparativă automată ($\Delta\text{cost}$, $\Delta\text{km}$, $\Delta\text{zile}$).
   - `MeasurementLog`: Telemetrie cantitativă pentru indici utilități cu curbe sezoniere, biomarkeri medicali cu intervale de referință (`* H` / `* L`), greutate și odometru.
4. **Seif Structurat de Documente**: Ingestie multi-sursă (cameră VisionKit, PDF, galerie foto, text copiat, manual), vizualizator de înaltă rezoluție și generator de dosar consolidat cu *Opis Documente* (`PDFDossierGenerator`).

### 3. Securitate & Deblocare Biometrică Just-in-Time (Model B)
Aplicația adoptă o arhitectură de securitate biometrică ergonomică (**Model B: Just-in-Time Unlock**):
- **Zero Fricțiune la Pornire**: Aplicația se deschide instantaneu pentru vizualizarea kilometrajului mașinii, notarea indicilor de utilități sau consultarea memento-urilor.
- **Autentificare Doar la Nevoie**: Face ID, Touch ID, Optic ID sau codul dispozitivului se solicită exclusiv la intrarea în seifurile sensibile:
  - 🪪 *Documente & Identitate (`.documents`)*
  - 🩺 *Sănătate & Card Medical (`.health`)*
  - 🔒 *Orice activ custom marcat drept sensibil*
- **Afișare Directă în Memorie**: Odată autentificat, codurile CNP, seriile de buletin și conturile IBAN sunt vizibile direct în clar în memorie fără a necesita dezvăluiri manuale câmp cu câmp.
- **Auto-Lock Sigur**: Seifurile se re-blochează automat după 5 minute de inactivitate continuă sau imediat ce aplicația trece în fundal.

### 4. Format Deschis & Portabilitate Cross-Platform (`.dosar`)
Zero platform lock-in. Datele utilizatorului pot fi exportate și importate liber între iOS (SwiftData) și Android (Room SQLite):
- **Format Standardizat**: Pachet de arhivă ZIP înregistrat în sistem cu identificatorul UTType `com.ar.dosarcusina.dossier` și extensia `.dosar`.
- **Structură Pachet v2**:
  - `manifest.json`: Schema v2, metadata platformă, contor entități și **hartă completă de integritate SHA-256**.
  - `data/*.json`: `assets.json`, `events.json`, `service_history.json`, `measurements.json`.
  - `vault/`: Binare atașate (`.pdf`, `.heic`, `.jpg`) stocate securizat după UUID.
  - `opis.pdf`: Cuprins tabelar oficial (*Opis Documente*) generat automat.
- **Moduri de Import**: `CLEAN_RESTORE` (restaurare curată cu resetare prealabilă) și `MERGE` (îmbinare inteligentă cu regula „cel mai recent câștigă”).

### 5. Gestiune Active, Personalizare & Resetare Sigură
- **Dashboard Modular pe Grilă de 8 Pătrate**: Ecranul principal de deschidere (`Active`) prezintă cele 8 domenii casnice ca plăci squircle continue cu simboluri native, contoare reactive și indicatori de scadență iminentă.
- **Personalizare & Reordonare Categorie**: Reordonare intuitivă drag-and-drop în Setări, ascundere plăci neutilizate și crearea de categorii personalizate nelimitate (ex. *Biciclete*, *Livadă*, *Echipamente*).
- **Ștergere Universală a Activelor (CRUD Parity)**: Meniu contextual la apăsare lungă pe carduri, buton de ștergere în vizualizarea de detaliu și în fișa de editare, plus opțiune de resetare completă a bazei de date în Setări.
- **Formulare Zero-Friction & `QuickPickChips`**: Formulare curate fără text pre-completat forțat, cu sugestii instantanee prin pastile de selecție rapidă cu 1 tap.
- **Inițializare Automată & Resetare Sigură**: La prima lansare pe un dispozitiv nou, aplicația detectează baza de date goală prin `@AppStorage("didSeedInitialDemoData")` și populează automat 8 active demonstrative realiste. Din Setări se pot reîncărca oricând datele demo sau goli complet baza de date.

### 6. Radar de Scadențe, Financial Pulse & Undo Framework
- **Filtrare pe Orizonturi Temporale**: Mod *Focalizare (14z)* pentru eliminarea zgomotului vizual, mod *Toate* pentru planificare pe termen lung și mod *Rezolvate* pentru istoricul obligațiilor finalizate (cu posibilitate de debifare pentru reactivare).
- **Snackbar de Anulare Plutitor (`UndoSnackbar`)**: Alertă tactilă de 5 secunde la bifarea oricărui eveniment ce permite anularea imediată dacă acțiunea a fost accidentală.
- **Cash-Flow Forecast pe 30 / 60 / 90 de zile**: Proiecție dinamică a sumelor de plată defalcată pe cheltuieli recurente (abonamente, utilități) vs punctuale (RCA, impozite, ITP, revizii).
- **Cost Total de Deținere (TCO)**: Cât costă fiecare mașină, casă sau animal de companie pe an.
- **Abonamente & Burn Rate**: Monitorizare a cheltuielilor lunare recurente și alerte de renegociere contracte.

---

## 🔒 Politica de Securitate pentru Repository Public (Zero-Secrets)

Acest depozit este **public**, conceput cu o arhitectură strictă **Zero-Leak / BYOK (Bring Your Own Key)**:
- **Zero API Keys în Cod**: Nicio cheie API, parolă sau credențial nu este salvată în Git.
- **Securitate BYOK**: Cheia opțională Gemini este stocată exclusiv în **iOS Keychain** criptat (`kSecClassGenericPassword` cu `kSecAttrAccessibleAfterFirstUnlock`) sau într-un fișier local `ios/Config.xcconfig` ignorat de Git.
- **Zero Central Database**: Fără servere backend de colectare a datelor. Datele stau 100% pe dispozitivul tău (`SwiftData` pe iOS, `Room` pe Android) și în conturile tale private de sincronizare (iCloud / Google Drive AppData).
- **Seiful Confidențial (`private/`)**: Vulnerabilitățile interne și jurnalele de depanare sunt stocate în `private/`, ignorate de Git și protejate activ de hook-ul `.git/hooks/pre-commit`.

---

## 🛠️ Structura Proiectului

```text
DosarCuSina/
├── SPEC.md                      # Specificația completă a produsului (arhitectură, standarde românești)
├── AGENTS.md                    # Standardul de excelență (Apple Craftsmanship & Reguli de Securitate)
├── shared/                      # Standarde administrative & scheme comune
│   └── ROMANIAN_ADMINISTRATIVE_STANDARDS.md # Ghid autoritar legal românesc (ITP, ANRE, ISCIR, Rovinietă)
├── ios/                         # Aplicația nativă iOS (SwiftUI + SwiftData)
│   ├── Config.xcconfig.template # Șablon de configurare locală pentru chei API
│   ├── DosarCuSina/             # Codul sursă Swift (Modele, Servicii, Vizualizări)
│   └── DosarCuSinaWidgets/      # Widget-uri native WidgetKit
├── android/                     # Aplicația nativă Android (Jetpack Compose + Room SQLite)
│   └── app/src/main/java/com/dosarcusina/
│       ├── data/                # Entități Room cu 1:1 SwiftData Parity (MeasurementLog, ServiceItem, etc.)
│       ├── archive/             # DosarArchiveParser (import/export .dosar cu verificare SHA-256)
│       └── ocr/                 # CameraXTextScanner (ML Kit Text Recognition)
└── tests/                       # Suită automată multi-platformă
    ├── run_tests.sh             # Rulor automatizat complet (iOS Swift + Android Room)
    ├── ios/                     # Teste unitare și de integrare Swift (13 suite, 137 teste)
    └── android/                 # Teste Room SQLite & teste de stres adversariale (13 teste)
```

---

## 🧪 Testare & Verificare Automată

Aplicația include o suită cuprinzătoare de teste automate multi-platformă ce verifică calculul cadențelor, parsarea OCR a chitanțelor românești, motorul de arhivă `.dosar`, securitatea biometrică și paritatea SQLite pe Android:

```bash
# Rulare completă a tuturor testelor (iOS + Android)
./tests/run_tests.sh

# Rulare teste de paritate Android Room SQLite
python3 tests/android/run_room_tests.py

# Rulare teste de stres adversarial Android Room (100 active cascade delete)
python3 tests/android/adversarial_room_stress_test.py
```

---

## 🚀 Cum Rulezi Aplicația pe iOS

1. Clonează depozitul:
   ```bash
   git clone https://github.com/your-username/DosarCuSina.git
   cd DosarCuSina
   ```
2. *(Opțional pentru dezvoltare cu Gemini API)*:
   ```bash
   cp ios/Config.xcconfig.template ios/Config.xcconfig
   # Adaugă cheia ta Gemini în ios/Config.xcconfig
   ```
   *Alternativ, poți introduce cheia Gemini direct din ecranul de Setări al aplicației.*
3. Deschide proiectul în Xcode și rulează pe simulator sau pe un dispozitiv fizic iOS 17+.

---

## 📜 Licență

Proiect cu sursă deschisă distribuit sub licența **[PolyForm Noncommercial License 1.0.0](LICENSE)**. 

Puteți descărca, modifica și utiliza liber codul sursă pentru uz personal, casnic sau comunitar, cu păstrarea atribuirii, fiind interzisă vânzarea sau exploatarea comercială a software-ului.
