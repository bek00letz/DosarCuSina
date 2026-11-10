import Foundation
import Testing
@testable import DosarCuSina

/// The owner's answers to the questions the 2026-11-03 work left open (docs/DECISIONS.md,
/// "The owner's answers"), pinned so a later change has to ask again.
@Suite("Settled decisions")
struct SettledDecisionsTests {
    let calendar = Calendar.bucharest

    @Test func aDueDayIsTheLastValidDayAsPapersPrintIt() {
        #expect(DueDayValidity.dueDayIsLastValidDay)
        let due = CalendarDay("2027-08-12")
        #expect(DueDayValidity.isValid(due: due, on: due))
        #expect(!DueDayValidity.isValid(due: due, on: CalendarDay("2027-08-13")))
    }

    @Test func anExpiredRCAOrITPReadFromAPhotoGetsNoOverdueDeadline() throws {
        let today = CalendarDay("2026-11-03")
        let past = CalendarDay("2026-10-01")
        for key in [BuiltInBlueprints.vehicleRCA, BuiltInBlueprints.vehicleITP] {
            let blueprint = try #require(BuiltInTemplates.vehicle.blueprints.first { $0.key == key })
            #expect(!blueprint.isWorthScheduling(on: past, today: today), "\(key): only history")
            #expect(blueprint.isWorthScheduling(on: today, today: today))
        }
        // An identity document that expired must still be renewed by law.
        let renew = try #require(BuiltInTemplates.documents.blueprints.first { $0.key == BuiltInBlueprints.documentRenew })
        #expect(renew.isWorthScheduling(on: past, today: today))
    }

    @Test("Due today is amber everywhere; red only when late past grace", arguments: ObligationKind.allCases)
    func dueTodayIsAmber(kind: ObligationKind) {
        let due = CalendarDay("2027-03-31")
        let rule = kind.defaultProfile.urgencyRule
        #expect(rule.urgency(of: due, today: due, calendar: calendar).tone == .soon)
        let pastGrace = due.adding(days: kind.defaultProfile.graceDays + 1, calendar: calendar)
        #expect(rule.urgency(of: due, today: pastGrace, calendar: calendar).tone == .overdue)
    }

    @Test func theConsequenceCapStays() {
        // An identity card reminds three months ahead and needs the person only in its last month.
        let card = ReminderProfile(leadDays: [90, 30], consequence: .legal).urgencyRule
        let due = CalendarDay("2027-08-12")
        #expect(card.attentionStart(before: due, calendar: calendar) == CalendarDay("2027-07-12"))
    }

    /// "Cazier, the health card and bank cards: the owner's answers" in DECISIONS.
    @Test func cazierHealthCardAndBankCardAnswers() throws {
        // A cazier fiscal or auto has no validity rule, so no reminder, until one is confirmed.
        for variant in [DocumentType.Variant.criminalRecordFiscal, DocumentType.Variant.criminalRecordDriving] {
            #expect(DocumentType.validityMonths(type: DocumentType.criminalRecord, variant: variant) == nil)
        }
        // A cazier judiciar reminds a week before and on the day, as "Doar să nu uit".
        let renew = try #require(BuiltInTemplates.documents.blueprints.first { $0.key == BuiltInBlueprints.documentRenew })
        let cazier = renew.reminders(for: FieldValues([DocumentType.typeFieldKey: .text(DocumentType.criminalRecord)]))
        #expect(cazier.leadDays == [7, 0])
        #expect(cazier.consequence == .comfort)
        // The national health card is read from a photo now ("More personal documents from a
        // photo", 2026-11-10, replaces "typed in only"): by its own kind, never as the European card.
        #expect(CaptureDocumentKind.allCases.filter { $0.profile.documentType == DocumentType.nationalHealthCard } == [.nationalHealthCard])
        #expect(CaptureDocumentKind.healthInsuranceCard.profile.documentType == DocumentType.euHealthCard)
        // A bank card is read only on the phone.
        #expect(DocumentType.readOnPhoneOnly == [DocumentType.bankCard])
    }

    @Test func monthRemindersFireOnTheSameDayOfTheMonth() {
        #expect(ReminderLead(days: 90).day(before: CalendarDay("2027-08-12"), calendar: calendar) == CalendarDay("2027-05-12"))
        #expect(ReminderLead(days: 30).day(before: CalendarDay("2027-03-31"), calendar: calendar) == CalendarDay("2027-02-28"))
    }
}
