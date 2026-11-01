import Foundation
import SwiftData

extension DosarSchemaV2 {
    /// Something the household looks after: a car, a home, a pet, a passport.
    /// Its details live in `values`, described by the template named in `templateKey`.
    @Model
    public final class Asset {
        public var id: UUID = UUID()
        public var name: String = ""
        /// `CategoryTemplate.key`. A key with no installed template renders as a standard asset.
        public var templateKey: String = ""
        public var symbolOverride: String?
        public var tintOverrideRaw: String?
        public var notes: String?
        @Attribute(.externalStorage) public var photoData: Data?
        /// JSON `FieldValues`.
        public var valuesData: Data?
        /// Created by "Explore with examples"; removed together with one tap.
        public var isExample: Bool = false
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \Obligation.asset)
        public var obligations: [Obligation]? = []

        @Relationship(deleteRule: .cascade, inverse: \Attachment.asset)
        public var attachments: [Attachment]? = []

        /// Everything that happened to it: visits, repairs, purchases, completed obligations.
        @Relationship(deleteRule: .cascade, inverse: \HistoryEntry.asset)
        public var history: [HistoryEntry]? = []

        @Relationship(deleteRule: .cascade, inverse: \MeasurementLog.asset)
        public var measurements: [MeasurementLog]? = []

        /// People and businesses who look after it (the mechanic, the vet).
        public var providers: [Provider]? = []

        public init(id: UUID = UUID(), name: String, templateKey: String, values: FieldValues = FieldValues(), notes: String? = nil, isExample: Bool = false) {
            self.id = id
            self.name = name
            self.templateKey = templateKey
            self.valuesData = StoredJSON.encode(values)
            self.notes = notes
            self.isExample = isExample
        }

        public var values: FieldValues {
            get { StoredJSON.decode(FieldValues.self, from: valuesData) ?? FieldValues() }
            set { valuesData = StoredJSON.encode(newValue); updatedAt = Date() }
        }

        public func value(_ key: String) -> FieldValue? {
            values[key]
        }

        public var tintOverride: TemplateTint? {
            get { tintOverrideRaw.flatMap(TemplateTint.init(rawValue:)) }
            set { tintOverrideRaw = newValue?.rawValue }
        }

        public var activeObligations: [Obligation] {
            (obligations ?? []).filter { $0.status == .active }.sorted { $0.dueDate < $1.dueDate }
        }

        public var nextObligation: Obligation? {
            activeObligations.first
        }

        /// History newest first.
        public var timeline: [HistoryEntry] {
            (history ?? []).sorted { $0.occurredAt > $1.occurredAt }
        }
    }
}
