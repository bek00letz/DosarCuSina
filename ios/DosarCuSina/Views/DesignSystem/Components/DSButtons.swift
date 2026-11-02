import SwiftUI

// Full-width actions. The main action of a screen is filled; every other
// full-width action is bordered. Both draw the same label, so a primary and a
// secondary button stacked together always line up.

/// The main action of a screen: full width, at least 50 pt tall, text always shown.
struct DSPrimaryButton: View {
    private let title: Text
    private let systemImage: String?
    private let role: ButtonRole?
    private let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(Text(title), systemImage: systemImage, role: role, action: action)
    }

    /// For titles that are already user or template data, or already localized.
    init(verbatim title: String, systemImage: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(Text(verbatim: title), systemImage: systemImage, role: role, action: action)
    }

    /// For components that receive their title as `Text`.
    init(_ title: Text, systemImage: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            DSButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.borderedProminent)
        .modifier(DSFullWidthButtonShape())
    }
}

/// Any other full-width action: quieter than `DSPrimaryButton`, same size and label.
/// Use `role: .destructive` for deletions.
struct DSSecondaryButton: View {
    private let title: Text
    private let systemImage: String?
    private let role: ButtonRole?
    private let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(Text(title), systemImage: systemImage, role: role, action: action)
    }

    /// For titles that are already user or template data, or already localized.
    init(verbatim title: String, systemImage: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(Text(verbatim: title), systemImage: systemImage, role: role, action: action)
    }

    /// For components that receive their title as `Text`.
    init(_ title: Text, systemImage: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            DSButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .modifier(DSFullWidthButtonShape())
    }
}

/// The label both full-width buttons share: an optional symbol and a title that
/// wraps instead of truncating at large text sizes.
private struct DSButtonLabel: View {
    let title: Text
    let systemImage: String?

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            if let systemImage {
                Image(systemName: systemImage).accessibilityHidden(true)
            }
            title.multilineTextAlignment(.center)
        }
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 34)
    }
}

/// Size and corners shared by both full-width buttons.
private struct DSFullWidthButtonShape: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonBorderShape(.roundedRectangle(radius: DS.Radius.control + 2))
            .controlSize(.large)
    }
}
