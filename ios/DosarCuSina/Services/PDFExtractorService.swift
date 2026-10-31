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

public enum PDFExtractorService {
    /// Extracts plain text from a digital PDF file (e.g. email attachments, utility downloads)
    public static func extractText(from pdfData: Data, sourceFileName: String? = nil) -> ExtractedMediaContent {
        guard let document = PDFDocument(data: pdfData) else {
            return ExtractedMediaContent(text: "", rawData: pdfData, sourceFileName: sourceFileName, isPDF: true, pageCount: 0)
        }
        
        var fullText = ""
        let count = document.pageCount
        for i in 0..<count {
            if let page = document.page(at: i), let pageString = page.string {
                fullText += pageString + "\n"
            }
        }
        
        return ExtractedMediaContent(
            text: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
            rawData: pdfData,
            sourceFileName: sourceFileName,
            isPDF: true,
            pageCount: count
        )
    }
    
    /// Renders the first page of a PDF as a thumbnail UIImage
    #if canImport(UIKit)
    public static func generateThumbnail(from pdfData: Data, targetSize: CGSize = CGSize(width: 200, height: 260)) -> UIImage? {
        guard let document = PDFDocument(data: pdfData),
              let page = document.page(at: 0) else { return nil }
        return page.thumbnail(of: targetSize, for: .cropBox)
    }
    #endif
}
