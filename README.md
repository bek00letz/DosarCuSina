# 📁 Dosar cu Șină

> Un asistent inteligent, elegant și privat pentru administrarea activelor, recurențelor și evenimentelor esențiale din viața de zi cu zi (Casă, Mașină, Pet, Sănătate, Documente, Garanții și Module Personalizate).

Construit conform standardelor **Apple Craftsmanship & Polish**: arhitectură local-first, confidențialitate totală prin iCloud/CloudKit, interacțiuni haptice rafinate și scanare inteligentă hibridă (On-Device Apple Vision + Gemini Flash AI).

---

## 🌟 Caracteristici Cheie

- **Model Mental pe Active (Assets)**: Fiecărui bun sau domeniu (ex. *Volkswagen Golf*, *Apartament Floreasca*, *Luna - Pisică*, *Sănătate Personală*) îi sunt asociate reguli de viață, scadențe, telemetrie și documente.
- **Sistem Inteligent de Scanare (Dual-Tier OCR)**:
  1. *Tier 1 (Instant & Offline)*: Apple Vision Framework decupează documentul, corectează perspectiva și recunoaște date/sume fără internet.
  2. *Tier 2 (Gemini Semantic Sweep)*: Extrage câmpuri structurate (furnizor, dată emitere, scadență, total, serie) folosind Google Gemini API.
- **Motor de Module Personalizate (Custom Modules Engine)**: Creează module noi pentru pasiunile sau activele tale (Bicicletă, E-Bike, Grădină, Proprietăți închiriate, Ambarcațiuni) cu declanșatoare pe timp sau pe unități de uzură (km, ore de funcționare, cicluri).
- **Radar de Scadențe & Financial Pulse**: Știi din timp ce cheltuieli urmează în următoarele 30/60/90 de zile și cât te costă anual fiecare activ.
- **100% Privat & Local-First**: Datele sunt salvate local prin SwiftData și sincronizate securizat exclusiv în contul tău iCloud privat. Fără servere intermediare, fără baze de date publice, fără trackeri.

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
