import Foundation
import SwiftData
import CryptoKit
import UniformTypeIdentifiers

public enum ArchiveError: LocalizedError, Equatable {
    case notADossier
    case unsupportedVersion(Int)
    case missingFile(String)
    case checksumMismatch(String)
    case unlistedFile(String)
    case unreadableFile(String)
    case brokenReference(String)

    public var errorDescription: String? {
        switch self {
        case .notADossier:
            return String(localized: "Fișierul nu e o arhivă Dosar cu Șină.")
        case .unsupportedVersion:
            return String(localized: "Arhiva a fost făcută de o versiune mai nouă a aplicației. Actualizează aplicația și încearcă din nou.")
        case .missingFile(let path):
            return String(localized: "Arhiva e incompletă: lipsește \(path).")
        case .checksumMismatch(let path), .unreadableFile(let path):
            return String(localized: "Fișierul \(path) din arhivă e deteriorat.")
        case .unlistedFile(let path):
            return String(localized: "Arhiva conține un fișier neașteptat: \(path).")
        case .brokenReference(let path):
            return String(localized: "Datele din \(path) nu se potrivesc între ele.")
        }
    }
}

public enum ArchiveImportMode: String, Sendable {
    /// Keeps what is here; for records in both, the more recently edited one wins.
    case merge
    /// Replaces everything here with the archive.
    case replace
}

public struct ArchiveSummary: Hashable, Sendable {
    public var schemaVersion: Int
    public var platform: String
    public var exportedAt: Date
    public var counts: DossierV3.Manifest.Counts
}

public struct ArchiveImportResult: Hashable, Sendable {
    public var inserted = 0
    public var updated = 0
    public var skipped = 0
}

// MARK: - Reading

/// Unpacks, checks and decodes an archive. Pure and thread-safe; nothing touches the database.
public enum DossierArchiveReader {
    public static func read(_ data: Data, limits: DosarZipEngine.Limits = .standard) throws -> DossierV3.Package {
        let entries = try DosarZipEngine.unpackArchive(data, limits: limits)
        var files: [String: Data] = [:]
        for entry in entries { files[entry.path] = entry.data }

        guard let manifestData = files[DossierV3.Path.manifest] else { throw ArchiveError.notADossier }
        struct VersionProbe: Decodable { let schemaVersion: Int; let format: String? }
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: manifestData) else { throw ArchiveError.notADossier }
        if let format = probe.format, format != DossierV3.format { throw ArchiveError.notADossier }

        switch probe.schemaVersion {
        case 2:
            return try DossierV2Converter.package(from: files)
        case 3:
            break
        default:
            throw ArchiveError.unsupportedVersion(probe.schemaVersion)
        }

        let decoder = DossierV3.decoder()
        guard let manifest = try? decoder.decode(DossierV3.Manifest.self, from: manifestData) else {
            throw ArchiveError.unreadableFile(DossierV3.Path.manifest)
        }
        try verify(files: files, checksums: manifest.checksums)

        func decode<T: Decodable>(_ type: [T].Type, _ path: String) throws -> [T] {
            guard let data = files[path] else { return [] }
            do { return try decoder.decode(type, from: data) } catch { throw ArchiveError.unreadableFile(path) }
        }
        let package = DossierV3.Package(
            manifest: manifest,
            templates: try decode([DossierV3.Template].self, DossierV3.Path.templates),
            assets: try decode([DossierV3.Asset].self, DossierV3.Path.assets),
            obligations: try decode([DossierV3.Obligation].self, DossierV3.Path.obligations),
            historyEntries: try decode([DossierV3.HistoryEntry].self, DossierV3.Path.history),
            serviceItems: try decode([DossierV3.ServiceItem].self, DossierV3.Path.serviceItems),
            providers: try decode([DossierV3.Provider].self, DossierV3.Path.providers),
            measurements: try decode([DossierV3.Measurement].self, DossierV3.Path.measurements),
            attachments: try decode([DossierV3.Attachment].self, DossierV3.Path.attachments),
            files: files.filter { $0.key.hasPrefix(DossierV3.Path.vaultPrefix) }
        )
        try validateReferences(package)
        return package
    }

    /// Every listed file must exist and match its SHA-256; every other file must be listed.
    static func verify(files: [String: Data], checksums: [String: String]) throws {
        for (path, expected) in checksums {
            guard let data = files[path] else { throw ArchiveError.missingFile(path) }
            guard sha256(data) == expected.lowercased() else { throw ArchiveError.checksumMismatch(path) }
        }
        for path in files.keys where path != DossierV3.Path.manifest && checksums[path] == nil {
            throw ArchiveError.unlistedFile(path)
        }
    }

    static func validateReferences(_ package: DossierV3.Package) throws {
        for attachment in package.attachments {
            for path in attachment.allPaths where package.files[path] == nil {
                throw ArchiveError.missingFile(path)
            }
        }
        for asset in package.assets {
            if let photo = asset.photoPath, package.files[photo] == nil { throw ArchiveError.missingFile(photo) }
        }
    }

    public static func sha256(_ data: Data) -> String {
        Hashing.sha256(data)
    }
}

// MARK: - Service

/// Exports the household to a `.dosar` archive and imports one back. Import
/// builds everything in a separate context and saves once, so a failure part
/// way through leaves the existing data exactly as it was.
@MainActor
public struct DossierArchiveService {
    public let container: ModelContainer
    private let calendar: Calendar

    public init(container: ModelContainer, calendar: Calendar = .current) {
        self.container = container
        self.calendar = calendar
    }

    // MARK: Export

    public func exportData(appVersion: String = Bundle.main.shortVersion, exportedAt: Date = Date()) throws -> Data {
        let context = ModelContext(container)
        let templates = try context.fetch(FetchDescriptor<CategoryTemplate>(sortBy: [SortDescriptor(\.homeOrder)]))
        let assets = try context.fetch(FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.createdAt)]))
        let obligations = try context.fetch(FetchDescriptor<Obligation>(sortBy: [SortDescriptor(\.createdAt)]))
        let entries = try context.fetch(FetchDescriptor<HistoryEntry>(sortBy: [SortDescriptor(\.occurredAt)]))
        let serviceItems = try context.fetch(FetchDescriptor<ServiceItem>()).sorted { $0.name < $1.name }
        let providers = try context.fetch(FetchDescriptor<Provider>(sortBy: [SortDescriptor(\.createdAt)]))
        let measurements = try context.fetch(FetchDescriptor<MeasurementLog>(sortBy: [SortDescriptor(\.recordedAt)]))
        let attachments = try context.fetch(FetchDescriptor<Attachment>(sortBy: [SortDescriptor(\.createdAt)]))

        var files: [String: Data] = [:]
        let encoder = DossierV3.encoder()

        let templateDTOs = templates.map { template in
            DossierV3.Template(
                key: template.key, name: template.name, summary: template.summary, symbol: template.symbol,
                tint: template.tintRaw, heroStyle: template.heroStyleRaw, isBuiltIn: template.isBuiltIn,
                version: template.builtInVersion, homeOrder: template.homeOrder, isOnHome: template.isOnHome,
                isSensitive: template.isSensitive, sections: template.sections, blueprints: template.blueprints,
                components: template.components, pockets: template.pockets.map(\.rawValue),
                createdAt: template.createdAt, updatedAt: template.updatedAt
            )
        }
        // Secret fields (PIN codes) never leave the phone: an archive carries none.
        let definitions = Dictionary(templates.map { ($0.key, $0.definition) }, uniquingKeysWith: { first, _ in first })
        let assetDTOs = assets.map { asset -> DossierV3.Asset in
            var photoPath: String?
            if let photo = asset.photoData {
                let path = "\(DossierV3.Path.photosPrefix)\(DossierV3.id(asset.id)).jpg"
                files[path] = photo
                photoPath = path
            }
            return DossierV3.Asset(
                id: DossierV3.id(asset.id), templateKey: asset.templateKey, name: asset.name,
                parentId: DossierV3.id(asset.parent?.id), symbolOverride: asset.symbolOverride, tintOverride: asset.tintOverrideRaw, notes: asset.notes,
                values: SecretFields.stripping(asset.values, definition: definitions[asset.templateKey] ?? BuiltInTemplates.definition(for: asset.templateKey)),
                customFacts: asset.customFacts.isEmpty ? nil : asset.customFacts,
                photoPath: photoPath, isExample: asset.isExample,
                createdAt: asset.createdAt, updatedAt: asset.updatedAt
            )
        }
        let obligationDTOs = obligations.map { obligation in
            DossierV3.Obligation(
                id: DossierV3.id(obligation.id), assetId: DossierV3.id(obligation.asset?.id), title: obligation.title,
                notes: obligation.notes, blueprintKey: obligation.blueprintKey, kind: obligation.kindRaw,
                dueDate: obligation.dueDay(in: calendar), dueMetric: obligation.dueMetric,
                reminders: obligation.reminders, reminderMinuteOfDay: obligation.reminderMinuteOfDay,
                recurrence: obligation.recurrence, estimatedCost: obligation.estimatedCost, provider: obligation.provider,
                reference: obligation.reference, status: obligation.statusRaw, snoozedUntil: obligation.snoozedUntil,
                isExample: obligation.isExample, createdAt: obligation.createdAt, updatedAt: obligation.updatedAt
            )
        }
        let historyDTOs = entries.map { entry in
            DossierV3.HistoryEntry(
                id: DossierV3.id(entry.id), assetId: DossierV3.id(entry.asset?.id), obligationId: DossierV3.id(entry.obligation?.id),
                kind: entry.kindRaw, title: entry.title, occurredAt: entry.occurredAt, metricReading: entry.metricReading,
                totalCost: entry.totalCost, note: entry.note, rating: entry.rating,
                cycleDueDate: entry.cycleDueDate.map { CalendarDay($0, calendar: calendar) },
                nextDueDate: entry.nextDueDate.map { CalendarDay($0, calendar: calendar) },
                previousStatus: entry.previousStatusRaw, previousDueMetric: entry.previousDueMetric,
                providerIds: entry.providerIds.map(DossierV3.id).sorted(), isExample: entry.isExample
            )
        }
        let serviceDTOs = serviceItems.map { item in
            DossierV3.ServiceItem(
                id: DossierV3.id(item.id), entryId: DossierV3.id(item.entry?.id), componentKey: item.componentKey,
                name: item.name, group: item.group, partBrandOrCode: item.partBrandOrCode, partSerialNumber: item.partSerialNumber,
                cost: item.costAmount.map { Money($0, currency: item.currency) },
                laborCost: item.laborCostAmount.map { Money($0, currency: item.currency) },
                partsCost: item.partsCostAmount.map { Money($0, currency: item.currency) },
                supplierId: DossierV3.id(item.supplier?.id), batchOrTicket: item.batchOrTicket, locationDetail: item.locationDetail,
                daysInService: item.daysInService, warrantyMonths: item.warrantyMonths, notes: item.notes, isExample: item.isExample
            )
        }
        let providerDTOs = providers.map { provider in
            DossierV3.Provider(
                id: DossierV3.id(provider.id), name: provider.name, trades: provider.trades, phone: provider.phone,
                email: provider.email, address: provider.address, notes: provider.notes, manualRating: provider.manualRating,
                wouldCallAgain: provider.wouldCallAgain, assetIds: (provider.assets ?? []).map { DossierV3.id($0.id) }.sorted(),
                isExample: provider.isExample, createdAt: provider.createdAt, updatedAt: provider.updatedAt
            )
        }
        let measurementDTOs = measurements.map { log in
            DossierV3.Measurement(
                id: DossierV3.id(log.id), assetId: DossierV3.id(log.asset?.id), kind: log.kindRaw, name: log.name,
                value: log.value, secondaryValue: log.secondaryValue, unit: log.unit, recordedAt: log.recordedAt,
                unitPrice: log.unitPrice, isSelfRead: log.isSelfRead, referenceMin: log.referenceMin,
                referenceMax: log.referenceMax, source: log.source, notes: log.notes, isExample: log.isExample
            )
        }
        let attachmentDTOs = attachments.map { attachment -> DossierV3.Attachment in
            let base = "\(DossierV3.Path.vaultPrefix)\(DossierV3.id(attachment.id))"
            var path: String?
            if let data = attachment.fileData {
                path = "\(base).\(Self.fileExtension(for: attachment))"
                files[path!] = data
            }
            var pagePaths: [String] = []
            for page in attachment.orderedPages {
                guard let data = page.imageData else { continue }
                let pagePath = "\(base)/page-\(pagePaths.count + 1).heic"
                files[pagePath] = data
                pagePaths.append(pagePath)
            }
            var thumbnailPath: String?
            if let data = attachment.thumbnailData {
                thumbnailPath = "\(base)/thumbnail.heic"
                files[thumbnailPath!] = data
            }
            return DossierV3.Attachment(
                id: DossierV3.id(attachment.id), title: attachment.title, fileName: attachment.fileName, kind: attachment.kindRaw,
                contentType: attachment.contentType, byteCount: attachment.byteCount, sha256: attachment.sha256,
                path: path, pagePaths: pagePaths, thumbnailPath: thumbnailPath, extractedText: attachment.extractedText,
                documentDate: attachment.documentDate.map { CalendarDay($0, calendar: calendar) }, isArchived: attachment.isArchived,
                supersededById: DossierV3.id(attachment.supersededBy?.id), createdAt: attachment.createdAt,
                isExample: attachment.isExample, assetId: DossierV3.id(attachment.asset?.id),
                obligationId: DossierV3.id(attachment.obligation?.id), historyEntryId: DossierV3.id(attachment.historyEntry?.id),
                serviceItemId: DossierV3.id(attachment.serviceItem?.id), measurementId: DossierV3.id(attachment.measurement?.id),
                providerId: DossierV3.id(attachment.provider?.id)
            )
        }

        files[DossierV3.Path.templates] = try encoder.encode(templateDTOs)
        files[DossierV3.Path.assets] = try encoder.encode(assetDTOs)
        files[DossierV3.Path.obligations] = try encoder.encode(obligationDTOs)
        files[DossierV3.Path.history] = try encoder.encode(historyDTOs)
        files[DossierV3.Path.serviceItems] = try encoder.encode(serviceDTOs)
        files[DossierV3.Path.providers] = try encoder.encode(providerDTOs)
        files[DossierV3.Path.measurements] = try encoder.encode(measurementDTOs)
        files[DossierV3.Path.attachments] = try encoder.encode(attachmentDTOs)

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
            checksums: files.mapValues(DossierArchiveReader.sha256)
        )
        var zipEntries = [DosarZipEngine.Entry(path: DossierV3.Path.manifest, data: try encoder.encode(manifest), modifiedDate: exportedAt)]
        for path in files.keys.sorted() {
            if let data = files[path] { zipEntries.append(DosarZipEngine.Entry(path: path, data: data, modifiedDate: exportedAt)) }
        }
        return try DosarZipEngine.createArchive(entries: zipEntries)
    }

    /// Writes an archive to a temporary file ready to share, protected while the device is locked.
    public func export(to directory: URL = .temporaryDirectory, exportedAt: Date = Date()) throws -> URL {
        let data = try exportData(exportedAt: exportedAt)
        let day = CalendarDay(exportedAt, calendar: calendar).isoString
        let url = directory.appending(path: "Dosar cu Șină \(day).dosar")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    // MARK: Inspect and import

    public func inspect(_ data: Data) throws -> ArchiveSummary {
        let package = try DossierArchiveReader.read(data)
        return ArchiveSummary(
            schemaVersion: package.manifest.schemaVersion,
            platform: package.manifest.platform,
            exportedAt: package.manifest.exportedAt,
            counts: package.manifest.counts
        )
    }

    @discardableResult
    public func importArchive(_ data: Data, mode: ArchiveImportMode) throws -> ArchiveImportResult {
        let package = try DossierArchiveReader.read(data)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let result = try DossierImporter(context: context, package: package, mode: mode, calendar: calendar).run()
            try context.save()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }

    static func fileExtension(for attachment: Attachment) -> String {
        let fromName = (attachment.fileName as NSString).pathExtension.lowercased()
        if !fromName.isEmpty, fromName.allSatisfy({ $0.isLetter || $0.isNumber }) { return fromName }
        return UTType(attachment.contentType)?.preferredFilenameExtension ?? "bin"
    }
}

extension Bundle {
    public var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
