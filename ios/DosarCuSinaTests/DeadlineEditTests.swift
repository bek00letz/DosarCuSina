import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// The deadline page's one "Editează": its name and importance (a deadline of the person's own),
/// date, repeat, reminders and reminder time saved as one undoable step; the line that says how
/// it repeats and reminds; the section's name that opens the section; and the cards under the
/// actions, each only when it has something.
@MainActor
@Suite("A deadline's one edit, and its page")
struct DeadlineEditTests {
    let calendar = Calendar.bucharest

    private func ownChore(_ actions: ObligationActions, title: String = "Udat palntele") throws -> Obligation {
        try actions.create(title: title, kind: .routine, dueDay: CalendarDay("2026-11-12"), for: nil,
                           recurrence: .interval(.weeks(1), anchor: .completion))
    }

    // MARK: One step

    @Test func theEditSavesEverythingAsOneStepAndOneUndoTakesItAllBack() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-10") })
        let plants = try ownChore(actions)
        let start = DeadlineEdit(plants)
        #expect(start.isPersonsOwn && start.importance == .reminder)

        var edited = start
        edited.title = "Udat plantele"
        edited.choose(.health)
        edited.dueDay = CalendarDay("2026-11-14")
        edited.recurrence = .interval(.days(3), anchor: .completion)
        edited.reminders = edited.reminders.withLeadDays([1, 0])
        edited.reminderMinuteOfDay = 7 * 60 + 30

        let receipt = try #require(try actions.edit(plants, to: edited, startedFrom: start))
        #expect(plants.title == "Udat plantele")
        #expect(plants.kind == .health)
        #expect(plants.dueDay == CalendarDay("2026-11-14"))
        #expect(plants.recurrence == .interval(.days(3), anchor: .completion))
        #expect(plants.reminders.leadDays == [1, 0])
        #expect(plants.reminders.consequence == ObligationKind.health.defaultProfile.consequence)
        #expect(plants.reminderMinuteOfDay == 7 * 60 + 30)

        try receipt.undo()
        #expect(DeadlineEdit(plants) == start, "One Anulează puts every part back")
        #expect(plants.kind == .routine)
    }

    @Test func anEditThatChangedNothingSavesNothing() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-10") })
        let plants = try ownChore(actions)
        let start = DeadlineEdit(plants)
        var edited = start
        edited.reminders = edited.reminders.withLeadDays([1])
        edited.reminders = edited.reminders.withLeadDays(start.reminders.leadDays)
        #expect(edited == start, "A lead turned on and off again is no change: no question before closing")
        let saved = try actions.edit(plants, to: edited, startedFrom: start)
        #expect(saved === nil)
    }

    @Test func anEditKeepsWhatAnotherDeviceChangedInAPartItLeftAlone() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-10") })
        let plants = try ownChore(actions)
        let start = DeadlineEdit(plants)

        // Meanwhile another device gives it a time of its own and a new name.
        try actions.setReminderTime(plants, minuteOfDay: 20 * 60, startedFrom: nil)
        try actions.rename(plants, to: "Udat florile", startedFrom: "Udat palntele")

        // This sheet, opened before that, changed only the date and the repeat.
        var edited = start
        edited.dueDay = CalendarDay("2026-11-15")
        edited.recurrence = .interval(.days(4), anchor: .completion)
        try actions.edit(plants, to: edited, startedFrom: start)

        #expect(plants.reminderMinuteOfDay == 20 * 60, "The other device's time stays")
        #expect(plants.title == "Udat florile", "The other device's name stays")
        #expect(plants.dueDay == CalendarDay("2026-11-15"))
        #expect(plants.recurrence == .interval(.days(4), anchor: .completion))

        // A part both changed is the later save's: the person's choice.
        var renamed = DeadlineEdit(plants)
        let opened = renamed
        renamed.title = "Udat plantele"
        try actions.rename(plants, to: "Udat ficusul", startedFrom: "Udat florile")
        try actions.edit(plants, to: renamed, startedFrom: opened)
        #expect(plants.title == "Udat plantele")
    }

    // MARK: Only one's own

    @Test func onlyADeadlineOfOnesOwnCanBeRenamedOrMadeMoreImportant() throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let car = try AssetActions(context: context).create(name: "VW Golf 2018", template: template, values: FieldValues())
        let blueprint = try #require(template.blueprints.first { $0.key == "vehicle.itp" })
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-10") })
        let itp = try actions.create(from: blueprint, for: car, firstDue: CalendarDay("2027-03-01"))

        let start = DeadlineEdit(itp)
        #expect(!start.isPersonsOwn)
        #expect(!start.offersImportance, "A category's deadline keeps its kind")
        #expect(throws: ObligationActionError.notPersonsOwn) { try actions.rename(itp, to: "Revizie tehnică") }
        #expect(throws: ObligationActionError.notPersonsOwn) { try actions.setImportance(itp, .reminder) }
        var renamed = start
        renamed.title = "Revizie tehnică"
        #expect(throws: ObligationActionError.notPersonsOwn) { try actions.edit(itp, to: renamed, startedFrom: start) }
        #expect(itp.title == blueprint.title)

        // Its date and reminders are still the person's to change.
        var moved = start
        moved.dueDay = CalendarDay("2027-04-01")
        moved.reminderMinuteOfDay = 8 * 60
        try actions.edit(itp, to: moved, startedFrom: start)
        #expect(itp.dueDay == CalendarDay("2027-04-01"))
        #expect(itp.reminderMinuteOfDay == 8 * 60)

        // A deadline of one's own can't lose its name.
        let plants = try ownChore(actions)
        #expect(throws: ObligationActionError.missingTitle) { try actions.rename(plants, to: "  ") }
    }

    @Test func importanceMovesOnlyTheRemindersThePersonHadntSet() {
        let chore = ObligationKind.routine.defaultProfile
        let legal = ObligationKind.legal.defaultProfile
        #expect(DeadlineChoice.reminders(chore, from: .routine, to: .legal) == legal, "Still the kind's own: the new kind's")

        let mine = chore.withLeadDays([3, 0])
        let moved = DeadlineChoice.reminders(mine, from: .routine, to: .legal)
        #expect(moved.leadDays == [3, 0], "The person's leads stay")
        #expect(moved.consequence == legal.consequence && moved.graceDays == legal.graceDays, "How serious it is is the kind's")
        #expect(DeadlineChoice.reminders(moved, from: .legal, to: .routine).consequence == chore.consequence)

        for answer in DeadlineChoice.Importance.allCases {
            #expect(DeadlineChoice.Importance(kind: answer.kind) == answer)
        }
        #expect(DeadlineChoice.Importance(kind: .maintenance) == nil, "Not one of the answers: not offered")
    }

    // MARK: Words

    @Test func thePageSaysHowItRepeatsAndRemindsInOneLine() {
        let line = ReminderWording.schedule(rule: .interval(.days(3), anchor: .completion),
                                            profile: ReminderProfile(leadDays: [1], consequence: .comfort),
                                            minuteOfDay: 7 * 60 + 30, usual: 9 * 60, calendar: calendar)
        #expect(line == "La fiecare 3 zile, de la data la care l-ai făcut · Îți amintesc cu o zi înainte, la 07:30")

        let usual = ReminderWording.schedule(rule: .none, profile: ReminderProfile(leadDays: [30, 7, 0], consequence: .legal),
                                             minuteOfDay: nil, usual: 9 * 60, calendar: calendar)
        #expect(usual == "Nu se repetă · Îți amintesc cu o lună și cu 7 zile înainte și în ziua termenului, la ora obișnuită (09:00)")

        let onTheDay = ReminderWording.summary(ReminderProfile(leadDays: [0], consequence: .comfort), minuteOfDay: 20 * 60, usual: 9 * 60, calendar: calendar)
        #expect(onTheDay == "Îți amintesc în ziua termenului, la 20:00")
        #expect(ReminderWording.summary(ReminderProfile(leadDays: [], consequence: .comfort), minuteOfDay: nil, usual: 9 * 60) == "Nu te anunț dinainte")

        // The sentences say the same as before, from the same parts.
        #expect(ReminderWording.sentence(ReminderProfile(leadDays: [30, 7, 0], consequence: .legal))
                == "Te anunț cu o lună și cu 7 zile înainte și în ziua termenului.")
        #expect(ReminderWording.sentence(ReminderProfile(leadDays: [0], consequence: .comfort)) == "Te anunț în ziua termenului.")
        #expect(RepeatWording.sentence(.interval(.months(1), anchor: .dueDate)) == "În fiecare lună, de la data termenului.")
    }

    // MARK: The page

    @Test func theSectionsNameOpensTheSection() throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let car = try AssetActions(context: context).create(name: "VW Golf 2018", template: template, values: FieldValues())
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-10") })
        let wash = try actions.create(title: "Spălat mașina", kind: .routine, dueDay: CalendarDay("2026-11-20"), for: car)
        #expect(ObligationScreen.sectionRoute(for: wash, isLocked: false) == .asset(car.id))
        #expect(ObligationScreen.sectionRoute(for: wash, isLocked: true) == nil, "A locked section's name isn't shown")
        let household = try ownChore(actions)
        #expect(ObligationScreen.sectionRoute(for: household, isLocked: false) == nil, "The whole household has no page of its own")
    }

    @Test func eachCardShowsOnlyWhenItHasSomethingAndNeverOpensWithASeparator() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-11-10") })
        let plants = try ownChore(actions)

        let new = DeadlinePageFacts.of(plants, template: nil, in: context)
        #expect(!new.showsLastTime && !new.showsPolicyCard, "A chore never done shows neither")

        try actions.complete(plants, on: noon("2026-11-10"), note: "Și ficusul")
        let done = DeadlinePageFacts.of(plants, template: nil, in: context)
        #expect(done.showsLastTime && !done.showsPolicyCard, "Last time alone: no policy card")

        let phoneOnly = DeadlinePageFacts(lastCompletion: nil, policyNumber: nil, claimsPhone: "0700 000 000", ownerClass: nil, documents: [])
        #expect(!phoneOnly.showsLastTime && phoneOnly.showsPolicyCard)
        #expect(phoneOnly.policyRows == [.claimsPhone("0700 000 000")], "The claims phone first, nothing before it")
        #expect(String(localized: phoneOnly.policyCardTitle) == "Polița")
        #expect(!phoneOnly.namesDocumentsInside)

        let full = DeadlinePageFacts(lastCompletion: nil, policyNumber: "RO/00/A/000000", claimsPhone: "0700 000 000", ownerClass: "B4", documents: [])
        #expect(full.policyRows == [.policyNumber("RO/00/A/000000"), .claimsPhone("0700 000 000"), .ownerClass("B4")])

        let paper = Attachment(fileName: "polita.pdf", contentType: "application/pdf", data: nil)
        context.insert(paper)
        let papersOnly = DeadlinePageFacts(lastCompletion: nil, policyNumber: nil, claimsPhone: nil, ownerClass: nil, documents: [paper])
        #expect(papersOnly.showsPolicyCard && String(localized: papersOnly.policyCardTitle) == "Acte în dosar")
        #expect(!papersOnly.namesDocumentsInside, "The heading already names them")
        let both = DeadlinePageFacts(lastCompletion: nil, policyNumber: "RO/00/A/000000", claimsPhone: nil, ownerClass: nil, documents: [paper])
        #expect(both.namesDocumentsInside)
    }
}
