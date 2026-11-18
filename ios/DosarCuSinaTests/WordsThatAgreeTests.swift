import Foundation
import Testing
@testable import DosarCuSina

/// Words that agree with whatever they are said of, and say only what is true (docs/COPY_GUIDE.md):
/// a repeat's anchor said of no noun, a paper's line by whether its day has passed, a paper read
/// with nothing found, one word for a deadline outside the app, and the steps „Altă zi” takes.
@MainActor
@Suite("Words that agree")
struct WordsThatAgreeTests {
    static let today = CalendarDay(year: 2026, month: 11, day: 18)

    // MARK: How a deadline repeats

    @Test("What a repeat counts from takes no pronoun, so it fits a rovinietă bought as well as an ITP done")
    func repeatAnchorsTakeNoGender() {
        for unit in [RecurrenceInterval.Unit.day, .week, .month, .year] {
            for anchor in RepeatWording.anchors {
                let words = [RepeatWording.title(of: anchor), RepeatWording.detail(of: anchor, every: 3, unit)]
                for line in words {
                    #expect(!line.contains("l-ai") && !line.contains(" îl ") && !line.contains("o-ai") && !line.contains(" o bifezi"), "„\(line)”")
                }
            }
        }
        #expect(RepeatWording.title(of: .completion) == "De la data rezolvării")
        #expect(RepeatWording.sentence(.interval(.days(3), anchor: .completion)) == "La fiecare 3 zile, de la data rezolvării.")
    }

    // MARK: A paper's last valid day

    @Test("A paper's line says it expired once its day has passed, in a verb that agrees with any paper")
    func aPapersLineFollowsItsDay() throws {
        let passed = CalendarDay(year: 2024, month: 3, day: 1)
        let coming = CalendarDay(year: 2031, month: 8, day: 12)
        #expect(PocketWording.validity(passed, today: Self.today).hasPrefix("A expirat pe"))
        #expect(PocketWording.validity(coming, today: Self.today).hasPrefix("Expiră pe"))
        #expect(PocketWording.validityLabel(passed, today: Self.today) == "A expirat pe")
        #expect(PocketWording.validityLabel(coming, today: Self.today) == "Expiră pe")

        let card = FieldValues([DocumentType.typeFieldKey: .text(DocumentType.idCard), DocumentFields.expiry: .date(passed)])
        let line = try #require(DocumentSummary.line(card, today: Self.today))
        #expect(line.hasPrefix("A expirat pe"), "\(line)")
        #expect(!line.contains("Valabil"))
    }

    // MARK: A visit's paper

    @Test("A paper with nothing read says so, and one read says only what it gave")
    func aVisitsPaperSaysWhatItGave() throws {
        let doctor = try #require(VisitForm.make(for: BuiltInTemplates.health))
        let nothing = try #require(doctor.readNote(found: 0, filled: []))
        #expect(!nothing.hasPrefix("Am trecut"), "„\(nothing)”")
        #expect(nothing.hasPrefix("Nu am găsit"))
        let some = try #require(doctor.readNote(found: 0, filled: [.day]))
        #expect(some.contains("data") && !some.contains("suma") && !some.contains("numele"), "„\(some)”")
    }

    // MARK: Outside the app

    @Test("Siri, Shortcuts and a locked reminder say „termen”, as the app does")
    func oneWordForADeadline() {
        let generic = ReminderPlanner.genericTitle(daysBefore: 1, from: Date())
        #expect(generic == "Ai un termen mâine")
        for days in [-3, 0, 1, 30] {
            let title = ReminderPlanner.genericTitle(daysBefore: days, from: Date())
            #expect(!title.contains("scaden") && !title.contains("obliga"), "„\(title)”")
        }
    }

    // MARK: „Altă zi”

    @Test("„Altă zi” reaches a year before in a few dozen steps, through whole weeks and months")
    func anotherDayStepsFurtherAsItGrows() {
        var days = 1
        var taps = 0
        while days < 365 {
            days = RepeatChoice.stepped(days, up: true, unit: .day, in: 1...365)
            taps += 1
        }
        #expect(days == 365)
        #expect(taps < 40, "\(taps) taps from a day to a year")
        #expect(RepeatChoice.stepped(14, up: true, unit: .day, in: 1...365) == 21, "Whole weeks after two")
    }

    // MARK: A refused save

    @Test("Every refused save is another attempt, and the problem highest on the screen is the one gone to")
    func aRefusedSaveGoesToTheFirstProblem() {
        var reveal = DSValidationReveal()
        #expect(!reveal.isOn)
        reveal.reveal()
        reveal.reveal()
        #expect(reveal.isOn && reveal.attempt == 2, "A second refusal goes to the problem again")
        reveal.reset()
        #expect(!reveal.isOn)

        let targets = DSValidationTargets()
        let lower = UUID(), higher = UUID(), fixed = UUID()
        targets.set(lower, message: "Completează acest câmp.")
        targets.place(lower, top: 600)
        targets.set(higher, message: "Scrie un nume.")
        targets.place(higher, top: 120)
        targets.set(fixed, message: "Alege o dată.")
        targets.place(fixed, top: 20)
        targets.set(fixed, message: nil)
        #expect(targets.first?.id == higher)
        #expect(targets.first?.message == "Scrie un nume.")
        targets.remove(higher)
        #expect(targets.first?.id == lower)
    }
}
