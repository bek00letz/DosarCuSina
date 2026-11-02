import CoreGraphics
import Foundation

/// An image going into the pipeline.
public struct CaptureImage: Sendable {
    public let image: CGImage
    /// The original bytes from the camera or Photos, used to recognize the same photo twice.
    public let sourceData: Data?
    /// True for pages from the document scanner, which are already flattened.
    public let isPerspectiveCorrected: Bool

    public init(image: CGImage, sourceData: Data? = nil, isPerspectiveCorrected: Bool = false) {
        self.image = image
        self.sourceData = sourceData
        self.isPerspectiveCorrected = isPerspectiveCorrected
    }
}

/// One thing to capture: photos or scanned pages, a PDF, or text pasted from an email or SMS.
public struct CaptureRequest: Sendable {
    public enum Payload: Sendable {
        case images([CaptureImage])
        case pdf(Data)
        case text(String)
    }

    public var payload: Payload
    public var options: CaptureOptions

    public init(_ payload: Payload, options: CaptureOptions = CaptureOptions()) {
        self.payload = payload
        self.options = options
    }
}

public struct CaptureOptions: Sendable {
    /// Use Apple's on-device model when available. Private and offline, so on by default.
    public var useOnDeviceModel: Bool = true
    /// Send the first page to the person's own Gemini key. Only when they ask for it on this capture.
    public var useCloudModel: Bool = false
    /// Keep the pages in the document store.
    public var storeDocument: Bool = true
    /// The asset the document belongs to, when the capture started from an asset.
    public var ownerID: String?
    /// "Today", for deciding the century of two-digit years. Injectable for tests.
    public var referenceDate: Date = Date()

    public init(useOnDeviceModel: Bool = true, useCloudModel: Bool = false, storeDocument: Bool = true, ownerID: String? = nil, referenceDate: Date = Date()) {
        self.useOnDeviceModel = useOnDeviceModel
        self.useCloudModel = useCloudModel
        self.storeDocument = storeDocument
        self.ownerID = ownerID
        self.referenceDate = referenceDate
    }
}

/// The single way into the binder. Every input (camera, Photos, PDF, Share Extension,
/// pasted text) goes through the same tiers:
///
/// 1. **Deterministic**: the MRZ with check digits, barcodes and QR codes, known invoice formats, tax ID checksums.
/// 2. **Heuristic**: Romanian dates, amounts, labels and identifiers in the recognized text.
/// 3. **On-device model**: Apple's language model fills what patterns can't, when the device has it.
/// 4. **Cloud model**: the person's Gemini key, only when they ask.
///
/// The result is a draft. Nothing is saved to the person's data until they confirm it;
/// only the document's pages are kept, so they're never lost.
public final class CaptureEngine: Sendable {

    /// Only the first pages of long PDFs are read; enough for any policy, invoice or contract.
    public static let maxPDFPages = 25

    let analyzer: CaptureAnalyzer
    let recognizer: any CaptureRecognizing
    let normalizer: (any CapturePagePreparing)?
    let onDeviceModel: (any CaptureSemanticExtracting)?
    let cloudModel: (any CaptureSemanticExtracting)?
    let store: CaptureDocumentStore?

    public init(
        analyzer: CaptureAnalyzer,
        recognizer: any CaptureRecognizing,
        normalizer: (any CapturePagePreparing)? = DocumentImageNormalizer(),
        onDeviceModel: (any CaptureSemanticExtracting)?,
        cloudModel: (any CaptureSemanticExtracting)?,
        store: CaptureDocumentStore?
    ) {
        self.analyzer = analyzer
        self.recognizer = recognizer
        self.normalizer = normalizer
        self.onDeviceModel = onDeviceModel
        self.cloudModel = cloudModel
        self.store = store
    }

    /// The engine as the app and the Share Extension use it.
    public static func standard(componentResolver: any CaptureComponentResolving = CatalogComponentResolver()) -> CaptureEngine {
        #if canImport(UIKit)
        let cloud: (any CaptureSemanticExtracting)? = GeminiCaptureExtractor(resolver: componentResolver)
        #else
        let cloud: (any CaptureSemanticExtracting)? = nil
        #endif
        return CaptureEngine(
            analyzer: CaptureAnalyzer(specializedParsers: [UtilityInvoiceParser()], componentResolver: componentResolver),
            recognizer: VisionCaptureRecognizer(),
            onDeviceModel: OnDeviceModelExtractor(resolver: componentResolver),
            cloudModel: cloud,
            store: CaptureDocumentStore.shared()
        )
    }

    // MARK: - Capture

    public func capture(_ request: CaptureRequest) async throws -> CaptureResult {
        var notices: [CaptureNotice] = []
        let options = request.options

        // 1. Pages and text.
        /// The pages as taken: what is kept and shown.
        var pages: [CGImage] = []
        /// The pages as read: found, flattened, turned upright and enlarged.
        var readImages: [CGImage] = []
        /// Recognized lines with their positions, page by page. Empty for pasted text and a PDF's text layer.
        var recognized: [[RecognizedLine]] = []
        var text = ""
        var barcodes: [CaptureBarcode] = []
        var pdfData: Data?
        var pdfThumbnail: CGImage?
        var sourceData: Data?

        switch request.payload {
        case .images(let images):
            for item in images {
                var page = item.image
                if let normalizer, !item.isPerspectiveCorrected {
                    page = await normalizer.prepare(item.image)
                }
                pages.append(item.image)
                readImages.append(page)
                let read = try await recognizer.recognize(page)
                recognized.append(read.items)
                text += (text.isEmpty ? "" : "\n") + read.text
                barcodes += read.barcodes
            }
            if images.count == 1 { sourceData = images[0].sourceData }

        case .pdf(let data):
            pdfData = data
            let extracted = PDFExtractorService.extractText(from: data)
            text = extracted.text
            if extracted.pageCount > Self.maxPDFPages {
                notices.append(.pagesTruncated(readPages: Self.maxPDFPages, totalPages: extracted.pageCount))
            }
            let rendered = PDFRasterizer.render(data, maxPages: text.count < 40 ? Self.maxPDFPages : 1)
            pdfThumbnail = rendered.first
            // A scanned PDF has no text layer; read its pages like photos.
            if text.count < 40 {
                text = ""
                for page in rendered {
                    let read = try await recognizer.recognize(page)
                    recognized.append(read.items)
                    text += (text.isEmpty ? "" : "\n") + read.text
                    barcodes += read.barcodes
                }
            } else if let first = rendered.first, let recognized = try? await recognizer.recognize(first) {
                // Digital PDFs still carry payment QR codes as images.
                barcodes += recognized.barcodes
            }

        case .text(let pasted):
            text = pasted
        }

        CaptureLog.engine.info("Recognized \(text.count) characters and \(barcodes.count) codes")

        // 2. Deterministic and heuristic tiers.
        var analysis = recognized.isEmpty
            ? analyzer.analyze(text: text, barcodes: barcodes, referenceDate: options.referenceDate)
            : analyzer.analyze(pages: recognized, barcodes: barcodes, referenceDate: options.referenceDate)

        // One retry for photos that read poorly: each page's best other variant (a quarter
        // turn, or the photo uncorrected), read once more; the better reading is kept.
        if !readImages.isEmpty, let normalizer, Self.readsPoorly(analysis) {
            var retried = recognized
            var retriedImages = readImages
            var retriedBarcodes: [CaptureBarcode] = []
            var changed = false
            for index in readImages.indices {
                guard let variant = await normalizer.retryVariant(of: readImages[index], original: pages[index]),
                      let read = try? await recognizer.recognize(variant) else { continue }
                retried[index] = read.items
                retriedImages[index] = variant
                retriedBarcodes += read.barcodes
                changed = true
            }
            if changed {
                let second = analyzer.analyze(pages: retried, barcodes: barcodes + retriedBarcodes, referenceDate: options.referenceDate)
                CaptureLog.engine.info("Retried a poor read: \(Self.readingScore(analysis)) → \(Self.readingScore(second))")
                if Self.readingScore(second) > Self.readingScore(analysis) {
                    analysis = second
                    recognized = retried
                    readImages = retriedImages
                    barcodes += retriedBarcodes
                    text = retried.map { $0.map(\.text).joined(separator: "\n") }.joined(separator: "\n")
                }
            }
        }
        notices += analysis.notices
        // Still poor after the retry: say so calmly, once.
        if Self.readsPoorly(analysis), !notices.contains(.littleTextRecognized) {
            notices.append(.littleTextRecognized)
        }
        let today = CaptureDay(date: options.referenceDate)
        var kind = analysis.kind
        // Each tier's dates are checked against their windows before merging, so an
        // impossible date (a passport "expiring in 1906") never pushes out a possible one.
        var fields = CaptureConsistency.plausible(analysis.fields, kind: kind, today: today)
        var kindConfidence = analysis.kindConfidence

        // 3. On-device model, unless the patterns already read everything that matters.
        let alreadyComplete = kindConfidence >= 0.8 && kind.isComplete(fields)
        if alreadyComplete { CaptureLog.engine.info("Skipping the on-device model: patterns found the essentials") }
        if options.useOnDeviceModel, !alreadyComplete, let model = onDeviceModel, !text.isEmpty {
            switch model.availability() {
            case .available:
                do {
                    let extraction = try await model.extract(SemanticInput(text: text, firstPage: readImages.first ?? pdfThumbnail, kind: kind, knownFields: fields, today: today))
                    fields = FieldMerger.merge(fields, with: CaptureConsistency.plausible(extraction.fields, kind: kind, today: today))
                    if let modelKind = extraction.kind, modelKind != kind, kindConfidence < 0.6 {
                        kind = modelKind
                        kindConfidence = 0.65
                    }
                } catch {
                    CaptureLog.engine.error("On-device model failed: \((error as NSError).domain, privacy: .public) \((error as NSError).code)")
                    notices.append(.onDeviceModelFailed)
                }
            case .unavailable(let reason):
                notices.append(.onDeviceModelUnavailable(reason: reason))
            }
        }

        // 4. Cloud model, only on request.
        if options.useCloudModel, let model = cloudModel {
            switch model.availability() {
            case .available:
                do {
                    let extraction = try await model.extract(SemanticInput(text: text, firstPage: readImages.first ?? pdfThumbnail, kind: kind, knownFields: fields, today: today))
                    fields = FieldMerger.merge(fields, with: CaptureConsistency.plausible(extraction.fields, kind: kind, today: today))
                } catch {
                    notices.append(.cloudModelFailed(reason: "requestFailed"))
                }
            case .unavailable(let reason):
                notices.append(.cloudModelFailed(reason: reason))
            }
        }

        // Dates checked against each other, then only fields that belong on this kind
        // of document, whichever tier found them.
        fields = CaptureConsistency.resolve(fields, kind: kind, today: today).fields
        fields = Self.derived(fields).filter { kind.allows($0.key) }

        // A card read from its front alone: the back carries the zone that confirms it.
        if kind == .identityCard, !analysis.hasMachineReadableZone, case .images(let images) = request.payload, images.count == 1 {
            notices.append(.identityBackMissing)
        }
        CaptureLog.engine.info("Read \(fields.count) fields, kind confidence \(kindConfidence)")
        let routing = CaptureRouter.route(kind: kind, kindConfidence: kindConfidence, fields: fields)

        // 5. Keep the pages.
        var documentID: UUID?
        if options.storeDocument, let store, !pages.isEmpty || pdfData != nil {
            let stored = try await store.store(CaptureDocumentStore.StoreRequest(
                pages: pages,
                originalPDF: pdfData,
                thumbnailSource: pdfThumbnail,
                sourceData: sourceData,
                kind: kind,
                ownerID: options.ownerID,
                capturedAt: options.referenceDate
            ))
            documentID = stored.document.id
            if stored.isDuplicate { notices.append(.duplicateDocument(documentID: stored.document.id)) }
        }

        return CaptureResult(
            kind: kind,
            kindConfidence: kindConfidence,
            fields: fields,
            suggestions: routing.suggestions,
            reminder: routing.reminder,
            // For people: laid out like the document when positions are known, as read otherwise.
            recognizedText: recognized.isEmpty ? text : analysis.readableText,
            barcodes: barcodes,
            documentID: documentID,
            notices: notices
        )
    }

    /// Whether a reading is too poor to trust: little text, or an identity document
    /// without any of the fields every such document carries.
    static func readsPoorly(_ analysis: CaptureAnalyzer.Analysis) -> Bool {
        if analysis.notices.contains(.littleTextRecognized) { return true }
        return analysis.kind.isIdentityDocument && analysis.kind.lacksExpectedFields(analysis.fields)
    }

    /// How good a reading is, for keeping the better of two: fields first, then text.
    static func readingScore(_ analysis: CaptureAnalyzer.Analysis) -> Int {
        let checked = analysis.fields.filter { $0.tier == .deterministic }.count
        let letters = analysis.text.joinedOriginal.filter { $0.isLetter || $0.isNumber }.count
        return checked * 1_000 + analysis.fields.count * 100 + min(letters, 99)
    }

    /// Values computed from other fields after all tiers have run.
    static func derived(_ fields: [CaptureField]) -> [CaptureField] {
        var result = fields
        let lookup = Dictionary(fields.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        if lookup[.warrantyUntil] == nil,
           let purchase = lookup[.purchaseDate], let start = purchase.value.day,
           let months = lookup[.warrantyMonths], case .number(let count) = months.value,
           let until = start.addingMonths(NSDecimalNumber(decimal: count).intValue) {
            result.append(CaptureField(
                key: .warrantyUntil, value: .day(until),
                confidence: min(purchase.confidence, months.confidence),
                sourceText: nil, tier: max(purchase.tier, months.tier)
            ))
        }
        if lookup[.purchasePrice] == nil, let total = lookup[.total], case .money = total.value,
           result.contains(where: { $0.key == .purchaseDate }) {
            result.append(CaptureField(key: .purchasePrice, value: total.value, confidence: total.confidence, sourceText: total.sourceText, tier: total.tier))
        }
        return result
    }
}

// MARK: - PDF pages

/// Renders PDF pages to images for recognition and thumbnails, without UIKit.
enum PDFRasterizer {
    static func render(_ data: Data, maxPages: Int, longEdge: CGFloat = 2000) -> [CGImage] {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else { return [] }
        let count = min(document.numberOfPages, maxPages)
        guard count > 0 else { return [] }
        return (1...count).compactMap { number in
            guard let page = document.page(at: number) else { return nil }
            let box = page.getBoxRect(.cropBox)
            guard box.width > 0, box.height > 0 else { return nil }
            let scale = longEdge / max(box.width, box.height)
            let width = Int(box.width * scale)
            let height = Int(box.height * scale)
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
            return context.makeImage()
        }
    }
}
