import Foundation
import SwiftData

/// Builds the search index from the database: assets with their field values,
/// obligations, history entries and their components, providers and their
/// trades, and documents with their extracted text.
@MainActor
public struct SearchIndexBuilder {
    public let context: ModelContext
    private let locale: Locale

    public init(context: ModelContext, locale: Locale = .dosarDefault) {
        self.context = context
        self.locale = locale
    }

    public func build() throws -> SearchIndex {
        let templates = try TemplateStore(context: context).templatesByKey()
        var documents: [SearchDocument] = []
        let assets = try context.fetch(FetchDescriptor<Asset>())
        for asset in assets {
            let template = templates[asset.templateKey]
            documents.append(assetDocument(asset, template: template))
            documents.append(contentsOf: componentDocuments(asset, template: template))
        }
        for obligation in try context.fetch(FetchDescriptor<Obligation>()) {
            documents.append(obligationDocument(obligation, templates: templates))
        }
        for entry in try context.fetch(FetchDescriptor<HistoryEntry>()) {
            documents.append(historyDocument(entry, templates: templates))
        }
        for provider in try context.fetch(FetchDescriptor<Provider>()) {
            documents.append(providerDocument(provider))
        }
        for attachment in try context.fetch(FetchDescriptor<Attachment>()) {
            documents.append(attachmentDocument(attachment, templates: templates))
        }
        return SearchIndex(documents)
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
            // Sensitive values (document numbers, CNP, medical notes) are never indexed.
            guard !field.isSensitive, let value = asset.value(field.key) else { continue }
            let text = FieldFormatter.display(value, as: field.type, unit: field.unit, locale: locale)
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
        fields.append(SearchField(asset.notes, weight: SearchField.Weight.note))
        let subtitle = definition.flatMap { def in
            def.fields(withRole: .subtitle).compactMap { asset.value($0.key).map { FieldFormatter.display($0, as: .text, locale: locale) } }.joined(separator: " ")
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
            let when = last.date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
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
        let due = obligation.dueDay().startDate().formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
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
            date: obligation.dueDate, isSensitive: isSensitive(obligation.asset, templates)
        )
    }

    private func historyDocument(_ entry: HistoryEntry, templates: [String: CategoryTemplate]) -> SearchDocument {
        let items = entry.items ?? []
        let when = entry.occurredAt.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
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

    private func attachmentDocument(_ attachment: Attachment, templates: [String: CategoryTemplate]) -> SearchDocument {
        let title = attachment.title ?? attachment.fileName
        return SearchDocument(
            id: id(.document, attachment.id), kind: .document, title: title,
            subtitle: [attachment.asset?.name, attachment.isArchived ? String(localized: "arhivat") : nil].compactMap { $0 }.joined(separator: " · "),
            route: .document(attachment.id),
            fields: [
                SearchField(title, weight: SearchField.Weight.title),
                SearchField(attachment.fileName, weight: SearchField.Weight.label),
                SearchField(attachment.asset?.name, weight: SearchField.Weight.label),
                SearchField(attachment.extractedText, weight: SearchField.Weight.extracted),
            ],
            date: attachment.documentDate ?? attachment.createdAt,
            isSensitive: isSensitive(attachment.asset, templates)
        )
    }
}
