import Foundation
import PDFKit
#if canImport(UIKit)
import UIKit
#endif
import SwiftData

/// Production PDFKit document generator creating an Apple-polished "Dosar Complet"
/// multi-page dossier conforming to Apple Craftsmanship & Polish Standards.
/// Includes asset overview, key metrics, historical lifecycle events, total cost of ownership,
/// dynamic custom attributes, and high-resolution scanned document appendices.
public final class PDFDossierGenerator: Sendable {
    public static let shared = PDFDossierGenerator()
    
    // Standard A4 dimensions in typographic points (72 points / inch)
    public static let pageA4Width: CGFloat = 595.2
    public static let pageA4Height: CGFloat = 841.8
    public static let pageMargin: CGFloat = 36.0
    
    public init() {}
    
    // MARK: - Public API
    
    /// Generates a complete, multi-page PDF document as raw `Data` ready for export via `ShareLink`.
    public func generateDossier(for asset: Asset) -> Data {
        #if canImport(UIKit)
        let pageRect = CGRect(x: 0, y: 0, width: Self.pageA4Width, height: Self.pageA4Height)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        // Pre-gather unique attachments from the asset and all its child events
        var allAttachments: [DocumentAttachment] = []
        var seenAttachmentIds: Set<UUID> = []
        
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
        
        // Estimate total pages: Page 1 (+ overflow event pages) + 1 page per attachment
        let events = asset.events.sorted(by: { $0.dueDate > $1.dueDate })
        let data = renderer.pdfData { context in
            var currentPageNumber = 1
            
            // --- PAGE 1: Overview & Initial Events ---
            context.beginPage()
            var currentY = Self.pageMargin
            
            drawRunningHeader(in: pageRect, currentY: &currentY, assetName: asset.name)
            drawAssetSummaryCard(for: asset, in: pageRect, currentY: &currentY)
            
            if !asset.dynamicFields.isEmpty {
                drawDynamicFieldsCard(for: asset.dynamicFields, in: pageRect, currentY: &currentY)
            }
            
            drawEventsSection(
                events: events,
                in: pageRect,
                context: context,
                currentY: &currentY,
                currentPage: &currentPageNumber,
                assetName: asset.name
            )
            
            drawRunningFooter(in: pageRect, pageNumber: currentPageNumber)
            
            // --- APPENDIX PAGES: Attached Documents ---
            for (index, attachment) in allAttachments.enumerated() {
                autoreleasepool {
                    currentPageNumber += 1
                    context.beginPage()
                    
                    var appendixY = Self.pageMargin
                    drawRunningHeader(in: pageRect, currentY: &appendixY, assetName: asset.name)
                    
                    drawAppendixPage(
                        attachment: attachment,
                        index: index + 1,
                        in: pageRect,
                        currentY: appendixY
                    )
                    
                    drawRunningFooter(in: pageRect, pageNumber: currentPageNumber)
                }
            }
        }
        
        return data
        #else
        return Data()
        #endif
    }
    
    /// Generates the dossier and saves it directly to a temporary file URL, suitable for `ShareLink`.
    public func generateDossierFile(
        for asset: Asset,
        in directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let pdfData = generateDossier(for: asset)
        let sanitizedName = asset.name
            .folding(options: .diacriticInsensitive, locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        let safeBase = sanitizedName.isEmpty ? "Activ" : sanitizedName
        let fileName = "Dosar_\(safeBase)_\(Int(Date().timeIntervalSince1970)).pdf"
        let fileURL = directory.standardizedFileURL.appendingPathComponent(fileName)
        try pdfData.write(to: fileURL, options: .atomic)
        return fileURL
    }
    
    // MARK: - Page Component Drawing
    
    #if canImport(UIKit)
    private func drawRunningHeader(in pageRect: CGRect, currentY: inout CGFloat, assetName: String) {
        let contentWidth = pageRect.width - (Self.pageMargin * 2)
        
        // Brand Title
        let brandAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: UIColor.systemBlue,
            .kern: 1.5
        ]
        let brandString = NSAttributedString(string: "DOSAR CU ȘINĂ — DOSAR COMPLET", attributes: brandAttributes)
        brandString.draw(at: CGPoint(x: Self.pageMargin, y: currentY))
        
        // Date Stamp (right aligned)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ro_RO")
        dateFormatter.dateFormat = "dd MMMM yyyy, HH:mm"
        let dateStr = "Generat la: \(dateFormatter.string(from: Date()))"
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let dateSize = (dateStr as NSString).size(withAttributes: dateAttributes)
        (dateStr as NSString).draw(
            at: CGPoint(x: pageRect.width - Self.pageMargin - dateSize.width, y: currentY),
            withAttributes: dateAttributes
        )
        
        currentY += 14
        
        // Top hairline divider
        let path = UIBezierPath()
        path.move(to: CGPoint(x: Self.pageMargin, y: currentY))
        path.addLine(to: CGPoint(x: Self.pageMargin + contentWidth, y: currentY))
        path.lineWidth = 0.5
        UIColor.separator.withAlphaComponent(0.4).setStroke()
        path.stroke()
        
        currentY += 12
    }
    
    private func drawAssetSummaryCard(for asset: Asset, in pageRect: CGRect, currentY: inout CGFloat) {
        let contentWidth = pageRect.width - (Self.pageMargin * 2)
        let cardHeight: CGFloat = 95.0
        let cardRect = CGRect(x: Self.pageMargin, y: currentY, width: contentWidth, height: cardHeight)
        
        // Background squircle surface
        let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 12)
        UIColor(red: 247/255, green: 248/255, blue: 251/255, alpha: 1.0).setFill()
        cardPath.fill()
        
        // Hairline stroke
        cardPath.lineWidth = 0.5
        UIColor(white: 0.86, alpha: 1.0).setStroke()
        cardPath.stroke()
        
        // Asset Title
        var textY = currentY + 12
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        (asset.name as NSString).draw(at: CGPoint(x: Self.pageMargin + 14, y: textY), withAttributes: titleAttributes)
        
        // Category Badge Pill
        let catText = asset.category.title
        let badgeFont = UIFont.systemFont(ofSize: 9, weight: .semibold)
        let badgeSize = (catText as NSString).size(withAttributes: [.font: badgeFont])
        let badgeRect = CGRect(
            x: pageRect.width - Self.pageMargin - badgeSize.width - 24,
            y: textY + 2,
            width: badgeSize.width + 16,
            height: 18
        )
        let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 9)
        UIColor.systemBlue.withAlphaComponent(0.12).setFill()
        badgePath.fill()
        (catText as NSString).draw(
            at: CGPoint(x: badgeRect.origin.x + 8, y: badgeRect.origin.y + 3),
            withAttributes: [.font: badgeFont, .foregroundColor: UIColor.systemBlue]
        )
        
        textY += 24
        
        // Subtitle / Telemetry
        var subtitleParts: [String] = []
        if let sub = asset.subtitle, !sub.isEmpty {
            subtitleParts.append(sub)
        }
        if let metric = asset.currentMetricValue, let unit = asset.metricUnit {
            let formattedMetric = NumberFormatter.localizedString(from: NSNumber(value: metric), number: .decimal)
            subtitleParts.append("Odometru / Contor: \(formattedMetric) \(unit)")
        }
        let subtitleText = subtitleParts.isEmpty ? "Fără note adiționale" : subtitleParts.joined(separator: " • ")
        let subAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]
        (subtitleText as NSString).draw(at: CGPoint(x: Self.pageMargin + 14, y: textY), withAttributes: subAttributes)
        
        textY += 20
        
        // 3 Key Metrics Columns
        let colWidth = (contentWidth - 28) / 3.0
        let metrics: [(label: String, value: String)] = [
            ("Obligații Active", "\(asset.pendingEventsCount)"),
            ("Scadențe Urgente", "\(asset.urgentEventsCount)"),
            ("Cheltuieli Anuale", "\(String(format: "%.2f", asset.totalCostThisYear)) RON")
        ]
        
        for (i, metric) in metrics.enumerated() {
            let colX = Self.pageMargin + 14 + (CGFloat(i) * colWidth)
            let valAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: (i == 1 && asset.urgentEventsCount > 0) ? UIColor.systemOrange : UIColor.label
            ]
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8, weight: .medium),
                .foregroundColor: UIColor.secondaryLabel
            ]
            (metric.value as NSString).draw(at: CGPoint(x: colX, y: textY), withAttributes: valAttrs)
            (metric.label as NSString).draw(at: CGPoint(x: colX, y: textY + 15), withAttributes: labelAttrs)
        }
        
        currentY += cardHeight + 16
    }
    
    private func drawDynamicFieldsCard(for fields: [DynamicField], in pageRect: CGRect, currentY: inout CGFloat) {
        guard !fields.isEmpty else { return }
        let contentWidth = pageRect.width - (Self.pageMargin * 2)
        
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: UIColor.secondaryLabel,
            .kern: 1.0
        ]
        ("ATRIBUTE & PROPRIETĂȚI SPECIFICE" as NSString).draw(
            at: CGPoint(x: Self.pageMargin, y: currentY),
            withAttributes: headerAttrs
        )
        currentY += 16
        
        let cardRect = CGRect(x: Self.pageMargin, y: currentY, width: contentWidth, height: CGFloat(fields.count * 20 + 12))
        let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 8)
        UIColor(white: 0.98, alpha: 1.0).setFill()
        cardPath.fill()
        cardPath.lineWidth = 0.5
        UIColor(white: 0.88, alpha: 1.0).setStroke()
        cardPath.stroke()
        
        var fieldY = currentY + 6
        for field in fields {
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: UIColor.secondaryLabel
            ]
            (field.label as NSString).draw(at: CGPoint(x: Self.pageMargin + 10, y: fieldY), withAttributes: labelAttrs)
            
            var displayVal = "—"
            if let s = field.stringValue, !s.isEmpty {
                displayVal = s
            } else if let n = field.numberValue {
                displayVal = String(format: "%.2f", n)
            } else if let b = field.boolValue {
                displayVal = b ? "Da" : "Nu"
            } else if let d = field.dateValue {
                displayVal = d.formatted(.dateTime.day().month().year())
            }
            
            let valAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: UIColor.label
            ]
            let valSize = (displayVal as NSString).size(withAttributes: valAttrs)
            (displayVal as NSString).draw(
                at: CGPoint(x: pageRect.width - Self.pageMargin - 10 - valSize.width, y: fieldY),
                withAttributes: valAttrs
            )
            fieldY += 20
        }
        
        currentY = cardRect.maxY + 16
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
        
        let sectionTitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor.label,
            .kern: 1.0
        ]
        ("ISTORIC EVENIMENTE & SCADENȚE" as NSString).draw(
            at: CGPoint(x: Self.pageMargin, y: currentY),
            withAttributes: sectionTitleAttrs
        )
        currentY += 18
        
        drawTableHeader(in: pageRect, currentY: &currentY)
        
        if events.isEmpty {
            let emptyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 10),
                .foregroundColor: UIColor.secondaryLabel
            ]
            ("Nu există evenimente înregistrate pentru acest activ." as NSString).draw(
                at: CGPoint(x: Self.pageMargin + 10, y: currentY + 12),
                withAttributes: emptyAttrs
            )
            currentY += 36
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        
        var totalHistoricalCost: Double = 0.0
        
        for event in events {
            if let cost = event.cost {
                totalHistoricalCost += cost
            }
            
            let rowHeight: CGFloat = 34.0
            // Check if row exceeds printable bottom margin
            if currentY + rowHeight > pageRect.height - Self.pageMargin - 30 {
                drawRunningFooter(in: pageRect, pageNumber: currentPage)
                currentPage += 1
                context.beginPage()
                currentY = Self.pageMargin
                drawRunningHeader(in: pageRect, currentY: &currentY, assetName: assetName)
                drawTableHeader(in: pageRect, currentY: &currentY)
            }
            
            // Alternating hairline bottom divider
            let line = UIBezierPath()
            line.move(to: CGPoint(x: Self.pageMargin, y: currentY + rowHeight))
            line.addLine(to: CGPoint(x: Self.pageMargin + contentWidth, y: currentY + rowHeight))
            line.lineWidth = 0.5
            UIColor.separator.withAlphaComponent(0.25).setStroke()
            line.stroke()
            
            // 1. Date Column (width 85 pt)
            let dateText = dateFormatter.string(from: event.dueDate)
            (dateText as NSString).draw(
                at: CGPoint(x: Self.pageMargin + 6, y: currentY + 6),
                withAttributes: [.font: UIFont.systemFont(ofSize: 9, weight: .regular), .foregroundColor: UIColor.label]
            )
            
            // 2. Title & Description (width 220 pt)
            let titleText = event.title
            (titleText as NSString).draw(
                at: CGPoint(x: Self.pageMargin + 95, y: currentY + 5),
                withAttributes: [.font: UIFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: UIColor.label]
            )
            if let desc = event.eventDescription, !desc.isEmpty {
                let truncatedDesc = desc.count > 38 ? String(desc.prefix(35)) + "…" : desc
                (truncatedDesc as NSString).draw(
                    at: CGPoint(x: Self.pageMargin + 95, y: currentY + 17),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 7.5, weight: .regular), .foregroundColor: UIColor.secondaryLabel]
                )
            }
            
            // 3. Status Badge (width 95 pt)
            let badgeX = Self.pageMargin + 320
            drawStatusPill(for: event, x: badgeX, y: currentY + 7)
            
            // 4. Cost Column (width 90 pt, right aligned)
            let costString: String
            if let cost = event.cost, cost > 0 {
                costString = "\(String(format: "%.2f", cost)) \(event.currency)"
            } else {
                costString = "—"
            }
            let costAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: UIColor.label
            ]
            let costSize = (costString as NSString).size(withAttributes: costAttrs)
            (costString as NSString).draw(
                at: CGPoint(x: pageRect.width - Self.pageMargin - 8 - costSize.width, y: currentY + 6),
                withAttributes: costAttrs
            )
            
            currentY += rowHeight
        }
        
        // Total historical aggregation row
        currentY += 8
        let totalLabel = "TOTAL INVESTIT / CHELTUIT:"
        let totalVal = "\(String(format: "%.2f", totalHistoricalCost)) RON"
        let totalLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let totalValAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        (totalLabel as NSString).draw(at: CGPoint(x: Self.pageMargin + 250, y: currentY + 2), withAttributes: totalLabelAttrs)
        let totalValSize = (totalVal as NSString).size(withAttributes: totalValAttrs)
        (totalVal as NSString).draw(
            at: CGPoint(x: pageRect.width - Self.pageMargin - 8 - totalValSize.width, y: currentY),
            withAttributes: totalValAttrs
        )
        currentY += 24
    }
    
    private func drawTableHeader(in pageRect: CGRect, currentY: inout CGFloat) {
        let contentWidth = pageRect.width - (Self.pageMargin * 2)
        let headerHeight: CGFloat = 22.0
        let headerRect = CGRect(x: Self.pageMargin, y: currentY, width: contentWidth, height: headerHeight)
        
        let path = UIBezierPath(roundedRect: headerRect, cornerRadius: 4)
        UIColor(red: 242/255, green: 243/255, blue: 246/255, alpha: 1.0).setFill()
        path.fill()
        
        let colAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .bold),
            .foregroundColor: UIColor.secondaryLabel
        ]
        
        ("SCADENȚĂ" as NSString).draw(at: CGPoint(x: Self.pageMargin + 6, y: currentY + 6), withAttributes: colAttrs)
        ("EVENIMENT / TITLU" as NSString).draw(at: CGPoint(x: Self.pageMargin + 95, y: currentY + 6), withAttributes: colAttrs)
        ("STATUS" as NSString).draw(at: CGPoint(x: Self.pageMargin + 320, y: currentY + 6), withAttributes: colAttrs)
        
        let costTitle = "COST"
        let costSize = (costTitle as NSString).size(withAttributes: colAttrs)
        (costTitle as NSString).draw(
            at: CGPoint(x: pageRect.width - Self.pageMargin - 8 - costSize.width, y: currentY + 6),
            withAttributes: colAttrs
        )
        
        currentY += headerHeight + 2
    }
    
    private func drawStatusPill(for event: LifecycleEvent, x: CGFloat, y: CGFloat) {
        let text = event.statusBadgeText
        let font = UIFont.systemFont(ofSize: 7.5, weight: .bold)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let pillRect = CGRect(x: x, y: y, width: size.width + 12, height: 16)
        
        let fillColor: UIColor
        let textColor: UIColor
        
        if event.isCompleted {
            fillColor = UIColor(red: 52/255, green: 199/255, blue: 89/255, alpha: 0.12)
            textColor = UIColor(red: 35/255, green: 140/255, blue: 60/255, alpha: 1.0)
        } else if event.isOverdue {
            fillColor = UIColor(red: 255/255, green: 59/255, blue: 48/255, alpha: 0.12)
            textColor = UIColor(red: 215/255, green: 40/255, blue: 30/255, alpha: 1.0)
        } else if event.isUrgent {
            fillColor = UIColor(red: 255/255, green: 149/255, blue: 0/255, alpha: 0.12)
            textColor = UIColor(red: 200/255, green: 110/255, blue: 0/255, alpha: 1.0)
        } else {
            fillColor = UIColor(red: 0/255, green: 122/255, blue: 255/255, alpha: 0.1)
            textColor = UIColor.systemBlue
        }
        
        let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: 8)
        fillColor.setFill()
        pillPath.fill()
        
        (text as NSString).draw(
            at: CGPoint(x: pillRect.origin.x + 6, y: pillRect.origin.y + 3),
            withAttributes: [.font: font, .foregroundColor: textColor]
        )
    }
    
    private func drawAppendixPage(
        attachment: DocumentAttachment,
        index: Int,
        in pageRect: CGRect,
        currentY: CGFloat
    ) {
        var localY = currentY
        let contentWidth = pageRect.width - (Self.pageMargin * 2)
        
        // Appendix Title Header
        let appendixTitle = "ANEXA \(index): \(attachment.fileName)"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        (appendixTitle as NSString).draw(at: CGPoint(x: Self.pageMargin, y: localY), withAttributes: titleAttrs)
        localY += 18
        
        // Metadata description
        var metaParts: [String] = []
        if let event = attachment.event {
            metaParts.append("Eveniment asociat: \(event.title)")
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        metaParts.append("Dată atașament: \(dateFormatter.string(from: attachment.createdAt))")
        
        let metaString = metaParts.joined(separator: " • ")
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]
        (metaString as NSString).draw(at: CGPoint(x: Self.pageMargin, y: localY), withAttributes: metaAttrs)
        localY += 18
        
        // Content Area for Attachment
        let availableHeight = pageRect.height - localY - Self.pageMargin - 30
        let previewBox = CGRect(x: Self.pageMargin, y: localY, width: contentWidth, height: availableHeight)
        
        guard let fileData = attachment.fileData else {
            drawNoDataPlaceholder(in: previewBox)
            return
        }
        
        // Try decoding as UIImage
        if let image = UIImage(data: fileData) {
            drawImageAttachment(image: image, in: previewBox)
        } else if let pdfDoc = PDFDocument(data: fileData), let firstPage = pdfDoc.page(at: 0) {
            drawPDFAttachment(page: firstPage, in: previewBox)
        } else {
            drawNoDataPlaceholder(in: previewBox)
        }
    }
    
    private func drawImageAttachment(image: UIImage, in targetRect: CGRect) {
        // Maintain aspect ratio
        let imageAspect = image.size.width / max(image.size.height, 1)
        let boxAspect = targetRect.width / max(targetRect.height, 1)
        
        var drawRect = targetRect
        if imageAspect > boxAspect {
            // Wider than box
            let scaledHeight = targetRect.width / imageAspect
            drawRect = CGRect(
                x: targetRect.origin.x,
                y: targetRect.origin.y + (targetRect.height - scaledHeight) / 2,
                width: targetRect.width,
                height: scaledHeight
            )
        } else {
            // Taller than box
            let scaledWidth = targetRect.height * imageAspect
            drawRect = CGRect(
                x: targetRect.origin.x + (targetRect.width - scaledWidth) / 2,
                y: targetRect.origin.y,
                width: scaledWidth,
                height: targetRect.height
            )
        }
        
        image.draw(in: drawRect)
        
        // Subtle outline around scanned document
        let border = UIBezierPath(rect: drawRect)
        border.lineWidth = 0.5
        UIColor.separator.withAlphaComponent(0.3).setStroke()
        border.stroke()
    }
    
    private func drawPDFAttachment(page: PDFPage, in targetRect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        
        let pageBounds = page.bounds(for: .mediaBox)
        let scaleX = targetRect.width / pageBounds.width
        let scaleY = targetRect.height / pageBounds.height
        let scale = min(scaleX, scaleY)
        
        let offsetX = targetRect.origin.x + (targetRect.width - (pageBounds.width * scale)) / 2
        let offsetY = targetRect.origin.y + (targetRect.height - (pageBounds.height * scale)) / 2
        
        context.translateBy(x: offsetX, y: offsetY + (pageBounds.height * scale))
        context.scaleBy(x: scale, y: -scale)
        page.draw(with: .mediaBox, to: context)
        
        context.restoreGState()
    }
    
    private func drawNoDataPlaceholder(in rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
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
        
        // Hairline divider above footer
        let line = UIBezierPath()
        line.move(to: CGPoint(x: Self.pageMargin, y: footerY - 4))
        line.addLine(to: CGPoint(x: Self.pageMargin + contentWidth, y: footerY - 4))
        line.lineWidth = 0.5
        UIColor.separator.withAlphaComponent(0.3).setStroke()
        line.stroke()
        
        let leftNotice = "Confidențial — Generat local pe dispozitiv via Dosar cu Șină"
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
}
