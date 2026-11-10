import CryptoKit
import Foundation
import UniformTypeIdentifiers

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

    /// The manifest's format. Items written before it had a version read as 1.
    /// The app reads every version up to `currentVersion`; a newer one is set aside
    /// as unreadable rather than guessed at.
    public static let currentVersion = 2

    public var version: Int
    public var id: UUID
    public var receivedAt: Date
    public var payload: Payload
    /// File names inside the item's folder, in page order.
    public var files: [String]
    /// The name the file had in the app it came from, for the list row, with any card number
    /// in it masked (`PaymentCardNumbers.redact`) as it is written, and again when an item an
    /// earlier version wrote is read: the App Group never keeps one, even until the item is filed.
    public private(set) var originalName: String?
    /// The sample invoice from the share practice, not a real document. Set when
    /// the item arrives, from the file's fingerprint (`expectPractice`), never its name.
    public var isPractice: Bool

    public init(version: Int = InboxItem.currentVersion, id: UUID = UUID(), receivedAt: Date, payload: Payload, files: [String], originalName: String?, isPractice: Bool) {
        self.version = version
        self.id = id
        self.receivedAt = receivedAt
        self.payload = payload
        self.files = files
        self.originalName = originalName.map { PaymentCardNumbers.redact($0) }
        self.isPractice = isPractice
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, receivedAt, payload, files, originalName, isPractice
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        id = try container.decode(UUID.self, forKey: .id)
        receivedAt = try container.decode(Date.self, forKey: .receivedAt)
        payload = try container.decode(Payload.self, forKey: .payload)
        files = try container.decode([String].self, forKey: .files)
        originalName = try container.decodeIfPresent(String.self, forKey: .originalName).map { PaymentCardNumbers.redact($0) }
        isPractice = try container.decodeIfPresent(Bool.self, forKey: .isPractice) ?? false
    }
}

/// What the app learned about a waiting item by reading its first page on the phone,
/// so the list can tell items apart: what it is, how many pages, a small picture.
///
/// Kept beside the manifest (`preview.json`, and `thumbnail.jpg` when there is a
/// picture), written by the app only, never by the extension. It is a cache: one
/// that is missing, damaged or from a newer version is made again, never set aside.
public struct InboxPreview: Codable, Hashable, Sendable {
    /// The preview's own format, separate from the manifest's.
    public static let currentVersion = 1

    public var version: Int
    /// What the reading found (`CaptureDocumentKind`'s raw value). Nil when the page
    /// couldn't be read, or reads as nothing the binder knows.
    public var kind: String?
    /// What it is, in a few words ("Factură ENGIE Romania S.A.", "Carte de identitate"),
    /// already without anything that may not be shown (`SearchPrivacy.outsideText`).
    public var title: String?
    /// The category it would be filed in, so an item of a locked one names nothing.
    public var categoryKey: String?
    /// Pages in the document: a PDF's own, or the photos shared together.
    public var pageCount: Int
    /// A first-page picture was kept beside it.
    public var hasThumbnail: Bool

    public init(version: Int = InboxPreview.currentVersion, kind: String?, title: String?, categoryKey: String?, pageCount: Int, hasThumbnail: Bool = false) {
        self.version = version
        self.kind = kind
        self.title = title
        self.categoryKey = categoryKey
        self.pageCount = pageCount
        self.hasThumbnail = hasThumbnail
    }
}

/// Something in the inbox the app couldn't open: a damaged manifest, a missing
/// file, or a format from a newer version. It is moved aside, never retried
/// forever, and shown calmly so the person can send it again or remove it.
public struct UnreadableInboxItem: Hashable, Sendable, Identifiable {
    /// The folder's name in the aside folder.
    public var id: String
    /// When it was set aside.
    public var setAsideAt: Date

    public init(id: String, setAsideAt: Date) {
        self.id = id
        self.setAsideAt = setAsideAt
    }
}

/// The folder in the App Group where shared items wait. A plain value over a
/// directory, so tests run it against a temporary folder.
public struct ShareInbox: Sendable {
    public static let folderName = "Inbox"
    static let manifestName = "manifest.json"
    static let stagingPrefix = ".staging-"
    /// Where items the app couldn't open are moved, inside the inbox.
    static let asideFolderName = ".unreadable"
    /// The fingerprint of the practice invoice the app is waiting for.
    static let practiceMarkerName = ".practice.json"
    /// How long the app waits for the practice invoice to come back.
    static let practiceWindow: TimeInterval = 3600

    /// The name the practice invoice is sent under, so it reads well in the share sheet.
    public static let practiceFileName = "Factura exemplu - Dosar cu Sina.pdf"

    /// Whether a sender's file name is the practice invoice's. No longer what marks
    /// the practice (its fingerprint does, `expectPractice`); kept as the way back
    /// until the fingerprint has been seen working on a phone.
    public static func isPracticeName(_ name: String?) -> Bool {
        guard let name else { return false }
        let base = (practiceFileName as NSString).deletingPathExtension
        return name == practiceFileName || name == base
    }

    /// Most files accepted from one share, so a huge selection can't fill the phone.
    public static let maxFiles = 20
    /// Largest single file accepted. A long scanned contract stays well under it.
    public static let maxFileBytes = 40 * 1024 * 1024
    /// Most bytes one share may add to the inbox, across all its files.
    public static let maxShareBytes = 150 * 1024 * 1024

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

    /// What a shared item is, from its declared type. Apps hand documents over
    /// either typed (a PDF, a photo) or as a link to a file; for a link, pass the
    /// file's own type (`kind(ofFile:)`).
    public static func kind(of type: UTType) -> IncomingKind? {
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .plainText) { return .text }
        return nil
    }

    /// What a shared file is, from its name's extension ("Factura.PDF" is a PDF).
    public static func kind(ofFile url: URL) -> IncomingKind? {
        UTType(filenameExtension: url.pathExtension).flatMap(kind(of:))
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
        case tooLarge
    }

    /// Throws `tooLarge` when a file of `bytes` would pass the per-file limit, or
    /// the share's running total (`sharedSoFar`) would pass the per-share limit.
    public static func checkRoom(for bytes: Int, sharedSoFar: Int) throws {
        guard bytes <= maxFileBytes, sharedSoFar + bytes <= maxShareBytes else { throw InboxError.tooLarge }
    }

    /// The size of a staged file, for the share's running total.
    public static func byteCount(of name: String, in staging: URL) -> Int {
        (try? staging.appending(path: name).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
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
    public func stage(copyOf source: URL, into staging: URL, index: Int, sharedSoFar: Int = 0) throws -> String {
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        try Self.checkRoom(for: size, sharedSoFar: sharedSoFar)
        let name = Self.safeName(index: index, extension: source.pathExtension)
        let target = staging.appending(path: name)
        try FileManager.default.copyItem(at: source, to: target)
        Self.protect(target)
        return name
    }

    /// Writes bytes into a staging folder. Returns the name used.
    @discardableResult
    public func stage(data: Data, fileExtension: String, into staging: URL, index: Int, sharedSoFar: Int = 0) throws -> String {
        try Self.checkRoom(for: data.count, sharedSoFar: sharedSoFar)
        let name = Self.safeName(index: index, extension: fileExtension)
        try data.write(to: staging.appending(path: name), options: [.atomic, .completeFileProtection])
        return name
    }

    /// Makes a staged folder visible as an inbox item, in one rename.
    @discardableResult
    public func commit(staging: URL, payload: InboxItem.Payload, files: [String], originalName: String?, receivedAt: Date = Date(), now: Date = Date()) throws -> InboxItem {
        guard !files.isEmpty else {
            try? FileManager.default.removeItem(at: staging)
            throw InboxError.nothingToSave
        }
        let item = InboxItem(
            receivedAt: receivedAt,
            payload: payload,
            files: files,
            originalName: originalName,
            isPractice: isExpectedPractice(staging: staging, files: files, now: now)
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

    // MARK: Practice

    private struct PracticeMarker: Codable {
        var sha256: String
        var expiresAt: Date
    }

    /// The app calls this with the practice invoice before it shows the share
    /// sheet. Whatever the sending app calls the file, the item that brings these
    /// exact bytes back within the hour is the practice.
    public func expectPractice(fileAt url: URL, now: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: Self.protection)
        let marker = PracticeMarker(sha256: Self.fingerprint(of: try Data(contentsOf: url)), expiresAt: now.addingTimeInterval(Self.practiceWindow))
        try Self.encoder.encode(marker).write(to: directory.appending(path: Self.practiceMarkerName), options: [.atomic, .completeFileProtection])
    }

    /// Whether one of the staged files is the practice invoice the app is waiting for.
    func isExpectedPractice(staging: URL, files: [String], now: Date) -> Bool {
        guard let data = try? Data(contentsOf: directory.appending(path: Self.practiceMarkerName)),
              let marker = try? Self.decoder.decode(PracticeMarker.self, from: data),
              marker.expiresAt > now else { return false }
        return files.contains { name in
            (try? Data(contentsOf: staging.appending(path: name))).map(Self.fingerprint) == marker.sha256
        }
    }

    static func fingerprint(of data: Data) -> String {
        let hex = Array("0123456789abcdef")
        return SHA256.hash(data: data).map { byte in "\(hex[Int(byte >> 4)])\(hex[Int(byte & 0x0f)])" }.joined()
    }

    // MARK: Reading (app)

    /// What the inbox holds.
    public struct Contents: Sendable, Equatable {
        /// Items waiting for review, newest first.
        public var items: [InboxItem] = []
        /// Items that couldn't be opened, newest first.
        public var unreadable: [UnreadableInboxItem] = []
    }

    /// Every committed item, newest first. A folder that can't be read (a damaged
    /// manifest, a missing file, a newer format) is moved aside the first time it
    /// is seen and listed under `unreadable`, so it is never skipped silently.
    ///
    /// The app reads the inbox here, so this is where a manifest an earlier version wrote is
    /// tidied, once: a name it kept whole is written again masked (`maskStoredName`).
    public func contents(now: Date = Date()) -> Contents {
        let fileManager = FileManager.default
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path())) ?? []
        var items: [InboxItem] = []
        for name in names where !name.hasPrefix(".") {
            if let item = readItem(named: name) {
                maskStoredName(of: item)
                items.append(item)
            } else {
                setAside(name, now: now)
            }
        }
        return Contents(items: items.sorted { $0.receivedAt > $1.receivedAt }, unreadable: unreadable())
    }

    /// Every committed item, newest first (`contents()`).
    public func items() -> [InboxItem] {
        contents().items
    }

    /// The items waiting now, newest first, read without changing anything: an item that
    /// can't be opened is left where it is for the app to set aside. For the share
    /// extension's notice and the app's coordinator, which only look.
    public func waitingItems() -> [InboxItem] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path())) ?? []
        return names.filter { !$0.hasPrefix(".") }.compactMap(readItem(named:)).sorted { $0.receivedAt > $1.receivedAt }
    }

    /// Posted in the app's own process whenever what waits in the inbox changes (an item
    /// arrived, was filed or dismissed), so the coordinator can follow the inbox notice.
    public static let didChangeNotification = Notification.Name("ShareInbox.didChange")

    private func readItem(named name: String) -> InboxItem? {
        let folder = directory.appending(path: name, directoryHint: .isDirectory)
        guard let data = try? Data(contentsOf: folder.appending(path: Self.manifestName)),
              let item = try? Self.decoder.decode(InboxItem.self, from: data),
              item.version <= InboxItem.currentVersion,
              folder.lastPathComponent == item.id.uuidString.lowercased(),
              !item.files.isEmpty,
              item.files.allSatisfy({ FileManager.default.fileExists(atPath: folder.appending(path: $0).path()) })
        else { return nil }
        return item
    }

    /// The name a manifest keeps on disk, as written.
    private struct StoredName: Decodable {
        let originalName: String?
    }

    /// A manifest written before the share extension masked names may keep a card number in the
    /// shared file's name until the item is filed or dismissed. Read, the item is masked by the
    /// shared rule (`InboxItem.originalName`); when the name on disk differs, the manifest is
    /// written again with it, once: the next read finds them the same. Its version and everything
    /// else stay as they were. Only the app does this; the share extension never needs to.
    func maskStoredName(of item: InboxItem) {
        let url = folder(for: item.id).appending(path: Self.manifestName)
        guard let data = try? Data(contentsOf: url),
              let stored = try? Self.decoder.decode(StoredName.self, from: data),
              stored.originalName != item.originalName,
              let rewritten = try? Self.encoder.encode(item) else { return }
        // Can't write it now (the phone is locked): the next read tries again.
        try? rewritten.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private var asideFolder: URL {
        directory.appending(path: Self.asideFolderName, directoryHint: .isDirectory)
    }

    private func setAside(_ name: String, now: Date) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: asideFolder, withIntermediateDirectories: true, attributes: Self.protection)
        let target = asideFolder.appending(path: name)
        if fileManager.fileExists(atPath: target.path()) { try? fileManager.removeItem(at: target) }
        do {
            try fileManager.moveItem(at: directory.appending(path: name), to: target)
            try? fileManager.setAttributes([.modificationDate: now], ofItemAtPath: target.path())
        } catch {
            // Can't move it: it stays where it is and is tried again next time.
        }
    }

    /// Items set aside because they couldn't be opened, newest first.
    public func unreadable() -> [UnreadableInboxItem] {
        let fileManager = FileManager.default
        let names = (try? fileManager.contentsOfDirectory(atPath: asideFolder.path())) ?? []
        return names.filter { !$0.hasPrefix(".") }.map { name in
            let date = (try? fileManager.attributesOfItem(atPath: asideFolder.appending(path: name).path())[.modificationDate]) as? Date
            return UnreadableInboxItem(id: name, setAsideAt: date ?? .distantPast)
        }
        .sorted { $0.setAsideAt > $1.setAsideAt }
    }

    /// Removes an item that couldn't be opened. Removing a missing one is fine.
    public func removeUnreadable(_ id: String) throws {
        guard !id.isEmpty, !id.contains("/"), !id.hasPrefix(".") else { return }
        let target = asideFolder.appending(path: id)
        guard FileManager.default.fileExists(atPath: target.path()) else { return }
        try FileManager.default.removeItem(at: target)
    }

    /// The item's files in page order.
    public func fileURLs(of item: InboxItem) -> [URL] {
        item.files.map { folder(for: item.id).appending(path: $0) }
    }

    // MARK: Previews (app)

    static let previewName = "preview.json"
    static let thumbnailName = "thumbnail.jpg"

    /// What the app learned about an item, or nil when it hasn't read it yet (or the
    /// preview can't be used and should be made again).
    public func preview(of item: InboxItem) -> InboxPreview? {
        guard let data = try? Data(contentsOf: folder(for: item.id).appending(path: Self.previewName)),
              let preview = try? Self.decoder.decode(InboxPreview.self, from: data),
              preview.version <= InboxPreview.currentVersion else { return nil }
        return preview
    }

    /// Keeps what the app learned about an item beside it, with its first-page picture.
    /// Does nothing for an item that has already left.
    public func savePreview(_ preview: InboxPreview, thumbnail: Data?, for item: InboxItem) throws {
        let folder = folder(for: item.id)
        guard FileManager.default.fileExists(atPath: folder.path()) else { return }
        var preview = preview
        if let thumbnail {
            try thumbnail.write(to: folder.appending(path: Self.thumbnailName), options: [.atomic, .completeFileProtection])
        }
        preview.hasThumbnail = thumbnail != nil
        try Self.encoder.encode(preview).write(to: folder.appending(path: Self.previewName), options: [.atomic, .completeFileProtection])
    }

    /// The item's first-page picture, when the app kept one.
    public func thumbnailURL(of item: InboxItem) -> URL? {
        let url = folder(for: item.id).appending(path: Self.thumbnailName)
        return FileManager.default.fileExists(atPath: url.path()) ? url : nil
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

    static var encoder: JSONEncoder { MachineText.jsonEncoder() }

    static var decoder: JSONDecoder { MachineText.jsonDecoder() }
}
