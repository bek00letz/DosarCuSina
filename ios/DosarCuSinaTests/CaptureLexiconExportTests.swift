import Foundation
import Testing
@testable import DosarCuSina

/// The words capture's shared readers look for that are no one kind's (`CaptureLexicon`), written to
/// `shared/catalog/capture/` as data, so the Android app reads the same words and never keeps a list
/// of its own (docs/ANDROID_PLAN.md, "How parity is kept", item 1). One file, `lexicon.json`, which
/// `shared/catalog/README.md` describes: today what a line of work is that is never a part
/// (`labourWords`, read by `LabourLine`); capture's other words join it with capture's port.
///
/// Fresh or failing, as `CatalogExportTests` keeps the built-in catalog, and written by the same
/// switch (`CATALOG_WRITE=1`): a run that finds the file out of date leaves it made afresh in
/// `TEST_RUNNER_CATALOG_OUT`'s `capture/` folder.
@Suite("Capture lexicon export")
struct CaptureLexiconExportTests {
    static var folder: URL { CatalogExportTests.folder.appending(path: "capture") }

    static let writtenBy = "ios/DosarCuSinaTests/CaptureLexiconExportTests.swift"

    static let regenerate = """
    is out of date with capture's lexicon (CaptureLexicon). Bring shared/catalog/capture up to date: a \
    failed run on GitHub keeps the file made afresh in its test-results artifact, catalog/capture/ (copy \
    it over), or TEST_RUNNER_CATALOG_WRITE=1 ./tests/run_tests.sh (or run CaptureLexiconExportTests in \
    Xcode with CATALOG_WRITE=1 in the scheme's environment); review the diff and commit it, then run the \
    Android tests (./gradlew :core:test in android/), which read the same file.
    """

    @Test("shared/catalog/capture is up to date with capture's lexicon")
    func lexiconIsUpToDate() throws {
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
        // A file nothing writes any more goes, so Android never reads an old list.
        let present = (try? manager.contentsOfDirectory(atPath: Self.folder.path(percentEncoded: false))) ?? []
        for stale in present where stale.hasSuffix(".json") && files[stale] == nil {
            if CatalogExportTests.writes {
                try manager.removeItem(at: Self.folder.appending(path: stale))
            } else {
                Issue.record(Comment(rawValue: "\(stale) is written by nothing any more and " + Self.regenerate))
            }
        }
        if !outOfDate.isEmpty, let out = CatalogExportTests.outOfDateGoesTo?.appending(path: "capture") {
            try manager.createDirectory(at: out, withIntermediateDirectories: true)
            for (name, fresh) in files { try fresh.write(to: out.appending(path: name), atomically: true, encoding: .utf8) }
        }
        for name in outOfDate {
            Issue.record(Comment(rawValue: "shared/catalog/capture/\(name) " + Self.regenerate))
        }
    }

    @Test("The labour words are folded, so they match as LabourLine reads a line")
    func theWordsAreFolded() {
        for word in CaptureLexicon.labourWords {
            #expect(SearchText.normalize(word) == word, "\(word)")
        }
    }

    // MARK: The file

    static func files() throws -> [String: String] {
        ["lexicon.json": try CatalogExportTests.render(Lexicon())]
    }

    /// Capture's words that are no one kind's, as data.
    struct Lexicon: Encodable {
        var labourWords = CaptureLexicon.labourWords
        var writtenBy = CaptureLexiconExportTests.writtenBy
    }
}
