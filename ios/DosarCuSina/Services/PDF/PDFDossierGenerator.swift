import Foundation
import PDFKit
import CoreGraphics
#if canImport(CoreText)
import CoreText
#endif
#if canImport(UIKit)
import UIKit
#endif
import SwiftData

// MARK: - Opis Entry Model

/// Represents a single cataloged document in the official Romanian *Opis Documente*
/// (Table of Contents / Borderou) conforming to Romanian administrative dossier standards.
public struct OpisEntry: Identifiable, Sendable {
    public let id: UUID
    public let index: Int
    public let title: String
    public let assetName: String
    public let categoryOrDomain: String
    public let issuerOrProvider: String
    public let expiryOrDueDate: Date?
    public let expiryText: String
    public var targetPageStart: Int
    public var targetPageCount: Int
    public let statusText: String
    public let statusColorHex: String
    public let attachmentId: UUID?
    
    public var pageDisplay: String {
        if targetPageCount > 1 {
            return "p. \(targetPageStart)–\(targetPageStart + targetPageCount - 1)"
        } else if targetPageStart > 0 {
            return "p. \(targetPageStart)"
        } else {
            return "—"
        }
    }
    
    public init(
        id: UUID = UUID(),
        index: Int,
        title: String,
        assetName: String,
        categoryOrDomain: String,
        issuerOrProvider: String,
        expiryOrDueDate: Date? = nil,
        expiryText: String = "Permanent / Nedeterminată",
        targetPageStart: Int = 0,
        targetPageCount: Int = 1,
        statusText: String = "Valabil",
        statusColorHex: String = "#34C759",
        attachmentId: UUID? = nil
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.assetName = assetName
        self.categoryOrDomain = categoryOrDomain
        self.issuerOrProvider = issuerOrProvider
        self.expiryOrDueDate = expiryOrDueDate
        self.expiryText = expiryText
        self.targetPageStart = targetPageStart
        self.targetPageCount = targetPageCount
        self.statusText = statusText
        self.statusColorHex = statusColorHex
        self.attachmentId = attachmentId
    }
}

// MARK: - PDF Dossier Generator

/// Production PDF generator creating an Apple-polished "Dosar cu Șină"
/// conforming to Apple Craftsmanship & Polish Standards and Romanian Administrative Guidelines.
/// Includes *Opis Documente* Table of Contents, full household aggregation,
/// non-truncated multi-page PDF appendices, and page-numbered cross-referencing.
public final class PDFDossierGenerator: Sendable {
    public static let shared = PDFDossierGenerator()
    
    // Standard A4 dimensions in typographic points (72 points / inch)
    public static let pageA4Width: CGFloat = 595.2
    public static let pageA4Height: CGFloat = 841.8
    public static let pageMargin: CGFloat = 36.0
    
    public init() {}
    
    // MARK: - Opis Indexing Engine
    
    /// Collects and builds sorted Opis entries for a single asset and all its child events and records.
    public func buildOpisEntries(for asset: Asset) -> [OpisEntry] {
        return buildOpisEntries(for: [asset])
    }
    
    /// Collects and builds a unified, sequentially numbered Opis Documente for an entire household.
    public func buildOpisEntries(for assets: [Asset]) -> [OpisEntry] {
        var entries: [OpisEntry] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        var currentIndex = 1
        var seenAttachmentIds: Set<UUID> = []
        
        let sortedAssets = assets.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        
        for asset in sortedAssets {
            // 1. Direct Asset Attachments
            for att in asset.attachments where !seenAttachmentIds.contains(att.id) && att.fileData != nil {
                seenAttachmentIds.insert(att.id)
                let title = att.fileName.isEmpty ? "Document Bun: \(asset.name)" : att.fileName
                let issuer = asset.retailerOrIssuer ?? "—"
                let expiryDate = asset.purchaseOrIssueDate
                let expiryStr = expiryDate != nil ? dateFormatter.string(from: expiryDate!) : "Permanent"
                
                let (statusText, statusHex) = statusForAsset(asset)
                let pageCount = Self.pageCount(for: att)
                
                entries.append(OpisEntry(
                    id: UUID(),
                    index: currentIndex,
                    title: title,
                    assetName: asset.name,
                    categoryOrDomain: asset.category.title,
                    issuerOrProvider: issuer,
                    expiryOrDueDate: expiryDate,
                    expiryText: expiryStr,
                    targetPageStart: 0,
                    targetPageCount: pageCount,
                    statusText: statusText,
                    statusColorHex: statusHex,
                    attachmentId: att.id
                ))
                currentIndex += 1
            }
            
            // 2. Lifecycle Event Attachments
            let sortedEvents = asset.events.sorted(by: { $0.dueDate < $1.dueDate })
            for event in sortedEvents {
                for att in event.attachments where !seenAttachmentIds.contains(att.id) && att.fileData != nil {
                    seenAttachmentIds.insert(att.id)
                    let title = "\(event.title) — \(att.fileName)"
                    let issuer = event.provider ?? asset.retailerOrIssuer ?? "—"
                    let expiryStr = dateFormatter.string(from: event.dueDate)
                    
                    let (statusText, statusHex) = statusForEvent(event)
                    let pageCount = Self.pageCount(for: att)
                    
                    entries.append(OpisEntry(
                        id: UUID(),
                        index: currentIndex,
                        title: title,
                        assetName: asset.name,
                        categoryOrDomain: asset.category.title,
                        issuerOrProvider: issuer,
                        expiryOrDueDate: event.dueDate,
                        expiryText: expiryStr,
                        targetPageStart: 0,
                        targetPageCount: pageCount,
                        statusText: statusText,
                        statusColorHex: statusHex,
                        attachmentId: att.id
                    ))
                    currentIndex += 1
                }
            }
        }
        
        return entries
    }
    
    private func statusForEvent(_ event: LifecycleEvent) -> (text: String, hex: String) {
        if event.isCompleted {
            return ("Rezolvat", "#34C759")
        }
        let now = Date()
        if event.dueDate < now {
            return ("Expirat", "#FF3B30")
        }
        let daysUntil = Calendar.current.dateComponents([.day], from: now, to: event.dueDate).day ?? 0
        if daysUntil <= 7 {
            return ("Urgent", "#FF9500")
        }
        return ("Valabil", "#34C759")
    }
    
    private func statusForAsset(_ asset: Asset) -> (text: String, hex: String) {
        return ("Activ", "#007AFF")
    }
    
    // MARK: - Public API
    
    /// Generates a complete, multi-page PDF document for a single asset including Opis, specs, and appendices.
    public func generateDossier(for asset: Asset) -> Data {
        return generateHouseholdDossier(for: [asset], title: "Dosar Complet: \(asset.name)")
    }
    
    /// Generates a complete, multi-page household-wide PDF document including Opis, all assets, and non-truncated appendices.
    public func generateHouseholdDossier(
        for assets: [Asset],
        title: String = "Dosar Administrativ al Gospodăriei"
    ) -> Data {
        #if canImport(UIKit)
        return generateUIKitPDF(for: assets, title: title)
        #else
        return generateCoreGraphicsPDF(for: assets, title: title)
        #endif
    }
    
    /// Generates the dossier and saves it directly to a temporary file URL, suitable for `ShareLink`.
    public func generateDossierFile(
        for asset: Asset,
        in directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        return try generateHouseholdDossierFile(
            for: [asset],
            title: "Dosar Complet: \(asset.name)",
            in: directory
        )
    }
    
    /// Generates the household dossier and saves it directly to a file URL.
    public func generateHouseholdDossierFile(
        for assets: [Asset],
        title: String = "Dosar Administrativ al Gospodăriei",
        in directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let pdfData = generateHouseholdDossier(for: assets, title: title)
        let sanitizedName = title
            .folding(options: .diacriticInsensitive, locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        let safeBase = sanitizedName.isEmpty ? "Dosar_Gospodarie" : sanitizedName
        let fileName = "\(safeBase)_\(Int(Date().timeIntervalSince1970)).pdf"
        let fileURL = directory.standardizedFileURL.appendingPathComponent(fileName)
        try pdfData.write(to: fileURL, options: .atomic)
        return fileURL
    }
    
    // MARK: - Multi-Page Page Count Helper
    
    public static func pageCount(for attachment: DocumentAttachment) -> Int {
        guard let data = attachment.fileData, !data.isEmpty else { return 1 }
        if let pdfDoc = PDFDocument(data: data), pdfDoc.pageCount > 0 {
            return pdfDoc.pageCount
        }
        return 1
    }
    
    // MARK: - UIKit High-Craft Rendering (iOS Target)
    
    #if canImport(UIKit)
    private func generateUIKitPDF(for assets: [Asset], title: String) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: Self.pageA4Width, height: Self.pageA4Height)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        // 1. Gather all unique attachments in order
        var allAttachments: [DocumentAttachment] = []
        var seenAttachmentIds: Set<UUID> = []
        
        for asset in assets {
            for att in asset.attachments where !seenAttachmentIds.contains(att.id) && att.fileData != nil {
                seenAttachmentIds.insert(att.id)
                allAttachments.append(att)
            }
            for event in asset.events {
                for att in event.attachments where !seenAttachmentIds.contains(att.id) && att.fileData != nil {
                    seenAttachmentIds.insert(att.id)
                    allAttachments.append(att)
                }
            }
        }
        
        // 2. Build Opis entries
        var opisEntries = buildOpisEntries(for: assets)
        
        // 3. Pre-calculate layout & page numbers for cross-referencing
        // Estimate number of Opis pages: Cover header + household card takes ~170 pt on page 1.
        // Each Opis row takes 22 pt. Header takes 24 pt.
        let page1AvailableOpisHeight = pageRect.height - Self.pageMargin - 190 - 30
        let page1OpisCapacity = max(1, Int(page1AvailableOpisHeight / 22.0))
        let remainingOpisEntries = max(0, opisEntries.count - page1OpisCapacity)
        let subsequentOpisCapacity = max(1, Int((pageRect.height - (Self.pageMargin * 2) - 60) / 22.0))
        let additionalOpisPages = remainingOpisEntries > 0 ? Int(ceil(Double(remainingOpisEntries) / Double(subsequentOpisCapacity))) : 0
        let totalOpisPages = 1 + additionalOpisPages
        
        // Estimate asset overview pages: 1 page per asset (or combined if 1 asset)
        let assetOverviewPages = assets.count
        let appendixStartPage = totalOpisPages + assetOverviewPages + 1
        
        // Assign exact target pages to Opis entries
        var runningAppendixPage = appendixStartPage
        for i in 0..<opisEntries.count {
            opisEntries[i].targetPageStart = runningAppendixPage
            runningAppendixPage += opisEntries[i].targetPageCount
        }
        
        // 4. Render PDF
        return renderer.pdfData { context in
            var currentPageNumber = 1
            
            // --- PAGE 1: Header, Household Summary, and Opis Table ---
            context.beginPage()
            var currentY = Self.pageMargin
            
            drawRunningHeader(in: pageRect, currentY: &currentY, assetName: title)
            drawHouseholdSummaryCard(for: assets, title: title, in: pageRect, currentY: &currentY)
            
            // Draw Opis Documente Table (with multi-page overflow)
            drawOpisSection(
                entries: opisEntries,
                in: pageRect,
                context: context,
                currentY: &currentY,
                currentPage: &currentPageNumber,
                headerTitle: title
            )
            
            drawRunningFooter(in: pageRect, pageNumber: currentPageNumber)
            
            // --- ASSET DETAIL PAGES ---
            for asset in assets {
                currentPageNumber += 1
                context.beginPage()
                var assetY = Self.pageMargin
                drawRunningHeader(in: pageRect, currentY: &assetY, assetName: "\(asset.name) (\(asset.category.title))")
                drawAssetSummaryCard(for: asset, in: pageRect, currentY: &assetY)
                
                if !asset.dynamicFields.isEmpty {
                    drawDynamicFieldsCard(for: asset.dynamicFields, in: pageRect, currentY: &assetY)
                }
                
                let sortedEvents = asset.events.sorted(by: { $0.dueDate < $1.dueDate })
                if !sortedEvents.isEmpty {
                    drawEventsSection(
                        events: sortedEvents,
                        in: pageRect,
                        context: context,
                        currentY: &assetY,
                        currentPage: &currentPageNumber,
                        assetName: asset.name
                    )
                }
                drawRunningFooter(in: pageRect, pageNumber: currentPageNumber)
            }
            
            // --- APPENDIX PAGES (Non-truncated Multi-Page Rendering) ---
            for (attIndex, attachment) in allAttachments.enumerated() {
                autoreleasepool {
                    let matchingOpis = opisEntries.first(where: { $0.attachmentId == attachment.id })
                    let attTitle = matchingOpis?.title ?? attachment.fileName
                    let parentName = matchingOpis?.assetName ?? "Activ"
                    
                    guard let fileData = attachment.fileData, !fileData.isEmpty else {
                        currentPageNumber += 1
                        context.beginPage()
                        var y = Self.pageMargin
                        drawRunningHeader(in: pageRect, currentY: &y, assetName: parentName)
                        drawAppendixHeaderCard(title: attTitle, index: attIndex + 1, pageInfo: "1 din 1", in: pageRect, currentY: &y)
                        drawNoDataPlaceholder(in: CGRect(x: Self.pageMargin, y: y, width: pageRect.width - Self.pageMargin * 2, height: 400))
                        drawRunningFooter(in: pageRect, pageNumber: currentPageNumber)
                        return
                    }
                    
                    // Check if PDF
                    if let pdfDoc = PDFDocument(data: fileData), pdfDoc.pageCount > 0 {
                        let totalPDFPages = pdfDoc.pageCount
                        for pageIdx in 0..<totalPDFPages {
                            currentPageNumber += 1
                            context.beginPage()
                            var y = Self.pageMargin
                            drawRunningHeader(in: pageRect, currentY: &y, assetName: parentName)
                            
                            let pageInfo = "Pagina \(pageIdx + 1) din \(totalPDFPages)"
                            drawAppendixHeaderCard(
                                title: "\(attTitle)",
                                index: attIndex + 1,
                                pageInfo: pageInfo,
                                in: pageRect,
                                currentY: &y
                            )
                            
                            if let pdfPage = pdfDoc.page(at: pageIdx) {
                                let availableHeight = pageRect.height - y - Self.pageMargin - 20
                                let box = CGRect(x: Self.pageMargin, y: y, width: pageRect.width - Self.pageMargin * 2, height: availableHeight)
                                drawPDFAttachment(page: pdfPage, in: box)
                            }
                            drawRunningFooter(in: pageRect, pageNumber: currentPageNumber)
                        }
                    } else if let image = UIImage(data: fileData) {
                        // Render full page image
                        currentPageNumber += 1
                        context.beginPage()
                        var y = Self.pageMargin
                        drawRunningHeader(in: pageRect, currentY: &y, assetName: parentName)
                        
                        drawAppendixHeaderCard(
                            title: attTitle,
                            index: attIndex + 1,
                            pageInfo: "Imagine Scannată",
                            in: pageRect,
                            currentY: &y
                        )
                        
                        let availableHeight = pageRect.height - y - Self.pageMargin - 20
                        let box = CGRect(x: Self.pageMargin, y: y, width: pageRect.width - Self.pageMargin * 2, height: availableHeight)
                        drawImageAttachment(image: image, in: box)
                        drawRunningFooter(in: pageRect, pageNumber: currentPageNumber)
                    } else {
                        currentPageNumber += 1
                        context.beginPage()
                        var y = Self.pageMargin
                        drawRunningHeader(in: pageRect, currentY: &y, assetName: parentName)
                        drawAppendixHeaderCard(title: attTitle, index: attIndex + 1, pageInfo: "1 din 1", in: pageRect, currentY: &y)
                        drawNoDataPlaceholder(in: CGRect(x: Self.pageMargin, y: y, width: pageRect.width - Self.pageMargin * 2, height: 400))
                        drawRunningFooter(in: pageRect, pageNumber: currentPageNumber)
                    }
                }
            }
        }
    }
    
    // MARK: - UIKit Section Drawing
    
    private func drawRunningHeader(in pageRect: CGRect, currentY: inout CGFloat, assetName: String) {
        let contentWidth = pageRect.width - (Self.pageMargin * 2)
        
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]
        
        let appTitle = "DOSAR CU ȘINĂ"
        (appTitle as NSString).draw(at: CGPoint(x: Self.pageMargin, y: currentY), withAttributes: titleAttrs)
        
        let maxRightWidth = contentWidth - 140
        let truncatedAsset = assetName.count > 45 ? String(assetName.prefix(42)) + "…" : assetName
        let rightSize = (truncatedAsset as NSString).size(withAttributes: subAttrs)
        (truncatedAsset as NSString).draw(
            at: CGPoint(x: pageRect.width - Self.pageMargin - min(rightSize.width, maxRightWidth), y: currentY + 1),
            withAttributes: subAttrs
        )
        
        currentY += 16
        
        let line = UIBezierPath()
        line.move(to: CGPoint(x: Self.pageMargin, y: currentY))
        line.addLine(to: CGPoint(x: Self.pageMargin + contentWidth, y: currentY))
        line.lineWidth = 0.5
        UIColor.separator.setStroke()
        line.stroke()
        
        currentY += 12
    }
    
    private func drawHouseholdSummaryCard(for assets: [Asset], title: String, in pageRect: CGRect, currentY: inout CGFloat) {
        let contentWidth = pageRect.width - (Self.pageMargin * 2)
        let cardHeight: CGFloat = 80.0
        let cardRect = CGRect(x: Self.pageMargin, y: currentY, width: contentWidth, height: cardHeight)
        
        let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 8)
        UIColor(red: 247/255, green: 248/255, blue: 250/255, alpha: 1.0).setFill()
        path.fill()
        
        let border = UIBezierPath(roundedRect: cardRect, cornerRadius: 8)
        border.lineWidth = 0.5
        UIColor.separator.withAlphaComponent(0.4).setStroke()
        border.stroke()
        
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        (title as NSString).draw(at: CGPoint(x: Self.pageMargin + 14, y: currentY + 12), withAttributes: titleAttrs)
        
        let totalEvents = assets.reduce(0) { $0 + $1.events.count }
        let totalAttachments = assets.reduce(0) { sum, a in
            sum + a.attachments.count + a.events.reduce(0) { $0 + $1.attachments.count }
        }
        
        let subtitle = "Total Bunuri & Active: \(assets.count)  •  Obligații & Termene: \(totalEvents)  •  Documente Atașate: \(totalAttachments)"
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]
        (subtitle as NSString).draw(at: CGPoint(x: Self.pageMargin + 14, y: currentY + 34), withAttributes: subAttrs)
        
        let dateStr = "Generat la: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))"
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .regular),
            .foregroundColor: UIColor.tertiaryLabel
        ]
        (dateStr as NSString).draw(at: CGPoint(x: Self.pageMargin + 14, y: currentY + 54), withAttributes: dateAttrs)
        
        currentY += cardHeight + 14
    }
    
    private func drawOpisSection(
        entries: [OpisEntry],
        in pageRect: CGRect,
        context: UIGraphicsPDFRendererContext,
        currentY: inout CGFloat,
        currentPage: inout Int,
        headerTitle: String
    ) {
        let contentWidth = pageRect.width - (Self.pageMargin * 2)
        
        // Section Header
        let sectionTitle = "OPIS DOCUMENTE (BORDEROU OFICIAL)"
        let secAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        (sectionTitle as NSString).draw(at: CGPoint(x: Self.pageMargin, y: currentY), withAttributes: secAttrs)
        currentY += 16
        
        drawOpisTableHeader(in: pageRect, currentY: &currentY)
        
        if entries.isEmpty {
            let emptyLabel = "Nu există documente sau atașamente înregistrate în acest dosar."
            let emptyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 9),
                .foregroundColor: UIColor.secondaryLabel
            ]
            (emptyLabel as NSString).draw(at: CGPoint(x: Self.pageMargin + 8, y: currentY + 8), withAttributes: emptyAttrs)
            currentY += 24
            return
        }
        
        for entry in entries {
            let rowHeight: CGFloat = 22.0
            if currentY + rowHeight > pageRect.height - Self.pageMargin - 30 {
                drawRunningFooter(in: pageRect, pageNumber: currentPage)
                currentPage += 1
                context.beginPage()
                currentY = Self.pageMargin
                drawRunningHeader(in: pageRect, currentY: &currentY, assetName: headerTitle)
                drawOpisTableHeader(in: pageRect, currentY: &currentY)
            }
            
            // Bottom hairline
            let line = UIBezierPath()
            line.move(to: CGPoint(x: Self.pageMargin, y: currentY + rowHeight))
            line.addLine(to: CGPoint(x: Self.pageMargin + contentWidth, y: currentY + rowHeight))
            line.lineWidth = 0.5
            UIColor.separator.withAlphaComponent(0.2).setStroke()
            line.stroke()
            
            // 1. Nr Crt (width 26 pt)
            let nrText = "\(entry.index)."
            (nrText as NSString).draw(
                at: CGPoint(x: Self.pageMargin + 4, y: currentY + 4),
                withAttributes: [.font: UIFont.systemFont(ofSize: 8, weight: .bold), .foregroundColor: UIColor.secondaryLabel]
            )
            
            // 2. Denumire Document (width 140 pt)
            let titleText = entry.title.count > 28 ? String(entry.title.prefix(26)) + "…" : entry.title
            (titleText as NSString).draw(
                at: CGPoint(x: Self.pageMargin + 26, y: currentY + 4),
                withAttributes: [.font: UIFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: UIColor.label]
            )
            
            // 3. Activ / Categorie (width 105 pt)
            let catText = entry.assetName.count > 20 ? String(entry.assetName.prefix(18)) + "…" : entry.assetName
            (catText as NSString).draw(
                at: CGPoint(x: Self.pageMargin + 166, y: currentY + 4),
                withAttributes: [.font: UIFont.systemFont(ofSize: 8, weight: .regular), .foregroundColor: UIColor.secondaryLabel]
            )
            
            // 4. Emitent / Furnizor (width 95 pt)
            let issuerText = entry.issuerOrProvider.count > 18 ? String(entry.issuerOrProvider.prefix(16)) + "…" : entry.issuerOrProvider
            (issuerText as NSString).draw(
                at: CGPoint(x: Self.pageMargin + 271, y: currentY + 4),
                withAttributes: [.font: UIFont.systemFont(ofSize: 8, weight: .regular), .foregroundColor: UIColor.secondaryLabel]
            )
            
            // 5. Scadență (width 72 pt)
            (entry.expiryText as NSString).draw(
                at: CGPoint(x: Self.pageMargin + 366, y: currentY + 4),
                withAttributes: [.font: UIFont.systemFont(ofSize: 7.5, weight: .regular), .foregroundColor: UIColor.label]
            )
            
            // 6. Pag. (width 30 pt)
            (entry.pageDisplay as NSString).draw(
                at: CGPoint(x: Self.pageMargin + 438, y: currentY + 4),
                withAttributes: [.font: UIFont.systemFont(ofSize: 8, weight: .bold), .foregroundColor: UIColor.systemBlue]
            )
            
            // 7. Status Pill (width 55 pt)
            drawStatusPillText(entry.statusText, hex: entry.statusColorHex, x: Self.pageMargin + 472, y: currentY + 3)
            
            currentY += rowHeight
        }
        
        currentY += 12
    }
    
    private func drawOpisTableHeader(in pageRect: CGRect, currentY: inout CGFloat) {
        let contentWidth = pageRect.width - (Self.pageMargin * 2)
        let headerHeight: CGFloat = 20.0
        let headerRect = CGRect(x: Self.pageMargin, y: currentY, width: contentWidth, height: headerHeight)
        
        let path = UIBezierPath(roundedRect: headerRect, cornerRadius: 4)
        UIColor(red: 240/255, green: 242/255, blue: 245/255, alpha: 1.0).setFill()
        path.fill()
        
        let colAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7.5, weight: .bold),
            .foregroundColor: UIColor.secondaryLabel
        ]
        
        ("NR." as NSString).draw(at: CGPoint(x: Self.pageMargin + 4, y: currentY + 5), withAttributes: colAttrs)
        ("DENUMIRE DOCUMENT" as NSString).draw(at: CGPoint(x: Self.pageMargin + 26, y: currentY + 5), withAttributes: colAttrs)
        ("ACTIV / DOMENIU" as NSString).draw(at: CGPoint(x: Self.pageMargin + 166, y: currentY + 5), withAttributes: colAttrs)
        ("EMITENT / FURNIZOR" as NSString).draw(at: CGPoint(x: Self.pageMargin + 271, y: currentY + 5), withAttributes: colAttrs)
        ("SCADENȚĂ" as NSString).draw(at: CGPoint(x: Self.pageMargin + 366, y: currentY + 5), withAttributes: colAttrs)
        ("PAG." as NSString).draw(at: CGPoint(x: Self.pageMargin + 438, y: currentY + 5), withAttributes: colAttrs)
        ("STATUS" as NSString).draw(at: CGPoint(x: Self.pageMargin + 472, y: currentY + 5), withAttributes: colAttrs)
        
        currentY += headerHeight + 2
    }
    
    private func drawStatusPillText(_ text: String, hex: String, x: CGFloat, y: CGFloat) {
        let pillColor = UIColor(hex: hex) ?? UIColor.systemGreen
        let font = UIFont.systemFont(ofSize: 7, weight: .bold)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let pillRect = CGRect(x: x, y: y, width: size.width + 10, height: 14)
        
        let path = UIBezierPath(roundedRect: pillRect, cornerRadius: 4)
        pillColor.withAlphaComponent(0.15).setFill()
        path.fill()
        
        (text as NSString).draw(
            at: CGPoint(x: x + 5, y: y + 2.5),
            withAttributes: [.font: font, .foregroundColor: pillColor]
        )
    }
    
    private func drawAppendixHeaderCard(
        title: String,
        index: Int,
        pageInfo: String,
        in pageRect: CGRect,
        currentY: inout CGFloat
    ) {
        let contentWidth = pageRect.width - (Self.pageMargin * 2)
        let cardHeight: CGFloat = 32.0
        let cardRect = CGRect(x: Self.pageMargin, y: currentY, width: contentWidth, height: cardHeight)
        
        let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 6)
        UIColor(red: 247/255, green: 248/255, blue: 250/255, alpha: 1.0).setFill()
        path.fill()
        
        let border = UIBezierPath(roundedRect: cardRect, cornerRadius: 6)
        border.lineWidth = 0.5
        UIColor.separator.withAlphaComponent(0.3).setStroke()
        border.stroke()
        
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        let label = "ANEXA \(index) • \(title)"
        (label as NSString).draw(at: CGPoint(x: Self.pageMargin + 10, y: currentY + 9), withAttributes: titleAttrs)
        
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let infoSize = (pageInfo as NSString).size(withAttributes: subAttrs)
        (pageInfo as NSString).draw(
            at: CGPoint(x: pageRect.width - Self.pageMargin - 10 - infoSize.width, y: currentY + 9),
            withAttributes: subAttrs
        )
        
        currentY += cardHeight + 8
    }
    
    private func drawAssetSummaryCard(for asset: Asset, in pageRect: CGRect, currentY: inout CGFloat) {
        let contentWidth = pageRect.width - (Self.pageMargin * 2)
        let cardHeight: CGFloat = 90.0
        let cardRect = CGRect(x: Self.pageMargin, y: currentY, width: contentWidth, height: cardHeight)
        
        let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 8)
        UIColor(red: 247/255, green: 248/255, blue: 250/255, alpha: 1.0).setFill()
        path.fill()
        
        let border = UIBezierPath(roundedRect: cardRect, cornerRadius: 8)
        border.lineWidth = 0.5
        UIColor.separator.withAlphaComponent(0.4).setStroke()
        border.stroke()
        
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        (asset.name as NSString).draw(at: CGPoint(x: Self.pageMargin + 12, y: currentY + 10), withAttributes: nameAttrs)
        
        let catStr = "\(asset.category.title)  •  ID: \(asset.id.uuidString.prefix(8))"
        let catAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8.5, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]
        (catStr as NSString).draw(at: CGPoint(x: Self.pageMargin + 12, y: currentY + 28), withAttributes: catAttrs)
        
        var metaItems: [String] = []
        if let notes = asset.notes, !notes.isEmpty {
            metaItems.append("Notițe: \(notes)")
        }
        if let date = asset.purchaseOrIssueDate {
            metaItems.append("Data: \(DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none))")
        }
        if let price = asset.purchasePrice, price > 0 {
            metaItems.append("Preț achiziție: \(String(format: "%.2f", price)) RON")
        }
        
        let metaText = metaItems.joined(separator: "  |  ")
        if !metaText.isEmpty {
            let metaAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel
            ]
            (metaText as NSString).draw(at: CGPoint(x: Self.pageMargin + 12, y: currentY + 48), withAttributes: metaAttrs)
        }
        
        currentY += cardHeight + 12
    }
    
    private func drawDynamicFieldsCard(for fields: [DynamicField], in pageRect: CGRect, currentY: inout CGFloat) {
        let contentWidth = pageRect.width - (Self.pageMargin * 2)
        let rowHeight: CGFloat = 16.0
        let cardHeight: CGFloat = CGFloat(fields.count) * rowHeight + 20.0
        let cardRect = CGRect(x: Self.pageMargin, y: currentY, width: contentWidth, height: cardHeight)
        
        let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 6)
        UIColor(white: 0.98, alpha: 1.0).setFill()
        path.fill()
        
        var fieldY = currentY + 10
        for field in fields {
            let keyStr = "\(field.label):"
            let valStr = field.stringValue ?? (field.numberValue.map { "\($0)" } ?? "—")
            
            (keyStr as NSString).draw(
                at: CGPoint(x: Self.pageMargin + 10, y: fieldY),
                withAttributes: [.font: UIFont.systemFont(ofSize: 8, weight: .bold), .foregroundColor: UIColor.secondaryLabel]
            )
            (valStr as NSString).draw(
                at: CGPoint(x: Self.pageMargin + 140, y: fieldY),
                withAttributes: [.font: UIFont.systemFont(ofSize: 8, weight: .regular), .foregroundColor: UIColor.label]
            )
            fieldY += rowHeight
        }
        currentY += cardHeight + 12
    }
    
    private func drawEventsSection(
        events: [LifecycleEvent],
        in pageRect: CGRect,
        context: UIGraphicsPDFRendererContext,
        currentY: inout CGFloat,
        currentPage: inout Int,
        assetName: String
    ) {
        let contentWidth = pageRect.width - (Self.pageMargin * 2)
        let secTitle = "ISTORIC OBLIGAȚII & EVENIMENTE"
        (secTitle as NSString).draw(
            at: CGPoint(x: Self.pageMargin, y: currentY),
            withAttributes: [.font: UIFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: UIColor.label]
        )
        currentY += 16
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        
        for event in events {
            let rowHeight: CGFloat = 24.0
            if currentY + rowHeight > pageRect.height - Self.pageMargin - 30 {
                drawRunningFooter(in: pageRect, pageNumber: currentPage)
                currentPage += 1
                context.beginPage()
                currentY = Self.pageMargin
                drawRunningHeader(in: pageRect, currentY: &currentY, assetName: assetName)
            }
            
            let dateStr = dateFormatter.string(from: event.dueDate)
            (dateStr as NSString).draw(
                at: CGPoint(x: Self.pageMargin + 4, y: currentY + 4),
                withAttributes: [.font: UIFont.systemFont(ofSize: 8, weight: .regular), .foregroundColor: UIColor.secondaryLabel]
            )
            
            let titleStr = event.title
            (titleStr as NSString).draw(
                at: CGPoint(x: Self.pageMargin + 80, y: currentY + 4),
                withAttributes: [.font: UIFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: UIColor.label]
            )
            
            let costStr = event.cost != nil ? "\(String(format: "%.2f", event.cost!)) RON" : "—"
            (costStr as NSString).draw(
                at: CGPoint(x: pageRect.width - Self.pageMargin - 90, y: currentY + 4),
                withAttributes: [.font: UIFont.systemFont(ofSize: 8, weight: .regular), .foregroundColor: UIColor.label]
            )
            
            currentY += rowHeight
        }
        currentY += 10
    }
    
    private func drawPDFAttachment(page: PDFPage, in targetRect: CGRect) {
        guard let currentContext = UIGraphicsGetCurrentContext() else { return }
        currentContext.saveGState()
        
        let pageBounds = page.bounds(for: .mediaBox)
        let scaleX = targetRect.width / max(pageBounds.width, 1)
        let scaleY = targetRect.height / max(pageBounds.height, 1)
        let scale = min(scaleX, scaleY)
        
        let scaledWidth = pageBounds.width * scale
        let scaledHeight = pageBounds.height * scale
        let originX = targetRect.origin.x + (targetRect.width - scaledWidth) / 2
        let originY = targetRect.origin.y + (targetRect.height - scaledHeight) / 2
        
        currentContext.translateBy(x: originX, y: originY + scaledHeight)
        currentContext.scaleBy(x: scale, y: -scale)
        page.draw(with: .mediaBox, to: currentContext)
        currentContext.restoreGState()
        
        let border = UIBezierPath(rect: CGRect(x: originX, y: originY, width: scaledWidth, height: scaledHeight))
        border.lineWidth = 0.5
        UIColor.separator.withAlphaComponent(0.3).setStroke()
        border.stroke()
    }
    
    private func drawImageAttachment(image: UIImage, in targetRect: CGRect) {
        let imageAspect = image.size.width / max(image.size.height, 1)
        let boxAspect = targetRect.width / max(targetRect.height, 1)
        
        var drawRect = targetRect
        if imageAspect > boxAspect {
            let scaledHeight = targetRect.width / imageAspect
            drawRect = CGRect(x: targetRect.origin.x, y: targetRect.origin.y + (targetRect.height - scaledHeight) / 2, width: targetRect.width, height: scaledHeight)
        } else {
            let scaledWidth = targetRect.height * imageAspect
            drawRect = CGRect(x: targetRect.origin.x + (targetRect.width - scaledWidth) / 2, y: targetRect.origin.y, width: scaledWidth, height: targetRect.height)
        }
        image.draw(in: drawRect)
        
        let border = UIBezierPath(rect: drawRect)
        border.lineWidth = 0.5
        UIColor.separator.withAlphaComponent(0.3).setStroke()
        border.stroke()
    }
    
    private func drawNoDataPlaceholder(in rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        UIColor(white: 0.96, alpha: 1.0).setFill()
        path.fill()
        
        let label = "Conținut atașament indisponibil sau corupt"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 10),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        (label as NSString).draw(
            at: CGPoint(x: rect.origin.x + (rect.width - size.width) / 2, y: rect.origin.y + (rect.height - size.height) / 2),
            withAttributes: attrs
        )
    }
    
    private func drawRunningFooter(in pageRect: CGRect, pageNumber: Int) {
        let footerY = pageRect.height - Self.pageMargin + 6
        let contentWidth = pageRect.width - (Self.pageMargin * 2)
        
        let line = UIBezierPath()
        line.move(to: CGPoint(x: Self.pageMargin, y: footerY - 4))
        line.addLine(to: CGPoint(x: Self.pageMargin + contentWidth, y: footerY - 4))
        line.lineWidth = 0.5
        UIColor.separator.withAlphaComponent(0.3).setStroke()
        line.stroke()
        
        let leftNotice = "Dosar cu Șină • Opis Documente & Arhivă Oficială"
        let leftAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7.5, weight: .regular),
            .foregroundColor: UIColor.tertiaryLabel
        ]
        (leftNotice as NSString).draw(at: CGPoint(x: Self.pageMargin, y: footerY), withAttributes: leftAttrs)
        
        let pageStr = "Pagina \(pageNumber)"
        let rightAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let pageSize = (pageStr as NSString).size(withAttributes: rightAttrs)
        (pageStr as NSString).draw(
            at: CGPoint(x: pageRect.width - Self.pageMargin - pageSize.width, y: footerY),
            withAttributes: rightAttrs
        )
    }
    #endif
    
    // MARK: - CoreGraphics Fallback (macOS & CLI Tests)
    
    private func generateCoreGraphicsPDF(for assets: [Asset], title: String) -> Data {
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: Self.pageA4Width, height: Self.pageA4Height)
        
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }
        
        let opisEntries = buildOpisEntries(for: assets)
        
        // Page 1: Opis Documente
        context.beginPDFPage(nil)
        #if canImport(CoreText)
        drawCoreTextHeader(context: context, text: "DOSAR CU ȘINĂ — \(title)", y: 800)
        drawCoreTextHeader(context: context, text: "OPIS DOCUMENTE (BORDEROU OFICIAL)", y: 770)
        
        var yPos: CGFloat = 740
        for entry in opisEntries {
            let rowStr = "\(entry.index). \(entry.title) | \(entry.assetName) | \(entry.issuerOrProvider) | \(entry.pageDisplay)"
            drawCoreTextLine(context: context, text: rowStr, y: yPos)
            yPos -= 20
            if yPos < 60 { break }
        }
        #endif
        context.endPDFPage()
        
        // Appendix Pages (Multi-Page PDF rendering without truncation)
        var seenAttachmentIds: Set<UUID> = []
        for asset in assets {
            var atts: [DocumentAttachment] = []
            for att in asset.attachments where !seenAttachmentIds.contains(att.id) && att.fileData != nil {
                seenAttachmentIds.insert(att.id)
                atts.append(att)
            }
            for event in asset.events {
                for att in event.attachments where !seenAttachmentIds.contains(att.id) && att.fileData != nil {
                    seenAttachmentIds.insert(att.id)
                    atts.append(att)
                }
            }
            
            for att in atts {
                guard let data = att.fileData, !data.isEmpty else {
                    context.beginPDFPage(nil)
                    #if canImport(CoreText)
                    drawCoreTextLine(context: context, text: "Anexa: \(att.fileName) (Fără date)", y: 750)
                    #endif
                    context.endPDFPage()
                    continue
                }
                
                if let pdfDoc = PDFDocument(data: data), pdfDoc.pageCount > 0 {
                    for i in 0..<pdfDoc.pageCount {
                        context.beginPDFPage(nil)
                        #if canImport(CoreText)
                        drawCoreTextLine(context: context, text: "Anexa: \(att.fileName) — Pagina \(i + 1) din \(pdfDoc.pageCount)", y: 800)
                        #endif
                        if let page = pdfDoc.page(at: i) {
                            context.saveGState()
                            page.draw(with: .mediaBox, to: context)
                            context.restoreGState()
                        }
                        context.endPDFPage()
                    }
                } else {
                    context.beginPDFPage(nil)
                    #if canImport(CoreText)
                    drawCoreTextLine(context: context, text: "Anexa: \(att.fileName) (Document)", y: 750)
                    #endif
                    context.endPDFPage()
                }
            }
        }
        
        context.closePDF()
        return pdfData as Data
    }
    
    #if canImport(CoreText)
    private func drawCoreTextHeader(context: CGContext, text: String, y: CGFloat) {
        let attrStr = NSAttributedString(string: text, attributes: [
            .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 14, nil)
        ])
        let line = CTLineCreateWithAttributedString(attrStr)
        context.textPosition = CGPoint(x: Self.pageMargin, y: y)
        CTLineDraw(line, context)
    }
    
    private func drawCoreTextLine(context: CGContext, text: String, y: CGFloat) {
        let attrStr = NSAttributedString(string: text, attributes: [
            .font: CTFontCreateWithName("Helvetica" as CFString, 9, nil)
        ])
        let line = CTLineCreateWithAttributedString(attrStr)
        context.textPosition = CGPoint(x: Self.pageMargin, y: y)
        CTLineDraw(line, context)
    }
    #endif
}

// MARK: - Color Extension Helper

#if canImport(UIKit)
private extension UIColor {
    convenience init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") {
            cleanHex.remove(at: cleanHex.startIndex)
        }
        guard cleanHex.count == 6, let hexValue = UInt64(cleanHex, radix: 16) else {
            return nil
        }
        let r = CGFloat((hexValue & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((hexValue & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(hexValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
#endif
