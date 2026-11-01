import Foundation
import PDFKit
#if canImport(UIKit)
import UIKit
#endif

public struct ExtractedMediaContent: Sendable {
    public let text: String
    public let rawData: Data?
    public let sourceFileName: String?
    public let isPDF: Bool
    public let pageCount: Int
}

public struct ParsedDocumentResult: Sendable {
    public let title: String?
    public let provider: String?
    public let invoiceNumber: String?
    public let dueDate: Date?
    public let amount: Double?
    public let extractedText: String
}

public final class PDFExtractorService: Sendable {
    public static let shared = PDFExtractorService()
    
    public init() {}
    
    /// Extracts plain text from a digital PDF file (e.g. email attachments, utility downloads).
    /// Clamps maximum pages to 25 to prevent memory exhaustion and UI thread freezes.
    public static func extractText(from pdfData: Data, sourceFileName: String? = nil) -> ExtractedMediaContent {
        guard let document = PDFDocument(data: pdfData) else {
            return ExtractedMediaContent(text: "", rawData: pdfData, sourceFileName: sourceFileName, isPDF: true, pageCount: 0)
        }
        
        var fullText = ""
        let totalPages = document.pageCount
        let maxPagesToScan = min(totalPages, 25)
        for i in 0..<maxPagesToScan {
            if let page = document.page(at: i), let pageString = page.string {
                fullText += pageString + "\n"
            }
        }
        
        return ExtractedMediaContent(
            text: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
            rawData: pdfData,
            sourceFileName: sourceFileName,
            isPDF: true,
            pageCount: totalPages
        )
    }
    
    /// Extracts text and parses utility/invoice metadata using `RomanianUtilityParser`.
    public func extractAndParse(pdfData: Data, fileName: String? = nil) -> ParsedDocumentResult {
        let extracted = Self.extractText(from: pdfData, sourceFileName: fileName)
        let parsedUtility = RomanianUtilityParser.shared.parseUtilityBill(text: extracted.text)
        
        let title: String?
        if parsedUtility.provider != .general {
            title = "Factură \(parsedUtility.provider.displayName)"
        } else if let fn = fileName {
            title = fn.replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
        } else {
            title = nil
        }
        
        let providerName = parsedUtility.provider != .general ? parsedUtility.provider.displayName : nil
        
        return ParsedDocumentResult(
            title: title,
            provider: providerName,
            invoiceNumber: parsedUtility.invoiceNumber,
            dueDate: parsedUtility.dueDate,
            amount: parsedUtility.totalAmount,
            extractedText: extracted.text
        )
    }
    
    /// Renders the first page of a PDF as a thumbnail UIImage
    #if canImport(UIKit)
    public static func generateThumbnail(from pdfData: Data, targetSize: CGSize = CGSize(width: 200, height: 260)) -> UIImage? {
        guard let document = PDFDocument(data: pdfData),
              document.pageCount > 0,
              let page = document.page(at: 0) else { return nil }
        return page.thumbnail(of: targetSize, for: .cropBox)
    }
    #endif
}
