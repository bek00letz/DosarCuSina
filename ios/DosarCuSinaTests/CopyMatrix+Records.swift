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
    /// One kind of record a category makes: its title, its page's shape, what it is (its stored
    /// kind, or a completion's record and the kind it is stored as) and, for a completion, the
    /// completion its deadline declares.
    struct RecordPage {
        var title: String
        var shape: HistoryEntryShape
        var said: String
        var completion: CompletionKind?
    }

    /// Each kind of record a category makes: its visits (by its visit kind), a note, and each of
    /// its deadlines' completions (by the completion its blueprint declares).
    static func recordPages(_ definition: TemplateDefinition) -> [RecordPage] {
        let visit = definition.behavior.visit.shape
        var pages: [RecordPage] = []
        if let visit {
            pages.append(RecordPage(title: visit.entryTitle, shape: HistoryEntryShape.make(visit.historyKind, visit: visit),
                                    said: visit.historyKind.rawValue, completion: nil))
        }
        if definition.behavior.visit.addsNote {
            pages.append(RecordPage(title: "Notă", shape: HistoryEntryShape.make(.note, visit: visit), said: HistoryKind.note.rawValue, completion: nil))
        }
        for blueprint in definition.blueprints {
            let completion = completionKind(blueprint)
            let stored = HistoryKind.forCompleting(completion, importance: blueprint.kind)
            pages.append(RecordPage(title: blueprint.title, shape: HistoryEntryShape.make(completing: completion, stored: stored, visit: visit),
                                    said: "\(completion.record.rawValue)`, stored as `\(stored.rawValue)", completion: completion))
        }
        return pages
    }

    /// What a record's page says, for each kind of record a category makes.
    static func historyRows(_ definition: TemplateDefinition) -> [(String, String)] {
        recordPages(definition).map { page in
            let shape = page.shape
            let isCompletion = page.completion != nil
            let rated = shape.asksRating(isCompletion: isCompletion, hasSomeone: false)
            let ratedWithSomeone = shape.asksRating(isCompletion: isCompletion, hasSomeone: true)
            let rating = rated ? shape.ratingHeader : ratedWithSomeone ? "\(shape.ratingHeader) (only when someone did it)" : "no rating"
            let deleted = isCompletion ? HistoryEntryWording.keepsDeadline : HistoryEntryWording.removesRows(parts: shape.rowsAreParts)
            return ("\(page.title) (`\(page.said)`)", "\(shape.itemsHeader) · \(shape.providerHeader) · \(rating) · \(shape.referenceWords("0001")) · deleting: \(deleted)")
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

    @Test("Each completion's page in Istoric fits what it is: a visit's provider only on a job or care, „Cui ai plătit” only where it asks what was paid, a check's words only on a check")
    func completionPagesFitTheirKind() throws {
        for category in try CopyMatrixTests.categories() {
            let visitProvider = category.definition.behavior.visit.shape?.provider?.header
            for page in CopyMatrixTests.recordPages(category.definition) {
                guard let completion = page.completion else { continue }
                let record = completion.record
                let said = "\(category.title): \(page.title) (\(record))"
                if let visitProvider, ![CompletionRecord.job, .care, .vaccination].contains(record) {
                    #expect(page.shape.providerHeader != visitProvider, "\(said) names „\(visitProvider)”")
                }
                #expect((page.shape.providerHeader == HistoryEntryWording.paidTo) == (completion.shape.cost == .paid), "\(said): „\(page.shape.providerHeader)”")
                #expect((page.shape.itemsHeader == HistoryEntryWording.whatWasChecked) == (record == .check), "\(said): „\(page.shape.itemsHeader)”")
                if completion.shape.isOneTap {
                    #expect(!page.shape.asksRating(isCompletion: true, hasSomeone: false), "\(said): a chore no one did asks no stars")
                }
            }
        }
    }

    @Test("A completion is stored as its record's kind: a rovinietă bought, a policy paid, the kit bought")
    func completionsAreStoredAsTheirRecord() {
        #expect(HistoryKind.forCompleting(.vignette, importance: .legal) == .purchase)
        #expect(HistoryKind.forCompleting(.safetyKit, importance: .legal) == .purchase)
        #expect(HistoryKind.forCompleting(.policy, importance: .insurance) == .payment)
        #expect(HistoryKind.forCompleting(.itp, importance: .legal) == .inspection)
        #expect(HistoryKind.forCompleting(.petVaccine, importance: .legal) == .vaccination, "The rabies vaccine is a vaccine, not a check")
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
