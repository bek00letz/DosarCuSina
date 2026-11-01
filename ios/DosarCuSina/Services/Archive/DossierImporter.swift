import Foundation
import SwiftData

/// Writes a decoded package into a context. The caller saves (once) or rolls back.
@MainActor
struct DossierImporter {
    let context: ModelContext
    let package: DossierV3.Package
    let mode: ArchiveImportMode
    let calendar: Calendar

    private func uuid(_ raw: String?) -> UUID? { raw.flatMap(UUID.init(uuidString:)) }

    func run() throws -> ArchiveImportResult {
        var result = ArchiveImportResult()
        if mode == .replace { try deleteEverything() }

        try importTemplates(&result)
        let assets = try importAssets(&result)
        let providers = try importProviders(&result, assets: assets)
        let obligations = try importObligations(&result, assets: assets)
        let entries = try importHistory(&result, assets: assets, obligations: obligations, providers: providers)
        let serviceItems = try importServiceItems(&result, entries: entries, providers: providers)
        let measurements = try importMeasurements(&result, assets: assets)
        try importAttachments(&result, assets: assets, obligations: obligations, entries: entries, serviceItems: serviceItems, measurements: measurements)
        return result
    }

    // MARK: Replace

    private func deleteEverything() throws {
        for item in try context.fetch(FetchDescriptor<Attachment>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<MeasurementLog>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<ServiceItem>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<HistoryEntry>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Provider>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Obligation>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Asset>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<CategoryTemplate>()) { context.delete(item) }
    }

    private func existing<T: PersistentModel>(_ type: T.Type, id: KeyPath<T, UUID>) throws -> [UUID: T] {
        guard mode == .merge else { return [:] }
        var map: [UUID: T] = [:]
        for item in try context.fetch(FetchDescriptor<T>()) where map[item[keyPath: id]] == nil {
            map[item[keyPath: id]] = item
        }
        return map
    }

    // MARK: Templates

    private func importTemplates(_ result: inout ArchiveImportResult) throws {
        var byKey: [String: CategoryTemplate] = [:]
        if mode == .merge {
            for template in try context.fetch(FetchDescriptor<CategoryTemplate>()) where byKey[template.key] == nil {
                byKey[template.key] = template
            }
        }
        for dto in package.templates {
            let catalog = BuiltInTemplates.definition(for: dto.key)
            let isBuiltIn = dto.isBuiltIn && catalog != nil
            var definition = TemplateDefinition(
                key: dto.key, name: dto.name, summary: dto.summary, symbol: dto.symbol,
                tint: TemplateTint(rawValue: dto.tint) ?? .gray, heroStyle: HeroStyle(rawValue: dto.heroStyle) ?? .standard,
                isOnHomeByDefault: dto.isOnHome, isSensitiveByDefault: dto.isSensitive,
                sections: dto.sections, blueprints: dto.blueprints, components: dto.components ?? [], version: dto.version
            )
            // A built-in from an older app version takes this app's definition.
            if isBuiltIn, let catalog, catalog.version >= dto.version {
                definition.name = catalog.name
                definition.summary = catalog.summary
                definition.symbol = catalog.symbol
                definition.tint = catalog.tint
                definition.heroStyle = catalog.heroStyle
                definition.sections = catalog.sections
                definition.blueprints = catalog.blueprints
                definition.components = catalog.components
                definition.version = catalog.version
            }
            if let template = byKey[dto.key] {
                guard dto.updatedAt > template.updatedAt else { result.skipped += 1; continue }
                if template.isCustom || isBuiltIn { template.apply(definition) }
                template.homeOrder = dto.homeOrder
                template.isOnHome = dto.isOnHome
                template.isSensitive = dto.isSensitive
                template.updatedAt = dto.updatedAt
                result.updated += 1
            } else {
                let template = CategoryTemplate(definition: definition, isBuiltIn: isBuiltIn, homeOrder: dto.homeOrder)
                template.isOnHome = dto.isOnHome
                template.isSensitive = dto.isSensitive
                template.createdAt = dto.createdAt
                template.updatedAt = dto.updatedAt
                context.insert(template)
                byKey[dto.key] = template
                result.inserted += 1
            }
        }
        // Built-ins the archive didn't mention.
        var order = (byKey.values.map(\.homeOrder).max() ?? -1) + 1
        for definition in BuiltInTemplates.all where byKey[definition.key] == nil {
            context.insert(CategoryTemplate(definition: definition, isBuiltIn: true, homeOrder: order))
            order += 1
        }
    }

    // MARK: Records

    private func importAssets(_ result: inout ArchiveImportResult) throws -> [UUID: Asset] {
        var map = try existing(Asset.self, id: \.id)
        for dto in package.assets {
            guard let id = uuid(dto.id) else { throw ArchiveError.brokenReference(DossierV3.Path.assets) }
            let asset: Asset
            if let current = map[id] {
                guard dto.updatedAt > current.updatedAt else { result.skipped += 1; continue }
                asset = current
                result.updated += 1
            } else {
                asset = Asset(id: id, name: dto.name, templateKey: dto.templateKey)
                context.insert(asset)
                map[id] = asset
                result.inserted += 1
            }
            asset.name = dto.name
            asset.templateKey = dto.templateKey
            asset.symbolOverride = dto.symbolOverride
            asset.tintOverrideRaw = dto.tintOverride
            asset.notes = dto.notes
            asset.valuesData = StoredJSON.encode(dto.values)
            asset.photoData = dto.photoPath.flatMap { package.files[$0] }
            asset.isExample = dto.isExample
            asset.createdAt = dto.createdAt
            asset.updatedAt = dto.updatedAt
        }
        return map
    }

    private func importObligations(_ result: inout ArchiveImportResult, assets: [UUID: Asset]) throws -> [UUID: Obligation] {
        var map = try existing(Obligation.self, id: \.id)
        for dto in package.obligations {
            guard let id = uuid(dto.id) else { throw ArchiveError.brokenReference(DossierV3.Path.obligations) }
            let obligation: Obligation
            if let current = map[id] {
                guard dto.updatedAt > current.updatedAt else { result.skipped += 1; continue }
                obligation = current
                result.updated += 1
            } else {
                obligation = Obligation(id: id, title: dto.title, kind: .routine, dueDay: dto.dueDate, calendar: calendar)
                context.insert(obligation)
                map[id] = obligation
                result.inserted += 1
            }
            obligation.title = dto.title
            obligation.notes = dto.notes
            obligation.blueprintKey = dto.blueprintKey
            obligation.kindRaw = ObligationKind(rawValue: dto.kind)?.rawValue ?? ObligationKind.routine.rawValue
            obligation.setDueDay(dto.dueDate, calendar: calendar)
            obligation.dueMetric = dto.dueMetric
            obligation.reminders = dto.reminders
            obligation.reminderMinuteOfDay = dto.reminderMinuteOfDay
            obligation.recurrence = dto.recurrence
            obligation.estimatedCost = dto.estimatedCost
            obligation.provider = dto.provider
            obligation.reference = dto.reference
            obligation.statusRaw = ObligationStatus(rawValue: dto.status)?.rawValue ?? ObligationStatus.active.rawValue
            obligation.snoozedUntil = dto.snoozedUntil
            obligation.isExample = dto.isExample
            obligation.createdAt = dto.createdAt
            obligation.updatedAt = dto.updatedAt
            obligation.asset = uuid(dto.assetId).flatMap { assets[$0] }
        }
        return map
    }

    private func importProviders(_ result: inout ArchiveImportResult, assets: [UUID: Asset]) throws -> [UUID: Provider] {
        var map = try existing(Provider.self, id: \.id)
        for dto in package.providers {
            guard let id = uuid(dto.id) else { throw ArchiveError.brokenReference(DossierV3.Path.providers) }
            let provider: Provider
            if let current = map[id] {
                guard dto.updatedAt > current.updatedAt else { result.skipped += 1; continue }
                provider = current
                result.updated += 1
            } else {
                provider = Provider(id: id, name: dto.name)
                context.insert(provider)
                map[id] = provider
                result.inserted += 1
            }
            provider.name = dto.name
            provider.trades = dto.trades
            provider.phone = dto.phone
            provider.email = dto.email
            provider.address = dto.address
            provider.notes = dto.notes
            provider.manualRating = dto.manualRating
            provider.wouldCallAgain = dto.wouldCallAgain
            provider.isExample = dto.isExample
            provider.createdAt = dto.createdAt
            provider.updatedAt = dto.updatedAt
            provider.assets = dto.assetIds.compactMap { uuid($0).flatMap { assets[$0] } }
        }
        return map
    }

    private func importHistory(
        _ result: inout ArchiveImportResult,
        assets: [UUID: Asset],
        obligations: [UUID: Obligation],
        providers: [UUID: Provider]
    ) throws -> [UUID: HistoryEntry] {
        var map = try existing(HistoryEntry.self, id: \.id)
        for dto in package.historyEntries {
            guard let id = uuid(dto.id) else { throw ArchiveError.brokenReference(DossierV3.Path.history) }
            guard map[id] == nil else { result.skipped += 1; continue }
            let entry = HistoryEntry(id: id, kind: HistoryKind(rawValue: dto.kind) ?? .note, title: dto.title, occurredAt: dto.occurredAt)
            entry.metricReading = dto.metricReading
            entry.totalCost = dto.totalCost
            entry.note = dto.note
            entry.rating = dto.rating
            entry.cycleDueDate = dto.cycleDueDate?.noonDate(in: calendar)
            entry.nextDueDate = dto.nextDueDate?.noonDate(in: calendar)
            entry.previousStatusRaw = dto.previousStatus
            entry.previousDueMetric = dto.previousDueMetric
            entry.isExample = dto.isExample
            context.insert(entry)
            entry.asset = uuid(dto.assetId).flatMap { assets[$0] }
            entry.obligation = uuid(dto.obligationId).flatMap { obligations[$0] }
            entry.providers = dto.providerIds.compactMap { uuid($0).flatMap { providers[$0] } }
            map[id] = entry
            result.inserted += 1
        }
        return map
    }

    private func importServiceItems(_ result: inout ArchiveImportResult, entries: [UUID: HistoryEntry], providers: [UUID: Provider]) throws -> [UUID: ServiceItem] {
        var map = try existing(ServiceItem.self, id: \.id)
        for dto in package.serviceItems {
            guard let id = uuid(dto.id) else { throw ArchiveError.brokenReference(DossierV3.Path.serviceItems) }
            guard map[id] == nil else { result.skipped += 1; continue }
            let item = ServiceItem(id: id, name: dto.name, componentKey: dto.componentKey)
            item.group = dto.group
            item.partBrandOrCode = dto.partBrandOrCode
            item.partSerialNumber = dto.partSerialNumber
            item.currency = (dto.cost ?? dto.laborCost ?? dto.partsCost)?.currency ?? Money.defaultCurrency
            item.costAmount = dto.cost?.amount
            item.laborCostAmount = dto.laborCost?.amount
            item.partsCostAmount = dto.partsCost?.amount
            item.batchOrTicket = dto.batchOrTicket
            item.locationDetail = dto.locationDetail
            item.daysInService = dto.daysInService
            item.warrantyMonths = dto.warrantyMonths
            item.notes = dto.notes
            item.isExample = dto.isExample
            context.insert(item)
            item.entry = uuid(dto.entryId).flatMap { entries[$0] }
            item.supplier = uuid(dto.supplierId).flatMap { providers[$0] }
            map[id] = item
            result.inserted += 1
        }
        return map
    }

    private func importMeasurements(_ result: inout ArchiveImportResult, assets: [UUID: Asset]) throws -> [UUID: MeasurementLog] {
        var map = try existing(MeasurementLog.self, id: \.id)
        for dto in package.measurements {
            guard let id = uuid(dto.id) else { throw ArchiveError.brokenReference(DossierV3.Path.measurements) }
            guard map[id] == nil else { result.skipped += 1; continue }
            let log = MeasurementLog(id: id, kind: MeasurementKind(rawValue: dto.kind) ?? .custom, name: dto.name, value: dto.value, unit: dto.unit, recordedAt: dto.recordedAt)
            log.secondaryValue = dto.secondaryValue
            log.unitPriceAmount = dto.unitPrice?.amount
            log.unitPriceCurrency = dto.unitPrice?.currency
            log.isSelfRead = dto.isSelfRead
            log.referenceMin = dto.referenceMin
            log.referenceMax = dto.referenceMax
            log.source = dto.source
            log.notes = dto.notes
            log.isExample = dto.isExample
            context.insert(log)
            log.asset = uuid(dto.assetId).flatMap { assets[$0] }
            map[id] = log
            result.inserted += 1
        }
        return map
    }

    private func importAttachments(
        _ result: inout ArchiveImportResult,
        assets: [UUID: Asset],
        obligations: [UUID: Obligation],
        entries: [UUID: HistoryEntry],
        serviceItems: [UUID: ServiceItem],
        measurements: [UUID: MeasurementLog]
    ) throws {
        let current = try existing(Attachment.self, id: \.id)
        for dto in package.attachments {
            guard let id = uuid(dto.id) else { throw ArchiveError.brokenReference(DossierV3.Path.attachments) }
            guard current[id] == nil else { result.skipped += 1; continue }
            guard let data = package.files[dto.path] else { throw ArchiveError.missingFile(dto.path) }
            let attachment = Attachment(id: id, fileName: dto.fileName, contentType: dto.contentType, data: data)
            attachment.extractedText = dto.extractedText
            attachment.createdAt = dto.createdAt
            attachment.isExample = dto.isExample
            context.insert(attachment)
            attachment.asset = uuid(dto.assetId).flatMap { assets[$0] }
            attachment.obligation = uuid(dto.obligationId).flatMap { obligations[$0] }
            attachment.historyEntry = uuid(dto.historyEntryId).flatMap { entries[$0] }
            attachment.serviceItem = uuid(dto.serviceItemId).flatMap { serviceItems[$0] }
            attachment.measurement = uuid(dto.measurementId).flatMap { measurements[$0] }
            result.inserted += 1
        }
    }
}
