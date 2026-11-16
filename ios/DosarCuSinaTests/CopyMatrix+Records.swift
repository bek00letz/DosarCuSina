import Foundation
import Testing
@testable import DosarCuSina

/// The copy matrix's sections for the deadline form (`DeadlineForm`) and a record's page in
/// Istoric (`HistoryEntryScreen`), category by category.
extension CopyMatrixTests {
    // MARK: The deadline form

    /// The deadline form's frame, the same for every category.
    static var deadlineFormSharedRows: [(String, String)] {
        [
            ("Its title", DeadlineFormWording.title),
            ("Which deadline", DeadlineFormWording.which),
            ("A deadline of one's own", "\(DeadlineFormWording.own) — \(DeadlineFormWording.ownHint)"),
            ("Its fields", "\(DeadlineFormWording.ownTitle) („\(DeadlineFormWording.ownTitleExample)”) · \(DeadlineFormWording.importance): "
                + DeadlineChoice.Importance.allCases.map(\.title).joined(separator: ", ") + " · \(DeadlineFormWording.repeats)"),
            ("When", "\(DeadlineFormWording.when) — \(DeadlineFormWording.date)"),
            ("The button", DeadlineFormWording.save),
            ("Not saved", DeadlineFormWording.notSaved),
            ("Saved", String(localized: DeadlineFormWording.added("ITP", reminders: ReminderWording.sentence(ObligationKind.legal.defaultProfile)))),
        ]
    }

    /// The usual deadlines the form offers a category: each with its note and how it reminds.
    static func deadlineFormRows(_ definition: TemplateDefinition) -> [(String, String)] {
        definition.blueprints.map { blueprint in
            let reminds = ReminderWording.sentence(blueprint.reminders(for: FieldValues()))
            return (blueprint.title, [blueprint.note, reminds].compactMap { $0 }.joined(separator: " — "))
        }
    }

    // MARK: A record's page in Istoric

    /// What a record's page says, for each kind of record a category makes: its visits (by its
    /// visit kind) and each of its deadlines' completions.
    static func historyRows(_ definition: TemplateDefinition) -> [(String, String)] {
        let visit = definition.behavior.visit.shape
        var records: [(String, HistoryKind, Bool)] = []
        if let visit { records.append((visit.entryTitle, visit.historyKind, false)) }
        if definition.behavior.visit.addsNote { records.append(("Notă", .note, false)) }
        for blueprint in definition.blueprints {
            records.append((blueprint.title, HistoryKind.forCompleting(blueprint.kind), true))
        }
        return records.map { title, kind, isCompletion in
            let shape = HistoryEntryShape.make(kind, visit: visit)
            let rated = shape.asksRating(isCompletion: isCompletion, hasSomeone: false)
            let ratedWithSomeone = shape.asksRating(isCompletion: isCompletion, hasSomeone: true)
            let rating = rated ? shape.ratingHeader : ratedWithSomeone ? "\(shape.ratingHeader) (only when someone did it)" : "no rating"
            let reference = shape.referenceIsInvoice ? HistoryEntryWording.invoiceNumber("0001") : HistoryEntryWording.number("0001")
            let deleted = isCompletion ? HistoryEntryWording.keepsDeadline : HistoryEntryWording.removesRows(parts: shape.rowsAreParts)
            return ("\(title) (`\(kind.rawValue)`)", "\(shape.itemsHeader) · \(shape.providerHeader) · \(rating) · \(reference) · deleting: \(deleted)")
        }
    }

    /// A record's page's frame, the same for every kind.
    static var historySharedRows: [(String, String)] {
        [
            ("Notes", "\(HistoryEntryWording.notes) · \(HistoryEntryWording.changeNote) · \(HistoryEntryWording.addNote)"),
            ("Under the stars, when someone did it", HistoryEntryWording.ratingFootnote),
            ("Deleting", "\(HistoryEntryWording.delete) — \(HistoryEntryWording.deleteQuestion("Revizie")) \(HistoryEntryWording.confirmDelete) / \(HistoryEntryWording.keep)"),
            ("What deleting does", [HistoryEntryWording.reopens(on: sampleDay), HistoryEntryWording.removesReading("45.724 km"),
                                    HistoryEntryWording.keepsDocuments].joined(separator: " ")),
        ]
    }

    /// Both sections, for every category.
    static func recordsSections(_ categories: [Category]) -> String {
        var out = "\n## Adding a deadline\n\n### What every category shares\n\n" + table(deadlineFormSharedRows) + "\n"
        for category in categories {
            out += "\n### \(category.title)\n\n"
            let rows = deadlineFormRows(category.definition)
            out += rows.isEmpty ? "No usual deadlines: only „\(DeadlineFormWording.own)”.\n" : table(rows) + "\n"
        }
        out += "\n## A record in Istoric\n\n### What every record shares\n\n" + table(historySharedRows) + "\n"
        for category in categories {
            let rows = historyRows(category.definition)
            guard !rows.isEmpty else { continue }
            out += "\n### \(category.title)\n\n" + table(rows) + "\n"
        }
        return out
    }
}

@MainActor
@Suite("Copy matrix: deadlines and records")
struct RecordsCopyRulesTests {
    @Test("A record's page: vehicle words only for vehicles, a doctor's and a vet's only for health and pets, no empty words")
    func recordWordsStayWithTheirCategories() throws {
        for category in try CopyMatrixTests.categories() {
            let rows = CopyMatrixTests.historyRows(category.definition) + CopyMatrixTests.deadlineFormSharedRows
            let words = CopyMatrixTests.tokens(rows.map(\.1).joined(separator: " "))
            let kind = category.definition.behavior.visit
            if kind != .service {
                #expect(words.isDisjoint(with: CopyMatrixTests.vehicleWords), "\(category.title): \(words.intersection(CopyMatrixTests.vehicleWords).sorted())")
            }
            if kind != .doctor && kind != .vet {
                #expect(words.isDisjoint(with: CopyMatrixTests.careWords), "\(category.title): \(words.intersection(CopyMatrixTests.careWords).sorted())")
            }
            #expect(rows.allSatisfy { !$0.1.isEmpty }, "\(category.title)")
        }
    }

    @Test("A bill, a purchase and a note ask no stars; a chore no one did neither; a job does")
    func onlyAJobAsksHowItWent() {
        for kind in [HistoryKind.payment, .purchase, .note] {
            #expect(!HistoryEntryShape.make(kind, visit: nil).asksRating(isCompletion: false, hasSomeone: true), "\(kind)")
        }
        let job = HistoryEntryShape.make(.maintenance, visit: nil)
        #expect(job.asksRating(isCompletion: false, hasSomeone: false), "A visit logged by hand")
        #expect(!job.asksRating(isCompletion: true, hasSomeone: false), "Watering, done with „Gata”")
        #expect(HistoryEntryShape.make(.inspection, visit: nil).asksRating(isCompletion: true, hasSomeone: true))
    }

    @Test("A visit's record speaks its category's words: a vet's „Veterinarul”, a car's parts")
    func aVisitsRecordTakesItsKindsWords() throws {
        let vet = try #require(VisitKind.vet.shape)
        #expect(HistoryEntryShape.make(vet.historyKind, visit: vet).providerHeader == vet.provider?.header)
        let service = try #require(VisitKind.service.shape)
        #expect(HistoryEntryShape.make(service.historyKind, visit: service).rowsAreParts)
        let job = try #require(VisitKind.job.shape)
        #expect(!HistoryEntryShape.make(job.historyKind, visit: job).rowsAreParts, "A tradesperson's job lists no parts")
    }
}
