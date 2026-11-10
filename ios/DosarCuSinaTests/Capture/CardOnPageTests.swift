import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import DosarCuSina

/// A page that shows a whole card number is treated by what it shows, not by its kind: its
/// photo is kept only on request, it never leaves the phone and the share inbox shows no
/// picture of it. One rule decides it (`CaptureResult.showsCardNumber`, through
/// `CaptureCardMask.showsCardNumber`), leaving out a pet's microchip read into its field.
/// Placeholder data only (`CardSamples`): the networks' published test numbers and a
/// microchip made at test time from obviously fake digits.
@Suite("A page that shows a card number")
@MainActor
struct CardOnPageTests {
    static let referenceDate = noon("2026-11-03")

    /// A receipt with the card's number printed in one piece, and no card cue near it.
    static let receipt = """
    MAGAZIN EXEMPLU S.R.L.
    CIF 98765438
    BON FISCAL
    Data: 10.06.2026
    Cablu USB 1 buc 45,00
    TOTAL 45,00 LEI
    Plată card \(CardSamples.visaInOnePiece)
    """

    /// A vet's record whose microchip (642, shaped like a Maestro card and passing its check)
    /// is printed on its own line.
    static let vetRecord = """
    Cabinet veterinar Exemplu
    Microcip \(CardSamples.chip)
    Vaccin antirabic
    Medic veterinar Exemplu Ana
    """

    private func engine(cloud: CaptureEngineTests.StubModel? = nil, text: String) -> CaptureEngine {
        CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: CaptureEngineTests.FixedRecognizer(text: text),
                      normalizer: nil, onDeviceModel: nil, cloudModel: cloud, store: nil)
    }

    private func read(_ text: String, cloud: CaptureEngineTests.StubModel? = nil) async throws -> CaptureResult {
        try await engine(cloud: cloud, text: text).capture(CaptureRequest(.text(text), options: CaptureOptions(
            useOnDeviceModel: false, useCloudModel: cloud != nil, storeDocument: false, referenceDate: Self.referenceDate)))
    }

    private func cloud() -> CaptureEngineTests.StubModel {
        CaptureEngineTests.StubModel(tier: .cloudModel, isAvailable: true, fields: [])
    }

    /// The reading with its pages waiting in `store`, as a photo's capture hands it on.
    private func withPages(_ read: CaptureResult, in store: CaptureDocumentStore, seed: UInt8) async throws -> CaptureResult {
        let pages = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 600, height: 800, seed: seed)], kind: read.kind))
        return CaptureResult(id: read.id, kind: read.kind, kindConfidence: read.kindConfidence, fields: read.fields,
                             suggestions: read.suggestions, reminder: read.reminder, recognizedText: read.recognizedText,
                             barcodes: read.barcodes, document: pages.ref, notices: read.notices, kindEvidence: read.kindEvidence,
                             kindAlternatives: read.kindAlternatives, fieldAlternatives: read.fieldAlternatives,
                             readWithCloudModel: read.readWithCloudModel, source: read.source, showedCardNumber: read.showedCardNumber)
    }

    private func filer(_ context: ModelContext, store: CaptureDocumentStore) -> CaptureFiler {
        CaptureFiler(context: context, store: store, calendar: .bucharest, now: { Self.referenceDate })
    }

    // MARK: The rule

    @Test func theRuleReadsWhatThePageShows() {
        func page(_ kind: CaptureDocumentKind, _ text: String, fields: [CaptureField] = []) -> CaptureResult {
            CaptureResult(kind: kind, kindConfidence: 0.7, fields: fields, suggestions: [], reminder: nil, recognizedText: text,
                          barcodes: [], document: nil, notices: [])
        }
        let chip = CaptureField(key: .microchip, value: .text(CardSamples.chip), confidence: 0.9, tier: .heuristic)
        #expect(page(.fiscalReceipt, "Plată card \(CardSamples.visaInOnePiece)").showsCardNumber)
        #expect(page(.other, "Card \(CardSamples.mastercard)").showsCardNumber)
        #expect(page(.veterinaryRecord, "Microcip \(CardSamples.chip)").showsCardNumber, "Nothing read it as a microchip")
        #expect(!page(.veterinaryRecord, "Microcip \(CardSamples.chip)", fields: [chip]).showsCardNumber, "Read into its field")
        #expect(page(.veterinaryRecord, "Microcip \(CardSamples.chip)\nPlată \(CardSamples.visa)", fields: [chip]).showsCardNumber,
                "A card beside the microchip still counts")
        #expect(!page(.other, "Plată cu cardul \(CardSamples.visaMasked)").showsCardNumber, "Only the last four printed")
        #expect(!page(.criminalRecord, "CNP 1800101990006").showsCardNumber)

        // The text masked, the fact is kept; read again as another kind, still.
        let masked = page(.fiscalReceipt, "Plată card \(CardSamples.visaInOnePiece)").withoutCardNumbers()
        #expect(!CardSamples.holdsTestNumber(masked.recognizedText))
        #expect(masked.showedCardNumber && masked.showsCardNumber)
        #expect(engine(text: "").reinterpret(masked, as: .serviceInvoice).showsCardNumber)
        // A vet's record with its microchip in its field shows none, masked or not.
        #expect(!page(.veterinaryRecord, "Microcip \(CardSamples.chip)", fields: [chip]).withoutCardNumbers().showsCardNumber)
    }

    // MARK: A receipt with a whole card number

    @Test func aReceiptWithACardNumberKeepsItsPhotoOnlyOnRequest() async throws {
        let read = try await read(Self.receipt)
        #expect(read.kind != .bankCard, "Not taken for a bank card")
        #expect(read.showsCardNumber)
        #expect(read.photoIsOnRequest)
        #expect(!CardSamples.holdsTestNumber(read.recognizedText), "Its text masked as before")

        let context = try makeContext()
        let store = CaptureDocumentStore()
        let result = try await withPages(read, in: store, seed: 51)
        var review = CaptureReview(result: result, assets: [], context: context)
        #expect(review.photoIsOnRequest)
        #expect(!review.keepsPhoto, "Off by default")
        #expect(try filer(context, store: store).plan(for: review).keepsPhoto == false)
        review.keepsPhotoOnRequest = true
        #expect(review.keepsPhoto)
        #expect(try filer(context, store: store).plan(for: review).keepsPhoto)
        #expect(!KeepPhotoChoice(keepsPhoto: .constant(false), kind: review.kind).isCard, "A page's words, not a card's")
    }

    @Test func aReceiptWithACardNumberStaysOnThePhone() async throws {
        let model = cloud()
        let result = try await read(Self.receipt, cloud: model)
        #expect(model.calls == 0, "Nothing was sent")
        #expect(result.notices.contains(.readOnPhoneOnly))
        #expect(PhoneOnlyReading.mayBeOne(result))
        let context = try makeContext()
        #expect(!CaptureReview(result: result, assets: [], context: context).providerMayRead)
        #expect(!InboxPreviewer.mayKeepPicture(of: result), "No picture in De verificat")
    }

    @Test func aVisitsInvoiceWithACardNumberKeepsItsPhotoOnlyOnRequest() async throws {
        let store = CaptureDocumentStore()
        let invoice = try await withPages(try await read(Self.receipt), in: store, seed: 52)
        var draft = VisitDraft(date: Self.referenceDate)
        draft.apply(invoice, components: [])
        #expect(draft.photoOnRequestKind == invoice.kind)
        #expect(!draft.keepsPhoto, "Off by default")
        draft.keepsPhotoOnRequest = true
        #expect(draft.keepsPhoto)

        // Another invoice asks again; one without a card number keeps its photo.
        let plain = try await withPages(try await read("SERVICE EXEMPLU S.R.L.\nFACTURĂ\nTotal 120,00 lei"), in: store, seed: 53)
        draft.apply(plain, components: [])
        #expect(draft.photoOnRequestKind == nil)
        #expect(!draft.keepsPhotoOnRequest)
        #expect(draft.keepsPhoto)
    }

    // MARK: A vet's record with its microchip

    @Test func aVetRecordWithItsMicrochipKeepsItsPhoto() async throws {
        let read = try await read(Self.vetRecord)
        #expect(read.kind == .veterinaryRecord)
        #expect(read.field(.microchip)?.value.text == CardSamples.chip)
        #expect(!read.showsCardNumber)
        #expect(!read.photoIsOnRequest)

        let context = try makeContext()
        let store = CaptureDocumentStore()
        let review = CaptureReview(result: try await withPages(read, in: store, seed: 54), assets: [], context: context)
        #expect(!review.photoIsOnRequest)
        #expect(review.keepsPhoto)
        #expect(try filer(context, store: store).plan(for: review).keepsPhoto)
    }

    @Test func aVetRecordWithItsMicrochipMayGoToTheProviderAndShowsItsPicture() async throws {
        let onThePhone = try await read(Self.vetRecord)
        #expect(!PhoneOnlyReading.mayBeOne(onThePhone))
        #expect(InboxPreviewer.mayKeepPicture(of: onThePhone), "Its first page in De verificat")
        let context = try makeContext()
        #expect(CaptureReview(result: onThePhone, assets: [], context: context).providerMayRead, "„Citește mai bine” is offered")

        // Asked, the engine sends it.
        let model = cloud()
        let asked = try await read(Self.vetRecord, cloud: model)
        #expect(model.calls == 1)
        #expect(asked.readWithCloudModel)
        #expect(!asked.notices.contains(.readOnPhoneOnly))
        #expect(asked.recognizedText.contains(CardSamples.chip), "The microchip stays whole")
    }

    @Test func aVetRecordWithACardNumberBesideItsMicrochipStaysOnThePhone() async throws {
        let model = cloud()
        let result = try await read(Self.vetRecord + "\nPlată cu cardul \(CardSamples.visaInOnePiece)", cloud: model)
        #expect(result.field(.microchip)?.value.text == CardSamples.chip)
        #expect(model.calls == 0)
        #expect(result.showsCardNumber && result.photoIsOnRequest)
        #expect(!InboxPreviewer.mayKeepPicture(of: result))
    }

    // MARK: A bank card, as before

    @Test func aBankCardIsUnchanged() async throws {
        let model = cloud()
        let read = try await read(CardSamples.bankCardFront, cloud: model)
        #expect(read.kind == .bankCard)
        #expect(model.calls == 0, "Never sent")
        #expect(read.notices.contains(.readOnPhoneOnly))
        #expect(read.photoIsOnRequest)
        #expect(PhoneOnlyReading.mayBeOne(read))
        #expect(!InboxPreviewer.mayKeepPicture(of: read))

        let context = try makeContext()
        let store = CaptureDocumentStore()
        var review = CaptureReview(result: try await withPages(read, in: store, seed: 55), assets: [], context: context)
        #expect(!review.keepsPhoto, "Off by default")
        #expect(!review.providerMayRead)
        #expect(KeepPhotoChoice(keepsPhoto: .constant(false), kind: review.kind).isCard, "The card's own words")
        review.keepsPhotoOnRequest = true
        #expect(try filer(context, store: store).plan(for: review).keepsPhoto)
        // Its kind alone decides, whatever its text shows.
        let blank = CaptureResult(kind: .bankCard, kindConfidence: 0.9, fields: [], suggestions: [], reminder: nil, recognizedText: "",
                                  barcodes: [], document: nil, notices: [])
        #expect(!blank.showsCardNumber && blank.photoIsOnRequest && PhoneOnlyReading.mayBeOne(blank))
    }
}
