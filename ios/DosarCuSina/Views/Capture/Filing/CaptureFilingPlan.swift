import Foundation

/// What saving a review will do, worked out once from the review as it stands: the
/// category the values land in, the deadline (made, moved or left), how early it
/// reminds, and who issued the document. The review shows this plan and
/// `CaptureFiler` carries it out, so the preview never promises a reminder that saving
/// doesn't make.
struct CaptureFilingPlan {
    /// The deadline saving makes or moves.
    struct Deadline {
        enum Action: Equatable {
            /// A new deadline from the blueprint, on `day`.
            case create
            /// The section's deadline from this blueprint moves to `day` (or its cycle closes
            /// and the next is `day`; see `CaptureFiler.renew`).
            case renew(obligationID: UUID)
        }

        var blueprint: ObligationBlueprint
        var day: CalendarDay
        var action: Action
        /// How early it reminds: the blueprint's profile for this section's values.
        var reminders: ReminderProfile
    }

    /// Why saving sets no reminder, so the review can say so plainly.
    enum Quiet: Equatable {
        /// The document's date has no place yet: the person hasn't picked where it goes.
        case needsPlace
        /// A bill whose reminder the person turned off.
        case notWanted
        /// The bank pays the subscription by direct debit.
        case paidByDirectDebit
        /// The day has passed, and a deadline that passed isn't worth a reminder.
        case dayPassed
        /// The category it goes to keeps no such deadline.
        case noSuchDeadline
        /// The section already has this deadline on a later day; an older document never moves it back.
        case alreadyLater(CalendarDay)
    }

    /// Who issued the document, kept in Agendă.
    struct Provider: Equatable {
        var name: String
        var taxID: String?
        var trade: ProviderTrade
        var phone: String?
    }

    /// The category the document's values land in (a subscription under a home, a
    /// member's personal document); nil when it is only kept.
    var templateKey: String?
    /// The deadline the document is about, scheduled or not.
    var blueprint: ObligationBlueprint?
    /// The day the document gives that deadline.
    var day: CalendarDay?
    /// What saving does to it; nil when it sets no reminder (see `quiet`).
    var deadline: Deadline?
    var quiet: Quiet?
    var provider: Provider?

    /// Saving makes or moves a deadline, so asking for the reminder permission first is worth it.
    var schedulesReminder: Bool { deadline != nil }

    // MARK: Making the plan

    /// The plan for `review` as it stands, with the household's categories and sections.
    @MainActor
    static func make(for review: CaptureReview, templates: [String: CategoryTemplate], assets: [Asset], today: CalendarDay,
                     calendar: Calendar = .current) -> CaptureFilingPlan {
        var plan = CaptureFilingPlan()
        let profile = review.kind.profile
        let section = review.existingSection(assets: assets, templates: templates)
        plan.templateKey = filedTemplateKey(for: review, assets: assets, templates: templates)
        let template = plan.templateKey.flatMap { templates[$0] }
        plan.blueprint = template.flatMap { review.deadlineBlueprint(in: $0.definition) }
        plan.day = review.reminderDay
        plan.provider = CaptureFiler.provider(of: review)

        guard let day = plan.day else { return plan }
        guard review.destination != .none, let template else {
            plan.quiet = .needsPlace
            return plan
        }
        guard let blueprint = plan.blueprint else {
            plan.quiet = .noSuchDeadline
            return plan
        }
        if profile.deadlineIsOptIn {
            guard review.remindsToPay else { plan.quiet = .notWanted; return plan }
            if review.paysByDirectDebit(assets: assets) { plan.quiet = .paidByDirectDebit; return plan }
        }
        // The section's values as saving leaves them: what it has, with what was read on top.
        var values = section?.values ?? FieldValues()
        for (key, value) in CaptureFiler.values(from: review, for: template.definition) { values[key] = value }
        guard blueprint.appliesWhen?.isMet(by: values) ?? true else {
            plan.quiet = .noSuchDeadline
            return plan
        }
        let reminders = blueprint.reminders(for: values)
        if let existing = section?.activeObligations.first(where: { $0.blueprintKey == blueprint.key }) {
            let due = existing.dueDay(in: calendar)
            // A deadline that follows a field takes the document's own date; any other never
            // moves back for an older document.
            guard blueprint.isFieldDriven || day >= due else {
                plan.quiet = .alreadyLater(due)
                return plan
            }
            plan.deadline = Deadline(blueprint: blueprint, day: day, action: .renew(obligationID: existing.id), reminders: reminders)
            return plan
        }
        guard blueprint.isWorthScheduling(on: day, today: today) else {
            plan.quiet = .dayPassed
            return plan
        }
        plan.deadline = Deadline(blueprint: blueprint, day: day, action: .create, reminders: reminders)
        return plan
    }

    /// The category the document's values land in: a bill or a contract filed under a
    /// home goes to the home's subscription, a document filed under a person becomes one
    /// of their personal documents, anything else lands where it is filed.
    @MainActor
    static func filedTemplateKey(for review: CaptureReview, assets: [Asset], templates: [String: CategoryTemplate]) -> String? {
        let destination: String? = switch review.destination {
        case .none: nil
        case .asset(let id): assets.first { $0.id == id }?.templateKey
        case .newAsset(let key): key
        }
        return destination.map { CaptureFiler.filedTemplateKey(for: review, destinationTemplateKey: $0, templates: templates) }
    }
}
