import SwiftUI

/// Marks records created by "Încarcă exemple", so they are never mistaken for real data.
struct DSExampleBadge: View {
    var body: some View {
        Text("Exemplu", comment: "Badge on example data loaded to explore the app.")
            .font(.system(.caption2, weight: .semibold))
            .foregroundStyle(DS.Palette.secondaryLabel)
            .padding(.horizontal, DS.Space.xs)
            .padding(.vertical, 2)
            .background(DS.Palette.fillStrong, in: .capsule)
            .accessibilityLabel(Text("Date de exemplu", comment: "VoiceOver label of the example badge."))
    }
}
