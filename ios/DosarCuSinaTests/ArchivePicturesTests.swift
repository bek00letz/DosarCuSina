import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import DosarCuSina

/// A scanned page or a thumbnail in a `.dosar` archive is a HEIC or a JPEG picture, named by
/// what it is (`page-1.heic`, `page-2.jpg`), and a reader knows it by its bytes, never by its
/// name, so an archive written before the rule, with a JPEG named `.heic`, reads as before
/// (`shared/schemas/dosar-v3.md`, "Pages and thumbnails"; DECISIONS 2026-11-25).
@MainActor
@Suite("Archive pictures")
struct ArchivePicturesTests {
    let calendar = Calendar.bucharest

    /// A real picture of each kind, from the golden archives' inputs.
    static func picture(_ name: String) throws -> Data {
        try Data(contentsOf: Fixtures.root.appending(path: "golden/inputs/\(name)"))
    }

    @Test("A page or a thumbnail is named by what its bytes are")
    func picturesAreNamedByWhatTheyAre() throws {
        let heic = try Self.picture("page-front.heic")
        let jpeg = try Self.picture("page-back.jpg")
        #expect(ShareInbox.type(sniffing: heic) == .heic && ShareInbox.type(sniffing: jpeg) == .jpeg, "The inputs are what they say")
        #expect(DossierV3.Path.pictureExtension(of: heic) == "heic")
        #expect(DossierV3.Path.pictureExtension(of: jpeg) == "jpg")
        #expect(DossierV3.Path.pictureExtension(of: Data([1, 2, 3])) == "heic", "Anything that isn't a JPEG keeps the name every page had")

        let context = try makeContext()
        let section = try AssetActions(context: context, calendar: calendar, now: { noon("2026-11-20") })
            .create(name: "Cutie", template: try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.other)), values: FieldValues())
        let documents = AttachmentActions(context: context, calendar: calendar)
        let mixed = try documents.file(
            DocumentDraft(title: "Două fețe", fileName: "acte.heic", kind: .identity, contentType: "public.heic",
                          pageImages: [heic, jpeg], thumbnail: try Self.picture("thumb-back.jpg")),
            asset: section
        )
        let kept = try documents.file(
            DocumentDraft(title: "O față", fileName: "act.heic", kind: .other, contentType: "public.heic",
                          pageImages: [jpeg], thumbnail: try Self.picture("thumb-front.heic")),
            asset: section
        )

        let archive = try DossierArchiveService(container: context.container, calendar: calendar).exportData(exportedAt: noon("2026-11-20"))
        let entries = Dictionary(try DosarZipEngine.unpackArchive(archive).map { ($0.path, $0.data) }, uniquingKeysWith: { first, _ in first })
        let package = try DossierArchiveReader.read(archive)
        let first = try #require(package.attachments.first { $0.id == DossierV3.id(mixed.id) })
        let base = "vault/\(DossierV3.id(mixed.id))"
        #expect(first.pagePaths == ["\(base)/page-1.heic", "\(base)/page-2.jpg"])
        #expect(first.thumbnailPath == "\(base)/thumbnail.jpg")
        #expect(entries[first.pagePaths[0]] == heic && entries[first.pagePaths[1]] == jpeg, "The bytes go out as they are kept")
        let second = try #require(package.attachments.first { $0.id == DossierV3.id(kept.id) })
        #expect(second.pagePaths == ["vault/\(DossierV3.id(kept.id))/page-1.jpg"])
        #expect(second.thumbnailPath == "vault/\(DossierV3.id(kept.id))/thumbnail.heic")
    }

    @Test("A JPEG page named .heic, from an archive written before the rule, still comes in")
    func aJPEGNamedHEICStillImports() throws {
        let jpeg = try Self.picture("page-back.jpg")
        let thumbnail = try Self.picture("thumb-back.jpg")
        let page = "vault/6b7c8d9e-0f1a-4b2c-9d4e-5f6a7b8c9db8/page-1.heic"
        let thumb = "vault/6b7c8d9e-0f1a-4b2c-9d4e-5f6a7b8c9db8/thumbnail.heic"
        let archive = try Fixtures.archive("dosar-v3/household") { files in
            files[page] = jpeg
            files[thumb] = thumbnail
            var manifest = try! JSONSerialization.jsonObject(with: files["manifest.json"]!) as! [String: Any]
            var checksums = manifest["checksums"] as! [String: String]
            checksums[page] = Hashing.sha256(jpeg)
            checksums[thumb] = Hashing.sha256(thumbnail)
            manifest["checksums"] = checksums
            files["manifest.json"] = try! JSONSerialization.data(withJSONObject: manifest)
        }
        let container = try makeInMemoryContainer()
        try DossierArchiveService(container: container, calendar: calendar).importArchive(archive, mode: .replace)
        let report = try #require(try ModelContext(container).fetch(FetchDescriptor<DosarCuSina.Attachment>()).first { $0.title == "Raport ITP 2026" })
        let kept = try #require(report.orderedPages.first?.imageData)
        #expect(kept == jpeg && report.thumbnailData == thumbnail, "The picture comes in as it is, whatever its name")
        #expect(ImageScaling.decoded(kept, maxLongEdge: nil) != nil, "And is drawn by its bytes")

        // Written again, it is named by what it is.
        let again = try DossierArchiveReader.read(try DossierArchiveService(container: container, calendar: calendar).exportData(exportedAt: noon("2026-11-20")))
        let written = try #require(again.attachments.first { $0.id == "6b7c8d9e-0f1a-4b2c-9d4e-5f6a7b8c9db8" })
        #expect(written.pagePaths == ["vault/6b7c8d9e-0f1a-4b2c-9d4e-5f6a7b8c9db8/page-1.jpg"])
        #expect(written.thumbnailPath == "vault/6b7c8d9e-0f1a-4b2c-9d4e-5f6a7b8c9db8/thumbnail.jpg")
    }
}
