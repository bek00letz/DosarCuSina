import SwiftUI

// Rows that show one labelled value. They do different jobs, so they stay two
// components: DSReadOnlyValueRow lines figures up for reading, DSActionValueRow
// offers the value to copy or call.

// MARK: - Read-only

/// A label and a value on one card row, read and compared down a column: costs,
/// totals, prices. Nothing to tap. The value uses tabular digits, and when the
/// two don't fit on one line it moves under the label (`DSAdaptiveStack`).
struct DSReadOnlyValueRow: View {
    let label: Text
    let value: Text

    var body: some View {
        DSAdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: DS.Space.s, stackedSpacing: 2) {
            label.dsFont(.body)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
            value.dsFont(.headline, numeric: true)
        }
        .padding(.vertical, DS.Space.xs)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - With an action

/// A value worth one tap: a policy number to copy, a phone to call. The value
/// sits under its title, with a labelled button beside it, never an icon alone.
/// A personal value (`copies: .personal`) stays on this phone's clipboard for a minute only.
struct DSActionValueRow: View {
    enum Action {
        case copy
        case call
    }

    let title: Text
    let value: String
    let action: Action
    var copies: Clipboard.Kind = .ordinary
    /// A line under the value ("Bun de călătorit până pe …").
    var note: Text?
    /// How urgent the value is, for a date something stops being valid on: drawn, never decided here.
    var status: DSStatusBadge?

    @State private var copied = 0
    @Environment(\.openURL) private var openURL

    var body: some View {
        DSValueWithActions {
            VStack(alignment: .leading, spacing: 2) {
                title.dsFont(.footnote)
                Text(verbatim: value)
                    .dsFont(.headline, numeric: true)
                    .textSelection(.enabled)
                if let note {
                    note.dsFont(.subheadline, numeric: true)
                }
                if let status {
                    status.padding(.top, DS.Space.xxs)
                }
            }
        } actions: {
            Button(action: perform) {
                DSValueActionLabel(title: action == .copy ? "Copiază" : "Sună", systemImage: action == .copy ? "doc.on.doc" : "phone.fill")
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
            Clipboard.copy(value, copies)
            copied += 1
            AccessibilityNotification.Announcement(copies == .personal
                ? String(localized: "Copiat. Se șterge singur din memorie într-un minut.", comment: "Note after copying a secret code.")
                : String(localized: "Copiat")).post()
        case .call:
            let digits = value.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel:\(digits)") { openURL(url) }
        }
    }
}

/// A value with its buttons: side by side when everything fits on one line, the
/// buttons on their own line under the value otherwise, and under each other when
/// even they don't fit side by side. Button labels never wrap, so a narrow screen
/// or large text moves the buttons down instead of breaking "Copiază" into
/// syllables. The one layout for every value-with-actions row.
struct DSValueWithActions<Value: View, Actions: View>: View {
    @ViewBuilder let value: () -> Value
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        DSAdaptiveStack(spacing: DS.Space.s) {
            value().frame(maxWidth: .infinity, alignment: .leading)
            // Buttons that don't fit beside each other stack too, so none runs off the screen.
            DSAdaptiveStack(spacing: DS.Space.xs) { actions() }
                .layoutPriority(1)
        }
    }
}

/// A small labelled button for a value's action ("Copiază", "Arată", "Sună"):
/// bordered, at least 44 pt tall, its label on one line.
struct DSValueActionLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        // One line, never wrapped; the row moves the button down instead, and a
        // label wider than the whole screen shortens rather than running off it.
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .frame(minHeight: 44)
    }
}
