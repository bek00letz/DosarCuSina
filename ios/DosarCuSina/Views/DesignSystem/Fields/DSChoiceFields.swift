import SwiftUI

/// Pick one option from a short list, e.g. fuel type or blood group.
/// Options come from templates, so their titles are data and shown verbatim.
struct DSChoiceField<Option: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Option?
    let options: [Option]
    let optionTitle: (Option) -> String
    var isRequired: Bool = false
    var footnote: LocalizedStringKey?

    @Environment(\.dsRevealsValidation) private var revealsValidation

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
                HStack {
                    if let selection {
                        Text(verbatim: optionTitle(selection))
                            .foregroundStyle(DS.Palette.label)
                    } else {
                        Text("Alege", comment: "Placeholder in an empty choice field.")
                            .foregroundStyle(DS.Palette.placeholder)
                    }
                    Spacer(minLength: DS.Space.xs)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: DS.Control.minimumHitTarget)
                .contentShape(.rect)
            }
            .accessibilityLabel(Text(title))
            .accessibilityValue(selection.map { Text(verbatim: optionTitle($0)) } ?? Text("Nimic ales", comment: "VoiceOver value of an empty choice field."))
        }
        .sensoryFeedback(.selection, trigger: selection)
        .dsValidationFeedback(validation)
    }
}

/// Pick any number of options, shown as chips that wrap onto new lines.
struct DSMultiChoiceField<Option: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Set<Option>
    let options: [Option]
    let optionTitle: (Option) -> String
    var footnote: LocalizedStringKey?

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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .dsFont(.captionEmphasized)
                .accessibilityAddTraits(.isHeader)
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
            if let footnote {
                Text(footnote).dsFont(.footnote)
            }
        }
        .accessibilityElement(children: .contain)
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
