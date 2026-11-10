import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// What the phone keeps only for itself (its secret rows and sealed values) stays through
/// "Înlocuiește tot" and "Adaugă" as it is stored here: a secret row this build can't read, and a
/// key a newer build wrote inside one it reads, included. None of it is ever exported. Every value
/// is a placeholder.
@MainActor
@Suite("A restore keeps the phone's own secrets, read or not")
struct LocalSecretsKeptTests {
    /// The person's rows as a newer build may have stored them: a secret row this build reads
    /// with a key it doesn't know, a secret row it can't read at all, and an ordinary row.
    private func storeNewerRows(on asset: Asset, sealer: SecretSealer) throws -> (readable: UUID, unreadable: UUID) {
        let readable = UUID()
        let unreadable = UUID()
        let rows: [[String: Any]] = [
            ["id": readable.uuidString.lowercased(), "label": "Parolă Wi-Fi", "value": try sealer.seal("0000"),
             "isSensitive": true, "isSecret": true, "hint": "din versiunea nouă"],
            ["id": unreadable.uuidString.lowercased(), "label": 7, "value": try sealer.seal("0000"),
             "isSecret": true, "kind": "cod-nou"],
            ["id": UUID().uuidString.lowercased(), "label": "Număr contract apă", "value": "123"],
        ]
        asset.customFactsData = try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
        try UnitOfWork.save(asset.modelContext!)
        return (readable, unreadable)
    }

    private func storedRows(_ asset: Asset) throws -> [[String: Any]] {
        let data = try #require(asset.customFactsData)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    @Test(arguments: [ArchiveImportMode.replace, .merge])
    func secretRowsStayAsStoredHere(mode: ArchiveImportMode) throws {
        let household = try BackupHousehold()
        let ids = try storeNewerRows(on: household.person, sealer: household.sealer)
        #expect(household.person.keptFacts.unreadable.count == 1, "One row this build can't read")

        let data = try household.service.exportData(exportedAt: noon("2026-11-02"))
        let package = try DossierArchiveReader.read(data)
        let person = try #require(package.assets.first { $0.id == DossierV3.id(household.person.id) })
        #expect(person.customFacts?.items.map(\.label) == ["Număr contract apă"], "No secret row leaves, read or not")
        #expect(person.customFacts?.isFullyRead == true)

        try household.service.importArchive(data, mode: mode)
        let restored = try household.asset(household.person.id)
        let rows = try storedRows(restored)
        let byID = Dictionary(uniqueKeysWithValues: rows.compactMap { row in (row["id"] as? String).map { ($0, row) } })
        let readable = try #require(byID[ids.readable.uuidString.lowercased()])
        #expect(readable["hint"] as? String == "din versiunea nouă", "A key a newer build wrote inside a secret row stays")
        let sealed = try #require(readable["value"] as? String)
        #expect(try household.sealer.open(sealed) == "0000")
        let unreadable = try #require(byID[ids.unreadable.uuidString.lowercased()], "A secret row this build can't read stays")
        #expect(unreadable["kind"] as? String == "cod-nou")
        #expect(rows.count == 3)
        #expect(restored.customFacts.map(\.label).sorted() == ["Număr contract apă", "Parolă Wi-Fi"])
    }

    @Test func aRowFromTheArchiveWithTheSameIDGivesWay() throws {
        let sealer = SecretSealer.ephemeral()
        let id = UUID()
        let local = KeptList([CustomFact(id: id, label: "Cod alarmă", value: try sealer.seal("0000"), isSecret: true)])
        let incoming = KeptList([CustomFact(id: id, label: "Cod alarmă", value: "vechi"), CustomFact(label: "Interfon", value: "12")])
        let kept = SecretFields.keepingLocalSecretFacts(incoming, from: local)
        #expect(kept.items.map(\.label) == ["Interfon", "Cod alarmă"])
        #expect(kept.items.last?.isSecret == true)
    }

    @Test func aSealedValueThisBuildCantReadStays() throws {
        let sealer = SecretSealer.ephemeral()
        let stored = try JSONSerialization.data(withJSONObject: [
            "document.pinNou": ["type": "sigiliu-nou", "value": try sealer.seal("0000")],
            "document.series": ["type": "text", "value": "XX"],
        ], options: [.sortedKeys])
        let existing = try JSONDecoder().decode(FieldValues.self, from: stored)
        let kept = SecretFields.sealedValues(in: existing)
        #expect(kept != FieldValues(), "The unreadable sealed value is kept")
        let restored = SecretFields.keepingLocalSecrets(FieldValues(), from: existing, definition: nil)
        let json = try #require(String(data: try JSONEncoder().encode(restored), encoding: .utf8))
        #expect(json.contains("sigiliu-nou"))
        #expect(!json.contains("XX"), "Only what is sealed comes from the phone")
    }
}
