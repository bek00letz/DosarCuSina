import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

@Suite("Catch-up reminders")
struct CatchUpReminderTests {
    let calendar = Calendar.bucharest

    /// Over every kind's default profile and every built-in blueprint's, a deadline
    /// added 1, 7 or 20 days before its due day gets a reminder before it's due
    /// whenever its profile warns ahead at all, and never more than one catch-up.
    @Test(arguments: [1, 7, 20])
    func aLateDeadlineStillGetsAWarning(daysBefore: Int) {
        var profiles = ObligationKind.allCases.map { ($0, $0.defaultProfile) }
        for template in BuiltInTemplates.all {
            for blueprint in template.blueprints {
                profiles.append((blueprint.kind, blueprint.reminders))
                for variant in blueprint.reminderVariants?.variants.values.map({ $0 }) ?? [] {
                    profiles.append((blueprint.kind, variant))
                }
            }
        }
        // Added at 8:00, before the 9:00 reminder time, and at 18:00, after it.
        for addedAt in [8, 18] {
            let known = CalendarDay("2026-11-02").noonDate(in: calendar).addingTimeInterval(TimeInterval((addedAt - 12) * 3600))
            let due = CalendarDay("2026-11-02").adding(days: daysBefore, calendar: calendar)
            for (kind, profile) in profiles {
                let item = ObligationSnapshot(title: "Termen", kind: kind, dueDay: due, reminders: profile, cycleKnownSince: known)
                let plan = ReminderPlanner.plan([item], now: known, calendar: calendar)
                let catchUps = plan.filter { $0.identifier.hasSuffix(".\(ReminderPlanner.catchUpSuffix)") }
                #expect(catchUps.count <= 1)
                guard profile.leadDays.contains(where: { $0 > 0 }) else { continue }
                let dueEnd = due.adding(days: 1, calendar: calendar).startDate(in: calendar)
                #expect(plan.contains { $0.fireDate < dueEnd }, "\(kind) \(profile.leadDays), added \(daysBefore) days before at \(addedAt):00")

                // Planned again after it fired, it doesn't come back.
                if let fired = catchUps.first {
                    let later = ReminderPlanner.plan([item], now: fired.fireDate.addingTimeInterval(60), calendar: calendar)
                    #expect(!later.contains { $0.identifier == fired.identifier })
                }
            }
        }
    }

    @Test func anIdentityCardTwentyDaysBeforeExpiry() throws {
        let known = CalendarDay("2026-11-02").noonDate(in: calendar).addingTimeInterval(-4 * 3600)
        let card = ObligationSnapshot(
            title: "Carte de identitate", kind: .renewal, dueDay: CalendarDay("2026-11-22"),
            reminders: ReminderProfile(leadDays: [90, 30], consequence: .legal), cycleKnownSince: known
        )
        let plan = ReminderPlanner.plan([card], now: known, calendar: calendar)
        let catchUp = try #require(plan.first)
        #expect(catchUp.identifier.hasSuffix(".catchup"))
        #expect(CalendarDay(catchUp.fireDate, calendar: calendar) == CalendarDay("2026-11-02"))
        #expect(catchUp.title == "În 20 de zile: Carte de identitate")
        #expect(catchUp.cycle == CalendarDay("2026-11-22"))
    }

    @Test func aDeadlineKnownInTimeGetsNoCatchUp() {
        let known = noon("2026-08-01")
        let card = ObligationSnapshot(title: "Pașaport", kind: .renewal, dueDay: CalendarDay("2026-11-22"),
                                      reminders: ReminderProfile(leadDays: [90, 30], consequence: .legal), cycleKnownSince: known)
        let plan = ReminderPlanner.plan([card], now: noon("2026-11-02"), calendar: calendar)
        #expect(!plan.contains { $0.identifier.hasSuffix(".catchup") })
    }
}
