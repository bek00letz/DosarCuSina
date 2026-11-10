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
        /// The bill is already in the binder and its reminder has been dealt with (paid, or
        /// taken away): another photo of it never makes a second one.
        case billFiledBefore
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
    /// The document's photo is kept. Not for a bank card unless the person asked: its
    /// photo shows the card's whole number.
    var keepsPhoto = true

    /// Where a policy's bonus-malus class goes: to the person it insures, never to a car.
    enum BonusMalus: Equatable {
        /// The class is kept on this household member.
        case keep(classKey: String, memberID: UUID, memberName: String)
        /// The policy doesn't say who it insures, so the class isn't kept.
        case noPolicyholder
        /// Nobody in the household is the person it insures, so the class isn't kept.
        case notInHousehold(name: String)
    }
    /// What happens to the class the policy prints; nil when it prints none.
    var bonusMalus: BonusMalus?

    /// What saving does with a bill's meter index: a reading on the subscription it goes to.
    enum Meter: Equatable {
        /// Recorded on the subscription named `subscription`, through the one reading path.
        case record(SubscriptionMeter.Reading, subscription: String)
        /// The same bill was filed there before, with this index: nothing new is kept.
        case alreadyKept(SubscriptionMeter.Reading, subscription: String)
        /// The subscription doesn't say what it supplies, so the index has no meter to go on.
        case unknownService

        /// The reading saving keeps (or already keeps) on the subscription.
        var reading: SubscriptionMeter.Reading? {
            switch self {
            case .record(let reading, _), .alreadyKept(let reading, _): reading
            case .unknownService: nil
            }
        }
    }
    /// What happens to the meter index the bill prints; nil when it prints none, or when it
    /// goes nowhere a meter is kept (no place chosen yet, not a subscription, a service without a meter).
    var meter: Meter?
    /// The bill already in the binder that this review files again (`FiledPaper`); nil for a
    /// new bill or any other document.
    var filedBill: FiledPaper?
    /// The meter reading this bill recorded when it was filed before (by the same document,
    /// or by another photo of the same bill): filing it again keeps, replaces or removes it,
    /// and it never counts against the new index.
    var readingFiledBefore: UUID?

    /// Where `review`'s bonus-malus class goes, from the person the policy insures
    /// (`Policyholders`): by the CNP read on it, else by name. Nil when there is no class.
    @MainActor
    static func bonusMalus(for review: CaptureReview, people: [Policyholders.Person]) -> BonusMalus? {
        guard review.kind.profile.readsCover, let classKey = BonusMalusClass.key(for: review.value(.bonusMalusClass)?.text) else { return nil }
        let name = review.value(.policyholder)?.text
        if let person = Policyholders.person(named: name, personalNumber: review.value(.policyholderPersonalNumber)?.text, among: people) {
            return .keep(classKey: classKey, memberID: person.id, memberName: person.name)
        }
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return .noPolicyholder }
        return .notInHousehold(name: name)
    }

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
        plan.keepsPhoto = review.keepsPhoto
        plan.bonusMalus = bonusMalus(for: review, people: Policyholders.people(in: assets, templates: templates))
        plan.filedBill = filedBill(for: review, section: section, templates: templates, assets: assets, today: today, calendar: calendar)
        plan.readingFiledBefore = readingFiledBefore(review: review, filedBill: plan.filedBill, templates: templates, assets: assets)
        plan.meter = meter(for: review, section: section, templateKey: plan.templateKey, templates: templates, assets: assets,
                           readingFiledBefore: plan.readingFiledBefore, today: today, calendar: calendar)

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
        if let existing = section.flatMap({ existingDeadline(blueprint, in: $0, takesUpPaused: profile.deadlineIsOptIn) }) {
            let due = existing.dueDay(in: calendar)
            // A deadline that follows a field takes the document's own date; any other never
            // moves back for an older document.
            guard blueprint.isFieldDriven || day >= due else {
                plan.quiet = .alreadyLater(due)
                return plan
            }
            // It keeps reminding the way it does now, the person's own changes included.
            plan.deadline = Deadline(blueprint: blueprint, day: day, action: .renew(obligationID: existing.id), reminders: existing.reminders)
            return plan
        }
        // A bill already logged here whose reminder is no longer running (paid, or taken
        // away): another photo of it never asks to be paid a second time.
        if profile.deadlineIsOptIn, let filed = plan.filedBill, let section, filed.sectionID == section.id {
            plan.quiet = .billFiledBefore
            return plan
        }
        guard blueprint.isWorthScheduling(on: day, today: today, values: values) else {
            plan.quiet = .dayPassed
            return plan
        }
        plan.deadline = Deadline(blueprint: blueprint, day: day, action: .create, reminders: reminders)
        return plan
    }

    /// What saving does with the meter index `review` shows (the value as it stands in the
    /// review, so one marked "Verifică" is kept only as the person left it): a reading on the
    /// subscription the bill goes to, in the unit its service gives, dated by the bill. The
    /// subscription is `section` (the one found by `SubscriptionMatcher`, or chosen), else the
    /// new one saving makes, named as it will be.
    @MainActor
    static func meter(for review: CaptureReview, section: Asset?, templateKey: String?, templates: [String: CategoryTemplate],
                      assets: [Asset], readingFiledBefore: UUID?, today: CalendarDay, calendar: Calendar) -> Meter? {
        guard let index = review.value(.meterIndex), SubscriptionMeter.number(index) != nil, review.destination != .none,
              let templateKey, templates.plays(.subscription, templateKey), let template = templates[templateKey] else { return nil }
        // The subscription's values as saving leaves them: a bill only fills what is still empty.
        var values = section?.values ?? FieldValues()
        for (key, value) in CaptureFiler.values(from: review, for: template.definition) where values[key] == nil { values[key] = value }
        guard let service = SubscriptionFields.service(of: values) else { return .unknownService }
        guard let reading = SubscriptionMeter.reading(index, service: service, day: CaptureFiler.billDay(review, today: today)) else { return nil }
        let name = section?.name ?? CaptureFiler.subscriptionName(review)
        // The same bill filed again: the reading it recorded is already there.
        if let section, let earlier = readingFiledBefore,
           let log = section.measurements?.first(where: { $0.id == earlier && !$0.isDeleted }),
           reading.isRecorded(by: log, calendar: calendar) {
            return .alreadyKept(reading, subscription: name)
        }
        return .record(reading, subscription: name)
    }

    /// The bill already in the binder that `review` files, by the one rule (`PaperIdentity`):
    /// the same document's own entry wherever it is now (it moves with the bill), else, in
    /// the subscription saving files into, the entry of the same bill read from another photo,
    /// unless the person said it is another bill. Nil for anything that isn't a bill.
    @MainActor
    static func filedBill(for review: CaptureReview, section: Asset?, templates: [String: CategoryTemplate], assets: [Asset],
                          today: CalendarDay, calendar: Calendar) -> FiledPaper? {
        guard review.kind.profile.deadlineIsOptIn else { return nil }
        if let kept = review.duplicateAttachmentID,
           let document = assets.lazy.flatMap({ $0.attachments ?? [] }).first(where: { $0.id == kept }),
           let entry = document.historyEntry, !entry.isDeleted, !entry.isCompletion, entry.kind == .payment,
           let owner = entry.asset, templates.plays(.subscription, owner.templateKey) {
            return FiledPaper(entry, match: .sameDocument, calendar: calendar)
        }
        guard !review.isAnotherBill, let section, templates.plays(.subscription, section.templateKey) else { return nil }
        let bill = PaperIdentity(number: review.value(.invoiceNumber)?.text, day: CaptureFiler.billDay(review, today: today), total: review.total)
        guard let found = bill.filed(among: PaperIdentity.bills(of: section), identity: { PaperIdentity(entry: $0, calendar: calendar) }) else { return nil }
        return FiledPaper(found.paper, match: FiledPaper.Match(found.match), calendar: calendar)
    }

    /// The meter reading the bill recorded before: the same document's, else one a document of
    /// the bill's entry recorded on a subscription.
    @MainActor
    static func readingFiledBefore(review: CaptureReview, filedBill: FiledPaper?, templates: [String: CategoryTemplate], assets: [Asset]) -> UUID? {
        let documents = assets.lazy.flatMap { $0.attachments ?? [] }
        let entry = filedBill.flatMap { filed in assets.lazy.flatMap { $0.history ?? [] }.first { $0.id == filed.entryID } }
        let candidates = (review.duplicateAttachmentID.flatMap { kept in documents.first { $0.id == kept } }.map { [$0] } ?? [])
            + (entry?.attachments ?? [])
        return candidates.lazy.compactMap(\.measurement).first { log in
            !log.isDeleted && log.asset.map { templates.plays(.subscription, $0.templateKey) } == true
        }?.id
    }

    /// The section's deadline from `blueprint` that a document moves: the running one, or,
    /// for a bill (`takesUpPaused`), the one paused while the bank paid by direct debit,
    /// which a bill asking to be reminded takes up again instead of making a second.
    @MainActor
    static func existingDeadline(_ blueprint: ObligationBlueprint, in section: Asset, takesUpPaused: Bool) -> Obligation? {
        if let active = section.activeObligations.first(where: { $0.blueprintKey == blueprint.key }) { return active }
        guard takesUpPaused else { return nil }
        return (section.obligations ?? []).filter { $0.blueprintKey == blueprint.key && $0.status == .paused }.max { $0.dueDate < $1.dueDate }
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
