import SwiftUI
import SwiftData

/// What a category of the person's own is, asked the same way when it is made
/// ("Altceva…") and when it is changed later (Setări › Categoriile tale): its name, its
/// symbol and a few plain questions (`CategorySwitches`). Every row is one whole target.
struct CustomCategoryForm: View {
    @Binding var draft: CustomSectionDraft
    /// Said under the questions, such as what happens to what was kept when one is turned off.
    var footnote: Text?

    /// The categories in the binder, for what „Ține de…” offers (`CategorySwitches.belongingChoices`).
    @Query private var templates: [CategoryTemplate]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            DSTextField("Cum se numește", text: $draft.name, prompt: "Barca, Rulota, Pianul", isRequired: true)
            CustomSymbolPicker(symbol: $draft.symbol)
            questions
            belonging
            boxes
            if let footnote {
                footnote
                    .dsFont(.footnote)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: What it keeps

    private var questions: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            DSSectionHeader("Ce ține minte")
            DSCard {
                VStack(spacing: 0) {
                    DSCheckRow(
                        title: Text("Are acte", comment: "Switch of a category of one's own: its sections keep documents."),
                        subtitle: Text("Poze și PDF-uri: acte, contracte, garanții.", comment: "Explains the documents switch."),
                        isOn: $draft.switches.hasDocuments
                    )
                    .padding(.vertical, DS.Space.xs)
                    DSRowSeparator()
                    DSCheckRow(
                        title: Text("Are facturi și contracte", comment: "Switch of a category of one's own: its sections keep subscriptions and their bills."),
                        subtitle: Text("Abonamente cu facturile lor, ca la o locuință: curent, internet, loc de parcare.", comment: "Explains the bills switch."),
                        isOn: $draft.switches.hasBills
                    )
                    .padding(.vertical, DS.Space.xs)
                    DSRowSeparator()
                    DSCheckRow(
                        title: Text("Are revizii", comment: "Switch of a category of one's own: its sections have a regular service."),
                        subtitle: Text("Îți amintesc din timp, ca la mașină.", comment: "Explains the service switch."),
                        isOn: draft.switches.service != nil,
                        action: { draft.switches.service = draft.switches.service == nil ? CategorySwitches.Service(.time) : nil }
                    ) {
                        serviceChoice
                    }
                    .padding(.vertical, DS.Space.xs)
                }
            }
        }
    }

    /// What the service counts by, one of three, and how often: a counter chosen starts
    /// at the car's numbers (10.000 km, 100 hours, 12 months).
    private var serviceChoice: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            VStack(spacing: 0) {
                ForEach(CategorySwitches.Counter.allCases, id: \.self) { counter in
                    DSCheckRow(
                        title: Self.title(of: counter),
                        subtitle: Self.subtitle(of: counter),
                        isOn: draft.switches.service?.counter == counter,
                        action: {
                            guard draft.switches.service?.counter != counter else { return }
                            draft.switches.service = CategorySwitches.Service(counter)
                        }
                    )
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Revizia se face", comment: "VoiceOver label of the service counter choice."))
            if let counter = draft.switches.service?.counter {
                DSMetricField(
                    Self.everyTitle(of: counter),
                    value: Binding(
                        get: { draft.switches.service.flatMap { $0.every > 0 ? Double($0.every) : nil } },
                        // Empty or not a whole number: kept as missing, so it can't be saved.
                        set: { value in draft.switches.service?.every = value.flatMap { $0 >= 1 && $0 <= 1_000_000 && $0 == $0.rounded() ? Int($0) : nil } ?? 0 }
                    ),
                    unit: counter.everyUnit,
                    fractionDigits: 0...0,
                    isRequired: true,
                    footnote: Self.everyFootnote(of: counter),
                    validator: { $0 >= 1 && $0 <= 1_000_000 && $0 == $0.rounded() ? .valid : .invalid("Scrie un număr întreg, mai mare ca zero.") }
                )
                // A new counter is a new field, starting at its own number.
                .id(counter)
            }
        }
        .padding(.leading, DS.Space.xl)
    }

    /// One line saying what a category keeps, for a list of categories: "Acte · Revizii după ore".
    static func summary(of switches: CategorySwitches) -> String {
        var parts: [String] = []
        if switches.hasDocuments { parts.append(String(localized: "Acte", comment: "Summary of a category of one's own: it keeps documents.")) }
        if switches.hasBills { parts.append(String(localized: "Facturi și contracte", comment: "Summary of a category of one's own: it keeps subscriptions.")) }
        switch switches.service?.counter {
        case .time?: parts.append(String(localized: "Revizii după timp", comment: "Summary of a category of one's own: a service every so many months."))
        case .kilometres?: parts.append(String(localized: "Revizii după kilometri", comment: "Summary of a category of one's own: a service by kilometres."))
        case .engineHours?: parts.append(String(localized: "Revizii după ore", comment: "Summary of a category of one's own: a service by engine hours."))
        case nil: break
        }
        if let role = switches.belongsTo {
            parts.append(String(localized: "Ține de: \(BelongingWording.option(role).lowercased(with: .dosarDefault))", comment: "Summary of a category of one's own: what its sections belong to (o mașină)."))
        }
        if parts.isEmpty { return String(localized: "Termene și date importante", comment: "Summary of a category of one's own that keeps nothing more.") }
        return parts.joined(separator: " · ")
    }

    static func title(of counter: CategorySwitches.Counter) -> Text {
        switch counter {
        case .time: Text("După timp", comment: "Service choice: every so many months.")
        case .kilometres: Text("După kilometri", comment: "Service choice: by kilometres.")
        case .engineHours: Text("După orele de motor", comment: "Service choice: by engine hours.")
        }
    }

    static func subtitle(of counter: CategorySwitches.Counter) -> Text {
        switch counter {
        case .time: Text("Fără contor, de obicei o dată pe an: un pian, o centrală.", comment: "Service choice explained: by time.")
        case .kilometres: Text("Ții kilometrajul la zi: o rulotă, o motocicletă.", comment: "Service choice explained: by kilometres.")
        case .engineHours: Text("Ții orele la zi: o barcă, un generator.", comment: "Service choice explained: by engine hours.")
        }
    }

    static func everyTitle(of counter: CategorySwitches.Counter) -> LocalizedStringKey {
        switch counter {
        case .time: "La câte luni?"
        case .kilometres: "La câți km?"
        case .engineHours: "La câte ore?"
        }
    }

    static func everyFootnote(of counter: CategorySwitches.Counter) -> LocalizedStringKey {
        switch counter {
        case .time: "Îți amintesc din timp de fiecare revizie."
        case .kilometres, .engineHours: "Sau o dată pe an, ce vine întâi."
        }
    }

    // MARK: Ține de…

    /// What its sections belong to: nothing, or one of the parts some category in the binder
    /// plays (a home, a car, a person), never a category's name. Choosing one starts them in one
    /// box, as plants do, so a section filed under a car still shows on the binder; the box
    /// choice right under it can be changed.
    private var belonging: some View {
        let choices = CategorySwitches.belongingChoices(among: templates, current: draft.switches.belongsTo)
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            DSSectionHeader("Ține de…")
            DSCard {
                VStack(spacing: 0) {
                    DSCheckRow(
                        title: Text("Nimic", comment: "„Ține de…” choice of a category of one's own: its sections stand on their own."),
                        isOn: draft.switches.belongsTo == nil,
                        action: { draft.switches.belongsTo = nil }
                    )
                    .padding(.vertical, DS.Space.xs)
                    ForEach(choices, id: \.self) { role in
                        DSRowSeparator()
                        DSCheckRow(
                            title: Text(verbatim: BelongingWording.option(role)),
                            isOn: draft.switches.belongsTo == role,
                            action: { belong(to: role) }
                        )
                        .padding(.vertical, DS.Space.xs)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Ține de", comment: "VoiceOver label of the choice of what a category's sections belong to."))
            Text("Fiecare apare și pe pagina celei de care ține și se adaugă și de acolo.", comment: "Explains „Ține de…”: each section shows on the page of the home, car or person it belongs to, and can be added from there.")
                .dsFont(.footnote)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sensoryFeedback(.selection, trigger: draft.switches.belongsTo)
    }

    private func belong(to role: CategoryBehavior.Role) {
        guard draft.switches.belongsTo != role else { return }
        // From nothing to a part: one box for them all, as plants start.
        if draft.switches.belongsTo == nil { draft.switches.grouping = .grouped }
        draft.switches.belongsTo = role
    }

    // MARK: Boxes

    /// One box or one each: the category's grouping, the same choice a box's menu, the category's
    /// page and Setări › Ecranul Dosar make (`CategorySwitches.grouping`).
    private var boxes: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            DSSectionHeader("Pe ecranul Dosar")
            DSCard {
                VStack(spacing: 0) {
                    DSCheckRow(
                        title: Text("Câte o cutie pentru fiecare", comment: "Boxes choice: one box per section."),
                        subtitle: Text("Ca la mașini: fiecare are cutia ei.", comment: "Explains one box per section."),
                        isOn: draft.switches.grouping == .separate,
                        action: { draft.switches.grouping = .separate }
                    )
                    .padding(.vertical, DS.Space.xs)
                    DSRowSeparator()
                    DSCheckRow(
                        title: Text("O cutie pentru toate", comment: "Boxes choice: one box for all of a category's sections, wherever they are filed."),
                        subtitle: Text("Ca la plante: toate stau la un loc.", comment: "Explains one box for all of a category's sections."),
                        isOn: draft.switches.grouping == .grouped,
                        action: { draft.switches.grouping = .grouped }
                    )
                    .padding(.vertical, DS.Space.xs)
                }
            }
        }
    }
}

/// The symbol of a category of one's own, picked from a grid of large targets.
struct CustomSymbolPicker: View {
    @Binding var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            DSSectionHeader("Simbol")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: DS.Space.xs)], spacing: DS.Space.xs) {
                ForEach(CustomSectionDraft.symbols, id: \.self) { option in
                    let isSelected = symbol == option
                    Button {
                        symbol = option
                    } label: {
                        Image(systemName: option)
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(isSelected ? Color.white : DS.Palette.accent)
                            .background(isSelected ? DS.Palette.accent : DS.Palette.fill, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
                    }
                    .buttonStyle(.dsPressable)
                    .accessibilityLabel(Text(verbatim: option.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " ")))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: symbol)
        }
    }
}
