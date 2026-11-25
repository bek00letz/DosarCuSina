import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A copy of the binder kept before an iCloud account change is never written over by the next
/// one, and the newest few stay, by one order. Every value is a placeholder.
@MainActor
@Suite("Copies kept before an account change")
struct KeptCopiesTests {
    private func folder() -> URL {
        URL.temporaryDirectory.appending(path: "kept-copies-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func binder(named name: String) throws -> ModelContainer {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(Asset(name: name, templateKey: BuiltInTemplates.Key.vehicle))
        try context.save()
        return container
    }

    @Test("Two copies kept on one day are two files, each with its own binder")
    func twoOnOneDayStayTwo() async throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let morning = noon("2026-11-18").addingTimeInterval(-3 * 3_600)
        let first = try await KeptCopies.keep(container: try binder(named: "VW Golf 2018"), in: folder, now: morning)
        let second = try await KeptCopies.keep(container: try binder(named: "Dacia Logan 2020"), in: folder, now: noon("2026-11-18"))

        #expect(first != second)
        #expect(KeptCopies.all(in: folder) == [second, first], "The newest first")
        let firstHolds = try DossierArchiveReader.summary(contentsOf: first)
        #expect(firstHolds.counts.assets == 1, "The first copy is still there, whole")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).filter { $0.hasPrefix(".") }.isEmpty,
                "Nothing half written is left beside them")
    }

    @Test("Past the most kept, the oldest go as a new one is kept")
    func theNewestStay() async throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var kept: [URL] = []
        for hour in 0..<(KeptCopies.mostKept + 2) {
            let moment = noon("2026-11-18").addingTimeInterval(Double(hour) * 3_600)
            kept.append(try await KeptCopies.keep(container: try binder(named: "VW Golf 2018"), in: folder, now: moment))
        }
        #expect(KeptCopies.all(in: folder) == Array(kept.reversed().prefix(KeptCopies.mostKept)))
    }

    @Test("A name already taken gets the next number; copies kept in the same moment are ordered by it")
    func namesNeverCollide() throws {
        let folder = folder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let written = URL.temporaryDirectory.appending(path: "Dosar cu Șină 2026-11-18.dosar")
        var names: [URL] = []
        for _ in 0..<3 {
            let url = KeptCopies.name(for: written, in: folder)
            try Data("copie".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: noon("2026-11-18")], ofItemAtPath: url.path(percentEncoded: false))
            names.append(url)
        }
        #expect(names.map(\.lastPathComponent) == ["Dosar cu Șină 2026-11-18.dosar", "Dosar cu Șină 2026-11-18 2.dosar", "Dosar cu Șină 2026-11-18 3.dosar"])
        #expect(KeptCopies.all(in: folder) == names.reversed())
    }

    @Test func eachCopySaysWhyItWasKept() {
        for reason in KeptCopies.Reason.allCases {
            let copy = reason.folder.appending(path: "Dosar 2026-11-25.dosar")
            #expect(KeptCopies.reason(of: copy) == reason)
        }
        #expect(Set(KeptCopies.Reason.allCases.map(\.folder)).count == KeptCopies.Reason.allCases.count, "A folder each")
    }
}
