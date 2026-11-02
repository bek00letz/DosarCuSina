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

// MARK: - Steps

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
                    DSActionValueRow(title: Text(verbatim: "Număr poliță"), value: "RO/00/EX0001", action: .copy)
                    DSActionValueRow(title: Text(verbatim: "Telefon pentru daune"), value: "0700 000 001", action: .call)
                    HStack {
                        DSStarRating(rating: 4.5, style: .compact)
                        DSExampleBadge()
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
