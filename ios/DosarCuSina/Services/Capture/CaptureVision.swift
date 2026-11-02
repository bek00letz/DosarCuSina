import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import OSLog
import Vision

/// The text and codes recognized on one page.
public struct RecognizedPage: Sendable, Hashable {
    /// Lines in reading order, top to bottom.
    public let lines: [String]
    public let barcodes: [CaptureBarcode]

    public init(lines: [String], barcodes: [CaptureBarcode]) {
        self.lines = lines
        self.barcodes = barcodes
    }

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

        var lines = Self.readingOrder(text ?? [])
        let literalLines = Self.readingOrder(literal ?? [])
        let machineReadable = literalLines.filter { $0.filter { $0 == "<" }.count >= 2 }
        if text == nil {
            // Without the corrected pass, the literal one is the page's text.
            lines = literalLines.filter { !$0.contains("<") }
        }
        lines.removeAll { $0.contains("<") }
        lines.append(contentsOf: machineReadable)

        let barcodes = (await Self.attempt("barcodes") { try await DetectBarcodesRequest().perform(on: image) })?
            .compactMap { observation -> CaptureBarcode? in
                guard let payload = observation.payloadString, !payload.isEmpty else { return nil }
                return CaptureBarcode(symbology: String(describing: observation.symbology), payload: payload)
            } ?? []

        return RecognizedPage(lines: lines, barcodes: barcodes)
    }

    /// Runs a pass, retrying once after a short pause. Returns nil when both tries fail.
    /// Cancellation isn't retried. Only the pass name and error code are logged, never content.
    private static func attempt<T: Sendable>(_ pass: String, _ work: @Sendable () async throws -> T) async -> T? {
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
                if attempt == 1 { try? await Task.sleep(for: .milliseconds(300)) }
            }
        }
        return nil
    }

    /// Sorts observations top to bottom, then left to right, and keeps the best candidate of each.
    static func readingOrder(_ observations: [RecognizedTextObservation]) -> [String] {
        observations
            .sorted { lhs, rhs in
                let (a, b) = (lhs.boundingBox, rhs.boundingBox)
                // Vision's origin is bottom-left: a higher y is higher on the page.
                if abs(a.origin.y - b.origin.y) > min(a.height, b.height) / 2 { return a.origin.y > b.origin.y }
                return a.origin.x < b.origin.x
            }
            .compactMap { $0.topCandidates(1).first?.string }
    }
}

/// Finds the document in a photo and flattens it, so a page photographed at an angle reads like a scan.
public struct DocumentImageNormalizer: Sendable {

    public init() {}

    /// Returns a perspective-corrected image when a document fills enough of the frame, otherwise the input.
    public func normalize(_ image: CGImage) async -> CGImage {
        guard let detected = try? await DetectDocumentSegmentationRequest().perform(on: image),
              detected.confidence >= 0.6 else { return image }

        let size = CGSize(width: image.width, height: image.height)
        let corners = [detected.topLeft, detected.topRight, detected.bottomRight, detected.bottomLeft]
            .map { $0.toImageCoordinates(size, origin: .lowerLeft) }
        // Ignore tiny detections: a business card on a desk shouldn't crop an invoice photo.
        let area = Self.polygonArea(corners)
        guard area >= 0.2 * size.width * size.height else { return image }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: image)
        filter.topLeft = corners[0]
        filter.topRight = corners[1]
        filter.bottomRight = corners[2]
        filter.bottomLeft = corners[3]
        guard let output = filter.outputImage else { return image }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(output, from: output.extent) ?? image
    }

    /// Shoelace formula for the area of the detected quadrilateral.
    static func polygonArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            sum += points[index].x * next.y - next.x * points[index].y
        }
        return abs(sum) / 2
    }
}
