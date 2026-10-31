import Foundation
import Vision
#if canImport(UIKit)
import UIKit
#endif

public struct LocalOCRScanResult: Sendable {
    public let rawText: String
    public let detectedDates: [Date]
    public let detectedAmounts: [Double]
    public let detectedCurrencies: [String]
    public let candidateDueDate: Date?
    public let candidateTotal: Double?
}

public final class LocalOCRService: Sendable {
    public static let shared = LocalOCRService()
    
    private init() {}
    
    #if canImport(UIKit)
    /// Performs fast, on-device OCR recognition on a CGImage/UIImage
    public func scanImage(_ image: UIImage) async throws -> LocalOCRScanResult {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "LocalOCRService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid image format"])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: LocalOCRScanResult(
                        rawText: "",
                        detectedDates: [],
                        detectedAmounts: [],
                        detectedCurrencies: [],
                        candidateDueDate: nil,
                        candidateTotal: nil
                    ))
                    return
                }
                
                let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
                let fullText = recognizedStrings.joined(separator: "\n")
                
                let result = self.parseExtractedText(fullText)
                continuation.resume(returning: result)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ro-RO", "en-US"]
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    #endif
    
    /// Parses dates and monetary amounts using regex patterns from Romanian invoices
    public func parseExtractedText(_ text: String) -> LocalOCRScanResult {
        let dates = extractDates(from: text)
        let amounts = extractAmounts(from: text)
        
        // Find best candidate for due date (usually the latest date found in the document)
        let candidateDue = dates.sorted(by: >).first
        
        // Find best candidate for total (highest detected amount, often labeled near Total/Plata)
        let candidateTotal = amounts.sorted(by: >).first
        
        return LocalOCRScanResult(
            rawText: text,
            detectedDates: dates,
            detectedAmounts: amounts,
            detectedCurrencies: ["RON"],
            candidateDueDate: candidateDue,
            candidateTotal: candidateTotal
        )
    }
    
    private func extractDates(from text: String) -> [Date] {
        var foundDates: [Date] = []
        // Pattern: DD.MM.YYYY, DD/MM/YYYY, DD-MM-YYYY
        let datePattern = #"\b(0?[1-9]|[12][0-9]|3[01])[./-](0?[1-9]|1[0-2])[./-](20\d\d)\b"#
        
        if let regex = try? NSRegularExpression(pattern: datePattern) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM.yyyy"
            
            for match in matches {
                let dateStr = nsString.substring(with: match.range)
                    .replacingOccurrences(of: "/", with: ".")
                    .replacingOccurrences(of: "-", with: ".")
                if let date = formatter.date(from: dateStr) {
                    foundDates.append(date)
                }
            }
        }
        return foundDates
    }
    
    private func extractAmounts(from text: String) -> [Double] {
        var foundAmounts: [Double] = []
        // Pattern: 1.234,56 or 1234.56 or 123,45
        let amountPattern = #"\b\d{1,4}([.,]\d{3})*([.,]\d{2})\b"#
        
        if let regex = try? NSRegularExpression(pattern: amountPattern) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                var amountStr = nsString.substring(with: match.range)
                // Normalize Romanian formatting (e.g. "1.450,50" -> "1450.50")
                if amountStr.contains(",") && amountStr.contains(".") {
                    amountStr = amountStr.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                } else if amountStr.contains(",") {
                    amountStr = amountStr.replacingOccurrences(of: ",", with: ".")
                }
                
                if let val = Double(amountStr), val > 0 && val < 500000 {
                    foundAmounts.append(val)
                }
            }
        }
        return foundAmounts
    }
}
