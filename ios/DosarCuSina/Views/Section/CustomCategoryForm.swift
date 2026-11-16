import SwiftUI
import SwiftData

/// What a category of the person's own is, asked the same way when it is made
/// ("Altceva…") and when it is changed later (Setări › Categoriile tale): its name, its
/// symbol and a few plain questions (`CategorySwitches`). Every row is one whole target.
///
/// A shaped screen: what its service counts by says its own words (`CategorySwitches.Counter`),
/// the rest are `CustomCategoryWording`'s; the file holds no words of its own (the
/// `text-in-shaped-screen` check), and `docs/COPY_MATRIX.md` lists them.
struct CustomCategoryForm: View {
    @Binding var draft: CustomSectionDraft
    /// Said under the questions, such as what happens to what was kept when one is turned off.
    var footnote: Text?

    /// The categories in the binder, for what „Ține de…” offers (`CategorySwitches.belongingChoices`).
    @Query private var templates: [CategoryTemplate]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            DSTextField(LocalizedStringKey(CustomCategoryWording.name), text: $draft.name,
                        prompt: LocalizedStringKey(CustomCategoryWording.namePrompt), isRequired: true)
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
            DSSectionHeader(verbatim: CustomCategoryWording.keeps)
            DSCard {
                VStack(spacing: 0) {
                    DSCheckRow(
                        title: Text(verbatim: CustomCategoryWording.documents),
                        subtitle: Text(verbatim: CustomCategoryWording.documentsHint),
                        isOn: $draft.switches.hasDocuments
                    )
                    .padding(.vertical, DS.Space.xs)
                    DSRowSeparator()
                    DSCheckRow(
                        title: Text(verbatim: CustomCategoryWording.bills),
                        subtitle: Text(verbatim: CustomCategoryWording.billsHint),
                        isOn: $draft.switches.hasBills
                    )
                    .padding(.vertical, DS.Space.xs)
                    DSRowSeparator()
                    DSCheckRow(
                        title: Text(verbatim: CustomCategoryWording.service),
                        subtitle: Text(verbatim: CustomCategoryWording.serviceHint),
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
                        title: Text(verbatim: counter.title),
                        subtitle: Text(verbatim: counter.subtitle),
                        isOn: draft.switches.service?.counter == counter,
                        action: {
                            guard draft.switches.service?.counter != counter else { return }
                            draft.switches.service = CategorySwitches.Service(counter)
                        }
                    )
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: CustomCategoryWording.serviceCounter))
            if let counter = draft.switches.service?.counter {
                DSMetricField(
                    LocalizedStringKey(counter.everyTitle),
                    value: Binding(
                        get: { draft.switches.service.flatMap { $0.every > 0 ? Double($0.every) : nil } },
                        // Empty or not a whole number: kept as missing, so it can't be saved.
                        set: { value in draft.switches.service?.every = value.flatMap { $0 >= 1 && $0 <= 1_000_000 && $0 == $0.rounded() ? Int($0) : nil } ?? 0 }
                    ),
                    unit: counter.everyUnit,
                    fractionDigits: 0...0,
                    isRequired: true,
                    footnote: LocalizedStringKey(counter.everyFootnote),
                    validator: { $0 >= 1 && $0 <= 1_000_000 && $0 == $0.rounded() ? .valid : .invalid(CustomCategoryWording.wholeNumber) }
                )
                // A new counter is a new field, starting at its own number.
                .id(counter)
            }
        }
        .padding(.leading, DS.Space.xl)
    }

    /// One line saying what a category keeps, for a list of categories: "Acte · Revizii după ore".
    static func summary(of switches: CategorySwitches) -> String {
        CustomCategoryWording.summary(of: switches)
    }

    // MARK: Ține de…

    /// What its sections belong to: nothing, or one of the parts some category in the binder
    /// plays (a home, a car, a person), never a category's name. Choosing one starts them in one
    /// box, as plants do, so a section filed under a car still shows on the binder; the box
    /// choice right under it can be changed.
    private var belonging: some View {
        let choices = CategorySwitches.belongingChoices(among: templates, current: draft.switches.belongsTo)
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            DSSectionHeader(verbatim: CustomCategoryWording.belongs)
            DSCard {
                VStack(spacing: 0) {
                    DSCheckRow(
                        title: Text(verbatim: CustomCategoryWording.belongsToNothing),
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
            .accessibilityLabel(Text(verbatim: CustomCategoryWording.belongsLabel))
            Text(verbatim: CustomCategoryWording.belongsFootnote)
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
            DSSectionHeader(verbatim: CustomCategoryWording.boxes)
            DSCard {
                VStack(spacing: 0) {
                    DSCheckRow(
                        title: Text(verbatim: CustomCategoryWording.boxEach),
                        subtitle: Text(verbatim: CustomCategoryWording.boxEachHint),
                        isOn: draft.switches.grouping == .separate,
                        action: { draft.switches.grouping = .separate }
                    )
                    .padding(.vertical, DS.Space.xs)
                    DSRowSeparator()
                    DSCheckRow(
                        title: Text(verbatim: CustomCategoryWording.boxAll),
                        subtitle: Text(verbatim: CustomCategoryWording.boxAllHint),
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
            DSSectionHeader(verbatim: CustomCategoryWording.symbol)
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
                    .accessibilityLabel(Text(verbatim: CustomCategoryWording.spokenName(ofSymbol: option)))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: symbol)
        }
    }
}
