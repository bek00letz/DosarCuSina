import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// The example household declared as data (`ExampleHousehold.standard`) makes exactly the records the
/// hand-written loader made before it: the same sections, deadlines and their dates, history, firms
/// and readings. `Fixtures/examples-before-the-household-data.json` is what the hand-written loader
/// left in an empty binder, written once by it on GitHub's Mac (a verbatim copy of main's loader at
/// c1086db2, run in this pull request's commit 410c5dc8, then removed) and never changed to match; the
/// binder is written as `ExampleVectorsTests` writes one (as a backup writes it, ids by place,
/// `createdAt` as `<made>`), today 2026-11-26 at noon in Bucharest.
@MainActor
@Suite("Examples before the household data")
struct ExamplesBeforeTheHouseholdDataTests {
    static var fixture: URL {
        URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/examples-before-the-household-data.json")
    }

    /// An empty binder with the built-in categories and `load` run in it, as a backup writes it.
    static func binder(_ load: (ModelContext) throws -> Void) throws -> JSONValue {
        let container = try makeInMemoryContainer()
        let context = PersistenceController.context(in: container)
        try TemplateStore(context: context).installBuiltIns()
        try load(context)
        return try ExampleVectorsTests.binder(of: container)
    }

    static func text(_ value: JSONValue) throws -> String {
        String(decoding: try MachineText.jsonEncoder(.readable).encode(value), as: UTF8.self) + "\n"
    }

    @Test("The household as data makes what the hand-written loader made, record by record")
    func theSameRecords() throws {
        let committed = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: Self.fixture))
        let now = ExampleVectorsTests.now()
        let fresh = try Self.binder { try ExampleDataService(context: $0, calendar: ExampleVectorsTests.calendar, now: { now }).loadExamples() }
        guard case .object(let before) = committed, case .object(let after) = fresh else {
            Issue.record("The fixture isn't a binder")
            return
        }
        for path in ExampleVectorsTests.paths {
            guard case .array(let old)? = before[path], case .array(let new)? = after[path] else {
                Issue.record("\(path) is missing")
                continue
            }
            #expect(new.count == old.count, "\(path): \(new.count) records, \(old.count) before")
            for (index, (was, made)) in zip(old, new).enumerated() where was != made {
                guard case .object(let a) = was, case .object(let b) = made else { continue }
                for key in Set(a.keys).union(b.keys).sorted() where a[key] != b[key] {
                    let wasText = try Self.text(a[key] ?? .null)
                    let madeText = try Self.text(b[key] ?? .null)
                    Issue.record("\(path)[\(index)].\(key): before \(wasText), now \(madeText)")
                }
            }
        }
    }
}
