import SwiftUI

/// Pick one option from a long list (a country), with search: the list a long
/// `DSChoiceField` opens, and the question a screen asks on its own ("Ce cetățenie are…?").
/// Search folds diacritics and case (`RomanianText.fold`), so "romania" finds „România”.
/// The whole row is the target; the chosen one carries a checkmark.
struct DSChoiceList<Option: Hashable>: View {
    let title: Text
    /// A line above the list, saying what is asked and why.
    var message: Text?
    let options: [Option]
    let optionTitle: (Option) -> String
    let selection: Option?
    /// An optional field offers "Niciuna" first.
    var allowsNone = false
    let choose: (Option?) -> Void

    @State private var query = ""

    private var matches: [Option] {
        let needle = RomanianText.fold(query.trimmingCharacters(in: .whitespaces))
        guard !needle.isEmpty else { return options }
        return options.filter { RomanianText.fold(optionTitle($0)).contains(needle) }
    }

    var body: some View {
        List {
            Section {
                if allowsNone, query.isEmpty {
                    row(Text("Niciuna", comment: "Choice that leaves an optional field empty."), isSelected: selection == nil) { choose(nil) }
                }
                ForEach(matches, id: \.self) { option in
                    row(Text(verbatim: optionTitle(option)), isSelected: option == selection) { choose(option) }
                }
            } header: {
                if let message, query.isEmpty {
                    message
                        .dsFont(.subheadline)
                        .textCase(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .overlay {
            if matches.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Caută", comment: "Search field of a long list of choices."))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func row(_ title: Text, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s) {
                title
                    .dsFont(.body)
                    .foregroundStyle(DS.Palette.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.Palette.accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: DS.Control.minimumHitTarget)
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A `DSChoiceList` in a sheet of its own, with "Renunță": what a long choice field opens.
struct DSChoiceListSheet<Option: Hashable>: View {
    let title: Text
    var message: Text?
    let options: [Option]
    let optionTitle: (Option) -> String
    let selection: Option?
    var allowsNone = false
    let choose: (Option?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DSChoiceList(title: title, message: message, options: options, optionTitle: optionTitle, selection: selection,
                         allowsNone: allowsNone) { option in
                choose(option)
                dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
            }
        }
        // Its own sheet: "Renunță" closes this list, never the form it was opened from.
        .environment(\.dsAttemptDismiss, nil)
    }
}
