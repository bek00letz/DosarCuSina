// SCRATCH: never commit. Measures reading of a local sample outside the repository.
import CoreGraphics
import Foundation
import Testing
@testable import DosarCuSina

@Suite("Scratch measure")
struct ScratchMeasure {
    struct NoText: CaptureRecognizing {
        func recognize(_ image: CGImage) async throws -> RecognizedPage { RecognizedPage(lines: [], barcodes: []) }
    }

    @Test func measure() async throws {
        let folder = URL(fileURLWithPath: "/private/tmp/pad-measure")
        let config = try String(contentsOf: folder.appendingPathComponent("input-after.txt"), encoding: .utf8)
            .components(separatedBy: .newlines).filter { !$0.isEmpty }
        let label = "after"
        var out = ""
        for path in config {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: NoText(), normalizer: nil, onDeviceModel: nil, cloudModel: nil, store: nil)
            let request = CaptureRequest(path.hasSuffix(".pdf") ? .pdf(data) : .text(String(decoding: data, as: UTF8.self)), options: CaptureOptions(useOnDeviceModel: false, storeDocument: false))
            let result = try await engine.capture(request)
            out += "=== \(URL(fileURLWithPath: path).lastPathComponent.prefix(6))\n"
            out += "kind: \(result.kind) \(result.kindConfidence)\n"
            for field in result.fields {
                out += "\(field.key.rawValue): \(field.value) [\(field.confidence)]\n"
            }
            out += "suggestions: \(result.suggestions.map { "\($0.destination)" })\n"
            out += "--- text\n\(result.recognizedText)\n"
        }
        try out.write(to: folder.appendingPathComponent("out-\(label).txt"), atomically: true, encoding: .utf8)
    }
}
