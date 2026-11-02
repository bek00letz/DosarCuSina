import Foundation

/// Something another app sent with the share sheet, waiting in the App Group
/// until the person reviews it in Adaugă › De verificat.
///
/// On disk: `<App Group>/Inbox/<uuid>/manifest.json` plus the files, all with
/// complete file protection. The share extension writes it; the app reads it
/// and removes the folder once the item is filed or dismissed.
public struct InboxItem: Codable, Hashable, Sendable, Identifiable {
    public enum Payload: String, Codable, Sendable {
        /// One or more photos, read together as the pages of one document.
        case images
        /// One PDF.
        case pdf
        /// Text copied from a message or an email.
        case text
    }

    public var id: UUID
    public var receivedAt: Date
    public var payload: Payload
    /// File names inside the item's folder, in page order.
    public var files: [String]
    /// The name the file had in the app it came from, for the list row.
    public var originalName: String?
    /// The sample invoice from the share practice, not a real document.
    public var isPractice: Bool

    public init(id: UUID = UUID(), receivedAt: Date, payload: Payload, files: [String], originalName: String?, isPractice: Bool) {
        self.id = id
        self.receivedAt = receivedAt
        self.payload = payload
        self.files = files
        self.originalName = originalName
        self.isPractice = isPractice
    }
}

/// The folder in the App Group where shared items wait. A plain value over a
/// directory, so tests run it against a temporary folder.
public struct ShareInbox: Sendable {
    public static let folderName = "Inbox"
    static let manifestName = "manifest.json"
    static let stagingPrefix = ".staging-"

    /// File name of the sample invoice used in the share practice. An item
    /// arriving with this name is marked as practice.
    public static let practiceFileName = "Factura exemplu - Dosar cu Sina.pdf"

    /// Whether a sender's file name is the practice invoice. Apps pass the name
    /// with or without its extension.
    public static func isPracticeName(_ name: String?) -> Bool {
        guard let name else { return false }
        let base = (practiceFileName as NSString).deletingPathExtension
        return name == practiceFileName || name == base
    }

    /// Most files accepted from one share, so a huge selection can't fill the phone.
    public static let maxFiles = 20

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The inbox in the App Group, or nil when the container isn't available.
    public static func shared() -> ShareInbox? {
        AppGroup.containerURL.map { ShareInbox(directory: $0.appending(path: folderName, directoryHint: .isDirectory)) }
    }

    // MARK: Planning

    /// What one shared attachment is.
    public enum IncomingKind: Sendable, Hashable {
        case pdf, image, text
    }

    /// One inbox item to make from a share: its payload and which attachments go in it.
    public struct PlannedItem: Sendable, Hashable {
        public var payload: InboxItem.Payload
        public var indices: [Int]
    }

    /// How a share becomes inbox items: every PDF on its own; photos together, as
    /// the pages of one document; text together. At most `maxFiles` attachments.
    public static func plan(_ kinds: [IncomingKind]) -> [PlannedItem] {
        var items: [PlannedItem] = []
        var imageSlot: Int?
        var textSlot: Int?
        for (index, kind) in kinds.enumerated().prefix(maxFiles) {
            switch kind {
            case .pdf:
                items.append(PlannedItem(payload: .pdf, indices: [index]))
            case .image:
                if let slot = imageSlot { items[slot].indices.append(index) } else {
                    imageSlot = items.count
                    items.append(PlannedItem(payload: .images, indices: [index]))
                }
            case .text:
                if let slot = textSlot { items[slot].indices.append(index) } else {
                    textSlot = items.count
                    items.append(PlannedItem(payload: .text, indices: [index]))
                }
            }
        }
        return items
    }

    // MARK: Writing (share extension)

    public enum InboxError: Error, Equatable {
        case nothingToSave
    }

    /// A private folder to copy incoming files into before they are committed.
    /// Half-copied items are never visible to the app.
    public func makeStagingFolder() throws -> URL {
        let folder = directory.appending(path: Self.stagingPrefix + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: Self.protection)
        return folder
    }

    /// Copies a file into a staging folder under a safe name. Returns the name used.
    @discardableResult
    public func stage(copyOf source: URL, into staging: URL, index: Int) throws -> String {
        let name = Self.safeName(index: index, extension: source.pathExtension)
        let target = staging.appending(path: name)
        try FileManager.default.copyItem(at: source, to: target)
        Self.protect(target)
        return name
    }

    /// Writes bytes into a staging folder. Returns the name used.
    @discardableResult
    public func stage(data: Data, fileExtension: String, into staging: URL, index: Int) throws -> String {
        let name = Self.safeName(index: index, extension: fileExtension)
        try data.write(to: staging.appending(path: name), options: [.atomic, .completeFileProtection])
        return name
    }

    /// Makes a staged folder visible as an inbox item, in one rename.
    @discardableResult
    public func commit(staging: URL, payload: InboxItem.Payload, files: [String], originalName: String?, receivedAt: Date = Date()) throws -> InboxItem {
        guard !files.isEmpty else {
            try? FileManager.default.removeItem(at: staging)
            throw InboxError.nothingToSave
        }
        let item = InboxItem(
            receivedAt: receivedAt,
            payload: payload,
            files: files,
            originalName: originalName,
            isPractice: Self.isPracticeName(originalName)
        )
        let manifest = try Self.encoder.encode(item)
        try manifest.write(to: staging.appending(path: Self.manifestName), options: [.atomic, .completeFileProtection])
        let final = folder(for: item.id)
        try FileManager.default.moveItem(at: staging, to: final)
        Self.protect(final)
        return item
    }

    /// Removes a staging folder that was never committed.
    public func discard(staging: URL) {
        try? FileManager.default.removeItem(at: staging)
    }

    // MARK: Reading (app)

    /// Every committed item, newest first. Unreadable folders are skipped.
    public func items() -> [InboxItem] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path())) ?? []
        return names
            .filter { !$0.hasPrefix(".") }
            .compactMap { name -> InboxItem? in
                let manifest = directory.appending(path: name).appending(path: Self.manifestName)
                guard let data = try? Data(contentsOf: manifest) else { return nil }
                return try? Self.decoder.decode(InboxItem.self, from: data)
            }
            .sorted { $0.receivedAt > $1.receivedAt }
    }

    /// The item's files in page order.
    public func fileURLs(of item: InboxItem) -> [URL] {
        item.files.map { folder(for: item.id).appending(path: $0) }
    }

    /// Removes an item once it was filed or dismissed. Removing a missing item is fine.
    public func remove(_ id: UUID) throws {
        let target = folder(for: id)
        guard FileManager.default.fileExists(atPath: target.path()) else { return }
        try FileManager.default.removeItem(at: target)
    }

    /// Removes staging folders a crashed extension left behind (older than an hour).
    public func removeAbandonedStaging(now: Date = Date()) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path())) ?? []
        for name in names where name.hasPrefix(Self.stagingPrefix) {
            let url = directory.appending(path: name)
            let created = (try? FileManager.default.attributesOfItem(atPath: url.path())[.creationDate]) as? Date
            if let created, now.timeIntervalSince(created) > 3600 {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: Private

    func folder(for id: UUID) -> URL {
        directory.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory)
    }

    /// Names are ours, never the sender's, so nothing odd ends up in a path.
    static func safeName(index: Int, extension ext: String) -> String {
        let cleaned = ext.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(5)
        return "file-\(index + 1)" + (cleaned.isEmpty ? "" : ".\(cleaned)")
    }

    static var protection: [FileAttributeKey: Any] {
        #if os(iOS)
        return [.protectionKey: FileProtectionType.complete]
        #else
        return [:]
        #endif
    }

    static func protect(_ url: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path())
        #endif
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
