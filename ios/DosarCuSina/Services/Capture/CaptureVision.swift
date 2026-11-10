import CoreGraphics
import Foundation
import ImageIO
import OSLog
import Vision

/// The text and codes recognized on one page.
public struct RecognizedPage: Sendable, Hashable {
    /// Lines in reading order, top to bottom, each with where it sits on the page when known.
    public let items: [RecognizedLine]
    public let barcodes: [CaptureBarcode]

    public init(items: [RecognizedLine], barcodes: [CaptureBarcode]) {
        self.items = items
        self.barcodes = barcodes
    }

    /// Lines without positions, for text that has none.
    public init(lines: [String], barcodes: [CaptureBarcode]) {
        self.init(items: lines.map { RecognizedLine($0) }, barcodes: barcodes)
    }

    public var lines: [String] { items.map(\.text) }
    public var text: String { lines.joined(separator: "\n") }
}

/// Reads text and codes from an image. A protocol so tests and previews can supply fixed text.
public protocol CaptureRecognizing: Sendable {
    func recognize(_ image: CGImage) async throws -> RecognizedPage
}

/// On-device recognition with Vision. Runs offline.
public struct VisionCaptureRecognizer: CaptureRecognizing {

    public init() {}

    /// Thrown only when no text pass worked at all, after one retry each.
    public struct RecognitionFailed: Error {}

    /// The passes run one after another, not side by side: on a cold start each
    /// loads its own model, and several loading at once is what makes a first
    /// read fail. A pass that fails is retried once; a page is only unreadable
    /// when every text pass failed. Barcodes are a bonus and never fail a page.
    ///
    /// The machine-readable zone gets a pass of its own: its band is found from the
    /// literal pass, cropped, enlarged and read again without language correction,
    /// and the reading whose check digits pass best is kept.
    public func recognize(_ image: CGImage) async throws -> RecognizedPage {
        var textRequest = RecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = [Locale.Language(identifier: "ro-RO"), Locale.Language(identifier: "en-US")]
        textRequest.usesLanguageCorrection = true

        // Language correction "fixes" the machine-readable zone into words, so it gets its own pass without it.
        var literalRequest = RecognizeTextRequest()
        literalRequest.recognitionLevel = .accurate
        literalRequest.usesLanguageCorrection = false

        let corrected = textRequest
        let literalPass = literalRequest
        let text = await Self.attempt("text") { try await corrected.perform(on: image) }
        let literal = await Self.attempt("literal") { try await literalPass.perform(on: image) }
        guard text != nil || literal != nil else { throw RecognitionFailed() }

        var lines = Self.lines(text ?? [])
        let literalLines = TextLayout.arrange(Self.lines(literal ?? []))
        let band = MachineReadableBand.find(in: literalLines)
        // The machine-readable zone keeps its own lines, last and without positions,
        // so it is never read as the value under a printed label.
        var machineReadable = literalLines.filter(MachineReadableBand.looksLikeZone).map { RecognizedLine($0.text) }
        if let band, let cropped = await Self.readBand(band, of: image),
           MachineReadableBand.score(cropped) >= MachineReadableBand.score(machineReadable.map(\.text)) {
            machineReadable = cropped.map { RecognizedLine($0) }
        }
        if text == nil {
            // Without the corrected pass, the literal one is the page's text.
            lines = literalLines
        }
        lines.removeAll { line in
            line.text.contains("<") || (band.map { band in line.box.map { band.contains($0) } ?? false } ?? false)
        }
        lines = TextLayout.arrange(lines) + machineReadable

        let barcodes = (await Self.attempt("barcodes") { try await DetectBarcodesRequest().perform(on: image) })?
            .compactMap { observation -> CaptureBarcode? in
                guard let payload = observation.payloadString, !payload.isEmpty else { return nil }
                return CaptureBarcode(symbology: String(describing: observation.symbology), payload: payload)
            } ?? []

        return RecognizedPage(items: lines, barcodes: barcodes)
    }

    /// The band cropped across the page's width, enlarged so OCR-B characters are large,
    /// and read literally. Nil when the pass fails or finds nothing shaped like the zone.
    private static func readBand(_ band: TextBox, of image: CGImage) async -> [String]? {
        let height = Double(image.height), width = Double(image.width)
        let rect = CGRect(x: 0, y: band.minY * height, width: width, height: band.height * height).integral
        guard rect.height >= 8, let crop = image.cropping(to: rect) else { return nil }
        let enlarged = ImageScaling.scaled(crop, toLongEdge: MachineReadableBand.readingWidth, .up) ?? crop
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        let pass = request
        guard let observations = await attempt("zone", { try await pass.perform(on: enlarged) }) else { return nil }
        let found = TextLayout.arrange(lines(observations)).map(\.text).filter { line in
            MachineReadableBand.looksLikeZone(RecognizedLine(line))
        }
        return found.isEmpty ? nil : found
    }

    /// How long a failed pass waits before its one retry. A pass fails on a cold start,
    /// while Vision loads its model, or while the Neural Engine is busy elsewhere, and
    /// Vision says nothing when it is ready again: there is no event to wait for. A
    /// backoff, not motion, so it lives with the reader and not in `DS.Motion`.
    static let retryPause: Duration = .milliseconds(300)

    /// Runs a pass, retrying once after `pause`. Returns nil when both tries fail.
    /// Cancellation isn't retried. Only the pass name and error code are logged, never content.
    static func attempt<T: Sendable>(_ pass: String, pause: Duration = retryPause, _ work: @Sendable () async throws -> T) async -> T? {
        for attempt in 1...2 {
            do {
                return try await work()
            } catch is CancellationError {
                return nil
            } catch {
                if Task.isCancelled { return nil }
                let code = (error as NSError).code
                let domain = (error as NSError).domain
                CaptureLog.engine.error("Vision \(pass, privacy: .public) pass failed (try \(attempt)): \(domain, privacy: .public) \(code)")
                // Sleeping throws only when the reading is cancelled: no retry then.
                if attempt == 1 { do { try await Task.sleep(for: pause) } catch { return nil } }
            }
        }
        return nil
    }

    /// The best candidate of each observation with its box turned to a top-left origin.
    /// `TextLayout` puts them in reading order.
    static func lines(_ observations: [RecognizedTextObservation]) -> [RecognizedLine] {
        observations.compactMap { observation in
            guard let string = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            // Vision's origin is bottom-left: flip y so a smaller y is higher on the page.
            return RecognizedLine(string, box: TextBox(
                x: Double(box.origin.x), y: Double(1 - box.origin.y - box.height),
                width: Double(box.width), height: Double(box.height)
            ))
        }
    }
}

// MARK: - The machine-readable band

/// Where the machine-readable zone sits on a page: the lines dense with `<` fillers
/// (or long runs of OCR-B capitals and digits) near the bottom. Pure, so it can be tested.
enum MachineReadableBand {

    /// How wide the cropped band is made before it is read, in pixels.
    static let readingWidth = 2400

    /// Whether a line looks like a zone line: fillers, or one long run of capitals and digits.
    static func looksLikeZone(_ line: RecognizedLine) -> Bool {
        let compact = line.text.uppercased().filter { !$0.isWhitespace }
        let fillers = compact.filter { $0 == "<" || $0 == "«" }.count
        if compact.count >= 20, fillers >= 3 || compact.contains("<<") { return true }
        guard compact.count >= 28, let box = line.box, box.midY > 0.5 else { return false }
        return fillers >= 1 && compact.allSatisfy { ($0.isASCII && ($0.isUppercase || $0.isNumber)) || $0 == "<" || $0 == "«" }
    }

    /// The band holding the zone, across the page and padded by a line above and below
    /// (so a line read without fillers is inside it). Nil when no line looks like the zone.
    static func find(in lines: [RecognizedLine]) -> TextBox? {
        let boxes = lines.filter(looksLikeZone).compactMap(\.box)
        guard let first = boxes.first else { return nil }
        let union = boxes.dropFirst().reduce(first) { $0.union($1) }
        let lineHeight = boxes.map(\.height).reduce(0, +) / Double(boxes.count)
        // Two or three lines make a zone; when fewer were seen, look a line further each way.
        let padding = lineHeight * (boxes.count >= 2 ? 0.8 : 1.8)
        let top = max(0, union.minY - padding)
        let bottom = min(1, union.maxY + padding)
        return TextBox(x: 0, y: top, width: 1, height: bottom - top)
    }

    /// How well a set of lines reads as a zone: a parse, then each check digit that passes.
    static func score(_ lines: [String]) -> Int {
        guard let result = MRZParser.parse(text: lines.joined(separator: "\n")) else { return 0 }
        return 1 + result.passingChecks
    }
}

extension TextBox {
    /// Whether another box's centre lies inside this one.
    func contains(_ other: TextBox) -> Bool {
        other.midX >= minX && other.midX <= maxX && other.midY >= minY && other.midY <= maxY
    }
}

// MARK: - Preparing pages

/// A page made ready for reading, and how the same page is shown and shared: the
/// document found in the photo and which way up it goes, as its `PageFraming`. What is
/// read and what is shown are the same cut-out, turned the same way.
public struct PreparedPage: Sendable {
    /// The image to read: the document found, flattened, turned upright and enlarged.
    public let image: CGImage
    /// The page as it is kept: the corners found in the photo as taken, and the turn.
    public let framing: PageFraming

    public init(image: CGImage, framing: PageFraming = .plain) {
        self.image = image
        self.framing = framing
    }
}

/// Gets a photographed page ready for reading. A protocol so the engine's retry can be
/// tested without Vision.
public protocol CapturePagePreparing: Sendable {
    /// The page to read, with how it is shown: the document found, flattened, turned upright and enlarged.
    func prepare(_ image: CGImage) async -> PreparedPage
    /// Another way to read the same page, when the first read found little: a quarter
    /// turn of the prepared page, or the photo as taken. Nil when none reads better.
    /// Its framing says how the page is shown when this reading is kept.
    func retryVariant(of prepared: PreparedPage, original: CGImage) async -> PreparedPage?
}

/// Finds the document in a photo and flattens it, so a card photographed at an angle
/// on a table reads like a scan. The one path every photo takes before it is read.
///
/// 1. **Find it.** Rectangles shaped like an ID-1 card (about 1.586 : 1) or a passport
///    data page (about 1.42 : 1); Vision's document segmentation when none is found, or
///    when the rectangle is only a box printed on a larger page.
/// 2. **Flatten it** with a perspective correction.
/// 3. **Turn it upright:** cards and passport pages are landscape, so a card that comes
///    out portrait is turned the way more text reads.
/// 4. **Enlarge it** when the card was small in the photo, so small print is legible.
///
/// The photo as taken is what is kept. The corners found and the turn are kept with it as the
/// page's `PageFraming`, so the page is shown and shared as it was read (`DocumentPicture`).
public struct DocumentImageNormalizer: CapturePagePreparing {

    public init() {}

    /// Card shapes as Vision measures them: the short side over the long side.
    static let cardAspect: ClosedRange<Float> = 0.55...0.80
    /// The ID-1 card (85.6 × 54 mm) and the passport data page (125 × 88 mm).
    static let targetAspects: [Double] = [1 / 1.586, 1 / 1.42]
    /// The long edge a prepared page is enlarged to, at most three times its size.
    static let readableLongEdge = 2000

    public func prepare(_ image: CGImage) async -> PreparedPage {
        let size = CGSize(width: image.width, height: image.height)
        let card = await Self.cardRectangle(in: image)
        let document = await Self.documentQuad(in: image)
        let corners: [CGPoint]?
        let isCard: Bool
        switch (card, document) {
        case let (card?, document?):
            // A box printed on a page (a table on an invoice) isn't the document.
            let pageIsLarger = Self.area(document) > 1.6 * Self.area(card)
            corners = pageIsLarger ? document : card
            isCard = !pageIsLarger
        case let (card?, nil):
            corners = card
            isCard = true
        case let (nil, document?):
            corners = document
            isCard = false
        case (nil, nil):
            corners = nil
            isCard = false
        }
        let flattened = corners.flatMap { ImageScaling.flattened(image, corners: $0) }
        // The corners are kept only when the document was cut out: what is read is what is shown.
        let crop = flattened == nil ? nil : corners.flatMap { DocumentPicture.pagePoints($0, width: image.width, height: image.height) }
        var page = PreparedPage(image: flattened ?? image, framing: PageFraming(crop: crop))
        if isCard, page.image.height > page.image.width {
            // A quarter turn either way; the one where more text reads is upright.
            let flat = page
            page = await Self.mostReadable([3, 1].compactMap { Self.turning(flat, by: $0) }) ?? flat
        }
        CaptureLog.engine.info("Prepared page: card \(isCard), corrected \(crop != nil), turned \(page.framing.quarterTurns), \(Int(size.width))×\(Int(size.height)) → \(page.image.width)×\(page.image.height)")
        return PreparedPage(image: ImageScaling.scaled(page.image, toLongEdge: Self.readableLongEdge, .up) ?? page.image, framing: page.framing)
    }

    public func retryVariant(of prepared: PreparedPage, original: CGImage) async -> PreparedPage? {
        var candidates = [1, 2, 3].compactMap { Self.turning(prepared, by: $0) }
        if original.width != prepared.image.width || original.height != prepared.image.height {
            // The photo as taken: the cut-out may have missed the document, so the whole photo is shown.
            var whole = prepared.framing
            whole.prefersWholePhoto = true
            whole.quarterTurns = 0
            candidates.append(PreparedPage(image: ImageScaling.scaled(original, toLongEdge: Self.readableLongEdge, .up) ?? original, framing: whole))
        }
        let baseline = await Self.readability(of: prepared.image)
        guard let best = await Self.mostReadable(candidates) else { return nil }
        let score = await Self.readability(of: best.image)
        CaptureLog.engine.info("Retry variant reads \(score) characters against \(baseline)")
        return score > baseline + max(10, baseline / 5) ? best : nil
    }

    /// The page turned `turns` more quarter turns clockwise, read and shown alike (a guess, never the person's turn).
    static func turning(_ page: PreparedPage, by turns: Int) -> PreparedPage? {
        guard let image = DocumentPicture.turned(page.image, quarterTurns: turns) else { return nil }
        var framing = page.framing
        framing.quarterTurns = PageFraming.normalized(framing.quarterTurns + turns)
        return PreparedPage(image: image, framing: framing)
    }

    // MARK: Finding the document

    /// The most card-like rectangle covering enough of the photo, as image-space corners
    /// (top-left, top-right, bottom-right, bottom-left), or nil.
    static func cardRectangle(in image: CGImage) async -> [CGPoint]? {
        var request = DetectRectanglesRequest()
        request.minimumAspectRatio = cardAspect.lowerBound
        request.maximumAspectRatio = cardAspect.upperBound
        request.quadratureToleranceDegrees = 25
        request.minimumSize = 0.25
        request.minimumConfidence = 0.6
        request.maximumObservations = 6
        let pass = request
        guard let rectangles = await VisionCaptureRecognizer.attempt("rectangles", { try await pass.perform(on: image) }) else { return nil }
        let size = CGSize(width: image.width, height: image.height)
        let candidates = rectangles.map { rectangle in
            [rectangle.topLeft, rectangle.topRight, rectangle.bottomRight, rectangle.bottomLeft]
                .map { $0.toImageCoordinates(size, origin: .lowerLeft) }
        }
        return bestCard(candidates, imageSize: size)
    }

    /// Of several quadrilaterals, the one that is largest and closest to a card's shape,
    /// ignoring any under 8% of the photo. Pure, so it can be tested.
    static func bestCard(_ quads: [[CGPoint]], imageSize: CGSize) -> [CGPoint]? {
        let photo = Double(imageSize.width * imageSize.height)
        guard photo > 0 else { return nil }
        return quads
            .map { quad -> (quad: [CGPoint], score: Double) in
                let share = area(quad) / photo
                let ratio = aspect(quad)
                let closeness = targetAspects.map { 1 - min(1, abs(ratio - $0) / 0.15) }.max() ?? 0
                return (quad, share >= 0.08 ? share * (0.5 + closeness) : 0)
            }
            .filter { $0.score > 0 }
            .max { $0.score < $1.score }?.quad
    }

    /// The page Vision's document segmentation finds, when it is sure and covers enough of the photo.
    static func documentQuad(in image: CGImage) async -> [CGPoint]? {
        guard let detected = await VisionCaptureRecognizer.attempt("document", { try await DetectDocumentSegmentationRequest().perform(on: image) }),
              let found = detected, found.confidence >= 0.6 else { return nil }
        let size = CGSize(width: image.width, height: image.height)
        let corners = [found.topLeft, found.topRight, found.bottomRight, found.bottomLeft]
            .map { $0.toImageCoordinates(size, origin: .lowerLeft) }
        // Ignore tiny detections: a business card on a desk shouldn't crop an invoice photo.
        return area(corners) >= 0.2 * Double(size.width * size.height) ? corners : nil
    }

    /// Shoelace formula for the area of a quadrilateral.
    static func area(_ points: [CGPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            sum += points[index].x * next.y - next.x * points[index].y
        }
        return Double(abs(sum) / 2)
    }

    /// Short side over long side, from the average of opposite edges.
    static func aspect(_ quad: [CGPoint]) -> Double {
        guard quad.count == 4 else { return 0 }
        func length(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(a.x - b.x, a.y - b.y)) }
        let horizontal = (length(quad[0], quad[1]) + length(quad[3], quad[2])) / 2
        let vertical = (length(quad[0], quad[3]) + length(quad[1], quad[2])) / 2
        let long = max(horizontal, vertical)
        return long > 0 ? min(horizontal, vertical) / long : 0
    }

    // MARK: Which way up

    /// The candidate where a quick read finds the most characters.
    static func mostReadable(_ candidates: [PreparedPage]) async -> PreparedPage? {
        var best: (page: PreparedPage, score: Int)?
        for candidate in candidates {
            let score = await readability(of: candidate.image)
            if score > (best?.score ?? -1) { best = (candidate, score) }
        }
        return best?.page
    }

    /// Letters and digits a fast, literal read finds: a cheap measure of which way is up.
    static func readability(of image: CGImage) async -> Int {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let pass = request
        guard let observations = await VisionCaptureRecognizer.attempt("orientation", { try await pass.perform(on: image) }) else { return 0 }
        return observations.reduce(0) { total, observation in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.3 else { return total }
            return total + candidate.string.filter { $0.isLetter || $0.isNumber }.count
        }
    }
}
