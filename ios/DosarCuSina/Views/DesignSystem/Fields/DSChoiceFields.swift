import SwiftUI

/// Pick one option, e.g. fuel type or blood group: a menu for a short list, and for a long
/// one (a country) a searchable list in a sheet (`DSChoiceListSheet`).
/// Options come from templates, so their titles are data and shown verbatim.
struct DSChoiceField<Option: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Option?
    let options: [Option]
    let optionTitle: (Option) -> String
    var isRequired: Bool = false
    var footnote: LocalizedStringKey?

    /// The most options a menu holds; a longer list opens with search.
    static var menuLimit: Int { 24 }

    @Environment(\.dsRevealsValidation) private var revealsValidation
    @State private var isChoosing = false

    init(
        _ title: LocalizedStringKey,
        selection: Binding<Option?>,
        options: [Option],
        isRequired: Bool = false,
        footnote: LocalizedStringKey? = nil,
        optionTitle: @escaping (Option) -> String
    ) {
        self.title = title
        self._selection = selection
        self.options = options
        self.isRequired = isRequired
        self.footnote = footnote
        self.optionTitle = optionTitle
    }

    private var validation: DSValidation {
        selection == nil && isRequired && revealsValidation ? .requiredMissing : .valid
    }

    var body: some View {
        DSFieldContainer(
            title: Text(title),
            isFocused: false,
            validation: validation,
            footnote: footnote.map { Text($0) }
        ) {
            if options.count > Self.menuLimit {
                Button { isChoosing = true } label: { chosen(symbol: "chevron.forward") }
                    .buttonStyle(.dsPressable)
                    .accessibilityLabel(Text(title))
                    .accessibilityValue(accessibilityValue)
                    .dsSheet(isPresented: $isChoosing) {
                        DSChoiceListSheet(title: Text(title), options: options, optionTitle: optionTitle, selection: selection,
                                          allowsNone: !isRequired) { selection = $0 }
                    }
            } else {
                Menu {
                    Picker(selection: $selection) {
                        if !isRequired {
                            Text("Niciuna", comment: "Choice that leaves an optional field empty.")
                                .tag(Option?.none)
                        }
                        ForEach(options, id: \.self) { option in
                            Text(verbatim: optionTitle(option)).tag(Option?.some(option))
                        }
                    } label: {
                        Text(title)
                    }
                } label: {
                    chosen(symbol: "chevron.up.chevron.down")
                }
                .accessibilityLabel(Text(title))
                .accessibilityValue(accessibilityValue)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .dsValidationFeedback(validation)
    }

    /// What is chosen, or "Alege", with the control's symbol.
    private func chosen(symbol: String) -> some View {
        HStack {
            if let selection {
                Text(verbatim: optionTitle(selection))
                    .foregroundStyle(DS.Palette.label)
            } else {
                Text("Alege", comment: "Placeholder in an empty choice field.")
                    .foregroundStyle(DS.Palette.placeholder)
            }
            Spacer(minLength: DS.Space.xs)
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .accessibilityHidden(true)
        }
        .frame(minHeight: DS.Control.minimumHitTarget)
        .contentShape(.rect)
    }

    private var accessibilityValue: Text {
        selection.map { Text(verbatim: optionTitle($0)) } ?? Text("Nimic ales", comment: "VoiceOver value of an empty choice field.")
    }
}

/// Pick any number of options, shown as chips that wrap onto new lines. A long list (a
/// person's citizenships) shows only the chosen ones, each taken away with a tap, and
/// „Adaugă” opens the same searchable list a long `DSChoiceField` opens (`DSChoiceListSheet`).
struct DSMultiChoiceField<Option: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Set<Option>
    let options: [Option]
    let optionTitle: (Option) -> String
    var footnote: LocalizedStringKey?

    @State private var isAdding = false

    init(
        _ title: LocalizedStringKey,
        selection: Binding<Set<Option>>,
        options: [Option],
        footnote: LocalizedStringKey? = nil,
        optionTitle: @escaping (Option) -> String
    ) {
        self.title = title
        self._selection = selection
        self.options = options
        self.footnote = footnote
        self.optionTitle = optionTitle
    }

    /// Whether the options are too many to show at once: the same limit as a choice's menu.
    private var isLong: Bool { options.count > DSChoiceField<Option>.menuLimit }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .dsFont(.captionEmphasized)
                .accessibilityAddTraits(.isHeader)
            if isLong {
                longList
            } else {
                DSFlowLayout {
                    ForEach(options, id: \.self) { option in
                        let isSelected = selection.contains(option)
                        DSChip(
                            verbatim: optionTitle(option),
                            systemImage: isSelected ? "checkmark" : nil,
                            isSelected: isSelected
                        ) {
                            if isSelected {
                                selection.remove(option)
                            } else {
                                selection.insert(option)
                            }
                        }
                    }
                }
            }
            if let footnote {
                Text(footnote).dsFont(.footnote)
            }
        }
        .accessibilityElement(children: .contain)
        .sensoryFeedback(.selection, trigger: selection)
    }

    /// The chosen options, in the list's order, each with its way out, and „Adaugă”.
    private var longList: some View {
        DSFlowLayout {
            ForEach(options.filter(selection.contains), id: \.self) { option in
                DSChip(verbatim: optionTitle(option), systemImage: "xmark", isSelected: true) {
                    selection.remove(option)
                }
                .accessibilityHint(Text("Atinge ca să o scoți.", comment: "VoiceOver hint of a chosen option in a long multiple choice: tapping takes it away."))
            }
            DSChip(title: Text("Adaugă", comment: "Adds an option to a long multiple choice, from a searchable list."), systemImage: "plus", isSelected: false) {
                isAdding = true
            }
            .dsSheet(isPresented: $isAdding) {
                DSChoiceListSheet(title: Text(title), options: options.filter { !selection.contains($0) }, optionTitle: optionTitle,
                                  selection: nil) { chosen in
                    if let chosen { selection.insert(chosen) }
                }
            }
        }
    }
}

/// An on/off setting with an optional explanation underneath.
struct DSToggleField: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    var footnote: LocalizedStringKey?
    var systemImage: String?

    init(_ title: LocalizedStringKey, isOn: Binding<Bool>, systemImage: String? = nil, footnote: LocalizedStringKey? = nil) {
        self.title = title
        self._isOn = isOn
        self.systemImage = systemImage
        self.footnote = footnote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isOn) {
                if let systemImage {
                    Label { Text(title) } icon: { Image(systemName: systemImage) }
                } else {
                    Text(title)
                }
            }
            .tint(DS.Palette.accent)
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .background(DS.Palette.fill, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
            .sensoryFeedback(.selection, trigger: isOn)

            if let footnote {
                Text(footnote)
                    .dsFont(.footnote)
                    .padding(.horizontal, DS.Space.xxs)
            }
        }
    }
}
