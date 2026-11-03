import Foundation
import PDFKit

public struct ExtractedMediaContent: Sendable {
    public let text: String
    public let rawData: Data?
    public let sourceFileName: String?
    public let isPDF: Bool
    public let pageCount: Int
}

public final class PDFExtractorService: Sendable {
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
}
