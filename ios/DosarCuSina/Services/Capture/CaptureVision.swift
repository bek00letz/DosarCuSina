import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
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

    public func recognize(_ image: CGImage) async throws -> RecognizedPage {
        var textRequest = RecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = [Locale.Language(identifier: "ro-RO"), Locale.Language(identifier: "en-US")]
        textRequest.usesLanguageCorrection = true

        // Language correction "fixes" the machine-readable zone into words, so it gets its own pass without it.
        var literalRequest = RecognizeTextRequest()
        literalRequest.recognitionLevel = .accurate
        literalRequest.usesLanguageCorrection = false

        let barcodeRequest = DetectBarcodesRequest()

        async let textObservations = textRequest.perform(on: image)
        async let literalObservations = literalRequest.perform(on: image)
        async let barcodeObservations = barcodeRequest.perform(on: image)

        var lines = Self.readingOrder(try await textObservations)
        let machineReadable = Self.readingOrder(try await literalObservations).filter { $0.filter { $0 == "<" }.count >= 2 }
        lines.removeAll { $0.contains("<") }
        lines.append(contentsOf: machineReadable)

        let barcodes = (try? await barcodeObservations)?.compactMap { observation -> CaptureBarcode? in
            guard let payload = observation.payloadString, !payload.isEmpty else { return nil }
            return CaptureBarcode(symbology: String(describing: observation.symbology), payload: payload)
        } ?? []

        return RecognizedPage(lines: lines, barcodes: barcodes)
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
