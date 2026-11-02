import SwiftUI

// Components first needed by the intake screens (Adaugă, Urmează, the
// obligation page, the visit flow, onboarding). Built only from DS tokens.

// MARK: - Big choice cards

/// A whole-card button with an icon, a title and a line of explanation, for
/// the few big choices on a screen ("Fotografiază un act", "Din Fișiere").
struct DSActionCard: View {
    let title: Text
    var subtitle: Text?
    let systemImage: String
    var tint: Color = DS.Palette.accent
    let action: () -> Void

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, systemImage: String, tint: Color = DS.Palette.accent, action: @escaping () -> Void) {
        self.title = Text(title)
        self.subtitle = subtitle.map { Text($0) }
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            DSCard {
                HStack(spacing: DS.Space.s) {
                    DSIconWell(systemImage: systemImage, tint: tint)
                    VStack(alignment: .leading, spacing: 2) {
                        title.dsFont(.headline)
                        if let subtitle { subtitle.dsFont(.subheadline) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.forward")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
            }
        }
        .buttonStyle(.dsPressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Facts with an action

/// A fact worth one tap: a policy number to copy, a phone to call.
/// The action is a labelled button, never an icon alone.
struct DSFactRow: View {
    enum Action {
        case copy
        case call
    }

    let title: Text
    let value: String
    let action: Action

    @State private var copied = 0
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: DS.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                title.dsFont(.footnote)
                Text(verbatim: value)
                    .dsFont(.headline, numeric: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: perform) {
                Label(action == .copy ? "Copiază" : "Sună", systemImage: action == .copy ? "doc.on.doc" : "phone.fill")
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

// MARK: - Labels

/// "Exemplu" on anything that comes from the example household.
struct DSExampleTag: View {
    var body: some View {
        Text("Exemplu", comment: "Tag on example data")
            .font(.system(.caption2, weight: .semibold))
            .foregroundStyle(DS.Palette.secondaryLabel)
            .padding(.horizontal, DS.Space.xs - 2)
            .padding(.vertical, 2)
            .background(DS.Palette.fill, in: .capsule)
            .accessibilityLabel(Text("Date de exemplu"))
    }
}

/// A numbered step in written instructions ("1 Apasă Trimite").
struct DSStepRow: View {
    let number: Int
    let text: Text

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text(number, format: .number)
                .font(.system(.subheadline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(DS.Palette.accent)
                .frame(width: side, height: side)
                .background(DS.Palette.accent.opacity(0.14), in: .circle)
                .accessibilityHidden(true)
            text
                .dsFont(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Intake components") {
    ScrollView {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            DSActionCard("Fotografiază un act", subtitle: "Pagina se îndreaptă singură.", systemImage: "camera.fill") {}
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    DSCheckRow(title: Text(verbatim: "Plăcuțe frână față"), subtitle: Text(verbatim: "Ultima dată: martie 2024"), isOn: true, action: {}) {
                        Text(verbatim: "380 lei").dsFont(.body, numeric: true)
                    }
                    DS.Hairline()
                    DSCheckRow(title: Text(verbatim: "Filtru de habitaclu"), isOn: false) {}
                }
            }
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    DSFactRow(title: Text(verbatim: "Număr poliță"), value: "RO/00/EX0001", action: .copy)
                    DSFactRow(title: Text(verbatim: "Telefon pentru daune"), value: "0700 000 001", action: .call)
                    HStack {
                        DSStarRating(rating: 4.5, style: .compact)
                        DSExampleTag()
                    }
                    DSStarRating(rating: 3) { _ in }
                }
            }
            DSStepRow(number: 1, text: Text(verbatim: "Apasă „Trimite”."))
            DSPrimaryButton("Salvează", systemImage: "checkmark") {}
            DSSecondaryButton("Mai târziu") {}
        }
        .padding(DS.Space.m)
    }
    .background(DS.Palette.background)
}
