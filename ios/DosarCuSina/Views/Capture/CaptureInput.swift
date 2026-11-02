import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns what the person picked (camera pages, photos, a file, an item shared
/// from another app) into one `CaptureRequest` for `CaptureEngine`.
enum CaptureInput {
    enum InputError: LocalizedError, Equatable {
        case unreadable
        case unsupported

        var errorDescription: String? {
            switch self {
            case .unreadable: return String(localized: "Fișierul nu se poate deschide. Poate s-a trimis doar pe jumătate; trimite-l din nou.")
            case .unsupported: return String(localized: "Pot citi poze, PDF-uri și text. Alege actul ca poză sau PDF.")
            }
        }
    }

    /// Long edge for recognition; plenty for small print, and it keeps memory low.
    static let maxPixelSize = 4000

    /// An image from encoded bytes (JPEG, HEIC, PNG), upright.
    static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Photos (from Photos or a share), read together as the pages of one document.
    static func payload(photos: [Data]) throws -> CaptureRequest.Payload {
        let images = photos.compactMap { data in image(from: data).map { CaptureImage(image: $0, sourceData: data) } }
        guard !images.isEmpty else { throw InputError.unreadable }
        return .images(images)
    }

    /// Pages from the document camera, already flattened.
    static func payload(scannedPages: [CGImage]) throws -> CaptureRequest.Payload {
        guard !scannedPages.isEmpty else { throw InputError.unreadable }
        return .images(scannedPages.map { CaptureImage(image: $0, isPerspectiveCorrected: true) })
    }

    /// A file from Files or Mail: a PDF, an image or plain text.
    static func payload(files urls: [URL]) throws -> CaptureRequest.Payload {
        guard let first = urls.first else { throw InputError.unreadable }
        let type = UTType(filenameExtension: first.pathExtension) ?? .data
        if type.conforms(to: .pdf) {
            guard let data = try? Data(contentsOf: first), !data.isEmpty else { throw InputError.unreadable }
            return .pdf(data)
        }
        if type.conforms(to: .image) {
            return try payload(photos: urls.compactMap { try? Data(contentsOf: $0) })
        }
        if type.conforms(to: .plainText) {
            let text = urls.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw InputError.unreadable }
            return .text(text)
        }
        throw InputError.unsupported
    }

    /// An item from the share inbox.
    static func payload(inboxItem item: InboxItem, files: [URL]) throws -> CaptureRequest.Payload {
        switch item.payload {
        case .pdf:
            guard let url = files.first, let data = try? Data(contentsOf: url), !data.isEmpty else { throw InputError.unreadable }
            return .pdf(data)
        case .images:
            return try payload(photos: files.compactMap { try? Data(contentsOf: $0) })
        case .text:
            let text = files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw InputError.unreadable }
            return .text(text)
        }
    }
}
