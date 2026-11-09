import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Which pages of a document go: both sides of a card, the front or the back; for a
/// longer document all its pages or the first. Only the pages there are are offered.
public enum DocumentSharePages: String, CaseIterable, Sendable {
    case all
    case front
    case back

    /// What a document with `pageCount` pages offers, the usual choice first: nothing to
    /// choose for one page; both sides, the front or the back for two; all or the first for more.
    public static func options(pageCount: Int) -> [DocumentSharePages] {
        switch pageCount {
        case ...1: [.all]
        case 2: [.all, .front, .back]
        default: [.all, .front]
        }
    }

    /// The pages this choice takes, from 0.
    public func indices(pageCount: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        switch self {
        case .all: return Array(0..<pageCount)
        case .front: return [0]
        case .back: return pageCount >= 2 ? [1] : [0]
        }
    }

    /// "Amândouă", "Fața", "Spatele"; "Toate paginile", "Doar prima pagină" for a longer document.
    public func title(pageCount: Int) -> String {
        switch (self, pageCount) {
        case (.all, 2): String(localized: "Amândouă", comment: "Share a two-sided document: both sides.")
        case (.all, _): String(localized: "Toate paginile", comment: "Share every page of a document.")
        case (.front, 2): String(localized: "Doar fața", comment: "Share a two-sided document: only the front.")
        case (.front, _): String(localized: "Doar prima pagină", comment: "Share only the first page of a document.")
        case (.back, _): String(localized: "Doar spatele", comment: "Share a two-sided document: only the back.")
        }
    }
}

/// How the pages go: each as a picture, or all of them in one PDF.
public enum DocumentShareFormat: String, CaseIterable, Sendable {
    case pictures
    case pdf
}

/// What the person chose to send.
public struct DocumentShareChoice: Hashable, Sendable {
    public var pages: DocumentSharePages
    public var format: DocumentShareFormat

    public init(pages: DocumentSharePages = .all, format: DocumentShareFormat = .pictures) {
        self.pages = pages
        self.format = format
    }
}

/// The files a share sends: the pages as they are shown (cut out, turned), as pictures or
/// one PDF, with a neutral name. Never what was read off the document, its values, or
/// anything written on it; pictures carry no location or camera details. Written into a
/// folder of their own under `root`, removed once the share sheet closes (`remove`), and any
/// a closed app left behind go the next time (`removeLeftovers`).
public enum DocumentShareFiles {
    /// Where shares are written for the moment they take.
    public static var root: URL {
        FileManager.default.temporaryDirectory.appending(path: "Trimite", directoryHint: .isDirectory)
    }

    /// The longest side of a picture made from a PDF page (300 pixels per inch on an A4 page).
    static let pdfPictureLongEdge = 3508
    static let pictureQuality = 0.85

    public enum ShareError: Error, Equatable {
        /// No page could be drawn.
        case nothingToSend
    }

    /// Writes the chosen pages of `pages` and returns the files, in order.
    public static func write(_ pages: [DocumentPageSource], choice: DocumentShareChoice, name: String, root: URL = root) throws -> [URL] {
        let chosen = choice.pages.indices(pageCount: pages.count).compactMap { index in pages.first { $0.index == index } }
        guard !chosen.isEmpty else { throw ShareError.nothingToSend }
        let folder = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let names = fileNames(base: name, choice: choice, pageCount: pages.count)
            switch choice.format {
            case .pdf:
                let url = folder.appending(path: names[0])
                try write(pdfData(of: chosen), to: url)
                return [url]
            case .pictures:
                return try zip(chosen, names).map { page, fileName in
                    guard let image = DocumentPicture.image(of: page, maxLongEdge: page.isPDF ? pdfPictureLongEdge : nil),
                          let data = jpegData(image) else { throw ShareError.nothingToSend }
                    let url = folder.appending(path: fileName)
                    try write(data, to: url)
                    return url
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Removes a share's files, and the folder they were written in.
    public static func remove(_ urls: [URL]) {
        for folder in Set(urls.map { $0.deletingLastPathComponent() }) {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// Removes whatever earlier shares left (the app closed while the share sheet was open).
    public static func removeLeftovers(root: URL = root) {
        try? FileManager.default.removeItem(at: root)
    }

    /// The files' names: one PDF is "<name>.pdf"; the sides of a card are "<name> – fața.jpg"
    /// and "<name> – spatele.jpg"; one picture is "<name>.jpg", and several are numbered.
    static func fileNames(base: String, choice: DocumentShareChoice, pageCount: Int) -> [String] {
        let base = safeName(base)
        if choice.format == .pdf { return ["\(base).pdf"] }
        let indices = choice.pages.indices(pageCount: pageCount)
        if pageCount == 2 {
            return indices.map { index in
                index == 0
                    ? String(localized: "\(base) – fața.jpg", comment: "File name of a shared document's front. Keep the extension.")
                    : String(localized: "\(base) – spatele.jpg", comment: "File name of a shared document's back. Keep the extension.")
            }
        }
        if indices.count == 1 { return ["\(base).jpg"] }
        return indices.map { "\(base) \($0 + 1).jpg" }
    }

    /// A name a file can have on any system: no slashes, colons or the like.
    static func safeName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = name.components(separatedBy: forbidden).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? String(localized: "Act", comment: "Neutral name of a shared document.") : cleaned
    }

    // MARK: Writing

    private static func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }

    /// A JPEG with nothing but the picture: no location, camera or date.
    static func jpegData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: pictureQuality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// One PDF of the pages. Pages of a PDF stay as they are, sharp at any zoom, turned as
    /// shown and without the file's own details (title, author); photos become pages as
    /// wide as an A4 page.
    static func pdfData(of pages: [DocumentPageSource]) throws -> Data {
        if case .pdf(let original, _)? = pages.first?.content,
           pages.allSatisfy({ if case .pdf(let data, _) = $0.content { data == original } else { false } }),
           let data = pdfPages(pages, of: original) {
            return data
        }
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw ShareError.nothingToSend }
        var drawn = 0
        for page in pages {
            guard let image = DocumentPicture.image(of: page, maxLongEdge: page.isPDF ? pdfPictureLongEdge : nil),
                  let jpeg = jpegData(image), let provider = CGDataProvider(data: jpeg as CFData),
                  // A picture kept as JPEG inside the PDF, so the file stays small.
                  let embedded = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent),
                  image.width > 0 else { continue }
            let width: CGFloat = 595
            var box = CGRect(x: 0, y: 0, width: width, height: width * CGFloat(image.height) / CGFloat(image.width))
            context.beginPage(mediaBox: &box)
            context.interpolationQuality = .high
            context.draw(embedded, in: box)
            context.endPage()
            drawn += 1
        }
        context.closePDF()
        guard drawn > 0 else { throw ShareError.nothingToSend }
        return output as Data
    }

    /// The chosen pages of a PDF, turned as shown, in a new document without the original's details.
    private static func pdfPages(_ pages: [DocumentPageSource], of data: Data) -> Data? {
        guard let source = PDFDocument(data: data) else { return nil }
        let result = PDFDocument()
        for page in pages {
            guard case .pdf(_, let index) = page.content, let original = source.page(at: index),
                  let copy = original.copy() as? PDFPage else { continue }
            copy.rotation = (original.rotation + 90 * page.framing.shownQuarterTurns) % 360
            result.insert(copy, at: result.pageCount)
        }
        guard result.pageCount > 0 else { return nil }
        result.documentAttributes = [:]
        return result.dataRepresentation()
    }
}
