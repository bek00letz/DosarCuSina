import Foundation
import SwiftData

/// How much space documents take, so the app can explain it and offer to shrink old scans.
public struct StorageReport: Sendable, Hashable {
    public struct Totals: Sendable, Hashable {
        public var documents: Int = 0
        public var bytes: Int = 0
    }

    public let total: Totals
    /// By the asset a document is filed under; `nil` collects documents not filed under an asset.
    public let byAsset: [UUID?: Totals]
    public let byKind: [DocumentKind: Totals]
    public let archived: Totals
    /// Documents whose pages are old and large enough to be worth shrinking.
    public let compactionCandidates: [UUID]
}

/// When and how far to shrink old scans. Original files (PDFs) are never touched.
public struct CompactionPolicy: Sendable, Hashable {
    public var olderThanDays: Int
    public var maxLongEdge: Int
    public var quality: Double
    /// Pages smaller than this are left alone; shrinking them saves too little.
    public var minimumPageBytes: Int

    public init(olderThanDays: Int = 365, maxLongEdge: Int = 1800, quality: Double = 0.55, minimumPageBytes: Int = 350_000) {
        self.olderThanDays = olderThanDays
        self.maxLongEdge = maxLongEdge
        self.quality = quality
        self.minimumPageBytes = minimumPageBytes
    }
}

/// The storage report and the compaction policy, over the one document record: `Attachment`.
@MainActor
public struct DocumentStorage {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func report(policy: CompactionPolicy = CompactionPolicy(), now: Date = Date()) throws -> StorageReport {
        var total = StorageReport.Totals()
        var archived = StorageReport.Totals()
        var byAsset: [UUID?: StorageReport.Totals] = [:]
        var byKind: [DocumentKind: StorageReport.Totals] = [:]
        var candidates: [UUID] = []
        for attachment in try context.fetch(FetchDescriptor<Attachment>()) {
            let bytes = attachment.byteCount + (attachment.thumbnailData?.count ?? 0)
            total.documents += 1
            total.bytes += bytes
            byAsset[attachment.asset?.id, default: .init()].documents += 1
            byAsset[attachment.asset?.id, default: .init()].bytes += bytes
            byKind[attachment.kind, default: .init()].documents += 1
            byKind[attachment.kind, default: .init()].bytes += bytes
            if attachment.isArchived {
                archived.documents += 1
                archived.bytes += bytes
            }
            if isCandidate(attachment, policy: policy, now: now) { candidates.append(attachment.id) }
        }
        return StorageReport(total: total, byAsset: byAsset, byKind: byKind, archived: archived, compactionCandidates: candidates)
    }

    /// Re-encodes old, large page images at a smaller size in one save. Returns the bytes saved.
    @discardableResult
    public func compact(policy: CompactionPolicy = CompactionPolicy(), now: Date = Date()) throws -> Int {
        var saved = 0
        for attachment in try context.fetch(FetchDescriptor<Attachment>()) where isCandidate(attachment, policy: policy, now: now) {
            for page in attachment.orderedPages {
                guard let data = page.imageData, data.count >= policy.minimumPageBytes,
                      let image = ImageEncoding.decode(data),
                      let encoded = try? ImageEncoding.encode(image, maxLongEdge: policy.maxLongEdge, quality: policy.quality),
                      encoded.data.count < data.count else { continue }
                saved += data.count - encoded.data.count
                page.imageData = encoded.data
            }
            attachment.byteCount = (attachment.fileData?.count ?? 0) + attachment.orderedPages.reduce(0) { $0 + ($1.imageData?.count ?? 0) }
            attachment.compactedAt = now
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return saved
    }

    private func isCandidate(_ attachment: Attachment, policy: CompactionPolicy, now: Date) -> Bool {
        guard attachment.compactedAt == nil else { return false }
        guard now.timeIntervalSince(attachment.createdAt) / 86_400 >= Double(policy.olderThanDays) else { return false }
        return attachment.orderedPages.contains { ($0.imageData?.count ?? 0) >= policy.minimumPageBytes }
    }
}

/// Full file protection for document bytes. SwiftData keeps large values (pages,
/// originals, thumbnails) as files beside the store; they get `.complete`
/// protection, so they can't be read while the device is locked. The store file
/// itself keeps the default class so reminders and widgets keep working.
public enum DocumentFileProtection {
    /// The folder where SwiftData keeps external storage for `storeURL`.
    public static func externalDataFolder(for storeURL: URL) -> URL {
        let name = storeURL.deletingPathExtension().lastPathComponent
        return storeURL.deletingLastPathComponent().appending(path: ".\(name)_SUPPORT/_EXTERNAL_DATA", directoryHint: .isDirectory)
    }

    /// Applies `.complete` protection to the folder (new files inherit it) and to
    /// every file already in it. Returns how many items were changed.
    @discardableResult
    public static func apply(toStoreAt storeURL: URL) -> Int {
        #if os(iOS)
        let folder = externalDataFolder(for: storeURL)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: folder.path()) else { return 0 }
        var changed = 0
        let items = [folder] + ((try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
        for item in items {
            let current = (try? fileManager.attributesOfItem(atPath: item.path())[.protectionKey]) as? FileProtectionType
            guard current != .complete else { continue }
            if (try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: item.path())) != nil {
                changed += 1
            }
        }
        return changed
        #else
        return 0
        #endif
    }
}
