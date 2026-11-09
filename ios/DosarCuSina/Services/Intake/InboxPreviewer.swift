import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// Reads a waiting share-inbox item's first page on the phone, so De verificat can say
/// what it is ("Factură ENGIE Romania S.A.", "Carte de identitate") and show its first
/// page, before the person opens it.
///
/// - The same engine as every capture (`CaptureEngine.standard()`), tiers 1–2 only: no
///   on-device model (it would cost battery for a title) and never the person's AI
///   provider. Nothing is kept in the document store; only the kind, the title and the
///   page count, through `SearchPrivacy.outsideText` so no CNP or card number is kept.
/// - A picture is kept only when the reading is sure the page can't be a bank card
///   (`PhoneOnlyReading`, the rule "Citește mai bine" follows): a card's photo shows its
///   whole number. A page that couldn't be read gets no picture either.
/// - Off the main thread; the item's files are only read.
enum InboxPreviewer {
    /// The picture's longest side in pixels: sharp in a 44 pt well at 3×, a few kilobytes.
    static let thumbnailPixels = 240

    static func read(_ item: InboxItem, files: [URL]) async -> (preview: InboxPreview, thumbnail: Data?) {
        let page = firstPage(of: item, files: files)
        guard let payload = page.payload,
              let result = try? await CaptureEngine.standard().capture(CaptureRequest(payload, options: Self.options))
        else {
            return (InboxPreview(kind: nil, title: nil, categoryKey: nil, pageCount: page.count), nil)
        }
        let summary = summary(of: result)
        let thumbnail = mayKeepPicture(of: result) ? page.picture.flatMap(jpeg) : nil
        return (InboxPreview(kind: summary.kind, title: summary.title, categoryKey: summary.categoryKey, pageCount: page.count), thumbnail)
    }

    /// Phone only, the quick tiers, nothing stored.
    static let options = CaptureOptions(useOnDeviceModel: false, useCloudModel: false, storeDocument: false)

    /// What a reading says the document is, as it may be shown in the list. Nothing for a
    /// page the binder doesn't know ("Document" wouldn't tell two apart): the file name does better.
    static func summary(of result: CaptureResult) -> (kind: String?, title: String?, categoryKey: String?) {
        guard result.kind != .other else { return (nil, nil, nil) }
        let profile = result.kind.profile
        var values: [CaptureFieldKey: CaptureValue] = [:]
        for field in result.fields where values[field.key] == nil { values[field.key] = field.value }
        let cover = profile.cover(read: values[.coverageType]?.text, hasVehicle: values[.licensePlate] != nil || values[.vin] != nil)
        let title = SearchPrivacy.outsideText(profile.defaultTitle(fields: values))
        return (result.kind.rawValue, title, profile.filedTemplateKey(cover: cover))
    }

    /// Whether the first page's picture may be kept beside the item.
    static func mayKeepPicture(of result: CaptureResult) -> Bool {
        !result.kind.profile.photoIsOptIn && !PhoneOnlyReading.mayBeOne(result)
    }

    // MARK: First page

    struct FirstPage {
        /// Only the first page, to read.
        var payload: CaptureRequest.Payload?
        /// Pages in the whole document.
        var count: Int
        /// The first page, small, for the list.
        var picture: CGImage?
    }

    static func firstPage(of item: InboxItem, files: [URL]) -> FirstPage {
        switch item.payload {
        case .images:
            guard let first = files.first, let data = try? Data(contentsOf: first) else { return FirstPage(count: files.count) }
            return FirstPage(payload: try? CaptureInput.payload(photos: [data]), count: files.count, picture: imageThumbnail(data))
        case .pdf:
            guard let url = files.first, let data = try? Data(contentsOf: url), let document = PDFDocument(data: data) else { return FirstPage(count: 1) }
            let count = max(document.pageCount, 1)
            guard let page = document.page(at: 0) else { return FirstPage(count: count) }
            let single = PDFDocument()
            if let copy = page.copy() as? PDFPage { single.insert(copy, at: 0) }
            let firstData = (single.pageCount > 0 ? single.dataRepresentation() : nil) ?? data
            let size = CGSize(width: thumbnailPixels, height: thumbnailPixels)
            return FirstPage(payload: CaptureRequest.Payload.pdf(firstData), count: count, picture: page.thumbnail(of: size, for: .mediaBox).cgImage)
        case .text:
            let text = files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return FirstPage(payload: trimmed.isEmpty ? nil : .text(text), count: 1)
        }
    }

    static func imageThumbnail(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func jpeg(_ image: CGImage) -> Data? {
        UIImage(cgImage: image).jpegData(compressionQuality: 0.7)
    }
}
