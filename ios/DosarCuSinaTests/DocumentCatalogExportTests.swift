import Foundation
import Testing
@testable import DosarCuSina

/// What a personal document can be, written to `shared/catalog/documents/` as data, so the Android
/// app reads the same document types and never keeps a list of its own (docs/ANDROID_PLAN.md, "How
/// parity is kept", item 1). One file, `documents.json`, which `shared/catalog/README.md` describes:
///
/// - the fields that hold a document's type and its variant;
/// - the types (`DocumentType.options`): each one's key, name and other spellings;
/// - the variants (`DocumentType.variants`): each one's type, key, name as offered, and the name a
///   document of that variant takes when it isn't its type's („Cazier fiscal”);
/// - what the app declares on the types as data: what a document of no known type is called, which
///   keep a back, how long one is valid after it is issued, which are read only on the phone and
///   which are sent only to someone trusted.
///
/// A type's travel data (its travel margin, whether a variant travels and until when) is the trip
/// check's, in `shared/travel/documents.json` (`TravelExportTests`), keyed by the same keys.
///
/// Fresh or failing, as `CatalogExportTests` keeps the built-in catalog, and written by the same
/// switch (`CATALOG_WRITE=1`): a run that finds the file out of date leaves it made afresh in
/// `TEST_RUNNER_CATALOG_OUT`'s `documents/` folder.
@Suite("Document catalog export")
struct DocumentCatalogExportTests {
    static var folder: URL { CatalogExportTests.folder.appending(path: "documents") }

    static let writtenBy = "ios/DosarCuSinaTests/DocumentCatalogExportTests.swift"

    static let regenerate = """
    is out of date with what a personal document can be (DocumentType). Bring shared/catalog/documents up to \
    date: a failed run on GitHub keeps the file made afresh in its test-results artifact, catalog/documents/ \
    (copy it over), or TEST_RUNNER_CATALOG_WRITE=1 ./tests/run_tests.sh (or run DocumentCatalogExportTests in \
    Xcode with CATALOG_WRITE=1 in the scheme's environment); review the diff and commit it, then run the \
    Android tests (./gradlew :core:test :catalog:test in android/), which read the same file.
    """

    @Test("shared/catalog/documents is up to date with what a personal document can be")
    func catalogIsUpToDate() throws {
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
        if !outOfDate.isEmpty, let out = CatalogExportTests.outOfDateGoesTo?.appending(path: "documents") {
            try manager.createDirectory(at: out, withIntermediateDirectories: true)
            for (name, fresh) in files { try fresh.write(to: out.appending(path: name), atomically: true, encoding: .utf8) }
        }
        for name in outOfDate {
            Issue.record(Comment(rawValue: "shared/catalog/documents/\(name) " + Self.regenerate))
        }
    }

    // MARK: The file

    static func files() throws -> [String: String] {
        ["documents.json": try CatalogExportTests.render(documents())]
    }

    static func strings(_ values: some Sequence<String>) -> JSONValue { .array(values.map(JSONValue.string)) }

    static func documents() -> JSONValue {
        let types = DocumentType.options.map { option -> JSONValue in
            .object(["key": .string(option.key), "label": .string(option.label), "aliases": strings(option.aliases)])
        }
        let variants = DocumentType.variants.map { spec -> JSONValue in
            .object([
                "type": .string(spec.type),
                "key": .string(spec.option.key),
                "label": .string(spec.option.label),
                // The name the document takes when it isn't its type's ("Cazier fiscal"), else null.
                "documentName": spec.documentName.map { .string($0) } ?? .null,
            ])
        }
        return .object([
            "typeField": .string(DocumentType.typeFieldKey),
            "variantField": .string(DocumentType.variantFieldKey),
            "types": .array(types),
            "variants": .array(variants),
            "unnamed": .string(DocumentType.unnamed),
            "keepsBackSide": strings(DocumentType.keepsBackSide.sorted()),
            "validityMonthsAfterIssue": .object(DocumentType.validityMonthsAfterIssue.mapValues { .int($0) }),
            "readOnPhoneOnly": strings(DocumentType.readOnPhoneOnly.sorted()),
            "sharedWithCare": strings(DocumentType.sharedWithCare.sorted()),
            "writtenBy": .string(writtenBy),
        ])
    }
}
