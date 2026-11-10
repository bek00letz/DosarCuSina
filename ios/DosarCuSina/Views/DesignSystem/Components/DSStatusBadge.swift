import SwiftUI

extension DSStatus {
    /// How an urgency's tone is drawn. The tone comes from the one urgency rule
    /// (`UrgencyRule`, ios/Shared/Urgency.swift); the design system never decides it.
    init(_ tone: UrgencyTone) {
        switch tone {
        case .overdue: self = .overdue
        case .soon: self = .soon
        case .calm: self = .later
        }
    }

    /// The status a line about a due day takes its text colour from, or nil when
    /// nothing is needed yet and the line keeps its own colour.
    static func urgent(_ tone: UrgencyTone) -> DSStatus? {
        tone == .calm ? nil : DSStatus(tone)
    }
}

/// Badge wording for a due day, from its urgency.
enum DSDueText {
    /// "Azi", "Mâine", "În 5 zile", "Întârziat cu 2 zile", "Depășit de 3 zile".
    static func text(_ urgency: AttentionUrgency, daysRemaining days: Int, from today: Date = Date(), calendar: Calendar = .dosar) -> String {
        WhenWording.standalone(urgency, daysRemaining: days, from: today, calendar: calendar)
    }

    /// For documents and warranties: "Valabil" until it needs the person, then
    /// "Expiră în 20 de zile", "Expiră mâine", "Expiră azi", "Expirat de 3 zile".
    static func expiryText(_ urgency: AttentionUrgency, daysRemaining days: Int, from today: Date = Date(), calendar: Calendar = .dosar) -> String {
        if urgency.tone == .calm {
            return String(localized: "Valabil", comment: "Badge: a document is valid and not close to expiring.")
        }
        let distance = DurationWording.distance(days: days, from: today, calendar: calendar)
        switch urgency {
        case .overdue, .withinGrace:
            return String(localized: "Expirat de \(distance)", comment: "Badge: a document expired this long ago, e.g. '5 zile' or '3 ani'.")
        case .today:
            return String(localized: "Expiră azi", comment: "Badge: a document expires today.")
        case .soon, .upcoming, .later:
            if days == 1 { return String(localized: "Expiră mâine", comment: "Badge: a document expires tomorrow.") }
            return String(localized: "Expiră \(DurationWording.inside(distance))", comment: "Badge: a document expires in a duration such as 'în 5 zile' or 'într-un an'.")
        }
    }
}

/// A compact status capsule: colored icon plus short text, on a soft tint of the status color.
/// Text uses the status's accessible text color, never the vivid fill.
struct DSStatusBadge: View {
    let status: DSStatus
    let text: Text

    /// Grows with the text, so one line is always a capsule and a badge that
    /// wraps at the largest sizes becomes a rounded rectangle, not a tall pill.
    @ScaledMetric(relativeTo: .caption) private var cornerRadius: CGFloat = 12

    /// A badge with custom wording.
    init(_ status: DSStatus, text: Text) {
        self.status = status
        self.text = text
    }

    /// A badge that just names the status ("Întârziat", "Rezolvat"…).
    init(_ status: DSStatus) {
        self.init(status, text: Text(status.title))
    }

    /// A badge for a due day, drawn from its urgency: "În 5 zile", "Azi", "Depășit de 3 zile".
    init(urgency: AttentionUrgency, daysRemaining: Int) {
        self.init(DSStatus(urgency.tone), text: Text(verbatim: DSDueText.text(urgency, daysRemaining: daysRemaining)))
    }

    /// A badge for an expiry, drawn from its urgency: "Valabil" while nothing is needed
    /// yet, then how far it is.
    init(expiry urgency: AttentionUrgency, daysRemaining: Int) {
        self.init(
            urgency.tone == .calm ? .done : DSStatus(urgency.tone),
            text: Text(verbatim: DSDueText.expiryText(urgency, daysRemaining: daysRemaining))
        )
    }

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            Image(systemName: status.systemImage)
                .imageScale(.small)
                .foregroundStyle(status.color)
            // Wraps instead of being cut off when the row is narrow or the text is large.
            text
                .foregroundStyle(status.textColor)
                .lineLimit(1...3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(.caption, weight: .semibold))
        .monospacedDigit()
        .padding(.horizontal, DS.Space.xs)
        .padding(.vertical, DS.Space.xxs)
        .background(status.color.opacity(0.14), in: .rect(cornerRadius: cornerRadius, style: .continuous))
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
