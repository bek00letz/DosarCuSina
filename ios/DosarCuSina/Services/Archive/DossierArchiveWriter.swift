import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Writes the household to a `.dosar` file a piece at a time, away from the main thread.
///
/// Memory doesn't grow with the binder: the records are read once, and the sections'
/// photos and the documents' files are read in batches, each on a context of its own that
/// goes once its files are written, so at most a batch's worth (`batchBytes`, or one
/// document bigger than that) is held at once. With a password the archive is sealed
/// chunk by chunk on its way to the file (`ArchiveEncryption.EncryptingSink`).
///
/// Every file is checked against the limits the reader reads (`DosarZipEngine.Limits`)
/// before it is written, so a backup this writes is one this app can put back. When one
/// isn't, the half-written file is removed and the error says which part was too much
/// and what to do; no file is ever handed out that can't be restored.
struct DossierArchiveWriter: Sendable {
    let container: ModelContainer
    let calendar: Calendar
    let appVersion: String
    let exportedAt: Date
    var limits = DosarZipEngine.Limits.standard

    /// How much of the documents' contents one batch reads before its context goes.
    static let batchBytes = 64 << 20
    /// How many sections or documents one batch fetches at most.
    static let batchCount = 32

    /// Writes the archive to `url` (which must not exist yet), sealed with `password` when
    /// there is one. On any failure nothing is left at `url`.
    func write(to url: URL, password: String?) throws {
        let fileManager = FileManager.default
        let partial = url.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).partial")
        do {
            let file = try ArchiveFileSink(creating: partial)
            if let password {
                let sealed = try ArchiveEncryption.EncryptingSink(file, password: password)
                try write(into: sealed)
                try sealed.finish()
            } else {
                try write(into: file)
            }
            try file.close()
            if fileManager.fileExists(atPath: url.path(percentEncoded: false)) { try fileManager.removeItem(at: url) }
            try fileManager.moveItem(at: partial, to: url)
        } catch {
            try? fileManager.removeItem(at: partial)
            throw error
        }
    }

    /// The plain archive, file by file. The documents' files come first, then the data
    /// files, then the manifest with every file's checksum.
    func write(into sink: ArchiveByteSink) throws {
        let zip = DosarZipEngine.Writer(sink: sink, limits: limits)
        var checksums: [String: String] = [:]
        func add(_ path: String, _ data: Data) throws {
            try zip.add(path: path, data: data, modifiedDate: exportedAt)
            checksums[path] = Hashing.sha256(data)
        }
        let encoder = DossierV3.encoder()

        // The records, read once. None of them holds a picture or a file.
        let context = PersistenceController.context(in: container)
        let templates = try context.fetch(FetchDescriptor<CategoryTemplate>(sortBy: [SortDescriptor(\.homeOrder)]))
        let templateDTOs = templates.map(Self.template)
        let definitions = Dictionary(templates.map { ($0.key, $0.definition) }, uniquingKeysWith: { first, _ in first })
        let obligationDTOs = try context.fetch(FetchDescriptor<Obligation>(sortBy: [SortDescriptor(\.createdAt)])).map(obligation)
        let historyDTOs = try context.fetch(FetchDescriptor<HistoryEntry>(sortBy: [SortDescriptor(\.occurredAt)])).map(historyEntry)
        let serviceDTOs = try context.fetch(FetchDescriptor<ServiceItem>()).sorted { $0.name < $1.name }.map(Self.serviceItem)
        let providerDTOs = try context.fetch(FetchDescriptor<Provider>(sortBy: [SortDescriptor(\.createdAt)])).map(Self.provider)
        let measurementDTOs = try context.fetch(FetchDescriptor<MeasurementLog>(sortBy: [SortDescriptor(\.recordedAt)])).map(Self.measurement)
        var assetOrder = FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.createdAt)])
        assetOrder.propertiesToFetch = [\.id]
        let assetIDs = try context.fetch(assetOrder).map(\.id)
        var attachmentOrder = FetchDescriptor<Attachment>(sortBy: [SortDescriptor(\.createdAt)])
        attachmentOrder.propertiesToFetch = [\.id]
        let attachmentIDs = try context.fetch(attachmentOrder).map(\.id)

        // Sections, with their photos, in batches.
        var assetDTOs: [DossierV3.Asset] = []
        try inBatches(assetIDs, fetch: { context, ids in
            try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { ids.contains($0.id) }))
        }, id: \.id) { asset in
            var photoPath: String?
            var bytes = 0
            if let photo = asset.photoData {
                guard photo.count <= limits.maxEntryBytes else { throw ArchiveError.photoTooLarge(asset.name) }
                let path = "\(DossierV3.Path.photosPrefix)\(DossierV3.id(asset.id)).jpg"
                try add(path, photo)
                photoPath = path
                bytes = photo.count
            }
            assetDTOs.append(Self.asset(asset, photoPath: photoPath, definitions: definitions))
            return bytes
        }

        // Documents, with their files, pages and thumbnails, in batches.
        var attachmentDTOs: [DossierV3.Attachment] = []
        try inBatches(attachmentIDs, fetch: { context, ids in
            try context.fetch(FetchDescriptor<Attachment>(predicate: #Predicate { ids.contains($0.id) }))
        }, id: \.id) { attachment in
            let base = "\(DossierV3.Path.vaultPrefix)\(DossierV3.id(attachment.id))"
            var bytes = 0
            func keep(_ path: String, _ data: Data) throws {
                guard data.count <= limits.maxEntryBytes else {
                    throw ArchiveError.documentTooLarge(attachment.title ?? attachment.fileName)
                }
                try add(path, data)
                bytes += data.count
            }
            var path: String?
            if let data = attachment.fileData {
                let filePath = "\(base).\(Self.fileExtension(for: attachment))"
                try keep(filePath, data)
                path = filePath
            }
            var pagePaths: [String] = []
            for page in attachment.orderedPages {
                guard let data = page.imageData else { continue }
                let pagePath = "\(base)/page-\(pagePaths.count + 1).heic"
                try keep(pagePath, data)
                pagePaths.append(pagePath)
            }
            var thumbnailPath: String?
            if let data = attachment.thumbnailData {
                let thumbnail = "\(base)/thumbnail.heic"
                try keep(thumbnail, data)
                thumbnailPath = thumbnail
            }
            attachmentDTOs.append(self.attachment(attachment, path: path, pagePaths: pagePaths, thumbnailPath: thumbnailPath))
            return bytes
        }

        try add(DossierV3.Path.templates, try encoder.encode(templateDTOs))
        try add(DossierV3.Path.assets, try encoder.encode(assetDTOs))
        try add(DossierV3.Path.obligations, try encoder.encode(obligationDTOs))
        try add(DossierV3.Path.history, try encoder.encode(historyDTOs))
        try add(DossierV3.Path.serviceItems, try encoder.encode(serviceDTOs))
        try add(DossierV3.Path.providers, try encoder.encode(providerDTOs))
        try add(DossierV3.Path.measurements, try encoder.encode(measurementDTOs))
        try add(DossierV3.Path.attachments, try encoder.encode(attachmentDTOs))

        let manifest = DossierV3.Manifest(
            format: DossierV3.format,
            schemaVersion: DossierV3.schemaVersion,
            appVersion: appVersion,
            platform: "iOS",
            exportedAt: exportedAt,
            counts: .init(
                templates: templateDTOs.count, assets: assetDTOs.count, obligations: obligationDTOs.count,
                historyEntries: historyDTOs.count, serviceItems: serviceDTOs.count, providers: providerDTOs.count,
                measurements: measurementDTOs.count, attachments: attachmentDTOs.count
            ),
            checksums: checksums
        )
        try zip.add(path: DossierV3.Path.manifest, data: try encoder.encode(manifest), modifiedDate: exportedAt)
        try zip.finish()
    }

    /// Runs `body` on each record of `ids`, in that order, a batch at a time: each batch is
    /// fetched on a context of its own, and ends after `batchCount` records or once `body`
    /// says it read `batchBytes`, so what a batch read goes with its context.
    private func inBatches<Model: PersistentModel>(
        _ ids: [UUID],
        fetch: (ModelContext, [UUID]) throws -> [Model],
        id: KeyPath<Model, UUID>,
        _ body: (Model) throws -> Int
    ) throws {
        var seen: Set<UUID> = []
        let ids = ids.filter { seen.insert($0).inserted }
        var next = 0
        while next < ids.count {
            try autoreleasepool {
                let context = PersistenceController.context(in: container)
                let batch = Array(ids[next..<min(next + Self.batchCount, ids.count)])
                let found = Dictionary(try fetch(context, batch).map { ($0[keyPath: id], $0) }, uniquingKeysWith: { first, _ in first })
                var bytes = 0
                for uuid in batch {
                    next += 1
                    if let model = found[uuid] { bytes += try body(model) }
                    if bytes >= Self.batchBytes { break }
                }
            }
        }
    }

    // MARK: Records

    private static func template(_ template: CategoryTemplate) -> DossierV3.Template {
        DossierV3.Template(
            key: template.key, name: template.name, summary: template.summary, symbol: template.symbol,
            tint: template.tintRaw, heroStyle: template.heroStyleRaw, isBuiltIn: template.isBuiltIn,
            version: template.builtInVersion, homeOrder: template.homeOrder, isOnHome: template.isOnHome,
            isSensitive: template.isSensitive, sections: template.keptSections, blueprints: template.keptBlueprints,
            // As stored: a pocket from a newer build goes out as it came in.
            components: template.keptComponents, pockets: template.pocketsRaw,
            createdAt: template.createdAt, updatedAt: template.updatedAt, behavior: template.keptBehavior?.omitted { $0 == .standard }
        )
    }

    /// Secrets (PIN codes, secret rows, anything sealed) never leave the phone: an archive carries none.
    private static func asset(_ asset: Asset, photoPath: String?, definitions: [String: TemplateDefinition]) -> DossierV3.Asset {
        DossierV3.Asset(
            id: DossierV3.id(asset.id), templateKey: asset.templateKey, name: asset.name,
            parentId: DossierV3.id(asset.parent?.id), symbolOverride: asset.symbolOverride, tintOverride: asset.tintOverrideRaw, notes: asset.notes,
            values: SecretFields.stripping(asset.keptValues, definition: definitions[asset.templateKey] ?? BuiltInTemplates.definition(for: asset.templateKey)),
            customFacts: SecretFields.strippingFacts(asset.keptFacts).nilIfEmpty,
            photoPath: photoPath, isExample: asset.isExample,
            createdAt: asset.createdAt, updatedAt: asset.updatedAt
        )
    }

    private func obligation(_ obligation: Obligation) -> DossierV3.Obligation {
        DossierV3.Obligation(
            id: DossierV3.id(obligation.id), assetId: DossierV3.id(obligation.asset?.id), title: obligation.title,
            notes: obligation.notes, blueprintKey: obligation.blueprintKey, kind: obligation.kindRaw,
            dueDate: obligation.dueDay, dueMetric: obligation.dueMetric,
            reminders: obligation.keptReminders, reminderMinuteOfDay: obligation.reminderMinuteOfDay,
            recurrence: obligation.keptRecurrence, estimatedCost: obligation.estimatedCost, provider: obligation.provider,
            reference: obligation.reference, status: obligation.statusRaw, snoozedUntil: obligation.snoozeEnds(in: calendar),
            isExample: obligation.isExample, createdAt: obligation.createdAt, updatedAt: obligation.updatedAt,
            remindersCustomized: obligation.remindersCustomized ? true : nil
        )
    }

    private func historyEntry(_ entry: HistoryEntry) -> DossierV3.HistoryEntry {
        DossierV3.HistoryEntry(
            id: DossierV3.id(entry.id), assetId: DossierV3.id(entry.asset?.id), obligationId: DossierV3.id(entry.obligation?.id),
            kind: entry.kindRaw, title: entry.title, occurredAt: entry.occurredAt, metricReading: entry.metricReading,
            totalCost: entry.totalCost, note: entry.note, rating: entry.rating,
            cycleDueDate: entry.cycleDueDay,
            nextDueDate: entry.nextDueDay,
            previousStatus: entry.previousStatusRaw, previousDueMetric: entry.previousDueMetric,
            providerIds: entry.providerIds.map(DossierV3.id).sorted(), isExample: entry.isExample,
            reference: entry.reference, updatedAt: DossierV3.changeTime(entry.updatedAt)
        )
    }

    private static func serviceItem(_ item: ServiceItem) -> DossierV3.ServiceItem {
        DossierV3.ServiceItem(
            id: DossierV3.id(item.id), entryId: DossierV3.id(item.entry?.id), componentKey: item.componentKey,
            name: item.name, group: item.group, partBrandOrCode: item.partBrandOrCode, partSerialNumber: item.partSerialNumber,
            cost: item.costAmount.map { Money($0, currency: item.currency) },
            laborCost: item.laborCostAmount.map { Money($0, currency: item.currency) },
            partsCost: item.partsCostAmount.map { Money($0, currency: item.currency) },
            supplierId: DossierV3.id(item.supplier?.id), batchOrTicket: item.batchOrTicket, locationDetail: item.locationDetail,
            daysInService: item.daysInService, warrantyMonths: item.warrantyMonths, notes: item.notes, isExample: item.isExample,
            updatedAt: DossierV3.changeTime(item.updatedAt)
        )
    }

    private static func provider(_ provider: Provider) -> DossierV3.Provider {
        DossierV3.Provider(
            id: DossierV3.id(provider.id), name: provider.name, trades: provider.trades, phone: provider.phone,
            email: provider.email, address: provider.address, notes: provider.notes, manualRating: provider.manualRating,
            wouldCallAgain: provider.wouldCallAgain, assetIds: (provider.assets ?? []).map { DossierV3.id($0.id) }.sorted(),
            isExample: provider.isExample, createdAt: provider.createdAt, updatedAt: provider.updatedAt, taxID: provider.taxID
        )
    }

    private static func measurement(_ log: MeasurementLog) -> DossierV3.Measurement {
        DossierV3.Measurement(
            id: DossierV3.id(log.id), assetId: DossierV3.id(log.asset?.id), kind: log.kindRaw, name: log.name,
            value: log.value, secondaryValue: log.secondaryValue, unit: MeasurementUnit.storedKey(for: log.unit), recordedAt: log.recordedAt,
            unitPrice: log.unitPrice, isSelfRead: log.isSelfRead, referenceMin: log.referenceMin,
            referenceMax: log.referenceMax, source: log.source, notes: log.notes, isExample: log.isExample,
            updatedAt: DossierV3.changeTime(log.updatedAt), startsCounter: log.startsCounter ? true : nil
        )
    }

    private func attachment(_ attachment: Attachment, path: String?, pagePaths: [String], thumbnailPath: String?) -> DossierV3.Attachment {
        DossierV3.Attachment(
            id: DossierV3.id(attachment.id), title: attachment.title, fileName: attachment.fileName, kind: attachment.kindRaw,
            contentType: attachment.contentType, byteCount: attachment.byteCount, sha256: attachment.sha256,
            path: path, pagePaths: pagePaths, thumbnailPath: thumbnailPath, extractedText: attachment.extractedText,
            documentDate: attachment.documentDay, isArchived: attachment.isArchived,
            supersededById: DossierV3.id(attachment.supersededBy?.id), createdAt: attachment.createdAt,
            isExample: attachment.isExample, assetId: DossierV3.id(attachment.asset?.id),
            obligationId: DossierV3.id(attachment.obligation?.id), historyEntryId: DossierV3.id(attachment.historyEntry?.id),
            serviceItemId: DossierV3.id(attachment.serviceItem?.id), measurementId: DossierV3.id(attachment.measurement?.id),
            providerId: DossierV3.id(attachment.provider?.id), validUntil: attachment.validUntil,
            framing: attachment.keptFraming?.omitted(when: \.isPlain),
            updatedAt: DossierV3.changeTime(attachment.updatedAt)
        )
    }

    static func fileExtension(for attachment: Attachment) -> String {
        let fromName = (attachment.fileName as NSString).pathExtension.lowercased()
        if !fromName.isEmpty, fromName.allSatisfy({ $0.isLetter || $0.isNumber }) { return fromName }
        return UTType(attachment.contentType)?.preferredFilenameExtension ?? "bin"
    }
}

private extension KeptList {
    /// Nothing at all: no row this build reads, and none it can't.
    var nilIfEmpty: Self? { isEmpty && isFullyRead ? nil : self }
}
