import SwiftUI

extension DSStatus {
    /// Display classification for a due date. The obligation engine owns the real
    /// attention rules; this is the shared mapping from "days left" to a badge.
    /// - Parameters:
    ///   - daysRemaining: Whole calendar days from today to the due date (negative when late).
    ///   - soonWithinDays: How many days ahead still counts as "soon".
    static func forDue(daysRemaining: Int, isDone: Bool, soonWithinDays: Int = 14) -> DSStatus {
        if isDone { return .done }
        if daysRemaining < 0 { return .overdue }
        if daysRemaining <= soonWithinDays { return .soon }
        return .later
    }
}

/// Plain-language wording for how far away a due date is, with correct Romanian plurals
/// ("în 2 zile", "în 20 de zile").
enum DSDueText {
    static func text(daysRemaining days: Int, isDone: Bool = false) -> LocalizedStringResource {
        if isDone {
            return LocalizedStringResource("Rezolvat", comment: "Badge on a completed obligation.")
        }
        switch days {
        case ..<0:
            let late = -days
            return LocalizedStringResource("Întârziat cu \(late) zile", comment: "Badge: the obligation is late. The number is how many days late.")
        case 0:
            return LocalizedStringResource("Azi", comment: "Badge: the obligation is due today.")
        case 1:
            return LocalizedStringResource("Mâine", comment: "Badge: the obligation is due tomorrow.")
        default:
            return LocalizedStringResource("În \(days) zile", comment: "Badge: the obligation is due in this many days.")
        }
    }
}

/// A compact status capsule: colored icon plus short text, on a soft tint of the status color.
/// Text uses the status's accessible text color, never the vivid fill.
struct DSStatusBadge: View {
    let status: DSStatus
    let text: Text

    /// A badge with custom wording.
    init(_ status: DSStatus, text: Text) {
        self.status = status
        self.text = text
    }

    /// A badge that just names the status ("Întârziat", "Rezolvat"…).
    init(_ status: DSStatus) {
        self.init(status, text: Text(status.title))
    }

    /// A badge for a due date: picks the status and the wording from the days remaining.
    init(daysRemaining: Int, isDone: Bool = false, soonWithinDays: Int = 14) {
        self.init(
            DSStatus.forDue(daysRemaining: daysRemaining, isDone: isDone, soonWithinDays: soonWithinDays),
            text: Text(DSDueText.text(daysRemaining: daysRemaining, isDone: isDone))
        )
    }

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            Image(systemName: status.systemImage)
                .imageScale(.small)
                .foregroundStyle(status.color)
            text
                .foregroundStyle(status.textColor)
                .lineLimit(1)
        }
        .font(.system(.caption, weight: .semibold))
        .monospacedDigit()
        .padding(.horizontal, DS.Space.xs)
        .padding(.vertical, DS.Space.xxs)
        .background(status.color.opacity(0.14), in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// A small colored dot, for dense lists where a full badge would be noise.
struct DSStatusDot: View {
    let status: DSStatus
    @ScaledMetric(relativeTo: .caption) private var side: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: side, height: side)
            .accessibilityLabel(Text(status.title))
    }
}
