import Foundation

/// What a deadline of the person's own is, from two plain answers: how important
/// it is and whether it repeats. Its kind comes from the first, its reminders from
/// the kind's default profile.
enum DeadlineChoice {
    enum Importance: String, CaseIterable, Identifiable, Hashable {
        case legal, money, health, reminder

        var id: String { rawValue }

        var kind: ObligationKind {
            switch self {
            case .legal: .legal
            case .money: .payment
            case .health: .health
            case .reminder: .routine
            }
        }

        /// The answer a deadline's kind is, for the four kinds the answers give; nil for any
        /// other (a deadline from an older backup with no category's blueprint), whose kind
        /// "Editează" then leaves as it is.
        init?(kind: ObligationKind) {
            guard let answer = Self.allCases.first(where: { $0.kind == kind }) else { return nil }
            self = answer
        }

        var title: String {
            switch self {
            case .legal: String(localized: "Obligatoriu prin lege", comment: "How important a deadline is.")
            case .money: String(localized: "Ține de bani", comment: "How important a deadline is.")
            case .health: String(localized: "Ține de sănătate", comment: "How important a deadline is.")
            case .reminder: String(localized: "Doar să nu uit", comment: "How important a deadline is.")
            }
        }
    }

    /// The three choices "Se repetă" offered before `DSRepeatField`. Kept, switched off
    /// (`DeadlineForm.usesRepeatField`), as the way back; remove once the owner agrees.
    enum Repeat: String, CaseIterable, Identifiable, Hashable {
        case never, monthly, yearly

        var id: String { rawValue }

        var rule: RecurrenceRule {
            switch self {
            case .never: .none
            case .monthly: .interval(.months(1), anchor: .dueDate)
            case .yearly: .interval(.years(1), anchor: .dueDate)
            }
        }

        var title: String {
            switch self {
            case .never: String(localized: "O singură dată", comment: "Repeat option.")
            case .monthly: String(localized: "În fiecare lună", comment: "Repeat option.")
            case .yearly: String(localized: "În fiecare an", comment: "Repeat option.")
            }
        }
    }

    /// The reminders a deadline of this importance gets: its kind's default profile.
    static func reminders(for importance: Importance) -> ReminderProfile {
        importance.kind.defaultProfile
    }

    /// A deadline's reminders once its importance moves it from kind `old` to `new`: what the
    /// person can't set (how serious it is, how many days late is still calm) is the new kind's;
    /// the leads and the follow-up the new kind's only while they are still the old kind's own,
    /// else the person's, as they set them. The travel margin stays. The one rule, for
    /// `ObligationActions.setImportance` and for the edit sheet while it is open.
    static func reminders(_ profile: ReminderProfile, from old: ObligationKind, to new: ObligationKind) -> ReminderProfile {
        guard old != new else { return profile }
        let was = old.defaultProfile
        let becomes = new.defaultProfile
        let isTheKinds = profile.leadDays == was.leadDays && profile.followUpAfterLapse == was.followUpAfterLapse
        return ReminderProfile(
            leadDays: isTheKinds ? becomes.leadDays : profile.leadDays,
            consequence: becomes.consequence,
            graceDays: becomes.graceDays,
            followUpAfterLapse: isTheKinds ? becomes.followUpAfterLapse : profile.followUpAfterLapse,
            travelMarginDays: profile.travelMarginDays
        )
    }
}
