import Foundation
import SwiftData

extension DosarSchemaV11 {
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
        /// JSON `[CustomFact]`: free label and value rows under Date importante.
        public var customFactsData: Data?
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

        /// The asset this one belongs under: a tenancy under its property, a product
        /// under a home, a document under its holder.
        public var parent: Asset?

        /// Assets filed under this one. Deleting this asset only unlinks them; the
        /// screen asks first (see `AssetActions.delete(_:children:)`).
        @Relationship(deleteRule: .nullify, inverse: \Asset.parent)
        public var children: [Asset]? = []

        public init(id: UUID = UUID(), name: String, templateKey: String, values: FieldValues = FieldValues(), notes: String? = nil, isExample: Bool = false) {
            self.id = id
            self.name = name
            self.templateKey = templateKey
            self.valuesData = StoredJSON.encode(values)
            self.notes = notes
            self.isExample = isExample
        }

        /// The values this build reads. Writing them keeps what a newer build wrote inside them
        /// that this one doesn't read (`KeptObject`).
        public var values: FieldValues {
            get { KeptObject<FieldValues>.value(in: valuesData) ?? FieldValues() }
            set { keptValues = keptValues.replacingValue(newValue) }
        }

        /// The values as stored, with what this build doesn't read: what a backup carries.
        public var keptValues: KeptObject<FieldValues> {
            get { KeptObject.stored(in: valuesData, fallback: FieldValues()) ?? KeptObject(FieldValues()) }
            set { valuesData = KeptObject.data(newValue) }
        }

        public func value(_ key: String) -> FieldValue? {
            values[key]
        }

        /// The rows this build can read. Writing them keeps any a newer build wrote that this one
        /// can't, and inside the ones it reads what it doesn't read there (`KeptList`).
        public var customFacts: [CustomFact] {
            get { KeptList.items(in: customFactsData) }
            set { keptFacts = keptFacts.replacingItems(newValue) }
        }

        /// The rows as stored, with any this build can't read: what a backup carries.
        public var keptFacts: KeptList<CustomFact> {
            get { KeptList.stored(in: customFactsData) }
            set { customFactsData = newValue.isEmpty && newValue.isFullyRead ? nil : StoredJSON.encode(newValue) }
        }

        public var tintOverride: TemplateTint? {
            get { tintOverrideRaw.flatMap(TemplateTint.init(rawValue:)) }
            set { tintOverrideRaw = newValue?.rawValue }
        }

        public var activeObligations: [Obligation] {
            (obligations ?? []).filter { $0.status == .active }.sorted { $0.dueDay < $1.dueDay }
        }

        public var nextObligation: Obligation? {
            activeObligations.first
        }

        /// How many assets are filed under this one, for the delete question.
        public var childCount: Int { children?.count ?? 0 }

        /// History newest first.
        public var timeline: [HistoryEntry] {
            (history ?? []).sorted { $0.occurredAt > $1.occurredAt }
        }
    }
}
