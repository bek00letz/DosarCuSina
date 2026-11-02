import SwiftUI

/// The title above a group of cards or rows, with an optional count and a trailing action
/// ("Vezi tot", "Editează"). Marked as a heading for VoiceOver rotor navigation.
struct DSSectionHeader: View {
    let title: Text
    var subtitle: Text?
    var count: Int?
    var actionTitle: Text?
    var action: (() -> Void)?

    init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        count: Int? = nil,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = Text(title)
        self.subtitle = subtitle.map { Text($0) }
        self.count = count
        self.actionTitle = actionTitle.map { Text($0) }
        self.action = action
    }

    /// For titles that come from data, such as an asset or category name.
    init(verbatim title: String, count: Int? = nil, actionTitle: LocalizedStringKey? = nil, action: (() -> Void)? = nil) {
        self.title = Text(verbatim: title)
        self.count = count
        self.actionTitle = actionTitle.map { Text($0) }
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                    title
                        .dsFont(.sectionTitle)
                    if let count {
                        Text(count, format: .number)
                            .dsFont(.subheadline, numeric: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    subtitle.dsFont(.subheadline)
                }
            }
            Spacer(minLength: DS.Space.xs)
            if let actionTitle, let action {
                Button(action: action) {
                    actionTitle
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, DS.Space.xxs)
    }
}
