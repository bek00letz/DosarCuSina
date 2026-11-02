#if DEBUG
import SwiftUI

/// A browsable catalog of every design-system token and component, for review.
/// DEBUG builds only. Open it from a debug menu or from the previews at the bottom.
struct DesignSystemGallery: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    link("Culori", "paintpalette.fill", .accentColor) { GalleryColors() }
                    link("Tipografie", "textformat.size", .indigo) { GalleryTypography() }
                    link("Spațiere și colțuri", "square.dashed", .teal) { GallerySpacing() }
                    link("Butoane și mișcare", "hand.tap.fill", .orange) { GalleryButtons() }
                } header: {
                    Text(verbatim: "Fundații")
                }
                Section {
                    link("Carduri și rânduri", "rectangle.stack.fill", .blue) { GalleryCards() }
                    link("Chips", "capsule.fill", .purple) { GalleryChips() }
                    link("Stări și termene", "clock.badge.exclamationmark.fill", .red) { GalleryStatus() }
                    link("Titluri și indicatori", "chart.bar.fill", .green) { GalleryHeaders() }
                    link("Ecrane goale și erori", "tray.fill", .gray) { GalleryStates() }
                    link("Confirmări și încărcare", "checkmark.bubble.fill", .mint) { GalleryFeedback() }
                } header: {
                    Text(verbatim: "Componente")
                }
                Section {
                    link("Câmpuri", "character.cursor.ibeam", .pink) { GalleryFields() }
                    link("Foaie de editare", "square.and.pencil", .brown) { GalleryDiscardGuard() }
                } header: {
                    Text(verbatim: "Formulare")
                }
            }
            .navigationTitle(Text(verbatim: "Sistem de design"))
        }
    }

    private func link<Destination: View>(
        _ title: String,
        _ systemImage: String,
        _ tint: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
                .navigationTitle(Text(verbatim: title))
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            DSListRow(title: Text(verbatim: title), systemImage: systemImage, tint: tint) { EmptyView() }
        }
    }
}

// MARK: - Page scaffold

private struct GalleryPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                content
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.background)
    }
}

private struct GallerySection<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).dsFont(.sectionTitle)
                if let note {
                    Text(verbatim: note).dsFont(.footnote)
                }
            }
            .padding(.horizontal, DS.Space.xxs)
            content
        }
    }
}

// MARK: - Colors

private struct GalleryColors: View {
    var body: some View {
        GalleryPage {
            GallerySection(title: "Accent", note: "O singură culoare de accent pentru acțiuni, linkuri și selecție.") {
                swatchRow([("Accent", DS.Palette.accent)])
            }
            GallerySection(title: "Stări", note: "Culoarea plină pentru puncte și pictograme; varianta de text păstrează contrastul de cel puțin 4,5:1.") {
                ForEach(DSStatus.allCases) { status in
                    DSCard {
                        HStack(spacing: DS.Space.s) {
                            swatch(status.color)
                            swatch(status.textColor)
                            VStack(alignment: .leading) {
                                Text(status.title).foregroundStyle(status.textColor).font(.headline)
                                Text(verbatim: status.rawValue).dsFont(.caption)
                            }
                            Spacer()
                            DSStatusBadge(status)
                        }
                    }
                }
            }
            GallerySection(title: "Suprafețe și text", note: "Culori de sistem: se adaptează singure la modul întunecat și la contrast crescut.") {
                swatchRow([
                    ("Fundal", DS.Palette.background),
                    ("Suprafață", DS.Palette.surface),
                    ("Umplere", DS.Palette.fill),
                    ("Separator", DS.Palette.separator),
                ])
                swatchRow([
                    ("Text", DS.Palette.label),
                    ("Secundar", DS.Palette.secondaryLabel),
                    ("Terțiar", DS.Palette.tertiaryLabel),
                    ("Indiciu", DS.Palette.placeholder),
                ])
            }
        }
    }

    private func swatchRow(_ items: [(String, Color)]) -> some View {
        DSCard {
            HStack(alignment: .top, spacing: DS.Space.s) {
                ForEach(items, id: \.0) { item in
                    VStack(spacing: DS.Space.xxs) {
                        swatch(item.1)
                        Text(verbatim: item.0).dsFont(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func swatch(_ color: Color) -> some View {
        ConcentricRectangle(corners: .concentric(minimum: 8), isUniform: true)
            .fill(color)
            .frame(width: 44, height: 44)
            .dsHairlineBorder(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Typography

private struct GalleryTypography: View {
    var body: some View {
        GalleryPage {
            GallerySection(title: "Scara tipografică", note: "Toate stilurile cresc cu dimensiunea textului din Setări.") {
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        ForEach(Array(DSTextStyle.allCases.enumerated()), id: \.offset) { _, style in
                            Text(verbatim: sample(for: style)).dsFont(style)
                        }
                    }
                }
            }
            GallerySection(title: "Cifre tabulare", note: "Cifrele au aceeași lățime, ca sumele să se alinieze pe coloane.") {
                DSCard {
                    VStack(alignment: .trailing, spacing: DS.Space.xxs) {
                        Text(1_250.5, format: .currency(code: "RON")).dsFont(.body, numeric: true)
                        Text(98.75, format: .currency(code: "RON")).dsFont(.body, numeric: true)
                        Text(11_111, format: .currency(code: "RON")).dsFont(.body, numeric: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private func sample(for style: DSTextStyle) -> String {
        switch style {
        case .display: "84.200 km"
        case .title: "VW Golf 2018"
        case .sectionTitle: "Scadențe apropiate"
        case .headline: "ITP — stația Auto Test"
        case .body: "Inspecția tehnică se face la doi ani pentru mașinile mai noi de 12 ani."
        case .subheadline: "Ultima: 14 martie 2025"
        case .footnote: "Poți schimba ora mementourilor din Setări."
        case .caption: "Actualizat azi"
        case .captionEmphasized: "NUMĂR DE ÎNMATRICULARE"
        }
    }
}

// MARK: - Spacing

private struct GallerySpacing: View {
    private let steps: [(String, CGFloat)] = [
        ("xxs", DS.Space.xxs), ("xs", DS.Space.xs), ("s", DS.Space.s), ("m", DS.Space.m),
        ("l", DS.Space.l), ("xl", DS.Space.xl), ("xxl", DS.Space.xxl),
    ]

    var body: some View {
        GalleryPage {
            GallerySection(title: "Spațiere", note: "Grilă de 4 pt. Folosește pașii numiți, nu valori brute.") {
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        ForEach(steps, id: \.0) { step in
                            HStack(spacing: DS.Space.s) {
                                Text(verbatim: step.0).dsFont(.caption, numeric: true).frame(width: 36, alignment: .leading)
                                Rectangle().fill(DS.Palette.accent).frame(width: step.1, height: 12)
                                Text(verbatim: "\(Int(step.1)) pt").dsFont(.caption, numeric: true)
                            }
                        }
                    }
                }
            }
            GallerySection(title: "Colțuri concentrice", note: "Interior = exterior − margine. Aici: 22 − 16 = 6, cu minimum 8.") {
                DSCard {
                    VStack(spacing: DS.Space.s) {
                        ConcentricRectangle(corners: .concentric(minimum: 8), isUniform: true)
                            .fill(DS.Palette.accent.opacity(0.15))
                            .frame(height: 64)
                            .overlay { Text(verbatim: "ConcentricRectangle").dsFont(.footnote) }
                        HStack(spacing: DS.Space.s) {
                            DSIconWell(systemImage: "car.fill", tint: .blue)
                            DSIconWell(systemImage: "house.fill", tint: .orange)
                            DSIconWell(systemImage: "pawprint.fill", tint: .brown)
                            DSIconWell(systemImage: "doc.text.fill", tint: .indigo)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Buttons & motion

private struct GalleryButtons: View {
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GalleryPage {
            GallerySection(title: "Butoane de sistem", note: "Pentru butoane obișnuite folosim stilurile sistemului.") {
                DSCard {
                    VStack(spacing: DS.Space.s) {
                        Button {} label: { Text(verbatim: "Salvează").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.capsule)
                        Button {} label: { Text(verbatim: "Adaugă o obligație").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered).controlSize(.large).buttonBorderShape(.capsule)
                        Button(role: .destructive) {} label: { Text(verbatim: "Șterge activul").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered).controlSize(.large).buttonBorderShape(.capsule)
                        HStack {
                            Button {} label: { Label { Text(verbatim: "Scanează") } icon: { Image(systemName: "doc.viewfinder") } }
                                .buttonStyle(.glass)
                            Button {} label: { Label { Text(verbatim: "Adaugă") } icon: { Image(systemName: "plus") } }
                                .buttonStyle(.glassProminent)
                        }
                        Text(verbatim: "Sticla (Liquid Glass) doar pentru controale care plutesc deasupra conținutului.")
                            .dsFont(.footnote)
                    }
                }
            }
            GallerySection(title: "Butoane pe toată lățimea", note: "Acțiunea principală e plină; restul sunt conturate. Cel puțin 50 pt înălțime, textul se rupe pe rânduri, nu se taie.") {
                DSCard {
                    VStack(spacing: DS.Space.s) {
                        DSPrimaryButton(verbatim: "Salvează", systemImage: "checkmark") {}
                        DSSecondaryButton(verbatim: "Adaugă un act", systemImage: "plus") {}
                        DSSecondaryButton(verbatim: "Șterge din istoric", systemImage: "trash", role: .destructive) {}
                    }
                }
            }
            GallerySection(title: "Suprafețe apăsabile", note: "Răspuns imediat la atingere; cu Reducere mișcare doar se estompează.") {
                Button {} label: {
                    DSCard {
                        DSListRow(title: Text(verbatim: "Apasă și ține"), subtitle: Text(verbatim: ".buttonStyle(.dsPressable)"), systemImage: "hand.tap.fill") { EmptyView() }
                    }
                }
                .buttonStyle(.dsPressable)
            }
            GallerySection(title: "Arcuri", note: "Rapid 0,22 s · Standard 0,32 s · Accentuat 0,4 s. Toate se pot întrerupe.") {
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Button {
                            withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { expanded.toggle() }
                        } label: {
                            Text(verbatim: expanded ? "Restrânge" : "Extinde")
                        }
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .fill(DS.Palette.accent.gradient)
                            .frame(width: expanded ? 260 : 80, height: 44)
                    }
                }
            }
        }
    }
}

// MARK: - Cards & rows

private struct GalleryCards: View {
    @State private var brakes = true
    @State private var cabinFilter = false
    @State private var reminder = 7
    @State private var rating: Int? = 4

    var body: some View {
        GalleryPage {
            GallerySection(title: "Card cu rânduri") {
                DSCard(padding: 0) {
                    VStack(spacing: 0) {
                        DSListRow("Kilometraj", value: Text(verbatim: "84.200 km"), systemImage: "gauge.with.dots.needle.bottom.50percent", tint: .blue)
                            .padding(.horizontal, DS.Space.m)
                        DS.Hairline().padding(.leading, 62)
                        DSListRow(title: Text(verbatim: "ITP"), subtitle: Text(verbatim: "Auto Test SRL"), systemImage: "checkmark.shield.fill", tint: .green, showsChevron: true) {
                            DSStatusBadge(daysRemaining: 12)
                        }
                        .padding(.horizontal, DS.Space.m)
                        DS.Hairline().padding(.leading, 62)
                        DSListRow(title: Text(verbatim: "RCA"), subtitle: Text(verbatim: "Poliță anuală"), systemImage: "car.side.fill", tint: .orange, showsChevron: true) {
                            DSStatusBadge(daysRemaining: -3)
                        }
                        .padding(.horizontal, DS.Space.m)
                    }
                }
            }
            GallerySection(title: "Rânduri cu bifă", note: "Tot rândul se apasă. Ce e dedesubt apare doar când e bifat și poate conține câmpuri.") {
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        DSCheckRow(title: Text(verbatim: "Plăcuțe frână față"), subtitle: Text(verbatim: "Ultima dată: martie 2024"), isOn: $brakes) {
                            Text(verbatim: "380 lei").dsFont(.body, numeric: true).padding(.leading, DS.Space.xl)
                        }
                        DS.Hairline()
                        DSCheckRow(title: Text(verbatim: "Filtru de habitaclu"), isOn: $cabinFilter)
                        DS.Hairline()
                        ForEach([7, 1], id: \.self) { days in
                            DSCheckRow(title: Text(verbatim: days == 7 ? "Cu o săptămână înainte" : "Cu o zi înainte"), isOn: reminder == days) {
                                reminder = days
                            }
                        }
                    }
                }
            }
            GallerySection(title: "Valori", note: "Doar de citit: sumele se aliniază pe coloană. Cu acțiune: se copiază sau se sună dintr-o atingere.") {
                DSCard {
                    VStack(alignment: .leading, spacing: 0) {
                        DSReadOnlyValueRow(label: Text(verbatim: "Pe lună"), value: Text(verbatim: "49,99 lei"))
                        DSRowSeparator()
                        DSReadOnlyValueRow(label: Text(verbatim: "În ultimul an"), value: Text(verbatim: "1.250,50 lei"))
                        DSRowSeparator()
                        DSActionValueRow(title: Text(verbatim: "Număr poliță"), value: "RO/00/EX0001", action: .copy)
                        DSRowSeparator()
                        DSActionValueRow(title: Text(verbatim: "Telefon pentru daune"), value: "0700 000 001", action: .call)
                        DSRowSeparator()
                        // A secret: in the app, "Arată" and "Copiază" ask for Face ID first, every time.
                        DSSecretValueRow(title: Text(verbatim: "PIN pentru autentificare"), isSet: true) { .revealed("0000") }
                    }
                }
            }
            GallerySection(title: "Note și exemple", note: "Stelele se pot apăsa doar unde se dă o notă; o atingere pe nota curentă o șterge.") {
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        DSStarRating(rating: rating.map(Double.init)) { rating = $0 }
                        HStack(spacing: DS.Space.s) {
                            DSStarRating(rating: 4.5)
                            DSStarRating(rating: 4.5, style: .compact)
                            Spacer(minLength: 0)
                            DSExampleBadge()
                        }
                    }
                }
            }
            GallerySection(title: "Card simplu") {
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text(verbatim: "Apartament Floreasca").dsFont(.title)
                        Text(verbatim: "Str. Exemplu nr. 1, București").dsFont(.subheadline)
                    }
                }
            }
        }
    }
}

// MARK: - Chips

private struct GalleryChips: View {
    enum Filter: String, CaseIterable { case toate = "Toate", auto = "Auto", casa = "Casă", pet = "Animale", acte = "Acte", sanatate = "Sănătate" }
    @State private var filter: Filter = .toate
    @State private var picked: Set<String> = ["Căpușe"]

    var body: some View {
        GalleryPage {
            GallerySection(title: "Bară de filtre") {
                DSChipBar(items: Filter.allCases, selection: $filter) { Text(verbatim: $0.rawValue) }
                    .padding(.horizontal, -DS.Space.m)
            }
            GallerySection(title: "Alegere multiplă") {
                DSCard {
                    DSMultiChoiceField("Paraziți vizați", selection: $picked, options: ["Căpușe", "Purici", "Flebotomi", "Viermi intestinali", "Acarieni"]) { $0 }
                }
            }
        }
    }
}

// MARK: - Status

private struct GalleryStatus: View {
    var body: some View {
        GalleryPage {
            GallerySection(title: "Termene", note: "Pluralele românești: o zi, 2 zile, 20 de zile.") {
                DSCard {
                    DSFlowLayout {
                        ForEach([-25, -3, -1, 0, 1, 2, 12, 20, 45], id: \.self) { days in
                            DSStatusBadge(daysRemaining: days)
                        }
                        DSStatusBadge(daysRemaining: 3, isDone: true)
                    }
                }
            }
            GallerySection(title: "Expirări", note: "Pentru acte și garanții. Pașaportul avertizează cu 180 de zile înainte.") {
                DSCard {
                    DSFlowLayout {
                        ForEach([-40, 0, 9, 150, 400], id: \.self) { days in
                            DSStatusBadge(
                                days < 0 ? .overdue : (days <= 180 ? .soon : .done),
                                text: Text(DSDueText.expiryText(daysRemaining: days, soonWithinDays: 180))
                            )
                        }
                    }
                }
            }
            GallerySection(title: "Puncte") {
                DSCard {
                    HStack(spacing: DS.Space.m) {
                        ForEach(DSStatus.allCases) { DSStatusDot(status: $0) }
                    }
                }
            }
        }
    }
}

// MARK: - Headers & metrics

private struct GalleryHeaders: View {
    var body: some View {
        GalleryPage {
            DSSectionHeader("Scadențe apropiate", count: 4, actionTitle: "Vezi tot") {}
            DSSectionHeader(verbatim: "VW Golf 2018", count: 2)
            HStack(spacing: DS.Space.s) {
                DSMetricTile("În 30 de zile", systemImage: "calendar", footnote: Text(verbatim: "3 plăți")) {
                    Text(1_480, format: .currency(code: "RON"))
                }
                DSMetricTile("Kilometraj", systemImage: "gauge.with.dots.needle.bottom.50percent", tint: .blue) {
                    Text(verbatim: "84.200 km")
                }
            }
        }
    }
}

// MARK: - Empty and error states

private struct GalleryStates: View {
    var body: some View {
        GalleryPage {
            DSCard {
                DSEmptyState(
                    "Nicio mașină încă",
                    systemImage: "car.fill",
                    message: "Adaugă mașina și îți amintim de ITP, RCA și rovinietă la timp.",
                    actionTitle: "Adaugă o mașină"
                ) {}
            }
            DSCard {
                DSErrorState(
                    "Arhiva nu s-a putut deschide",
                    message: "Fișierul pare incomplet. Exportă-l din nou pe telefonul vechi și încearcă iar."
                ) {}
            }
            DSNotice(.info, title: "Mementourile sunt oprite", message: "Pornește notificările ca să afli la timp de scadențe.", actionTitle: "Deschide Setări") {}
            DSNotice(.warning, title: "Pașaportul expiră în 5 luni", message: "Multe țări din afara UE cer cel puțin 6 luni de valabilitate.")
            DSNotice(.error, title: "Nu am putut salva", message: "Spațiul de pe telefon e plin. Eliberează puțin spațiu și încearcă din nou.")
            DSNotice(.success, title: "Copia de rezervă e gata")
        }
    }
}

// MARK: - Toast and loading

private struct GalleryFeedback: View {
    @State private var toast: DSToast?
    @State private var isLoading = true
    @State private var showsSpinner = false

    var body: some View {
        GalleryPage {
            GallerySection(title: "Confirmare cu anulare", note: "Dispare după 5 secunde (10 cu VoiceOver), la glisare în jos sau la anulare.") {
                DSCard {
                    Button {
                        toast = .undo("ITP marcat ca rezolvat") {}
                    } label: {
                        Text(verbatim: "Marchează ITP ca rezolvat").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                }
            }
            GallerySection(title: "Schelet", note: "Păstrează forma conținutului, ca nimic să nu sară la încărcare.") {
                DSCard(padding: 0) {
                    DSListRow(title: Text(verbatim: "Factură ENGIE Romania S.A."), subtitle: Text(verbatim: "Scadentă pe 14 noiembrie"), systemImage: "flame.fill", tint: .orange) {
                        Text(348.5, format: .currency(code: "RON"))
                    }
                    .padding(.horizontal, DS.Space.m)
                    .dsSkeleton(isLoading)
                }
                Toggle(isOn: $isLoading) { Text(verbatim: "Se încarcă") }
            }
            GallerySection(title: "Indicator cu întârziere", note: "Apare doar dacă lucrul durează peste 0,4 s.") {
                DSCard {
                    HStack {
                        Button { showsSpinner.toggle() } label: { Text(verbatim: showsSpinner ? "Ascunde" : "Pornește") }
                        Spacer()
                        if showsSpinner { DSDelayedProgress() }
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        .dsToast($toast)
    }
}

// MARK: - Fields

private struct GalleryFields: View {
    @State private var plate = ""
    @State private var vin = "WVWZZZ1KZ8W00000"
    @State private var microchip = ""
    @State private var pin = ""
    @State private var iban = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var url = ""
    @State private var address = ""
    @State private var notes = ""
    @State private var amount: Decimal? = 348.5
    @State private var currency = "RON"
    @State private var odometer: Double? = 84_200
    @State private var date: Date?
    @State private var expiry: Date? = Calendar.current.date(byAdding: .day, value: 120, to: .now)
    @State private var fuel: String? = "Benzină"
    @State private var reminders = true
    @State private var contact: DSContactValue? = DSContactValue(name: "Service Auto Exemplu", phone: "0700 000 000")
    @State private var revealAll = false

    var body: some View {
        GalleryPage {
            DSToggleField("Arată toate problemele", isOn: $revealAll, footnote: "Așa arată formularul după ce apeși Salvează.")

            GallerySection(title: "Mașină") {
                DSCard {
                    VStack(spacing: DS.Space.m) {
                        DSTextField("Număr de înmatriculare", text: $plate, kind: .plate, isRequired: true, formatter: { $0.uppercased() })
                        DSTextField("Serie de șasiu (VIN)", text: $vin, kind: .vin, validator: { value in
                            value.count == 17 ? .valid : .invalid("Seria de șasiu are 17 caractere. Ai scris \(value.count).")
                        })
                        DSMetricField("Kilometraj", value: $odometer, unit: "km")
                        DSChoiceField("Combustibil", selection: $fuel, options: ["Benzină", "Motorină", "Hibrid", "Electric", "GPL"]) { $0 }
                        DSContactField("Mecanic", contact: $contact)
                    }
                }
            }
            GallerySection(title: "Bani și date") {
                DSCard {
                    VStack(spacing: DS.Space.m) {
                        DSMoneyField("Cost estimat", amount: $amount, currencyCode: $currency)
                        DSDateField("Data cumpărării", date: $date)
                        DSExpiryDateField("Pașaport valabil până la", date: $expiry, soonWithinDays: 180, footnote: "Avertizăm cu 6 luni înainte, pentru călătorii în afara UE.")
                        DSToggleField("Mementouri", isOn: $reminders, systemImage: "bell.fill")
                    }
                }
            }
            GallerySection(title: "Coduri și contact") {
                DSCard {
                    VStack(spacing: DS.Space.m) {
                        DSTextField("Microcip", text: $microchip, kind: .microchip)
                        DSSecretField("PIN pentru semnare", value: $pin, footnote: "Rămâne ascuns; îl vezi doar după Face ID.")
                        DSTextField("IBAN", text: $iban, kind: .iban)
                        DSTextField("Telefon", text: $phone, kind: .phone)
                        DSTextField("E-mail", text: $email, kind: .email)
                        DSTextField("Link de anulare", text: $url, kind: .url)
                        DSTextField("Adresă", text: $address, kind: .address)
                        DSTextField("Note", text: $notes, kind: .longText, footnote: "Orice vrei să ții minte despre acest activ.")
                    }
                }
            }
        }
        .environment(\.dsRevealsValidation, revealAll)
    }
}

// MARK: - Discard guard

private struct GalleryDiscardGuard: View {
    @State private var isEditing = false

    var body: some View {
        GalleryPage {
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text(verbatim: "Scrie ceva în foaie, apoi încearcă s-o închizi trăgând în jos sau cu Anulează.")
                        .dsFont(.subheadline)
                    Button { isEditing = true } label: { Text(verbatim: "Deschide foaia").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            GalleryEditSheet()
        }
    }
}

private struct GalleryEditSheet: View {
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GalleryPage {
                DSTextField("Denumire", text: $name, prompt: "VW Golf 2018")
            }
            .navigationTitle(Text(verbatim: "Activ nou"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text(verbatim: "Salvează") }
                        .disabled(name.isEmpty)
                }
            }
        }
        .dsDiscardGuard(hasChanges: !name.isEmpty)
    }
}

// MARK: - Previews

#Preview("Light") {
    DesignSystemGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    DesignSystemGallery()
        .preferredColorScheme(.dark)
}

#Preview("Accessibility text") {
    DesignSystemGallery()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Fields · dark · large text") {
    NavigationStack { GalleryFields() }
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility1)
}

#Preview("Status · accessibility text") {
    NavigationStack { GalleryStatus() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
