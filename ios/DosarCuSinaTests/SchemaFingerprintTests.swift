import CoreData
import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A frozen schema version must keep exactly the shape its stores have on people's
/// phones, or a migration can't recognise them. These pin each frozen version.
@MainActor
struct SchemaFingerprintTests {
    /// Each entity's version hash, as Core Data computes it, base64.
    static func fingerprint(_ models: [any PersistentModel.Type]) -> [String: String] {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: models) else { return [:] }
        return model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }
    }

    @Test func theFrozenVersionTwoMatchesTheShippedOne() {
        let shipped = Self.fingerprint(DosarSchemaV2.models)
        let frozen = Self.fingerprint(DosarSchemaV2Snapshot.models)
        #expect(!shipped.isEmpty)
        #expect(frozen == shipped)
        let listed = shipped.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        Issue.record("V2 fingerprint: \(listed)")
    }
}
