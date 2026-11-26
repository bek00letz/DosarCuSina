import Foundation
import Testing
@testable import DosarCuSina

/// Android's golden archives in `shared/fixtures/golden/android/` (made by the Android writer from
/// the iOS golden household brought into an empty Android binder, `GoldenAndroidArchivesTest`),
/// brought into an empty binder here: iOS → Android → iOS. Written out again, the binder must hold
/// exactly what the iOS golden household holds (`ios/expected/`), by the one comparison the iOS
/// golden archives are kept fresh by (`GoldenContents.canonical`), and every record as the Android
/// archive wrote it.
@MainActor
@Suite("Android's golden archives", .serialized)
struct AndroidGoldenArchiveTests {
    static var android: URL { GoldenArchiveTests.root.appending(path: "android") }

    @Test("Both Android golden archives come in whole and hold the iOS household", arguments: [false, true])
    func androidArchivesComeInWhole(protected: Bool) throws {
        let name = protected ? "household-password.dosar" : "household.dosar"
        let archive = try Data(contentsOf: Self.android.appending(path: name))
        #expect(ArchiveEncryption.isEncrypted(archive) == protected)
        let container = try makeInMemoryContainer()
        let service = DossierArchiveService(container: container, calendar: GoldenHousehold.calendar)
        try service.importArchive(archive, password: protected ? GoldenArchiveTests.password : nil, mode: .replace)

        let ios = try GoldenContents.read(GoldenArchiveTests.expected)
        let manifest = try GoldenContents.manifest(ios)
        let again = try GoldenContents.unpack(service.exportData(appVersion: manifest.appVersion, exportedAt: GoldenArchiveTests.exportedAt))

        // What it holds, written out by this app, is the iOS household: nothing was lost either way.
        let fresh = try GoldenContents.canonical(again)
        let expected = try GoldenContents.canonical(ios)
        for path in Set(fresh.keys).union(expected.keys).sorted() where fresh[path] != expected[path] {
            Issue.record(Comment(rawValue: "\(name): \(path) differs from the iOS household after the trip through Android"))
        }

        // And every record comes back as the Android archive wrote it.
        let written = try GoldenContents.read(Self.android.appending(path: "expected"))
        #expect(try GoldenContents.manifest(written).platform == "Android")
        #expect(try GoldenContents.manifest(again).counts == GoldenContents.manifest(written).counts, "\(name): every record came in")
        #expect(again.vault == written.vault, "\(name): every page, file, thumbnail and photo came in as it was")
        for path in DossierV3.Path.dataFiles {
            let before = try GoldenContents.records(written, path)
            let after = try GoldenContents.records(again, path)
            #expect(Set(after.keys) == Set(before.keys), "\(name): \(path) has the same records")
            for (id, record) in before where after[id] != record {
                Issue.record(Comment(rawValue: "\(name): \(path) record \(id) came back different"))
            }
        }
        let readme = try String(contentsOf: Self.android.appending(path: "README.md"), encoding: .utf8)
        #expect(readme.contains("`\(GoldenArchiveTests.password)`"), "The README beside them says the password")
    }
}
