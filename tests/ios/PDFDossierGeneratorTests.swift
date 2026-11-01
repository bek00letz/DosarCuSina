import Foundation
import PDFKit
import SwiftData

public final class PDFDossierGeneratorTests {
    public static func runAll() -> TestSuiteResult {
        let startTime = Date()
        var passed = 0
        var failed = 0
        var failures: [TestFailure] = []
        
        let tests: [(String, () throws -> Void)] = [
            ("testSingleAssetDossier_GeneratesValidPDFData", testSingleAssetDossier_GeneratesValidPDFData),
            ("testOpisDocumente_ExtractsCorrectColumnsAndMetadata", testOpisDocumente_ExtractsCorrectColumnsAndMetadata),
            ("testHouseholdDossier_MultipleAssets_BuildsUnifiedOpis", testHouseholdDossier_MultipleAssets_BuildsUnifiedOpis),
            ("testMultiPagePDF_NonTruncatedAppendix", testMultiPagePDF_NonTruncatedAppendix),
            ("testOpisDocumente_CrossReferencingPageNumbers", testOpisDocumente_CrossReferencingPageNumbers),
            ("testFileExport_WritesValidFileToDisk", testFileExport_WritesValidFileToDisk),
            ("testEmptyAsset_GeneratesGracefully", testEmptyAsset_GeneratesGracefully)
        ]
        
        for (testName, testFunc) in tests {
            do {
                try testFunc()
                passed += 1
                print("  ✅ PASS  \(testName)")
            } catch {
                failed += 1
                let failure = TestFailure(testName: testName, message: "\(error)", file: #file, line: #line)
                failures.append(failure)
                print("  ❌ FAIL  \(testName): \(error)")
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        return TestSuiteResult(
            suiteName: "PDFDossierGeneratorTests",
            passed: passed,
            failed: failed,
            failures: failures,
            duration: duration
        )
    }
    
    // MARK: - Test Cases
    
    public static func testSingleAssetDossier_GeneratesValidPDFData() throws {
        let asset = Asset(
            name: "Dacia Duster 2023",
            category: .vehicle,
            iconName: "car.fill",
            accentColorHex: "#007AFF"
        )
        asset.vin = "UU1HSD7890123456"
        asset.licensePlate = "B-123-DAC"
        asset.purchasePrice = 98500.0
        
        let pdfData = PDFDossierGenerator.shared.generateDossier(for: asset)
        try assertTrue(!pdfData.isEmpty, "Generated PDF data should not be empty")
        
        // Check PDF header '%PDF-'
        let header = String(data: pdfData.prefix(5), encoding: .ascii)
        try assertEqual(header, "%PDF-", "PDF output must start with '%PDF-' magic bytes")
        
        let pdfDoc = PDFDocument(data: pdfData)
        try assertTrue(pdfDoc != nil, "PDFKit should successfully load the generated PDF")
        try assertTrue((pdfDoc?.pageCount ?? 0) >= 1, "PDF should have at least 1 page")
    }
    
    public static func testOpisDocumente_ExtractsCorrectColumnsAndMetadata() throws {
        let asset = Asset(
            name: "Apartament 3 Camere",
            category: .home,
            iconName: "house.fill",
            accentColorHex: "#34C759"
        )
        asset.retailerOrIssuer = "Dezvoltator Imobiliar S.A."
        
        let att1 = DocumentAttachment(
            fileName: "Contract_Vanzare_Cumparare.pdf",
            fileExtension: "pdf",
            fileData: "Dummy Contract Bytes".data(using: .utf8)
        )
        asset.attachments.append(att1)
        
        let event = LifecycleEvent(
            title: "Revizie Gaze (RIG 10 Ani)",
            dueDate: Calendar.current.date(byAdding: .year, value: 2, to: Date())!,
            cost: 450.0,
            provider: "Distrigaz Rețele"
        )
        let att2 = DocumentAttachment(
            fileName: "Proces_Verbal_RIG.pdf",
            fileExtension: "pdf",
            fileData: "Dummy PV Bytes".data(using: .utf8)
        )
        event.attachments.append(att2)
        asset.events.append(event)
        
        let entries = PDFDossierGenerator.shared.buildOpisEntries(for: asset)
        try assertEqual(entries.count, 2, "Should produce exactly 2 Opis entries for 2 attachments")
        
        let e1 = entries[0]
        try assertEqual(e1.index, 1)
        try assertTrue(e1.title.contains("Contract_Vanzare_Cumparare"), "Title should match attachment file")
        try assertEqual(e1.assetName, "Apartament 3 Camere")
        try assertEqual(e1.issuerOrProvider, "Dezvoltator Imobiliar S.A.")
        
        let e2 = entries[1]
        try assertEqual(e2.index, 2)
        try assertTrue(e2.title.contains("Revizie Gaze"), "Title should include event title")
        try assertEqual(e2.issuerOrProvider, "Distrigaz Rețele")
        try assertEqual(e2.statusText, "Valabil")
    }
    
    public static func testHouseholdDossier_MultipleAssets_BuildsUnifiedOpis() throws {
        let car = Asset(name: "VW Golf", category: .vehicle)
        let home = Asset(name: "Garsonieră", category: .home)
        let health = Asset(name: "Dosar Medical Copil", category: .health)
        
        car.attachments.append(DocumentAttachment(fileName: "CIV.pdf", fileExtension: "pdf", fileData: "CIV".data(using: .utf8)))
        home.attachments.append(DocumentAttachment(fileName: "CPE.pdf", fileExtension: "pdf", fileData: "CPE".data(using: .utf8)))
        health.attachments.append(DocumentAttachment(fileName: "Vaccinuri.pdf", fileExtension: "pdf", fileData: "Vaccin".data(using: .utf8)))
        
        let assets = [car, home, health]
        let opis = PDFDossierGenerator.shared.buildOpisEntries(for: assets)
        try assertEqual(opis.count, 3, "Unified Opis should index attachments across all household assets")
        try assertEqual(opis[0].index, 1)
        try assertEqual(opis[1].index, 2)
        try assertEqual(opis[2].index, 3)
        
        let dossierData = PDFDossierGenerator.shared.generateHouseholdDossier(for: assets, title: "Dosar Test")
        try assertTrue(!dossierData.isEmpty, "Household dossier data should not be empty")
        
        let pdf = PDFDocument(data: dossierData)
        try assertTrue(pdf != nil, "Should load as valid PDFDocument")
        try assertTrue((pdf?.pageCount ?? 0) >= 3, "Should contain multiple pages for overview and appendices")
    }
    
    public static func testMultiPagePDF_NonTruncatedAppendix() throws {
        // Create an in-memory 3-page PDF document
        let multiPagePDFData = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        let consumer = CGDataConsumer(data: multiPagePDFData as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
        
        ctx.beginPDFPage(nil)
        ctx.endPDFPage()
        ctx.beginPDFPage(nil)
        ctx.endPDFPage()
        ctx.beginPDFPage(nil)
        ctx.endPDFPage()
        ctx.closePDF()
        
        let samplePDF = multiPagePDFData as Data
        let sampleDoc = PDFDocument(data: samplePDF)
        try assertEqual(sampleDoc?.pageCount, 3, "Fixture PDF must have 3 pages")
        
        let asset = Asset(name: "Poliță Asigurare CASCO", category: .warranties)
        let att = DocumentAttachment(
            fileName: "Polita_CASCO_3Pagini.pdf",
            fileExtension: "pdf",
            fileData: samplePDF
        )
        asset.attachments.append(att)
        
        let opis = PDFDossierGenerator.shared.buildOpisEntries(for: asset)
        try assertEqual(opis.count, 1)
        try assertEqual(opis[0].targetPageCount, 3, "Opis entry must recognize 3 pages for the multi-page PDF")
        
        let dossier = PDFDossierGenerator.shared.generateDossier(for: asset)
        let generatedDoc = PDFDocument(data: dossier)
        try assertTrue(generatedDoc != nil, "Dossier should load as valid PDFDocument")
        // Dossier must contain overview page(s) + 3 full pages for the attachment!
        try assertTrue((generatedDoc?.pageCount ?? 0) >= 4, "Generated dossier must render all 3 pages of the attachment without truncation (expected >= 4 pages, got \(generatedDoc?.pageCount ?? 0))")
    }
    
    public static func testOpisDocumente_CrossReferencingPageNumbers() throws {
        let asset = Asset(name: "Generator", category: .home)
        let att = DocumentAttachment(fileName: "Manual.pdf", fileExtension: "pdf", fileData: "Manual content".data(using: .utf8))
        asset.attachments.append(att)
        
        var opis = PDFDossierGenerator.shared.buildOpisEntries(for: asset)
        try assertEqual(opis.count, 1)
        opis[0].targetPageStart = 5
        opis[0].targetPageCount = 2
        try assertEqual(opis[0].pageDisplay, "p. 5–6", "Multi-page appendix display should format as 'p. start-end'")
        
        opis[0].targetPageCount = 1
        try assertEqual(opis[0].pageDisplay, "p. 5", "Single-page appendix display should format as 'p. start'")
    }
    
    public static func testFileExport_WritesValidFileToDisk() throws {
        let asset = Asset(name: "Laptop MacBook Pro", category: .warranties)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let fileURL = try PDFDossierGenerator.shared.generateDossierFile(for: asset, in: tempDir)
        try assertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Exported dossier file must exist on disk")
        
        let fileData = try Data(contentsOf: fileURL)
        try assertTrue(fileData.count > 0, "Exported file must contain non-zero bytes")
        try assertEqual(String(data: fileData.prefix(5), encoding: .ascii), "%PDF-", "Exported file must be a valid PDF")
    }
    
    public static func testEmptyAsset_GeneratesGracefully() throws {
        let emptyAsset = Asset(name: "Bun Nou Fără Detalii", category: .custom)
        let pdfData = PDFDossierGenerator.shared.generateDossier(for: emptyAsset)
        try assertTrue(!pdfData.isEmpty, "Empty asset should still produce a valid cover dossier")
        let doc = PDFDocument(data: pdfData)
        try assertTrue(doc != nil, "Doc should load as valid PDFDocument")
        try assertTrue((doc?.pageCount ?? 0) >= 1)
    }
}
