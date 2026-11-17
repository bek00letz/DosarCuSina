import CoreGraphics
import Foundation
import PDFKit
import SwiftData
import Testing
@testable import DosarCuSina

/// A PAD policy (the mandatory home insurance) is read like every other policy: its kind,
/// its insurer and their tax ID, its series and number, its period, the sum it insures for,
/// its premium, the home it insures and who holds it, and the home's PAD deadline it files
/// into. Its PDF is a form, so it is read by where each piece of text is printed
/// (`PDFTextLines`). Every value is a placeholder (`PADPolicyFixture`).
@Suite("Reading a PAD policy")
struct PADReadingTests {
    let today = Date(timeIntervalSince1970: 1_793_577_600) // 2 November 2026

    /// The insurers the analyzer knows, with the seller of the fixture among them, before the
    /// pool, as a partner insurer is in the catalog.
    static var insurers: [InsuranceProviderItem] {
        [InsuranceProviderItem(id: "vanzator", name: "Vânzător Exemplu", words: ["vanzator exemplu"])] + CaptureAnalyzer.catalogInsurers
    }

    static var paid: String { RomanianInsuranceCatalog.recommendedInsurers.first { $0.id == "paid" }?.name ?? "" }

    struct NoText: CaptureRecognizing {
        func recognize(_ image: CGImage) async throws -> RecognizedPage { RecognizedPage(lines: [], barcodes: []) }
    }

    /// The fixture's PDF as the app reads it, without a language model.
    static func captured(_ data: Data = PADPolicyFixture.pdf(), today: Date) async throws -> CaptureResult {
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(insurers: insurers), recognizer: NoText(), normalizer: nil,
                                   onDeviceModel: nil, cloudModel: nil, store: nil)
        return try await engine.capture(CaptureRequest(.pdf(data), options: CaptureOptions(useOnDeviceModel: false, storeDocument: false, referenceDate: today)))
    }

    // MARK: Field by field

    @Test("A PAD's PDF is read field by field, as a policy")
    func aPADIsReadFieldByField() async throws {
        let result = try await Self.captured(today: today)
        #expect(result.kind == .insurancePolicy)
        #expect(result.field(.coverageType)?.value == .text(InsuranceCover.pad))
        #expect(result.field(.provider)?.value == .text(Self.paid), "The pool issues it, whoever sold it")
        #expect(result.field(.providerTaxID)?.value == .text("12345674"), "The pool's own tax ID, never the seller's")
        #expect(result.field(.policyNumber)?.value == .text("RA-000 0000000012"), "Its own series and number, never the one it renews")
        #expect(result.field(.policyNumber)?.needsCheck == false)
        #expect(result.field(.startDate)?.value == .day(CalendarDay("2026-12-01")))
        #expect(result.field(.expiryDate)?.value == .day(CalendarDay("2027-11-30")))
        #expect(result.field(.total)?.value == .money(Money(100, currency: "RON")), "The premium")
        #expect(result.field(.insuredSum)?.value == .money(Money(50_000, currency: "RON")))
        #expect(result.field(.insuredAddress)?.value == .text(PADPolicyFixture.address))
        #expect(result.field(.policyholder)?.value == .text("Exemplu Ion"))
        #expect(result.reminder?.blueprintKey == BuiltInBlueprints.homePAD, "It files into the home's PAD")
        #expect(result.reminder?.day == CalendarDay("2027-11-30"))
    }

    @Test("A form's row of labels is read with each value after its label")
    func aRowOfLabelsKeepsItsValues() throws {
        let pages = PDFTextLines.pages(of: PADPolicyFixture.pdf(), maxPages: CaptureEngine.maxPDFPages)
        #expect(pages.count == 3)
        let rows = CaptureText(pages: pages).joiningRows().original
        #expect(rows.contains { $0.hasPrefix("Seria: RA-000 Nr: 0000000012") && $0.hasSuffix("reînnoiește PAD Seria: RA-000 Nr: 0000000013") })
        #expect(rows.contains("PERIOADĂ DE VALABILITATE: 1 AN De la: 01.12.2026 Până la: 30.11.2027"))
        #expect(rows.contains("PRIMA DE ASIGURARE: 100 LEI încasată în data de: 25.11.2026"))
    }

    @Test("A turned page's lines are placed as the page is shown")
    func aTurnedPageIsShownTurned() throws {
        let page = try #require(PDFDocument(data: PADPolicyFixture.pdf())?.page(at: 2))
        let area = page.bounds(for: .cropBox)
        let corner = CGRect(x: area.minX, y: area.maxY - 10, width: 20, height: 10) // the top-left corner, upright
        #expect(PDFTextLines.box(of: corner, on: page, area: area).x == 0)
        page.rotation = 90
        let turned = PDFTextLines.box(of: corner, on: page, area: area)
        #expect(abs(turned.maxX - 1) < 0.001 && turned.y == 0, "Turned a quarter clockwise, the top-left is at the top-right")
    }

    // MARK: The rules that read it

    @Test("The policy a PAD renews is never its number")
    func theRenewedPolicyIsNotThisOne() {
        let analysis = CaptureAnalyzer().analyze(text: "Seria: RA-000 Nr: 0000000012 reînnoiește PAD Seria: RA-000 Nr: 0000000013",
                                                 referenceDate: today, as: .insurancePolicy)
        let number = analysis.fields.first { $0.key == .policyNumber }
        #expect(number?.value.text == "RA-000 0000000012")
        #expect(number?.needsCheck == false, "Not two policy numbers to choose from")
        #expect(CompositeValue.policy.parts(in: "SERIA: RA-000 NR: 0000000012") == .init(series: "RA-000", number: "0000000012"))
    }

    @Test("A PAD is the pool's even when only its seller is named")
    func aPADIsThePoolsWhoeverSoldIt() {
        let analysis = CaptureAnalyzer(insurers: Self.insurers).analyze(text: """
            ASIGURAREA OBLIGATORIE A LOCUINȚEI - POLIȚĂ PAD
            prin: VÂNZĂTOR EXEMPLU ASIGURĂRI S.A., CUI 11111110
            Seria: RA-000 Nr: 0000000012
            """, referenceDate: today, as: .insurancePolicy)
        #expect(analysis.fields.first { $0.key == .provider }?.value == .text(Self.paid))
        #expect(!analysis.fields.contains { $0.key == .providerTaxID }, "The seller's tax ID is never the pool's")
    }

    @Test("A home policy's sum and the home it insures are read from its table, never its holder's address")
    func theSumAndTheHomeAreItsOwn() {
        let analysis = CaptureAnalyzer().analyze(text: """
            POLIȚĂ DE ASIGURARE A LOCUINȚEI
            Asigurat: EXEMPLU ION, domiciliul: Str. Altă nr. 5, Exemplu
            Suma asigurată: 50.000 lei
            Prima de asigurare: 100 lei
            Adresa locuinței asigurate: Str. Exemplu nr. 1, ap. 2, Exemplu
            """, referenceDate: today, as: .insurancePolicy)
        #expect(analysis.fields.first { $0.key == .insuredSum }?.value == .money(Money(50_000, currency: "RON")))
        #expect(analysis.fields.first { $0.key == .total }?.value == .money(Money(100, currency: "RON")))
        #expect(analysis.fields.first { $0.key == .insuredAddress }?.value == .text("Str. Exemplu nr. 1, ap. 2, Exemplu"))
        #expect(!CaptureDocumentKind.utilityInvoice.allows(.insuredAddress), "Only a policy names the home it insures")
    }

    @Test("A UAT names the town of an address, as a policy prints it")
    func theUATIsTheTown() throws {
        let read = try #require(PostalAddress(PADPolicyFixture.address))
        let kept = try #require(PostalAddress("Str. Exemplu nr. 1, ap. 2, Exemplu"))
        #expect(read.agreement(with: kept) == .same)
        #expect(read.street == ["exemplu"])
    }

    // MARK: Filed into its home

    @MainActor
    private func homes(_ addresses: [String], in context: ModelContext) throws -> [Asset] {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.home))
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        return try addresses.enumerated().map { index, address in
            var values = FieldValues()
            values[HomeFields.address] = .text(address)
            return try actions.create(name: "Locuința \(index + 1)", template: template, values: values)
        }
    }

    @Test("A PAD goes to the home at the address it insures")
    @MainActor
    func aPADFindsItsHome() async throws {
        let context = try makeContext()
        let homes = try homes(["Str. Altă nr. 5, Exemplu", "Str. Exemplu nr. 1, ap. 2, Exemplu"], in: context)
        let review = CaptureReview(result: try await Self.captured(today: today), assets: homes, context: context)
        #expect(review.destination == .asset(homes[1].id))
        #expect(review.placeCheck == nil)
        #expect(review.deadlineBlueprint(in: BuiltInTemplates.home)?.key == BuiltInBlueprints.homePAD)
    }

    @Test("The only home at another address is chosen, marked to check")
    @MainActor
    func theOnlyHomeElsewhereIsMarked() async throws {
        let context = try makeContext()
        let homes = try homes(["Str. Altă nr. 5, Exemplu"], in: context)
        let review = CaptureReview(result: try await Self.captured(today: today), assets: homes, context: context)
        #expect(review.destination == .asset(homes[0].id))
        #expect(review.placeCheck == .addressDiffers)
        #expect(CaptureReviewWording.placeCheck(.addressDiffers, address: review.placeAddressKey) == CaptureReviewWording.insuredAddressDiffers)
    }

    @Test("A new home made from its PAD takes the address the policy names")
    @MainActor
    func aNewHomeTakesThePolicysAddress() async throws {
        let context = try makeContext()
        var review = CaptureReview(result: try await Self.captured(today: today), assets: [], context: context)
        #expect(review.destination == .newAsset(templateKey: BuiltInTemplates.Key.home))
        review.newAssetName = "Apartament"
        let outcome = try await CaptureFiler(context: context, calendar: .bucharest, now: { noon("2026-11-02") }).save(review)
        let home = try #require(outcome.asset)
        #expect(home.values[HomeFields.address] == .text(PADPolicyFixture.address))
        #expect(home.values[HomeFields.policyNumber] == .text("RA-000 0000000012"))
        #expect(home.values[HomeFields.insurer] == .text(Self.paid))
        #expect(home.activeObligations.first { $0.blueprintKey == BuiltInBlueprints.homePAD }?.dueDay == CalendarDay("2027-11-30"))
    }
}
