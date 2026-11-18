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

/// A small action beside a row ("Adaugă" next to a suggestion): bordered, never
/// wrapping its title, and still at least a 44 pt target.
struct DSCompactButton: View {
    private let title: Text
    private let systemImage: String?
    private let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.action = action
    }

    /// For titles that are already localized (a wording type's).
    init(verbatim title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = Text(verbatim: title)
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xxs) {
                if let systemImage {
                    Image(systemName: systemImage).accessibilityHidden(true)
                }
                // One line wherever it fits; at the largest text sizes, or beside a long value on a
                // narrow screen, it wraps rather than running past the screen's edge.
                title
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: DS.Control.compactLabel)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        // Beside a row's words it keeps its own width first, so it wraps only when the screen
        // itself is too narrow for it.
        .layoutPriority(1)
    }
}

/// An action written as words inside content (under a notice, under a paper's photo, under a
/// row of a form): borderless, in the accent colour, and its whole 44 pt is the target. The
/// frame is on its label, so a tap anywhere in it lands, never only on the words.
struct DSLinkButton: View {
    private let title: Text
    private let role: ButtonRole?
    private let action: () -> Void

    init(_ title: LocalizedStringKey, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = Text(title)
        self.role = role
        self.action = action
    }

    /// For titles that are already localized (a wording type's).
    init(verbatim title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = Text(verbatim: title)
        self.role = role
        self.action = action
    }

    /// For a title with its own look (a notice's action, in its weight).
    init(title: Text, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            title
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: DS.Control.minimumHitTarget, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
    }
}

extension View {
    /// The full-width look for a control that isn't a plain button, such as a
    /// `ShareLink`: give it a `DSButtonLabel` as its label.
    func dsFullWidthButton(prominent: Bool) -> some View {
        modifier(DSFullWidthButtonStyle(prominent: prominent))
    }
}

private struct DSFullWidthButtonStyle: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent).modifier(DSFullWidthButtonShape())
        } else {
            content.buttonStyle(.bordered).modifier(DSFullWidthButtonShape())
        }
    }
}

/// The label both full-width buttons share: an optional symbol and a title that
/// wraps instead of truncating at large text sizes.
struct DSButtonLabel: View {
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
        .frame(maxWidth: .infinity, minHeight: DS.Control.fullWidthLabel)
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
