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
    /// Send the first page to the AI provider the person set up, with their own key. Only when they ask for it on this capture.
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
/// 4. **Cloud model**: the AI provider the person set up with their own key, when they ask (or
///    automatically after a weak reading, when they chose so): a full second opinion that
///    `ReadingArbiter` ranks against the phone's reading by evidence.
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
        CaptureEngine(
            analyzer: CaptureAnalyzer(specializedParsers: [UtilityInvoiceParser()], componentResolver: componentResolver),
            recognizer: VisionCaptureRecognizer(),
            onDeviceModel: OnDeviceModelExtractor(resolver: componentResolver),
            cloudModel: CloudCaptureExtractor(resolver: componentResolver),
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
        var reading = ReadingArbiter.KindReading(kind: analysis.kind, confidence: analysis.kindConfidence, evidence: analysis.kindEvidence)
        var kindAlternatives: [CaptureAlternative<CaptureDocumentKind>] = []
        var readWithCloudModel = false
        /// What the phone read so far, as the models are told it.
        let known = CaptureConsistency.plausible(analysis.fields, kind: reading.kind, today: today)
        /// The on-device model's answers, kept apart so the phone's reading can be redone for another kind.
        var modelFields: [CaptureField] = []
        var aiFields: [CaptureField]?
        let firstPage = readImages.first ?? pdfThumbnail

        // 3. On-device model, unless the patterns already read everything that matters.
        let alreadyComplete = reading.confidence >= 0.8 && reading.kind.isComplete(known)
        if alreadyComplete { CaptureLog.engine.info("Skipping the on-device model: patterns found the essentials") }
        try Task.checkCancellation()
        if options.useOnDeviceModel, !alreadyComplete, let model = onDeviceModel, !text.isEmpty {
            switch model.availability() {
            case .available:
                do {
                    let extraction = try await model.extract(SemanticInput(text: text, firstPage: firstPage, kind: reading.kind, knownFields: known, today: today))
                    modelFields = extraction.fields
                    reading = ReadingArbiter.kind(reading, onDeviceModel: extraction.kind)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    CaptureLog.engine.error("On-device model failed: \((error as NSError).domain, privacy: .public) \((error as NSError).code)")
                    notices.append(.onDeviceModelFailed)
                }
            case .unavailable(let reason):
                notices.append(.onDeviceModelUnavailable(reason: reason))
            }
        }

        // 4. The person's AI provider: a second opinion on the whole page, on request.
        // `ReadingArbiter` ranks it against the phone's reading by evidence. Closing the
        // capture before this point means nothing is sent. A page that may be a bank card
        // (`PhoneOnlyReading`, on what the phone read of these very pages) is never sent,
        // whoever asked: the tap, the automatic reading, or a reading again with added pages.
        try Task.checkCancellation()
        let staysOnPhone = PhoneOnlyReading.mayBeOne(kinds: [analysis.kind, reading.kind], text: text)
        if options.useCloudModel, staysOnPhone {
            CaptureLog.engine.info("Not sending to the AI provider: read only on the phone")
            notices.append(.readOnPhoneOnly)
        } else if options.useCloudModel, let model = cloudModel {
            switch model.availability() {
            case .available:
                do {
                    let phone = FieldMerger.merge(known, with: CaptureConsistency.plausible(modelFields, kind: reading.kind, today: today))
                    let extraction = try await model.extract(SemanticInput(text: text, firstPage: firstPage, kind: reading.kind, knownFields: phone, today: today))
                    readWithCloudModel = true
                    let decided = ReadingArbiter.kind(reading, secondOpinion: extraction.kind)
                    if decided.reading.kind != reading.kind { CaptureLog.engine.info("Second opinion changed the kind") }
                    reading = decided.reading
                    kindAlternatives = decided.alternatives
                    aiFields = extraction.fields
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let reason = AIProviderError(transport: error).code
                    CaptureLog.engine.error("Cloud model failed: \(reason, privacy: .public)")
                    notices.append(.cloudModelFailed(reason: reason))
                }
            case .unavailable(let reason):
                notices.append(.cloudModelFailed(reason: reason))
            }
        }
        var isSinglePhoto = false
        if case .images(let images) = request.payload, images.count == 1 { isSinglePhoto = true }
        let source = CaptureReadingSource(
            text: text, pages: recognized, barcodes: barcodes, referenceDate: options.referenceDate,
            modelFields: modelFields, aiFields: aiFields, isSinglePhoto: isSinglePhoto
        )

        // The kind decided: its fields, from every reader, read as that kind.
        let settled = settle(source, as: reading.kind, analysis: reading.kind == analysis.kind ? analysis : nil)
        notices += settled.notices
        CaptureLog.engine.info("Read \(settled.fields.count) fields, kind confidence \(reading.confidence), \(settled.alternatives.count) alternatives")
        let routing = CaptureRouter.route(kind: reading.kind, kindConfidence: reading.confidence, fields: settled.fields)

        // 5. Keep the pages, unless the capture was closed meanwhile.
        try Task.checkCancellation()
        var document: CapturedDocumentRef?
        if options.storeDocument, let store, !pages.isEmpty || pdfData != nil {
            let stored = try await store.store(CaptureDocumentStore.StoreRequest(
                pages: pages,
                originalPDF: pdfData,
                thumbnailSource: pdfThumbnail,
                sourceData: sourceData,
                kind: reading.kind,
                ownerID: options.ownerID,
                capturedAt: options.referenceDate
            ))
            if Task.isCancelled {
                await store.release(stored.ref)
                throw CancellationError()
            }
            document = stored.ref
        }

        // No card number goes further than this, whatever the kind.
        return CaptureResult(
            kind: reading.kind,
            kindConfidence: reading.confidence,
            fields: settled.fields,
            suggestions: routing.suggestions,
            reminder: routing.reminder,
            // For people: laid out like the document when positions are known, as read otherwise.
            recognizedText: recognized.isEmpty ? text : analysis.readableText,
            barcodes: barcodes,
            document: document,
            notices: notices,
            kindEvidence: reading.evidence,
            kindAlternatives: kindAlternatives,
            fieldAlternatives: settled.alternatives,
            readWithCloudModel: readWithCloudModel,
            source: source
        ).withoutCardNumbers()
    }

    // MARK: - Reading as another kind

    /// The same pages read as `kind`: when the person corrects the kind in the review.
    /// The stored text is read again with that kind's patterns and labels, merged with
    /// the models' answers through `ReadingArbiter`, and only the fields `kind` carries
    /// are kept. Nothing is read from the pictures again and nothing is sent anywhere.
    /// The review keeps what the person changed (`CaptureReview.carryingEdits`).
    public func reinterpret(_ result: CaptureResult, as kind: CaptureDocumentKind) -> CaptureResult {
        let settled: Settled
        if let source = result.source {
            settled = settle(source, as: kind, analysis: nil)
        } else {
            // A result made by hand has no text to read again: what it has, as this kind allows.
            settled = Settled(fields: result.fields.filter { kind.allows($0.key) },
                              alternatives: result.fieldAlternatives.filter { kind.allows($0.key) }, notices: [])
        }
        let structural = result.notices.filter { $0 != .valueFailedCheck && $0 != .identityBackMissing }
        let routing = CaptureRouter.route(kind: kind, kindConfidence: 1, fields: settled.fields)
        return CaptureResult(
            kind: kind,
            kindConfidence: 1,
            fields: settled.fields,
            suggestions: routing.suggestions,
            reminder: routing.reminder,
            recognizedText: result.recognizedText,
            barcodes: result.barcodes,
            document: result.document,
            notices: structural + settled.notices,
            kindEvidence: result.kindEvidence,
            kindAlternatives: result.kindAlternatives.filter { $0.value != kind },
            fieldAlternatives: settled.alternatives,
            readWithCloudModel: result.readWithCloudModel,
            source: result.source
        ).withoutCardNumbers()
    }

    struct Settled {
        var fields: [CaptureField]
        var alternatives: [CaptureFieldAlternative]
        var notices: [CaptureNotice]
    }

    /// Every reader's fields for a document of `kind`: the phone's patterns and labels
    /// read as that kind (`analysis` when the text was already read so), Apple's model,
    /// then the AI's second opinion, ranked by `ReadingArbiter`. Each reader's dates are
    /// checked against their windows before merging, so an impossible date never pushes
    /// out a possible one; then dates are checked against each other, and only fields
    /// that belong on this kind of document are kept, whichever reader found them.
    func settle(_ source: CaptureReadingSource, as kind: CaptureDocumentKind, analysis: CaptureAnalyzer.Analysis?) -> Settled {
        let today = CaptureDay(date: source.referenceDate)
        let analysis = analysis ?? (source.pages.isEmpty
            ? analyzer.analyze(text: source.text, barcodes: source.barcodes, referenceDate: source.referenceDate, as: kind)
            : analyzer.analyze(pages: source.pages, barcodes: source.barcodes, referenceDate: source.referenceDate, as: kind))
        /// Set when a value falls outside its window or breaks a rule with another.
        var failedCheck = false
        func plausible(_ fields: [CaptureField]) -> [CaptureField] {
            let kept = CaptureConsistency.plausible(fields, kind: kind, today: today)
            if kept != fields { failedCheck = true }
            return kept
        }
        var fields = FieldMerger.merge(plausible(analysis.fields), with: plausible(source.modelFields))
        var alternatives: [CaptureFieldAlternative] = []
        if let ai = source.aiFields {
            let merged = ReadingArbiter.secondOpinion(phone: fields, ai: plausible(ai))
            fields = merged.fields
            alternatives = merged.alternatives
        }
        let resolved = CaptureConsistency.resolve(fields, kind: kind, today: today)
        if !resolved.dropped.isEmpty || resolved.fields.contains(where: { field in
            fields.contains { $0.key == field.key && $0.value == field.value && $0.confidence > field.confidence }
        }) { failedCheck = true }
        fields = Self.derived(resolved.fields).filter { kind.allows($0.key) }.compactMap { field in
            // Lines that aren't lines (prose, zero amounts) go, whichever reader read them.
            guard case .lineItems(let items) = field.value else { return field }
            let real = CaptureDocumentKind.realLineItems(items)
            guard !real.isEmpty else { return nil }
            return CaptureField(key: field.key, value: .lineItems(real), confidence: field.confidence, sourceText: field.sourceText, tier: field.tier)
        }
        // An alternative stays only beside a value it differs from.
        alternatives = alternatives.filter { alternative in
            fields.contains { $0.key == alternative.key && $0.value != alternative.alternative.value }
        }
        var notices: [CaptureNotice] = failedCheck ? [.valueFailedCheck] : []
        // A card read from its front alone: the back carries the zone that confirms it.
        if kind == .identityCard, !analysis.hasMachineReadableZone, source.isSinglePhoto {
            notices.append(.identityBackMissing)
        }
        return Settled(fields: fields, alternatives: alternatives, notices: notices)
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
        // A contract's minimum period ends its length after it starts.
        if lookup[.minimumPeriodEnd] == nil,
           let start = lookup[.startDate], let day = start.value.day,
           let months = lookup[.minimumMonths], case .number(let count) = months.value,
           let end = day.addingMonths(NSDecimalNumber(decimal: count).intValue) {
            result.append(CaptureField(
                key: .minimumPeriodEnd, value: .day(end),
                confidence: min(start.confidence, months.confidence),
                sourceText: nil, tier: max(start.tier, months.tier)
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
