import Foundation
import SwiftData

/// Builds the search index from the database: assets with their field values,
/// obligations, history entries and their components, providers and their
/// trades, and documents with their extracted text.
///
/// What never reaches the index, whatever a record or its template says
/// (`SearchPrivacy`): text read off a document filed in a locked section or off
/// an identity document, sensitive and secret values, and any number shaped
/// like a CNP or sealed value, wherever it was typed or read.
///
/// It reads its own context and nothing else, so it runs off the main thread
/// (`SearchIndexer`). The index is kept per record: `documents(forRecord:templates:)`
/// gives one record's documents, `recordsShowing(_:)` the records to read again when
/// one changes.
public struct SearchIndexBuilder {
    public let context: ModelContext
    private let locale: Locale

    public init(context: ModelContext, locale: Locale = .dosarDefault) {
        self.context = context
        self.locale = locale
    }

    public func build() throws -> SearchIndex {
        SearchIndex(try buildByRecord().values.flatMap { $0 })
    }

    public func templates() throws -> [String: CategoryTemplate] {
        try TemplateStore.templatesByKey(in: context)
    }

    /// Every record's documents, redacted, keyed by the record they come from.
    public func buildByRecord() throws -> [PersistentIdentifier: [SearchDocument]] {
        let templates = try templates()
        var result: [PersistentIdentifier: [SearchDocument]] = [:]
        for asset in try context.fetch(FetchDescriptor<Asset>()) {
            result[asset.persistentModelID] = assetDocuments(asset, templates: templates)
        }
        for obligation in try context.fetch(FetchDescriptor<Obligation>()) {
            result[obligation.persistentModelID] = obligationDocuments(obligation, templates: templates)
        }
        for entry in try context.fetch(FetchDescriptor<HistoryEntry>()) {
            result[entry.persistentModelID] = historyDocuments(entry, templates: templates)
        }
        for provider in try context.fetch(FetchDescriptor<Provider>()) {
            result[provider.persistentModelID] = [Self.redacted(providerDocument(provider), keeping: .nothing)]
        }
        for attachment in try context.fetch(FetchDescriptor<Attachment>()) {
            result[attachment.persistentModelID] = attachmentDocuments(attachment, templates: templates)
        }
        return result
    }

    /// One record's documents, redacted: an asset with its components, or one
    /// deadline, history entry, firm or document. Empty when the record is gone or
    /// isn't something search shows.
    public func documents(forRecord id: PersistentIdentifier, templates: [String: CategoryTemplate]) throws -> [SearchDocument] {
        switch id.entityName {
        case Self.entity(Asset.self):
            return try fetch(Asset.self, id).map { assetDocuments($0, templates: templates) } ?? []
        case Self.entity(Obligation.self):
            return try fetch(Obligation.self, id).map { obligationDocuments($0, templates: templates) } ?? []
        case Self.entity(HistoryEntry.self):
            return try fetch(HistoryEntry.self, id).map { historyDocuments($0, templates: templates) } ?? []
        case Self.entity(Provider.self):
            return try fetch(Provider.self, id).map { [Self.redacted(providerDocument($0), keeping: .nothing)] } ?? []
        case Self.entity(Attachment.self):
            return try fetch(Attachment.self, id).map { attachmentDocuments($0, templates: templates) } ?? []
        default:
            return []
        }
    }

    /// The records whose documents show something of a changed record: itself, and
    /// those that print its name, take its lock or list it. `nil` when the change can
    /// reach any record (a category's name, fields or lock), so everything is read again.
    public func recordsShowing(_ id: PersistentIdentifier) throws -> Set<PersistentIdentifier>? {
        var result: Set<PersistentIdentifier> = []
        switch id.entityName {
        case Self.entity(CategoryTemplate.self):
            return nil
        case Self.entity(Asset.self):
            result.insert(id)
            guard let asset = try fetch(Asset.self, id) else { return result }
            let obligations = asset.obligations ?? []
            let history = asset.history ?? []
            let items = history.flatMap { $0.items ?? [] }
            result.formUnion(obligations.map(\.persistentModelID))
            result.formUnion(history.map(\.persistentModelID))
            result.formUnion((asset.providers ?? []).map(\.persistentModelID))
            var attachments = asset.attachments ?? []
            attachments += obligations.flatMap { $0.attachments ?? [] }
            attachments += history.flatMap { $0.attachments ?? [] }
            attachments += items.flatMap { $0.attachments ?? [] }
            attachments += (asset.measurements ?? []).flatMap { $0.attachments ?? [] }
            result.formUnion(attachments.map(\.persistentModelID))
        case Self.entity(Obligation.self):
            result.insert(id)
            result.formUnion((try fetch(Obligation.self, id)?.attachments ?? []).map(\.persistentModelID))
        case Self.entity(HistoryEntry.self):
            result.insert(id)
            guard let entry = try fetch(HistoryEntry.self, id) else { return result }
            if let asset = entry.asset { result.insert(asset.persistentModelID) }
            let attachments = (entry.attachments ?? []) + (entry.items ?? []).flatMap { $0.attachments ?? [] }
            result.formUnion(attachments.map(\.persistentModelID))
        case Self.entity(ServiceItem.self):
            guard let item = try fetch(ServiceItem.self, id) else { return result }
            result.formUnion((item.attachments ?? []).map(\.persistentModelID))
            if let entry = item.entry {
                result.insert(entry.persistentModelID)
                if let asset = entry.asset { result.insert(asset.persistentModelID) }
            }
        case Self.entity(Provider.self):
            result.insert(id)
            guard let provider = try fetch(Provider.self, id) else { return result }
            let entries = (provider.historyEntries ?? []) + (provider.suppliedItems ?? []).compactMap(\.entry)
            result.formUnion(entries.map(\.persistentModelID))
            result.formUnion(entries.compactMap { $0.asset?.persistentModelID })
        case Self.entity(MeasurementLog.self):
            result.formUnion((try fetch(MeasurementLog.self, id)?.attachments ?? []).map(\.persistentModelID))
        case Self.entity(Attachment.self):
            result.insert(id)
        default:
            break
        }
        return result
    }

    /// A model's entity name, as a `PersistentIdentifier` carries it.
    static func entity(_ type: any PersistentModel.Type) -> String {
        String(describing: type)
    }

    private func fetch<Model: PersistentModel>(_ type: Model.Type, _ id: PersistentIdentifier) throws -> Model? {
        var descriptor = FetchDescriptor<Model>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func assetDocuments(_ asset: Asset, templates: [String: CategoryTemplate]) -> [SearchDocument] {
        let template = templates[asset.templateKey]
        let kept = PaymentCardNumbers.KeptWhole(section: asset, template: template)
        return ([assetDocument(asset, template: template)] + componentDocuments(asset, template: template)).map { Self.redacted($0, keeping: kept) }
    }

    private func obligationDocuments(_ obligation: Obligation, templates: [String: CategoryTemplate]) -> [SearchDocument] {
        [Self.redacted(obligationDocument(obligation, templates: templates), keeping: Self.keptWhole(by: obligation.asset, templates))]
    }

    private func historyDocuments(_ entry: HistoryEntry, templates: [String: CategoryTemplate]) -> [SearchDocument] {
        [Self.redacted(historyDocument(entry, templates: templates), keeping: Self.keptWhole(by: entry.asset, templates))]
    }

    private func attachmentDocuments(_ attachment: Attachment, templates: [String: CategoryTemplate]) -> [SearchDocument] {
        [Self.redacted(attachmentDocument(attachment, templates: templates), keeping: Self.keptWhole(by: Self.section(of: attachment), templates))]
    }

    /// What a section keeps whole in its own words and its records' (a pet's microchip in its
    /// field), so the index holds it as the binder stores it (`PaymentCardNumbers.KeptWhole`).
    static func keptWhole(by section: Asset?, _ templates: [String: CategoryTemplate]) -> PaymentCardNumbers.KeptWhole {
        PaymentCardNumbers.KeptWhole(section: section, template: section.flatMap { templates[$0.templateKey] })
    }

    /// The document with every CNP-shaped number, card number and sealed value taken out of
    /// what can be matched; what its section keeps whole (`kept`) stays, as it is stored.
    static func redacted(_ document: SearchDocument, keeping kept: PaymentCardNumbers.KeptWhole) -> SearchDocument {
        var result = document
        result.fields = document.fields.map { SearchField(SearchPrivacy.redacting($0.text, keeping: kept), weight: $0.weight) }
        return result
    }

    // MARK: Documents

    private func id(_ kind: SearchResultKind, _ uuid: UUID) -> String { "\(kind.rawValue):\(uuid.uuidString)" }

    private func isSensitive(_ asset: Asset?, _ templates: [String: CategoryTemplate]) -> Bool {
        asset.flatMap { templates[$0.templateKey]?.isSensitive } ?? false
    }

    private func assetDocument(_ asset: Asset, template: CategoryTemplate?) -> SearchDocument {
        var fields = [SearchField(asset.name, weight: SearchField.Weight.title), SearchField(template?.name, weight: SearchField.Weight.label)]
        let definition = template?.definition
        for field in definition?.allFields ?? [] {
            // Sensitive values (document numbers, CNP, medical notes) and secrets (PIN codes) are never indexed.
            guard field.isIndexable, let value = asset.value(field.key) else { continue }
            let text = FieldFormatter.display(value, field: field, locale: locale)
            let weight: Int
            switch field.role {
            case .identifier?, .keyFact?, .documentNumber?: weight = SearchField.Weight.identifier
            case .subtitle?, .holder?, .issuer?, .retailer?: weight = SearchField.Weight.label
            default: weight = SearchField.Weight.value
            }
            fields.append(SearchField("\(field.label) \(text)", weight: weight))
            // Plates and IBANs are also searchable without separators ("b123abc").
            if field.type == .plate || field.type == .iban || field.type == .vin {
                fields.append(SearchField(value.textValue?.filter { $0.isLetter || $0.isNumber }, weight: weight))
            }
        }
        for fact in SecretFields.strippingFacts(asset.customFacts) where !fact.isSensitive {
            fields.append(SearchField("\(fact.label) \(fact.value)", weight: SearchField.Weight.value))
        }
        fields.append(SearchField(asset.notes, weight: SearchField.Weight.note))
        let subtitle = definition.flatMap { def in
            def.fields(withRole: .subtitle).compactMap { field in asset.value(field.key).map { FieldFormatter.display($0, field: field, locale: locale) } }.joined(separator: " ")
        }
        return SearchDocument(
            id: id(.asset, asset.id), kind: .asset, title: asset.name,
            subtitle: (subtitle?.isEmpty == false ? subtitle : template?.name),
            route: .asset(asset.id), fields: fields, date: asset.updatedAt, isSensitive: template?.isSensitive ?? false
        )
    }

    /// One result per component with history on an asset: "Plăcuțe frână față · VW Golf".
    private func componentDocuments(_ asset: Asset, template: CategoryTemplate?) -> [SearchDocument] {
        let items = HistoryItemSnapshot.items(of: asset)
        let catalog = template?.components ?? []
        return MaintenanceLog.trackedComponents(in: items).compactMap { key -> SearchDocument? in
            guard let last = MaintenanceLog.lastOccurrence(of: key, in: items) else { return nil }
            let component = catalog.first { $0.key == key }
            let name = component?.name ?? last.name
            let when = DosarFormat.day(last.date, locale: locale)
            return SearchDocument(
                id: "\(SearchResultKind.component.rawValue):\(asset.id.uuidString):\(key)", kind: .component, title: name,
                subtitle: "\(asset.name) · \(when)", route: .historyEntry(last.entryId),
                fields: [
                    SearchField(name, weight: SearchField.Weight.title),
                    SearchField(component.map { ([$0.group] + $0.synonyms).joined(separator: " ") }, weight: SearchField.Weight.label),
                    SearchField(asset.name, weight: SearchField.Weight.label),
                    SearchField(([last.partBrandOrCode, last.supplierName] + last.providerNames.map(Optional.some)).compactMap { $0 }.joined(separator: " "), weight: SearchField.Weight.value),
                ],
                date: last.date, isSensitive: template?.isSensitive ?? false
            )
        }
    }

    private func obligationDocument(_ obligation: Obligation, templates: [String: CategoryTemplate]) -> SearchDocument {
        let due = DosarFormat.day(obligation.dueDay, locale: locale)
        return SearchDocument(
            id: id(.obligation, obligation.id), kind: .obligation, title: obligation.title,
            subtitle: [obligation.asset?.name, due].compactMap { $0 }.joined(separator: " · "),
            route: .obligation(obligation.id),
            fields: [
                SearchField(obligation.title, weight: SearchField.Weight.title),
                SearchField(obligation.reference, weight: SearchField.Weight.identifier),
                SearchField(obligation.provider, weight: SearchField.Weight.label),
                SearchField(obligation.asset?.name, weight: SearchField.Weight.label),
                SearchField(obligation.notes, weight: SearchField.Weight.note),
            ],
            date: obligation.dueDay.noonDate(), isSensitive: isSensitive(obligation.asset, templates)
        )
    }

    private func historyDocument(_ entry: HistoryEntry, templates: [String: CategoryTemplate]) -> SearchDocument {
        let items = entry.items ?? []
        let when = DosarFormat.day(entry.occurredAt, locale: locale)
        return SearchDocument(
            id: id(.historyEntry, entry.id), kind: .historyEntry, title: entry.title,
            subtitle: [entry.asset?.name, when].compactMap { $0 }.joined(separator: " · "),
            route: .historyEntry(entry.id),
            fields: [
                SearchField(entry.title, weight: SearchField.Weight.title),
                SearchField(items.map(\.name).joined(separator: " "), weight: SearchField.Weight.label),
                SearchField(entry.providerNames.joined(separator: " "), weight: SearchField.Weight.label),
                SearchField(entry.asset?.name, weight: SearchField.Weight.label),
                SearchField(items.compactMap { [$0.partBrandOrCode, $0.supplier?.name].compactMap { $0 }.joined(separator: " ") }.joined(separator: " "), weight: SearchField.Weight.value),
                SearchField(entry.note, weight: SearchField.Weight.note),
                SearchField(entry.reference, weight: SearchField.Weight.value),
            ],
            date: entry.occurredAt, isSensitive: isSensitive(entry.asset, templates)
        )
    }

    private func providerDocument(_ provider: Provider) -> SearchDocument {
        let trades = provider.trades.map { ProviderTrade(rawValue: $0)?.title ?? $0 }
        return SearchDocument(
            id: id(.provider, provider.id), kind: .provider, title: provider.name,
            subtitle: trades.formatted(.list(type: .and).locale(locale)),
            route: .provider(provider.id),
            fields: [
                SearchField(provider.name, weight: SearchField.Weight.title),
                SearchField(trades.joined(separator: " "), weight: SearchField.Weight.label),
                SearchField(provider.phone, weight: SearchField.Weight.identifier),
                SearchField((provider.assets ?? []).map(\.name).joined(separator: " "), weight: SearchField.Weight.value),
                SearchField([provider.address, provider.notes].compactMap { $0 }.joined(separator: " "), weight: SearchField.Weight.note),
            ],
            date: provider.updatedAt
        )
    }

    /// The section a document is filed in: its own, or the one of the deadline,
    /// visit, part or reading it belongs to.
    static func section(of attachment: Attachment) -> Asset? {
        attachment.asset
            ?? attachment.obligation?.asset
            ?? attachment.historyEntry?.asset
            ?? attachment.serviceItem?.entry?.asset
            ?? attachment.measurement?.asset
    }

    private func attachmentDocument(_ attachment: Attachment, templates: [String: CategoryTemplate]) -> SearchDocument {
        let title = attachment.title ?? attachment.fileName
        let section = Self.section(of: attachment)
        let isLocked = isSensitive(section, templates)
        // Text read off an identity document, or off anything filed in a locked
        // section, holds personal numbers: never indexed, whatever its kind says.
        let readText = isLocked || attachment.kind == .identity ? nil : attachment.extractedText
        return SearchDocument(
            id: id(.document, attachment.id), kind: .document, title: title,
            subtitle: [section?.name, attachment.isArchived ? String(localized: "arhivat") : nil].compactMap { $0 }.joined(separator: " · "),
            route: .document(attachment.id),
            fields: [
                SearchField(title, weight: SearchField.Weight.title),
                SearchField(attachment.fileName, weight: SearchField.Weight.label),
                SearchField(section?.name, weight: SearchField.Weight.label),
                SearchField(readText, weight: SearchField.Weight.extracted),
            ],
            date: attachment.documentDay?.noonDate() ?? attachment.createdAt,
            isSensitive: isLocked
        )
    }
}
