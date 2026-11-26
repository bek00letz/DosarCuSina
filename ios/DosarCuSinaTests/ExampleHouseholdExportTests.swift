import Foundation
import Testing
@testable import DosarCuSina

/// The example household (`ExampleHousehold.standard`), written to `shared/catalog/examples/` as
/// data, so the Android app loads the same household through its own actions and never keeps one
/// of its own (docs/ANDROID_PLAN.md, "How parity is kept", item 1). One file, `household.json`,
/// which `shared/catalog/README.md` describes: the loader's steps in order, each one key naming
/// its kind (`section`, `firm`, `record`, `pastCompletion`, `reading`) and holding it. The words in
/// it are the household's made-up names and values, data like the rest, not the app's copy.
///
/// Fresh or failing, as `CatalogExportTests` keeps the built-in catalog, and written by the same
/// switch (`CATALOG_WRITE=1`): a run that finds the file out of date leaves it made afresh in
/// `TEST_RUNNER_CATALOG_OUT`'s `examples/` folder.
@Suite("Example household export")
struct ExampleHouseholdExportTests {
    static var folder: URL { CatalogExportTests.folder.appending(path: "examples") }

    static let writtenBy = "ios/DosarCuSinaTests/ExampleHouseholdExportTests.swift"

    static let regenerate = """
    is out of date with the example household (ExampleHousehold.standard). Bring \
    shared/catalog/examples up to date: a failed run on GitHub keeps the file made afresh in its \
    test-results artifact, catalog/examples/ (copy it over), or TEST_RUNNER_CATALOG_WRITE=1 \
    ./tests/run_tests.sh (or run ExampleHouseholdExportTests in Xcode with CATALOG_WRITE=1 in the \
    scheme's environment); review the diff and commit it, then run the Android tests \
    (./gradlew :catalog:test :store:test in android/), which load the same household.
    """

    @Test("shared/catalog/examples is up to date with the example household")
    func householdIsUpToDate() throws {
        let files = try Self.files()
        let manager = FileManager.default
        if CatalogExportTests.writes { try manager.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        var outOfDate: [String] = []
        for (name, fresh) in files.sorted(by: { $0.key < $1.key }) {
            let url = Self.folder.appending(path: name)
            if CatalogExportTests.writes {
                try fresh.write(to: url, atomically: true, encoding: .utf8)
                continue
            }
            let committed = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if committed != fresh { outOfDate.append(name) }
        }
        // A file nothing writes any more goes, so Android never loads an old household.
        let present = (try? manager.contentsOfDirectory(atPath: Self.folder.path(percentEncoded: false))) ?? []
        for stale in present where stale.hasSuffix(".json") && files[stale] == nil {
            if CatalogExportTests.writes {
                try manager.removeItem(at: Self.folder.appending(path: stale))
            } else {
                Issue.record(Comment(rawValue: "\(stale) is written by nothing any more and " + Self.regenerate))
            }
        }
        if !outOfDate.isEmpty, let out = CatalogExportTests.outOfDateGoesTo?.appending(path: "examples") {
            try manager.createDirectory(at: out, withIntermediateDirectories: true)
            for (name, fresh) in files { try fresh.write(to: out.appending(path: name), atomically: true, encoding: .utf8) }
        }
        for name in outOfDate {
            Issue.record(Comment(rawValue: "shared/catalog/examples/\(name) " + Self.regenerate))
        }
    }

    @Test("Every step names a section, firm and deadline the household has made by then")
    func theStepsHoldTogether() {
        var sections: [String: String] = [:]
        var firms: Set<String> = []
        for step in ExampleHousehold.standard.steps {
            switch step {
            case .section(let section):
                #expect(BuiltInTemplates.definition(for: section.category) != nil, "\(section.ref)")
                #expect(section.parent.map { sections[$0] != nil } ?? true, "\(section.ref)'s parent comes first")
                #expect(sections[section.ref] == nil, "\(section.ref) is made once")
                sections[section.ref] = section.category
            case .firm(let firm):
                #expect(firm.linkedTo.allSatisfy { sections[$0] != nil }, "\(firm.ref)")
                firms.insert(firm.ref)
            case .record(let record):
                #expect(sections[record.section] != nil && record.firms.allSatisfy(firms.contains), "\(record.title)")
            case .pastCompletion(let completion):
                let blueprints = sections[completion.section].flatMap(BuiltInTemplates.definition(for:))?.blueprints ?? []
                #expect(blueprints.contains { $0.key == completion.deadline }, "\(completion.deadline)")
            case .reading(let reading):
                #expect(sections[reading.section] != nil, "\(reading.kind)")
            }
        }
    }

    // MARK: The file

    static func files() throws -> [String: String] {
        ["household.json": try CatalogExportTests.render(File(steps: ExampleHousehold.standard.steps, writtenBy: writtenBy))]
    }

    /// The household's steps, and the test that writes them.
    struct File: Encodable {
        let steps: [ExampleHousehold.Step]
        let writtenBy: String
    }
}
