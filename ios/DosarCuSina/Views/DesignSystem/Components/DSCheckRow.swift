import SwiftUI

/// A whole-row check, at least 44 pt tall: checklist parts, reminder choices,
/// one pick out of several. The row is the button; the checkmark is not a tiny target.
///
/// `detail` appears under the row only while it is checked, and may hold fields.
/// Use the `action:` form when checking means something more than flipping a
/// Bool (picking one of several, saving at once); otherwise pass a binding.
struct DSCheckRow<Detail: View>: View {
    private let title: Text
    private let subtitle: Text?
    private let isOn: Bool
    private let action: () -> Void
    private let detail: Detail

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(title: Text, subtitle: Text? = nil, isOn: Bool, action: @escaping () -> Void, @ViewBuilder detail: () -> Detail) {
        self.title = title
        self.subtitle = subtitle
        self.isOn = isOn
        self.action = action
        self.detail = detail()
    }

    init(title: Text, subtitle: Text? = nil, isOn: Binding<Bool>, @ViewBuilder detail: () -> Detail) {
        self.init(title: title, subtitle: subtitle, isOn: isOn.wrappedValue, action: { isOn.wrappedValue.toggle() }, detail: detail)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Button(action: action) {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isOn ? DS.Palette.accent : DS.Palette.tertiaryLabel)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        title.dsFont(.body)
                        if let subtitle { subtitle.dsFont(.footnote) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.dsPressable)
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            if isOn {
                detail
                    .transition(DS.Motion.transition(from: .top, reduceMotion: reduceMotion))
            }
        }
        .sensoryFeedback(.selection, trigger: isOn)
        .animation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion), value: isOn)
    }
}

extension DSCheckRow where Detail == EmptyView {
    init(title: Text, subtitle: Text? = nil, isOn: Bool, action: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, isOn: isOn, action: action, detail: { EmptyView() })
    }

    init(title: Text, subtitle: Text? = nil, isOn: Binding<Bool>) {
        self.init(title: title, subtitle: subtitle, isOn: isOn, detail: { EmptyView() })
    }
}
