import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// `docs/COPY_MATRIX.md`: what each shaped screen says to each category, generated from the
/// kinds' descriptions (`VisitShape` through `VisitForm` for the visit form, `CompletionShape`
/// for „Gata” and „Am rezolvat”), for every built-in and one category of one's own per
/// combination of its switches. The file is committed; this test fails when it is out of date.
/// Beside it, the rules the matrix makes checkable: vehicle words only in a vehicle's kind,
/// a save requirement its own fields can meet, no empty checklist.
@MainActor
@Suite("Copy matrix")
struct CopyMatrixTests {
    /// The committed matrix.
    static var file: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "docs/COPY_MATRIX.md")
    }

    /// How to bring the file up to date, said when it isn't.
    static let regenerate = """
    docs/COPY_MATRIX.md is out of date with the kinds' descriptions. Bring it up to date: \
    TEST_RUNNER_COPY_MATRIX_WRITE=1 ./tests/run_tests.sh (or run CopyMatrixTests in Xcode with \
    COPY_MATRIX_WRITE=1 in the scheme's environment), then review the diff and commit it. The \
    test log also holds the new matrix between "BEGIN COPY_MATRIX.md" and "END COPY_MATRIX.md".
    """

    // MARK: The categories

    /// One category the matrix shows: its name, and its definition as installed.
    struct Category {
        var title: String
        var definition: TemplateDefinition
    }

    /// Every built-in, then one category of one's own per combination of its switches.
    static func categories() throws -> [Category] {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        var result = try BuiltInTemplates.all.map { builtIn in
            let installed = try store.template(forKey: builtIn.key)!
            return Category(title: "\(installed.name) (`\(builtIn.key)`)", definition: installed.definition)
        }
        let services: [(CategorySwitches.Service?, String)] = [
            (nil, "fără revizii"), (.init(.time), "revizii după timp"),
            (.init(.kilometres), "revizii după kilometri"), (.init(.engineHours), "revizii după ore"),
        ]
        for hasDocuments in [true, false] {
            for hasBills in [false, true] {
                for (service, said) in services {
                    let switches = CategorySwitches(hasDocuments: hasDocuments, hasBills: hasBills, service: service)
                    let made = try store.createCustom(name: "Categorie", symbol: "square", switches: switches)
                    let parts = [hasDocuments ? "cu acte" : "fără acte", hasBills ? "cu facturi" : "fără facturi", said]
                    result.append(Category(title: "A ta: " + parts.joined(separator: ", "), definition: made.definition))
                }
            }
        }
        return result
    }

    // MARK: The visit form's words

    /// Sample values for the words that carry one.
    static let sampleCount = 3
    static var sampleSum: String { Money(1_250, currency: "RON").formattedCompact() }
    static var sampleDay: String { DosarFormat.longDay(CalendarDay("2027-05-03")) }

    /// What the visit form says to one category, row by row, its kind's words only (the frame
    /// every kind shares is listed once, `sharedRows`).
    static func visitRows(_ form: VisitForm) -> [(String, String)] {
        let shape = form.shape
        var rows: [(String, String)] = [
            ("Its title, in the page's „Adaugă…” and Istoric", shape.title),
            ("„Scriu eu”'s card", "\(shape.title) — \(shape.startHint)"),
        ]
        if let paper = shape.paper {
            rows.append(("The paper's card", "\(paper.action) — \(form.paperHint ?? "")"))
            rows.append(("Where the photo comes from", "\(paper.sourceTitle): \(paper.camera)"))
            rows.append(("While it is read", paper.reading))
            rows.append(("Read", "\(paper.attached) (\(paper.read), photo not kept) — \(form.readNote(found: sampleCount) ?? "") / \(form.readNote(found: 0) ?? "")"))
            rows.append(("Not read", "\(paper.unread) — \(form.failedNote ?? "")"))
            rows.append(("Already in the binder", paper.isInvoice ? FiledPaperWording.title : "(only the same document, said nothing)"))
        }
        if form.hasChecklist, let work = shape.work {
            let groups = ComponentCatalog.checklist(for: form.components).map { "\($0.title): " + $0.components.map(\.name).joined(separator: ", ") }
            rows.append(("What was done: the checklist", "\(work.header) — \(work.checklistHint)"))
            rows.append(("Its rows", groups.joined(separator: " · ")))
            let detail = shape.asksBrand ? "\(VisitFormWording.rowCost), \(VisitFormWording.brand) (\(VisitFormWording.optional))" : VisitFormWording.rowCost
            rows.append(("A ticked row asks", "\(detail) · \(VisitFormWording.lastDone(DosarFormat.monthYear(noon("2026-03-15"))))"))
        }
        if form.hasRows, let work = shape.work {
            rows.append(("Rows of one's own", "\(form.rowsHeader ?? "") — \(form.rowsHint ?? "") · \(work.rowName), \(VisitFormWording.rowCost) · \(form.addRow ?? "")"))
        }
        if let note = shape.note {
            rows.append(("A note", "\(note.label) — \(note.prompt)"))
        }
        if form.warrantyField != nil {
            rows.append(("The warranty, under the date", "\(VisitFormWording.underWarranty(until: sampleDay)) / \(VisitFormWording.warrantyEnded(on: sampleDay))"))
        }
        if let counter = form.counterField {
            rows.append(("The counter", "\(counter.label) — \(VisitFormWording.estimate)"))
        }
        rows.append(("What it cost", [shape.costLabel, shape.costHint, form.sumNote(sampleSum)].compactMap { $0 }.joined(separator: " — ")))
        if let provider = shape.provider {
            rows.append(("Who did it", "\(provider.header) — \(VisitFormWording.name) / \(VisitFormWording.someoneElse), „\(provider.prompt)” — \(provider.rating)"))
        }
        rows.append(("Before it can save", form.requirementNote ?? "(saves with its day alone)"))
        rows.append(("The button", shape.save))
        rows.append(("The toast", "\(shape.toast) Anulează"))
        return rows
    }

    /// The visit form's frame, the same for every kind.
    static var sharedRows: [(String, String)] {
        [
            ("Details", "\(VisitFormWording.details) · \(VisitFormWording.date)"),
            ("Where the photo comes from", "\(VisitFormWording.photos) · \(VisitFormWording.files) · \(VisitFormWording.cancel)"),
            ("A row of one's own", VisitFormWording.removeRow),
            ("A firm already rated", VisitFormWording.rating("4,5")),
            ("Not saved", "\(VisitFormWording.notSaved) · \(VisitFormWording.photoDidNotOpen)"),
            ("A section that has gone", "\(VisitFormWording.sectionGone) — \(VisitFormWording.sectionGoneMessage)"),
            ("A link to a visit where the category has none", "\(VisitFormWording.noVisits) — \(VisitFormWording.noVisitsMessage)"),
        ]
    }

    // MARK: „Gata” and „Am rezolvat”

    /// What closing each of a category's deadlines asks, in its kind's words.
    static func completionRows(_ definition: TemplateDefinition) -> [(String, String)] {
        definition.blueprints.map { blueprint in
            let shape = blueprint.kind.completion
            var asks: [String] = []
            if shape.isOneTap { asks.append("nothing: done today, „Adaugă o notă” after") }
            if shape.asksDate { asks.append("Când") }
            if let cost = shape.cost { asks.append(cost.words) }
            if let paper = shape.paper {
                asks.append("\(paper.headerWords) (\(paper.purposeWords)) — \(paper.actionWords): \(paper.exampleWords)")
            }
            if shape.asksNewExpiry { asks.append("the new expiry") }
            if shape.asksNote { asks.append("a note") }
            if shape.asksReading, HouseholdMutations.heroMetricField(of: definition) != nil { asks.append("the counter") }
            return ("\(blueprint.title) (\(blueprint.kind.rawValue))", "\(shape.actionWords) / \(shape.menuWords) — " + asks.joined(separator: "; "))
        }
    }

    // MARK: The file

    static func table(_ rows: [(String, String)]) -> String {
        let escaped = rows.map { ($0.0, $0.1.replacingOccurrences(of: "|", with: "\\|")) }
        return (["| Where | Words |", "| :--- | :--- |"] + escaped.map { "| \($0.0) | \($0.1) |" }).joined(separator: "\n")
    }

    static func matrix() throws -> String {
        var out = """
        # Copy matrix

        What each shaped screen says to each category, generated from the kinds' descriptions: \
        the visit form from `VisitShape` laid over the category (`VisitForm`), „Gata” and \
        „Am rezolvat” from `CompletionShape`. Every built-in category is here, and one category \
        of one's own per combination of its switches. Reviews walk every category through it.

        Don't edit it by hand: `CopyMatrixTests` writes it and fails when it is out of date. \
        To bring it up to date, run `TEST_RUNNER_COPY_MATRIX_WRITE=1 ./tests/run_tests.sh` and \
        commit the diff. Sample values: \(sampleCount) rows, \(sampleSum), \(sampleDay).

        ## The visit form

        ### What every kind shares

        \(table(sharedRows))

        """
        let categories = try categories()
        for category in categories {
            let kind = category.definition.behavior.visit
            out += "\n### \(category.title) · `\(kind.rawValue)`\n\n"
            if let form = VisitForm.make(for: category.definition) {
                out += table(visitRows(form)) + "\n"
            } else if kind.addsNote {
                out += "No visits: offered nowhere. Istoric takes a dated note, „Adaugă o notă”.\n"
            } else {
                out += "No visits: offered nowhere, and Istoric adds nothing by hand.\n"
            }
        }
        out += "\n## „Gata” and „Am rezolvat”\n"
        for category in categories where !category.definition.blueprints.isEmpty {
            out += "\n### \(category.title)\n\n" + table(completionRows(category.definition)) + "\n"
        }
        return out
    }

    // MARK: Tests

    @Test("docs/COPY_MATRIX.md is up to date with the kinds' descriptions")
    func matrixIsUpToDate() throws {
        let fresh = try Self.matrix()
        if ProcessInfo.processInfo.environment["COPY_MATRIX_WRITE"] == "1" {
            try fresh.write(to: Self.file, atomically: true, encoding: .utf8)
            return
        }
        let committed = (try? String(contentsOf: Self.file, encoding: .utf8)) ?? ""
        if committed != fresh {
            print("BEGIN COPY_MATRIX.md\n\(fresh)\nEND COPY_MATRIX.md")
        }
        #expect(committed == fresh, Comment(rawValue: Self.regenerate))
    }

    /// Words about vehicles: a car's or a bike's parts, kilometres and dashboard.
    static let vehicleWords: Set<String> = ["km", "kilometraj", "kilometri", "kilometrajul", "piese", "piesele", "piesa", "marca", "ulei", "bord"]

    @Test("Vehicle words are only in a kind about vehicles")
    func vehicleWordsStayWithVehicles() throws {
        for category in try Self.categories() {
            guard let form = VisitForm.make(for: category.definition), form.kind != .service else { continue }
            let words = Self.visitRows(form).map(\.1).joined(separator: " ")
            let tokens = Set(RomanianText.fold(words).split { !$0.isLetter }.map(String.init))
            #expect(tokens.isDisjoint(with: Self.vehicleWords), "\(category.title): \(tokens.intersection(Self.vehicleWords).sorted())")
        }
    }

    @Test("Every save requirement can be met by the form's own fields, and no checklist is empty")
    func requirementsAndChecklists() throws {
        for category in try Self.categories() {
            guard let form = VisitForm.make(for: category.definition) else { continue }
            if let requirement = form.shape.requirement {
                #expect(!requirement.fields.isDisjoint(with: form.fields), "\(category.title): \(requirement.fields) against \(form.fields)")
            }
            #expect(form.hasChecklist == !form.components.isEmpty, "\(category.title)")
            if form.shape.work == nil { #expect(form.components.isEmpty, "\(category.title): a kind that ticks nothing lists no parts") }
            #expect(Self.visitRows(form).allSatisfy { !$0.1.isEmpty && !$0.1.contains("— —") }, "\(category.title): no empty words")
        }
    }
}
