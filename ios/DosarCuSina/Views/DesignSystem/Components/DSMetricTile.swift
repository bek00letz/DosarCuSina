import SwiftUI

/// A tile for one number that matters: "Cheltuieli în 30 de zile", "Kilometraj".
/// The value is a `Text` so callers format it with format styles (currency, units, dates).
struct DSMetricTile<Value: View>: View {
    let title: Text
    var systemImage: String?
    var tint: Color = DS.Palette.accent
    var footnote: Text?
    @ViewBuilder var value: Value

    init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        tint: Color = DS.Palette.accent,
        footnote: Text? = nil,
        @ViewBuilder value: () -> Value
    ) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.tint = tint
        self.footnote = footnote
        self.value = value()
    }

    var body: some View {
        DSCard(padding: DS.Space.m) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(spacing: DS.Space.xxs) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .foregroundStyle(tint)
                            .accessibilityHidden(true)
                    }
                    title
                }
                .dsFont(.captionEmphasized)

                value
                    .dsFont(.title, numeric: true)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let footnote {
                    footnote.dsFont(.footnote)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
