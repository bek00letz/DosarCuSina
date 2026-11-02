import SwiftUI

// Rows that show one labelled value. They do different jobs, so they stay two
// components: DSReadOnlyValueRow lines figures up for reading, DSActionValueRow
// offers the value to copy or call.

// MARK: - Read-only

/// A label and a value on one card row, read and compared down a column: costs,
/// totals, prices. Nothing to tap. The value uses tabular digits, and at
/// accessibility sizes it moves under the label.
struct DSReadOnlyValueRow: View {
    let label: Text
    let value: Text

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    label.dsFont(.subheadline)
                    value.dsFont(.headline, numeric: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                    label.dsFont(.body)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                    Spacer(minLength: DS.Space.xs)
                    value.dsFont(.headline, numeric: true)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, DS.Space.xs)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - With an action

/// A value worth one tap: a policy number to copy, a phone to call. The value
/// sits under its title, with a labelled button beside it, never an icon alone.
struct DSActionValueRow: View {
    enum Action {
        case copy
        case call
    }

    let title: Text
    let value: String
    let action: Action

    @State private var copied = 0
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the button moves under the value, so the value keeps the full width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s))
            : AnyLayout(HStackLayout(spacing: DS.Space.s))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                title.dsFont(.footnote)
                Text(verbatim: value)
                    .dsFont(.headline, numeric: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: perform) {
                Label(action == .copy ? LocalizedStringKey("Copiază") : LocalizedStringKey("Sună"), systemImage: action == .copy ? "doc.on.doc" : "phone.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
        .sensoryFeedback(.success, trigger: copied)
        .accessibilityElement(children: .combine)
    }

    private func perform() {
        switch action {
        case .copy:
            UIPasteboard.general.string = value
            copied += 1
            AccessibilityNotification.Announcement(String(localized: "Copiat")).post()
        case .call:
            let digits = value.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel:\(digits)") { openURL(url) }
        }
    }
}
