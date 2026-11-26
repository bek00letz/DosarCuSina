import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// The example household loaded, kept and removed, written to `shared/test-vectors/examples/`:
/// what loading leaves in the binder (`ExampleDataService.loadExamples`), what removing leaves
/// (`removeExamples`) and the sections it keeps as the person's, what "Anulează" brings back, and
/// what keeping one as one's own (`adopt`) does to removing. The Android app's tests run the same
/// steps through its own store (android/store, `store.examples`) and must leave the same binder
/// (docs/ANDROID_PLAN.md, "How parity is kept"). A sibling of `SectionVectorsTests`.
///
/// A binder is written as a backup writes it, record by record in each data file (the categories
/// left out: the catalog's, pinned by shared/catalog/), with only what must differ from one run to
/// the next left out, as the golden archives are compared (`GoldenContents.canonical`): every id
/// is written as the place it takes (`id-1`, `id-2`…), counted over the records in an order of
/// their own contents, and `createdAt` is `<made>`. The order and the places are worked out on
/// each record written as compact machine JSON (`MachineText`), the same bytes on both apps.
///
/// Nothing depends on the machine: the calendar is the app's in Bucharest and today is fixed, so
/// `TEST_RUNNER_TZ=UTC` writes the same files. Placeholder data only.
@MainActor
@Suite("Example vectors", .serialized)
struct ExampleVectorsTests {
    static var folder: URL { SectionVectorsTests.folder.deletingLastPathComponent().appending(path: "examples") }

    static let regenerate = """
    is out of date with the example household. Bring shared/test-vectors/examples up to date: a \
    failed run on GitHub keeps them made afresh in its test-results artifact, test-vectors/examples/ \
    (copy them over), or TEST_RUNNER_EXAMPLE_VECTORS_WRITE=1 ./tests/run_tests.sh (or run \
    ExampleVectorsTests in Xcode with EXAMPLE_VECTORS_WRITE=1 in the scheme's environment); review \
    the diff and commit it, then run the Android tests (./gradlew :store:test in android/), which \
    read the same files.
    """

    typealias Vectors = ValueVectorsTests.Vectors

    /// The day every case is run on.
    static let today = SectionVectorsTests.today

    static var calendar: Calendar { SectionVectorsTests.calendar }

    static func now() -> Date { CalendarDay(today).noonDate(in: calendar) }

    /// The data files a binder is written with, in the archive's order: every one but the categories.
    static var paths: [String] { DossierV3.Path.dataFiles.filter { $0 != DossierV3.Path.templates } }

    @Test("shared/test-vectors/examples is up to date with the example household")
    func vectorsAreUpToDate() throws {
        let files = try Self.all()
        let environment = ProcessInfo.processInfo.environment
        let writes = environment["EXAMPLE_VECTORS_WRITE"] == "1"
        let manager = FileManager.default
        if writes { try manager.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        var fresh: [String: String] = [:]
        var outOfDate: [String] = []
        for file in files {
            let name = "\(file.name).json"
            let text = try ValueVectorsTests.render(file)
                .replacingOccurrences(of: "ios/DosarCuSinaTests/ValueVectorsTests.swift", with: "ios/DosarCuSinaTests/ExampleVectorsTests.swift")
            fresh[name] = text
            let url = Self.folder.appending(path: name)
            if writes {
                try text.write(to: url, atomically: true, encoding: .utf8)
                continue
            }
            let committed = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if committed != text { outOfDate.append(name) }
        }
        // A file no rule writes any more goes, so Android never tests against an old answer.
        let present = (try? manager.contentsOfDirectory(atPath: Self.folder.path(percentEncoded: false))) ?? []
        for stale in present where stale.hasSuffix(".json") && fresh[stale] == nil {
            if writes {
                try manager.removeItem(at: Self.folder.appending(path: stale))
            } else {
                Issue.record(Comment(rawValue: "\(stale) is written by no rule any more " + Self.regenerate))
            }
        }
        // A run that finds them out of date leaves them as they should be, for a failed run on GitHub to keep.
        if !outOfDate.isEmpty, let out = environment["VECTORS_OUT"], !out.isEmpty {
            let folder = URL(filePath: out, directoryHint: .isDirectory).appending(path: "examples")
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, text) in fresh { try text.write(to: folder.appending(path: name), atomically: true, encoding: .utf8) }
        }
        for name in outOfDate.sorted() {
            Issue.record(Comment(rawValue: "\(name) " + Self.regenerate))
        }
    }

    static func all() throws -> [Vectors] {
        [try loadAndRemove()]
    }

    // MARK: The steps

    /// One thing a case does to the binder, as the case writes it.
    enum Step {
        /// A section of the person's own, made with `AssetActions.create`.
        case ownSection(name: String, category: String)
        /// "Explore with examples".
        case load
        /// A section of the person's filed inside an example, as an earlier version let it be,
        /// before the app asked (`ExampleSectionQuestion`): written straight into the binder.
        case ownSectionInside(name: String, category: String, parent: String)
        /// "Da" to "Păstrezi … ca al tău?" for the section with this name.
        case adopt(String)
        /// "Șterge exemplele".
        case remove
        /// "Anulează" on the last removal's toast.
        case undo

        var json: JSONValue {
            switch self {
            case .ownSection(let name, let category): ["do": "ownSection", "name": .string(name), "category": .string(category)]
            case .load: ["do": "load"]
            case .ownSectionInside(let name, let category, let parent):
                ["do": "ownSectionInside", "name": .string(name), "category": .string(category), "parent": .string(parent)]
            case .adopt(let name): ["do": "adopt", "section": .string(name)]
            case .remove: ["do": "remove"]
            case .undo: ["do": "undo"]
            }
        }
    }

    /// The cases: each one's name and its steps, from an empty binder with the built-in categories.
    static let cases: [(String, [Step])] = [
        ("loading the examples into an empty binder", [.load]),
        ("loading them twice leaves one household", [.load, .load]),
        ("removing them leaves nothing", [.load, .remove]),
        ("removing them leaves the person's own section beside them",
         [.ownSection(name: "Mașina mea", category: BuiltInTemplates.Key.vehicle), .load, .remove]),
        ("Anulează brings every example back", [.load, .remove, .undo]),
        ("an example holding a section of the person's stays, as theirs",
         [.load, .ownSectionInside(name: "Boxa", category: BuiltInTemplates.Key.other, parent: "Apartament Floreasca"), .remove]),
        ("a document kept as one's own keeps its holder and the other document, and removing leaves them",
         [.load, .adopt("Pașaport"), .remove]),
    ]

    /// What the steps leave: the sections the last removal kept as the person's, and the binder.
    static func run(_ steps: [Step]) throws -> (kept: [String]?, binder: JSONValue) {
        let container = try makeInMemoryContainer()
        let context = PersistenceController.context(in: container)
        try TemplateStore(context: context).installBuiltIns()
        let service = ExampleDataService(context: context, calendar: calendar, now: { now() })
        var kept: [String]?
        var receipt: UndoReceipt?
        for step in steps {
            switch step {
            case .ownSection(let name, let category):
                let template = try SectionVectorsTests.category(category, in: context)
                try SectionVectorsTests.makeActions(context).create(name: name, template: template, values: FieldValues())
            case .load:
                try service.loadExamples()
            case .ownSectionInside(let name, let category, let parentName):
                let parent = try #require(try context.fetch(FetchDescriptor<Asset>()).first { $0.name == parentName })
                try UnitOfWork.perform(in: context, now: now()) {
                    let section = Asset(name: name, templateKey: category)
                    context.insert(section)
                    section.parent = parent
                }
            case .adopt(let name):
                let section = try #require(try context.fetch(FetchDescriptor<Asset>()).first { $0.name == name })
                try service.adopt(sectionID: section.id)
            case .remove:
                let removed = try service.removeExamples()
                kept = removed.value.sorted()
                receipt = removed.receipt
            case .undo:
                try #require(receipt).undo()
            }
        }
        return (kept, try binder(of: container))
    }

    static func loadAndRemove() throws -> Vectors {
        var written: [JSONValue] = []
        for (name, steps) in cases {
            let outcome = try run(steps)
            written.append(.object([
                "name": .string(name),
                "steps": .array(steps.map(\.json)),
                "kept": outcome.kept.map { .array($0.map(JSONValue.string)) } ?? .null,
                "binder": outcome.binder,
            ]))
        }
        return Vectors(
            name: "load-and-remove",
            rule: "ExampleDataService.loadExamples(), removeExamples() with its receipt, and adopt(sectionID:), over ExampleHousehold.standard",
            source: "ios/DosarCuSina/Services/Examples/ExampleDataService.swift, ExampleHousehold.swift",
            shape: "name; steps, each {do: ownSection (name, category: a section of the person's, through AssetActions.create) | load | ownSectionInside (name, category, parent: the name of the example it is filed in, written straight into the binder as an earlier version let it be) | adopt (section: its name) | remove | undo (the last removal's receipt)}, run in order on an empty binder with the built-in categories, today 2026-11-26 at noon in Europe/Bucharest; kept: the names the last removal kept as the person's, in order, or null with no removal; binder: what the steps leave, by data file as a backup writes it (the categories left out), each file's records in an order of their own contents, every id written as the place it takes (id-1, id-2…, the records' own ids first, file by file, then the others as they come), a list of ids in the order of their places, createdAt as <made>",
            cases: written
        )
    }

    // MARK: The binder as a backup writes it

    /// The binder's records as an archive writes them, in the canonical form the shape says.
    static func binder(of container: ModelContainer) throws -> JSONValue {
        let service = DossierArchiveService(container: container, calendar: calendar)
        let contents = try GoldenContents.unpack(try service.exportData(appVersion: "0", exportedAt: now()))
        var files: [(String, [JSONValue])] = []
        for path in paths {
            let records: JSONValue = try contents.files[path].map { try JSONDecoder().decode(JSONValue.self, from: $0) } ?? .array([])
            guard case .array(let list) = records else { throw Unreadable(path: path) }
            files.append((path, list))
        }
        return try Canonical.form(files)
    }

    struct Unreadable: Error { let path: String }
}

/// A binder's records with what must differ from one run to the next left out: ids written as
/// the place they take, `createdAt` as `<made>` (see `ExampleVectorsTests`).
@MainActor
enum Canonical {
    static var uuid: Regex<Substring> { GoldenContents.uuid }

    /// Each file's records (`files`, in order), in canonical form, by file.
    static func form(_ files: [(String, [JSONValue])]) throws -> JSONValue {
        var places: [String: String] = [:]
        func place(_ id: String) -> String {
            let key = id.lowercased()
            if let known = places[key] { return known }
            let made = "id-\(places.count + 1)"
            places[key] = made
            return made
        }
        // The records of each file, in an order of their contents alone.
        var ordered: [(String, [JSONValue])] = []
        for (path, records) in files {
            let blank = try records.map { (record: $0, text: try text(written($0) { _ in "<id>" })) }
            let sorted = blank.sorted { $0.text < $1.text }
            for (a, b) in zip(sorted, sorted.dropFirst()) where a.text == b.text {
                Issue.record("\(path) has two records that differ only by their ids: tell them apart")
            }
            ordered.append((path, sorted.map(\.record)))
        }
        // Every record's own id first, so a link counts the same whatever the order of the links.
        for (_, records) in ordered {
            for case .object(let record) in records {
                if case .string(let id)? = record["id"] { for match in id.matches(of: uuid) { _ = place(String(match.output)) } }
            }
        }
        var result: [String: JSONValue] = [:]
        for (path, records) in ordered {
            result[path] = .array(records.map { written($0, ids: place) })
        }
        return .object(result)
    }

    /// `value` with every id given by `ids`, a list of ids in the order of what they are written
    /// as, and `createdAt` as `<made>`.
    static func written(_ value: JSONValue, key: String? = nil, ids: (String) -> String) -> JSONValue {
        switch value {
        case .string(let string):
            return key == "createdAt" ? .string("<made>") : .string(string.replacing(uuid) { ids(String($0.output)) })
        case .array(let list):
            let items = list.map { written($0, ids: ids) }
            // A list of ids (a firm's sections, a visit's firms) is a set: written in the ids' order.
            let allIDs = list.allSatisfy { if case .string(let text) = $0 { text.wholeMatch(of: uuid) != nil } else { false } }
            if !list.isEmpty, allIDs {
                return .array(items.compactMap { if case .string(let text) = $0 { text } else { nil } }.sorted().map(JSONValue.string))
            }
            return .array(items)
        case .object(let object):
            var formed: [String: JSONValue] = [:]
            for (name, field) in object.sorted(by: { $0.key < $1.key }) {
                formed[name.replacing(uuid) { ids(String($0.output)) }] = written(field, key: name, ids: ids)
            }
            return .object(formed)
        default:
            return value
        }
    }

    /// `value` as compact machine JSON: its keys sorted, the same bytes on both apps.
    static func text(_ value: JSONValue) throws -> String {
        String(decoding: try MachineText.jsonEncoder(.compact).encode(value), as: UTF8.self)
    }
}
