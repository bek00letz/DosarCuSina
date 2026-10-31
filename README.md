# 📁 Dosar cu Șină

> Un asistent inteligent, elegant și privat pentru administrarea activelor, recurențelor și evenimentelor esențiale din viața de zi cu zi (Casă, Mașină, Pet, Sănătate, Documente, Garanții și Module Personalizate).

Construit conform standardelor **Apple Craftsmanship & Polish**: arhitectură local-first, confidențialitate totală prin iCloud/CloudKit, interacțiuni haptice rafinate și scanare inteligentă hibridă (On-Device Apple Vision + Gemini Flash AI).

---

## 🌟 Caracteristici Cheie

- **Model Mental pe Active (Assets) cu Scheme Specializate**: Fiecărui bun sau domeniu (ex. *Vehicul* cu serie VIN, număr de înmatriculare, an și motorizare; *Locuință* cu adrese, specificații centrală termică și serii contoare gaz/curent/apă; *Pet* cu rasă, microcip ISO și medic veterinar; *Sănătate* cu grupă sanguină, contact de urgență și medic de familie) îi sunt asociate reguli de viață, scadențe și telemetrie.
- **Istoric Granular Piese & Mentenanță Service**: Detaliază fiecare piesă înlocuită la revizie (plăcuțe de frână, filtre, ulei, distribuție) și compară automat cu intervenția anterioară: diferența de kilometri ($\Delta\text{km}$), diferența de preț ($\Delta\text{cost}$) și timpul scurs.
- **Catalog Asigurători & Obligații Românești**: Configurare și editare completă cu asigurători reali (Groupama, Allianz-Țiriac, Omniasig, Generali, Grawe, Axeria, PAID), polițe RCA/CASCO/PAD și clase Bonus-Malus (B0–B8, M1–M8).
- **Intake Universal Multi-Sursă (Digital & Fizic)**:
  1. *Fișiere PDF Digitale*: Extrage nativ textul curat din facturile și contractele PDF primite pe e-mail sau descărcate.
  2. *Fotografii & Galerie Foto*: Capturi de ecran din Homebank / e-banking sau poze din camera roll.
  3. *Scanare Cameră Hârtie*: Corecție automată de perspectivă și contrast prin VisionKit.
  4. *Text Copiat din E-mail / SMS*: Lipește direct mesajul primit de la furnizor și datele sunt parsate automat.
  5. *Introducere Manuală Rapidă*: Formular complet pentru înregistrare instantanee.
- **Motor de Module & Câmpuri Dinamice Nelimitate**: Adaugă oricâte câmpuri personalizate (text, numere, date, boolean, valută) pe orice activ.
- **Radar de Scadențe & Financial Pulse**: Știi din timp ce cheltuieli urmează în următoarele 30/60/90 de zile și cât te costă anual fiecare activ.
- **100% Privat & Local-First**: Datele sunt salvate local prin SwiftData/Room și sincronizate securizat exclusiv în contul tău privat. Fără servere intermediare, fără baze de date publice, fără trackeri.

---

## 🔒 Politica de Securitate pentru Repository Public (Open-Source)

Acest depozit este **public**, conceput cu o arhitectură **Zero-Leak / BYOK (Bring Your Own Key)**:
- Nicio cheie API, credențial sau dată personală nu este versionată în Git.
- Cheia opțională pentru Gemini API este stocată exclusiv în **iOS Keychain** criptat al dispozitivului tău sau într-un fișier local `Config.xcconfig` ignorat de Git.
- Aplicația funcționează complet offline chiar și fără nicio cheie API externă (folosind OCR-ul nativ Apple Vision).

---

## 🛠️ Structura Proiectului

```text
DosarCuSina/
├── SPEC.md                      # Specificația completă și detaliată a aplicației
├── AGENTS.md                    # Standardul de excelență (Apple Craftsmanship)
├── shared/                      # Scheme JSON & Șabloane comune
│   ├── schemas/                 # Schema JSON pentru răspunsul structurat OCR
│   └── templates/               # Module predefinite (Casă, Mașină, Pet, etc.)
├── ios/                         # Aplicația nativă iOS (SwiftUI + SwiftData)
│   ├── Config.xcconfig.template # Șablon de configurare locală pentru chei API
│   └── DosarCuSina/             # Codul sursă Swift
└── android/                     # Aplicația nativă Android (Jetpack Compose + Room)
```

---

## 🚀 Cum Rulezi Aplicația (iOS)

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

Proiect licențiat sub licența MIT.
