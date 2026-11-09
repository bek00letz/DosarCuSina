import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import SwiftData
import Testing
@testable import DosarCuSina

/// The document's corners in a 1000 × 800 photo: an 800 × 400 card.
private let cardCornersInPhoto = [PagePoint(x: 0.1, y: 0.1), PagePoint(x: 0.9, y: 0.1), PagePoint(x: 0.9, y: 0.6), PagePoint(x: 0.1, y: 0.6)]

/// A document's picture: the cut-out of a library photo with the photo kept, the whole
/// photo back, turning, PDF pages drawn sharp, and "Trimite". Placeholder data only.
@MainActor
@Suite("Document pictures and sharing")
struct DocumentPicturesTests {

    // MARK: Fixtures

    /// A white image with a red block in its top-left corner, to see which way it turned.
    static func marked(width: Int = 40, height: Int = 20) -> CGImage {
        let context = PageTurn.canvas(width: width, height: height)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        // Bitmap contexts count from the bottom: the top-left block sits at the top of the space.
        context.fill(CGRect(x: 0, y: height - height / 2, width: width / 4, height: height / 2))
        return context.makeImage()!
    }

    /// Whether the pixel at `x`, `y` (from the top-left) is red.
    static func isRed(_ image: CGImage, x: Int, y: Int) -> Bool {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4
        return bytes[offset] > 200 && bytes[offset + 1] < 60 && bytes[offset + 2] < 60
    }

    static func encoded(_ image: CGImage) throws -> Data {
        try ImageEncoding.encode(image, maxLongEdge: 4000, quality: 0.9).data
    }

    static func pixelSize(_ data: Data) -> (width: Int, height: Int) {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
        return (properties[kCGImagePropertyPixelWidth] as! Int, properties[kCGImagePropertyPixelHeight] as! Int)
    }

    /// A PDF of `pages` A4 pages with a little drawing on each.
    static func pdf(pages: Int, size: CGSize = CGSize(width: 595, height: 842)) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        let context = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        for page in 0..<pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 50, y: 700, width: 100 + 10 * page, height: 20))
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    static var cardCorners: [PagePoint] { cardCornersInPhoto }

    static func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "share-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// An identity card filed under the documents category, its pages as given.
    static func identityCard(pages: [Data], framing: DocumentFraming = DocumentFraming(), in context: ModelContext) throws -> DosarCuSina.Attachment {
        let card = Asset(name: "Carte de identitate – Exemplu Ana", templateKey: BuiltInTemplates.Key.documents,
                         values: FieldValues([DocumentType.typeFieldKey: .text(DocumentType.idCard)]))
        context.insert(card)
        var draft = DocumentDraft(title: "Carte de identitate – Exemplu Ana", fileName: "Carte de identitate.heic", kind: .identity,
                                  contentType: "public.heic", pageImages: pages)
        draft.framing = framing
        return try AttachmentActions(context: context).file(draft, asset: card)
    }

    // MARK: How a page is framed

    @Test("The person's turn wins over the app's guess, and a later guess never undoes it")
    func personsTurnWins() {
        let guessed = PageFraming(quarterTurns: 1)
        let turned = guessed.turned()
        #expect(turned.shownQuarterTurns == 2)
        #expect(turned.choice?.quarterTurns == 2)
        // A later reading guesses another way; the person's turn stays.
        let reread = PageFraming(quarterTurns: 3).applying(turned.choice)
        #expect(reread.shownQuarterTurns == 2)
        #expect(PageFraming(quarterTurns: 3).turned(by: 2).shownQuarterTurns == 1)
        #expect(PageFraming.normalized(-1) == 3)

        let document = DocumentFraming(pages: [PageFraming(crop: Self.cardCorners)])
            .applying([0: PageChoice(showsWholePhoto: true), 2: PageChoice(quarterTurns: 1)])
        #expect(!document[page: 0].showsCrop)
        #expect(document[page: 0].hasCrop, "The crop is kept, to switch back")
        #expect(document[page: 1] == .plain)
        #expect(document[page: 2].shownQuarterTurns == 1)
    }

    @Test("What a page keeps reads back, and anything unknown or broken reads as the page as it is")
    func framingReadsBack() throws {
        let framing = DocumentFraming(pages: [PageFraming(crop: Self.cardCorners, quarterTurns: 1, choice: PageChoice(showsWholePhoto: true))])
        let decoded = try JSONDecoder().decode(DocumentFraming.self, from: JSONEncoder().encode(framing))
        #expect(decoded == framing)

        let newer = Data(#"{"version":2,"pages":[{"quarterTurns":5,"later":true,"crop":[{"x":0.1,"y":0.1}]},{}]}"#.utf8)
        let read = try JSONDecoder().decode(DocumentFraming.self, from: newer)
        #expect(read[page: 0].shownQuarterTurns == 1)
        #expect(read[page: 0].crop == nil, "Fewer than four corners isn't a crop")
        #expect(read[page: 1].isPlain)
    }

    @Test("A document with nothing decided keeps nothing")
    func plainKeepsNothing() throws {
        let context = try makeContext()
        let attachment = try Self.identityCard(pages: [Self.encoded(Self.marked())], in: context)
        #expect(attachment.framingData == nil)
        attachment.framing = DocumentFraming(pages: [PageFraming(quarterTurns: 1)])
        #expect(attachment.framingData != nil)
        attachment.framing = DocumentFraming(pages: [.plain])
        #expect(attachment.framingData == nil)
    }

    // MARK: Drawing

    @Test("A quarter turn clockwise puts the top-left corner at the top right")
    func turningIsClockwise() throws {
        let image = Self.marked()
        #expect(Self.isRed(image, x: 2, y: 2))
        let once = try #require(DocumentPicture.turned(image, quarterTurns: 1))
        #expect(once.width == 20 && once.height == 40)
        #expect(Self.isRed(once, x: 17, y: 2))
        #expect(!Self.isRed(once, x: 2, y: 2))
        let twice = try #require(DocumentPicture.turned(image, quarterTurns: 2))
        #expect(Self.isRed(twice, x: 37, y: 17))
        let thrice = try #require(DocumentPicture.turned(image, quarterTurns: 3))
        #expect(Self.isRed(thrice, x: 2, y: 37))
        #expect(DocumentPicture.turned(image, quarterTurns: 4) === image)
    }

    @Test("A photo is shown cut out to the document found, or whole, and turned after")
    func cutOut() throws {
        let photo = CaptureDocumentStoreTests.page(width: 1000, height: 800)
        let framing = PageFraming(crop: Self.cardCorners)
        let shown = DocumentPicture.shown(photo, framing: framing)
        #expect(abs(shown.width - 800) <= 2 && abs(shown.height - 400) <= 2)
        let whole = DocumentPicture.shown(photo, framing: framing.showingWholePhoto(true))
        #expect(whole.width == 1000 && whole.height == 800)
        let turned = DocumentPicture.shown(photo, framing: framing.turned())
        #expect(abs(turned.width - 400) <= 2 && abs(turned.height - 800) <= 2)

        let source = DocumentPageSource(index: 0, content: .image(try Self.encoded(photo)), framing: framing.turned())
        let size = try #require(DocumentPicture.shownSize(of: source))
        #expect(abs(size.width - 400) <= 2 && abs(size.height - 800) <= 2, "Its space is known before it is drawn")
    }

    @Test("Corners found in a photo are kept as fractions from the top-left and come back the same")
    func cornersRoundTrip() throws {
        let found = [CGPoint(x: 100, y: 720), CGPoint(x: 900, y: 720), CGPoint(x: 900, y: 320), CGPoint(x: 100, y: 320)]
        let kept = try #require(DocumentPicture.pagePoints(found, width: 1000, height: 800))
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
        let keptRight = zip(kept, Self.cardCorners).allSatisfy { near($0.x, $1.x) && near($0.y, $1.y) }
        let backRight = zip(DocumentPicture.imageCorners(kept, width: 1000, height: 800), found).allSatisfy { near($0.x, $1.x) && near($0.y, $1.y) }
        #expect(keptRight)
        #expect(backRight)
        // The same fractions on the page kept smaller.
        let smaller = DocumentPicture.imageCorners(kept, width: 500, height: 400)[0]
        #expect(near(smaller.x, 50) && near(smaller.y, 360))
    }

    // MARK: Library photos

    /// Finds an 800 × 400 card in any photo, as `DocumentImageNormalizer` would.
    struct CroppingPreparer: CapturePagePreparing {
        func prepare(_ image: CGImage) async -> PreparedPage {
            PreparedPage(image: CaptureDocumentStoreTests.page(width: 800, height: 400), framing: PageFraming(crop: cardCornersInPhoto))
        }
        func retryVariant(of prepared: PreparedPage, original: CGImage) async -> PreparedPage? { nil }
    }

    struct FixedRecognizer: CaptureRecognizing {
        func recognize(_ image: CGImage) async throws -> RecognizedPage {
            RecognizedPage(lines: ["ROMANIA", "CARTE DE IDENTITATE", "EXEMPLU ANA"], barcodes: [])
        }
    }

    @Test("A photo from the library is kept as taken, shown cut out, and can go back to the whole photo with undo")
    func libraryPhotoIsCutOut() async throws {
        let store = CaptureDocumentStore()
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: FixedRecognizer(), normalizer: CroppingPreparer(),
                                   onDeviceModel: nil, cloudModel: nil, store: store)
        let photo = CaptureDocumentStoreTests.page(width: 1000, height: 800)
        let result = try await engine.capture(CaptureRequest(.images([CaptureImage(image: photo)])))
        let ref = try #require(result.document)
        let pendingID = try #require(ref.pendingID)
        let processed = try #require(await store.processed(id: pendingID))

        // The photo as taken is what is kept; the cut-out is how it is shown.
        #expect(Self.pixelSize(processed.pageData[0]).width == 1000 && Self.pixelSize(processed.pageData[0]).height == 800)
        #expect(processed.framing[page: 0].crop == Self.cardCorners)
        let thumbnail = Self.pixelSize(try #require(processed.thumbnailData))
        #expect(abs(Double(thumbnail.width) / Double(thumbnail.height) - 2) < 0.05, "The thumbnail is the cut-out")

        // Filed: the binder keeps the photo and how to show it.
        let context = try makeContext()
        let actions = AttachmentActions(context: context)
        let attachment = try actions.fileCaptured(.new(processed, ref: ref), title: "Carte de identitate")
        #expect(attachment.orderedPages.first?.imageData == processed.pageData[0])
        let firstPage = try #require(DocumentPages.sources(of: attachment).first)
        let shown = try #require(DocumentPicture.image(of: firstPage))
        #expect(abs(shown.width - 800) <= 2)

        // "Folosește poza întreagă", and back with "Anulează".
        let receipt = try await actions.showWholePhoto(true, of: attachment)
        let wholePage = try #require(DocumentPages.sources(of: attachment).first)
        let whole = try #require(DocumentPicture.image(of: wholePage))
        #expect(whole.width == 1000 && whole.height == 800)
        let wholeThumbnail = Self.pixelSize(try #require(attachment.thumbnailData))
        #expect(wholeThumbnail.width * 800 == wholeThumbnail.height * 1000, "The thumbnail follows")
        #expect(receipt.canUndo)
        try receipt.undo()
        #expect(attachment.framing[page: 0].showsCrop)
    }

    @Test("The review's choice of the whole photo is kept when it saves")
    func reviewChoiceIsFiled() async throws {
        let store = CaptureDocumentStore()
        let photo = CaptureDocumentStoreTests.page(width: 1000, height: 800)
        let stored = try await store.store(CaptureDocumentStore.StoreRequest(
            pages: [photo], framing: DocumentFraming(pages: [PageFraming(crop: Self.cardCorners)])))
        let pendingID = try #require(stored.ref.pendingID)
        let processed = try #require(await store.processed(id: pendingID))
        let context = try makeContext()
        let actions = AttachmentActions(context: context)
        let document = CapturedDocument.new(processed, ref: stored.ref)
        let choices = [0: PageChoice(quarterTurns: 1, showsWholePhoto: true)]
        #expect(await actions.pictureChange(for: document, choices: [:]) == nil)
        let pictures = try #require(await actions.pictureChange(for: document, choices: choices))
        let attachment = try actions.fileCaptured(document, pictures: pictures, title: "Carte de identitate")
        #expect(attachment.framing[page: 0].hasCrop)
        #expect(!attachment.framing[page: 0].showsCrop)
        #expect(attachment.framing[page: 0].shownQuarterTurns == 1)
        let thumbnail = Self.pixelSize(try #require(attachment.thumbnailData))
        #expect(thumbnail.height > thumbnail.width, "The whole photo, turned")
    }

    // MARK: PDFs

    @Test("A PDF's pages are its pages, not its thumbnail, and are drawn sharp at any zoom")
    func pdfIsSharp() throws {
        let data = Self.pdf(pages: 2)
        let thumbnail = try Self.encoded(CaptureDocumentStoreTests.page(width: 254, height: 360))
        let pages = DocumentPages.sources(pageImages: [], original: data, thumbnail: thumbnail, framing: DocumentFraming())
        #expect(pages.count == 2)
        #expect(pages.allSatisfy { $0.isPDF })

        // Shared or printed: 300 pixels per inch.
        let printed = try #require(DocumentPicture.image(of: pages[0]))
        #expect(printed.width == 2479 && printed.height == 3508)

        // On a 390-point screen at 3x, zoomed four times: one drawn pixel for each pixel on screen.
        let pixelsPerPoint = PDFPageRendering.pixelsPerPoint(pageWidth: 595, viewWidth: 390, zoom: 4, screenScale: 3)
        #expect(abs(pixelsPerPoint - 390.0 / 595.0 * 12) < 0.0001)
        let onScreen = try #require(DocumentPicture.region(of: pages[0], rect: CGRect(x: 100, y: 100, width: 595.0 / 4, height: 200),
                                                           pixelsPerPoint: pixelsPerPoint))
        #expect(onScreen.width == 1170)
        // Fitted to the screen, the page is drawn at the screen's pixels, not a fixed small size.
        let fitted = try #require(DocumentPicture.image(of: pages[0], pdfPixelsPerPoint: 390.0 / 595.0 * 3))
        #expect(fitted.width == 1170)
        #expect(DocumentPicture.region(of: DocumentPageSource(index: 0, content: .image(thumbnail), framing: .plain),
                                       rect: CGRect(x: 0, y: 0, width: 10, height: 10), pixelsPerPoint: 2) == nil)
    }

    @Test("A turned PDF page is drawn on its side, and asking for too much draws as sharp as fits")
    func pdfTurnsAndKeepsMemory() throws {
        let page = DocumentPageSource(index: 0, content: .pdf(Self.pdf(pages: 1), page: 0), framing: PageFraming(quarterTurns: 1))
        let size = try #require(DocumentPicture.shownSize(of: page))
        #expect(size == CGSize(width: 842, height: 595))
        let drawn = try #require(DocumentPicture.image(of: page, maxLongEdge: 1000))
        #expect(drawn.width == 1000 && drawn.height == 707)
        let huge = try #require(DocumentPicture.image(of: page, pdfPixelsPerPoint: 40))
        #expect(huge.width * huge.height <= PDFPageRendering.maxPixels + huge.width + huge.height)
    }

    // MARK: Turning a filed page

    @Test("A turn is kept, shows in the thumbnail, goes into what is shared, and can be taken back")
    func turnPersistsAndIsShared() async throws {
        let context = try makeContext()
        let attachment = try Self.identityCard(pages: [Self.encoded(CaptureDocumentStoreTests.page(width: 300, height: 200))], in: context)
        let receipt = try await AttachmentActions(context: context).turnPage(attachment, page: 0)
        #expect(attachment.framing[page: 0].shownQuarterTurns == 1)
        #expect(attachment.framing[page: 0].choice?.quarterTurns == 1, "It is the person's turn")
        let thumbnail = Self.pixelSize(try #require(attachment.thumbnailData))
        #expect(thumbnail.height > thumbnail.width)

        // Kept: another context reads it back.
        let id = attachment.id
        let other = ModelContext(context.container)
        let reread = try #require(try other.fetch(FetchDescriptor<DosarCuSina.Attachment>(predicate: #Predicate { $0.id == id })).first)
        #expect(reread.framing[page: 0].shownQuarterTurns == 1)

        // What is shared is the page as shown.
        let root = Self.folder()
        defer { DocumentShareFiles.removeLeftovers(root: root) }
        let files = try DocumentShareFiles.write(DocumentPages.sources(of: attachment), choice: DocumentShareChoice(format: .pictures),
                                                 name: "Carte de identitate", root: root)
        let size = Self.pixelSize(try Data(contentsOf: files[0]))
        #expect(size.width == 200 && size.height == 300)

        try receipt.undo()
        #expect(attachment.framing[page: 0].shownQuarterTurns == 0)
    }

    // MARK: Sharing

    @Test("Each document offers only the pages it has")
    func pageOptions() {
        #expect(DocumentSharePages.options(pageCount: 1) == [.all])
        #expect(DocumentSharePages.options(pageCount: 2) == [.all, .front, .back])
        #expect(DocumentSharePages.options(pageCount: 5) == [.all, .front])
        #expect(DocumentSharePages.back.indices(pageCount: 2) == [1])
        #expect(DocumentSharePages.all.indices(pageCount: 3) == [0, 1, 2])
        #expect(DocumentSharePages.all.title(pageCount: 2) == "Amândouă")
        #expect(DocumentSharePages.front.title(pageCount: 2) == "Doar fața")
        #expect(DocumentSharePages.front.title(pageCount: 4) == "Doar prima pagină")
    }

    @Test("The choices give the right files, with neutral names and nothing but the picture")
    func shareChoices() throws {
        let root = Self.folder()
        defer { DocumentShareFiles.removeLeftovers(root: root) }
        let front = try Self.encoded(Self.marked(width: 400, height: 250))
        let back = try Self.encoded(CaptureDocumentStoreTests.page(width: 400, height: 250))
        let pages = DocumentPages.sources(pageImages: [front, back], original: nil, thumbnail: nil, framing: DocumentFraming())

        let both = try DocumentShareFiles.write(pages, choice: DocumentShareChoice(pages: .all, format: .pictures), name: "Carte de identitate", root: root)
        #expect(both.map(\.lastPathComponent) == ["Carte de identitate – fața.jpg", "Carte de identitate – spatele.jpg"])
        let properties = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(both[0] as CFURL, nil)!, 0, nil) as! [CFString: Any]
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect((properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] == nil)

        let backOnly = try DocumentShareFiles.write(pages, choice: DocumentShareChoice(pages: .back, format: .pictures), name: "Carte de identitate", root: root)
        #expect(backOnly.map(\.lastPathComponent) == ["Carte de identitate – spatele.jpg"])

        let pdf = try DocumentShareFiles.write(pages, choice: DocumentShareChoice(pages: .all, format: .pdf), name: "Carte de identitate", root: root)
        #expect(pdf.map(\.lastPathComponent) == ["Carte de identitate.pdf"])
        #expect(PDFDocument(url: pdf[0])?.pageCount == 2)
        #expect(PDFDocument(url: pdf[0])?.string?.isEmpty ?? true, "No text read off the document")

        let three = DocumentPages.sources(pageImages: [front, back, back], original: nil, thumbnail: nil, framing: DocumentFraming())
        let numbered = try DocumentShareFiles.write(three, choice: DocumentShareChoice(pages: .all, format: .pictures), name: "Poliță", root: root)
        #expect(numbered.map(\.lastPathComponent) == ["Poliță 1.jpg", "Poliță 2.jpg", "Poliță 3.jpg"])
        let first = try DocumentShareFiles.write(three, choice: DocumentShareChoice(pages: .front, format: .pictures), name: "Poliță", root: root)
        #expect(first.map(\.lastPathComponent) == ["Poliță.jpg"])

        #expect(DocumentShareFiles.safeName("Act/2026: copie") == "Act-2026- copie")
        #expect(DocumentShareFiles.safeName("  ") == "Act")
    }

    @Test("A PDF goes as its own pages, turned as shown, without the file's details")
    func pdfSharedAsPDF() throws {
        let root = Self.folder()
        defer { DocumentShareFiles.removeLeftovers(root: root) }
        let data = Self.pdf(pages: 3)
        let pages = DocumentPages.sources(pageImages: [], original: data, thumbnail: nil,
                                          framing: DocumentFraming(pages: [.plain, PageFraming(choice: PageChoice(quarterTurns: 1))]))
        let files = try DocumentShareFiles.write(pages, choice: DocumentShareChoice(pages: .all, format: .pdf), name: "Poliță", root: root)
        let shared = try #require(PDFDocument(url: files[0]))
        #expect(shared.pageCount == 3)
        #expect(shared.page(at: 1)?.rotation == 90)
        #expect(shared.page(at: 0)?.rotation == 0)
        #expect(shared.documentAttributes?[PDFDocumentAttribute.titleAttribute] == nil)

        let firstOnly = try DocumentShareFiles.write(pages, choice: DocumentShareChoice(pages: .front, format: .pictures), name: "Poliță", root: root)
        let firstSize = Self.pixelSize(try Data(contentsOf: firstOnly[0]))
        #expect(firstSize.width == 2479 && firstSize.height == 3508)
    }

    @Test("A document's files are named after its type or kind, never its holder or number")
    func neutralNames() throws {
        let context = try makeContext()
        let card = try Self.identityCard(pages: [Self.encoded(Self.marked())], in: context)
        #expect(DocumentShareFiles.name(for: card) == "Carte de identitate")
        let car = Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle,
                        values: FieldValues(["vehicle.plate": .text("B-123-ABC")]))
        context.insert(car)
        let policy = try AttachmentActions(context: context).file(DocumentDraft(title: "Poliță RCA B-123-ABC", fileName: "RCA.pdf", kind: .policy), asset: car)
        #expect(DocumentShareFiles.name(for: policy) == "Poliță")
        let other = try AttachmentActions(context: context).file(DocumentDraft(title: "Bon", fileName: "bon.heic", kind: .other), asset: car)
        #expect(DocumentShareFiles.name(for: other) == "Act")
    }

    @Test("A document from a locked category asks for Face ID every time; one from an open category doesn't")
    func lockedAsksFirst() async throws {
        let context = try makeContext()
        let card = try Self.identityCard(pages: [Self.encoded(Self.marked())], in: context)
        #expect(DocumentShareRequest(attachment: card, context: context).isFromLockedCategory, "Acte starts locked")
        let car = Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
        context.insert(car)
        let policy = try AttachmentActions(context: context).file(DocumentDraft(title: "Poliță RCA", fileName: "RCA.heic", kind: .policy), asset: car)
        #expect(!DocumentShareRequest(attachment: policy, context: context).isFromLockedCategory)

        let authenticator = FakeAuthenticator(.succeed)
        let vault = BiometricVaultManager(authenticator: authenticator, appLockEnabled: { false }, observesAppLifecycle: false)
        #expect(await vault.unlock(reason: "Test") == .success)
        #expect(await vault.confirmSharing(fromLockedCategory: true, reason: "Test") == .success)
        #expect(authenticator.prompts == 2, "Asked again, with the session open")
        #expect(vault.isSessionUnlocked, "The session is as it was")
        #expect(await vault.confirmSharing(fromLockedCategory: false, reason: "Test") == .success)
        #expect(authenticator.prompts == 2, "Nothing asked for an open category")
        authenticator.outcome = .cancel
        #expect(await vault.confirmSharing(fromLockedCategory: true, reason: "Test") == .cancelled)
    }

    @Test("A bank card's picture says to send it with care")
    func cardNeedsCare() {
        #expect(DocumentType.isSharedWithCare(DocumentType.bankCard))
        #expect(!DocumentType.isSharedWithCare(DocumentType.idCard))
        let request = DocumentShareRequest(pages: [], name: "Card bancar", needsCare: true)
        #expect(request.needsCare)
    }

    @Test("A share's files are temporary: removed after it, and whatever a closed app left goes next time")
    func temporaryFilesGo() throws {
        let root = Self.folder()
        let pages = DocumentPages.sources(pageImages: [try Self.encoded(Self.marked())], original: nil, thumbnail: nil, framing: DocumentFraming())
        let files = try DocumentShareFiles.write(pages, choice: DocumentShareChoice(), name: "Act", root: root)
        #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path()) })
        #expect(files.allSatisfy { $0.path().hasPrefix(root.path()) })
        DocumentShareFiles.remove(files)
        #expect(!files.contains { FileManager.default.fileExists(atPath: $0.path()) })
        #expect(!FileManager.default.fileExists(atPath: files[0].deletingLastPathComponent().path()))

        let left = try DocumentShareFiles.write(pages, choice: DocumentShareChoice(format: .pdf), name: "Act", root: root)
        #expect(FileManager.default.fileExists(atPath: left[0].path()))
        DocumentShareFiles.removeLeftovers(root: root)
        #expect(!FileManager.default.fileExists(atPath: root.path()))

        #expect(throws: DocumentShareFiles.ShareError.nothingToSend) {
            try DocumentShareFiles.write([], choice: DocumentShareChoice(), name: "Act", root: root)
        }
    }

    // MARK: Backups

    @Test("A backup carries how the pages are shown")
    func backupCarriesFraming() throws {
        let context = try makeContext()
        let framing = DocumentFraming(pages: [PageFraming(crop: Self.cardCorners, quarterTurns: 1, choice: PageChoice(showsWholePhoto: true))])
        let card = try Self.identityCard(pages: [Self.encoded(Self.marked())], framing: framing, in: context)
        let id = card.id
        let data = try DossierArchiveService(container: context.container).exportData()

        let target = try makeInMemoryContainer()
        try DossierArchiveService(container: target).importArchive(data, mode: .replace)
        let restored = try #require(try ModelContext(target).fetch(FetchDescriptor<DosarCuSina.Attachment>(predicate: #Predicate { $0.id == id })).first)
        #expect(restored.framing == framing)
    }
}
