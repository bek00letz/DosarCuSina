import SwiftUI

extension DS {
    /// Semantic colors. Each one has light, dark and Increase Contrast variants
    /// in the asset catalog, so nothing here is inverted or hand-adjusted for dark mode.
    ///
    /// Rule of thumb: one accent, status colors only for status, everything else
    /// from the system's label and background colors.
    enum Palette {
        /// The app's single accent: buttons, links, selection, focus rings.
        static let accent = Color.accentColor

        // Surfaces (system colors already adapt to dark mode and Increase Contrast).
        static let background = Color(uiColor: .systemGroupedBackground)
        static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        static let surfaceRaised = Color(uiColor: .tertiarySystemGroupedBackground)
        static let fill = Color(uiColor: .tertiarySystemFill)
        static let fillStrong = Color(uiColor: .secondarySystemFill)
        static let separator = Color(uiColor: .separator)

        // Text.
        static let label = Color(uiColor: .label)
        static let secondaryLabel = Color(uiColor: .secondaryLabel)
        static let tertiaryLabel = Color(uiColor: .tertiaryLabel)
        static let placeholder = Color(uiColor: .placeholderText)
    }
}

// MARK: - Status

/// Where an obligation stands. Drives badge color, icon and wording everywhere.
enum DSStatus: String, CaseIterable, Sendable, Identifiable {
    case overdue
    case soon
    case later
    case done

    var id: String { rawValue }

    /// Vivid fill for dots, icons, rings and tinted backgrounds.
    var color: Color {
        switch self {
        case .overdue: Color(.statusOverdue)
        case .soon: Color(.statusSoon)
        case .later: Color(.statusLater)
        case .done: Color(.statusDone)
        }
    }

    /// Text color that keeps 4.5:1 contrast on cards and on its own tinted fill.
    var textColor: Color {
        switch self {
        case .overdue: Color(.statusOverdueText)
        case .soon: Color(.statusSoonText)
        case .later: Color(.statusLaterText)
        case .done: Color(.statusDoneText)
        }
    }

    var systemImage: String {
        switch self {
        case .overdue: "exclamationmark.circle.fill"
        case .soon: "clock.fill"
        case .later: "calendar"
        case .done: "checkmark.circle.fill"
        }
    }

    /// Short name of the state, also used as the VoiceOver label.
    var title: LocalizedStringResource {
        switch self {
        case .overdue: LocalizedStringResource("Întârziat", comment: "Status of an obligation whose due date has passed.")
        case .soon: LocalizedStringResource("În curând", comment: "Status of an obligation due within the next days.")
        case .later: LocalizedStringResource("Mai târziu", comment: "Status of an obligation that is not due soon.")
        case .done: LocalizedStringResource("Rezolvat", comment: "Status of an obligation that has been completed.")
        }
    }
}
