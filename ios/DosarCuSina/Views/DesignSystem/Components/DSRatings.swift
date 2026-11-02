import SwiftUI

/// A 1–5 rating, with half stars.
///
/// Read-only when `onRate` is nil: five small stars, or with `.compact` one star
/// and the number (nothing at all when there is no rating yet). With `onRate`
/// every star is a 44 pt button, and tapping the current rating clears it.
struct DSStarRating: View {
    enum Style: Sendable {
        /// Five stars.
        case stars
        /// One star and the number, for tight rows. Read-only only.
        case compact
    }

    let rating: Double?
    var style: Style = .stars
    var onRate: ((Int?) -> Void)?

    /// Stars are a rating, not a status, so they don't borrow a status color.
    private static let starColor = Color.yellow

    var body: some View {
        if let onRate {
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        onRate(Int((rating ?? 0).rounded()) == value ? nil : value)
                    } label: {
                        star(for: value)
                            .font(.title2)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.dsPressable)
                    .accessibilityLabel(Text("Nota \(value) din 5", comment: "VoiceOver: a star rating button."))
                    .accessibilityAddTraits(isFilled(value) ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityValue(valueText)
            .sensoryFeedback(.selection, trigger: rating)
        } else {
            switch style {
            case .stars:
                HStack(spacing: 1) {
                    ForEach(1...5, id: \.self) { value in
                        star(for: value).imageScale(.small)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(valueText)
            case .compact:
                if let rating {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(Self.starColor)
                            .imageScale(.small)
                            .accessibilityHidden(true)
                        Text(verbatim: Self.formatted(rating))
                    }
                    .dsFont(.subheadline, numeric: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(valueText)
                }
            }
        }
    }

    private func isFilled(_ value: Int) -> Bool {
        (rating ?? 0) >= Double(value) - 0.25
    }

    private func star(for value: Int) -> some View {
        let filled = isFilled(value)
        let half = !filled && (rating ?? 0) >= Double(value) - 0.75
        return Image(systemName: filled ? "star.fill" : (half ? "star.leadinghalf.filled" : "star"))
            .foregroundStyle(filled || half ? Self.starColor : DS.Palette.tertiaryLabel)
            .accessibilityHidden(true)
    }

    private var valueText: Text {
        if let rating {
            return Text("\(Self.formatted(rating)) din 5 stele", comment: "VoiceOver value of a star rating.")
        }
        return Text("Fără notă", comment: "VoiceOver value of a rating that hasn't been given.")
    }

    private static func formatted(_ rating: Double) -> String {
        rating.formatted(.number.precision(.fractionLength(0...1)).locale(.dosarDefault))
    }
}
