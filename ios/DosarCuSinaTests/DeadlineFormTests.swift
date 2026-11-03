import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// One form adds a deadline, from Adaugă › Scriu eu and from a section's "Alt termen",
/// so the same deadline of the person's own reminds the same wherever it was typed.
@MainActor
@Suite("One deadline form")
struct DeadlineFormTests {
    @Test(arguments: DeadlineChoice.Importance.allCases)
    func ownDeadlinesTakeTheirKindAndItsReminders(importance: DeadlineChoice.Importance) {
        #expect(DeadlineChoice.reminders(for: importance) == importance.kind.defaultProfile)
    }

    @Test func aPaymentOfYourOwnRemindsLikeAPaymentAndAChoreLikeAChore() throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.home))
        let home = try AssetActions(context: context).create(name: "Apartament", template: template, values: FieldValues())
        let actions = ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-11-03") })
        let payment = try actions.create(title: "Plata asigurării", kind: DeadlineChoice.Importance.money.kind, dueDay: CalendarDay("2026-12-01"),
                                         for: home, recurrence: DeadlineChoice.Repeat.yearly.rule, reminders: DeadlineChoice.reminders(for: .money))
        let chore = try actions.create(title: "Verificarea stingătorului", kind: DeadlineChoice.Importance.reminder.kind, dueDay: CalendarDay("2026-12-01"),
                                       for: home, recurrence: DeadlineChoice.Repeat.yearly.rule, reminders: DeadlineChoice.reminders(for: .reminder))
        #expect(payment.kind == .payment)
        #expect(chore.kind == .routine)
        #expect(payment.reminders == ObligationKind.payment.defaultProfile)
        #expect(chore.reminders == ObligationKind.routine.defaultProfile)
    }
}
