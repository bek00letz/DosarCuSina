import Foundation
import Testing
@testable import DosarCuSina

/// Apple's model, standing in: it keeps the text it was handed.
private final class ReadingModel: CaptureSemanticExtracting, @unchecked Sendable {
    let tier: CaptureTier = .onDeviceModel
    private(set) var texts: [String] = []
    func availability() -> CaptureModelAvailability { .available }
    func extract(_ input: SemanticInput) async throws -> SemanticExtraction {
        texts.append(input.text)
        return SemanticExtraction(kind: nil, fields: [])
    }
}

/// The text a language model reads has its card numbers masked by the rule capture's result
/// goes through (`CaptureCardMask`, `SemanticInput.text`), keeping what a bank card's questions
/// need; the AI provider is sent no text at all. Placeholder data only (`CardSamples`).
@Suite("The text a model reads")
struct ModelTextTests {
    private func modelInput(_ text: String, kind: CaptureDocumentKind, known: [CaptureField] = []) -> SemanticInput {
        SemanticInput(text: text, firstPage: nil, kind: kind, knownFields: known)
    }

    @Test func aBankCardsNumberNeverReachesAModelButWhatItsQuestionsNeedDoes() {
        for kind in [CaptureDocumentKind.bankCard, .other] {
            let input = modelInput(CardSamples.bankCardFront, kind: kind)
            #expect(!CardSamples.holdsTestNumber(input.text), "\(kind)")
            #expect(input.text.contains("\(PaymentCardNumbers.mask) 1111"), "Its last four digits")
            for kept in ["VALID THRU 08/28", "VISA", "Banca Transilvania", "ION EXEMPLU", "DEBIT"] {
                #expect(input.text.contains(kept), "\(kept)")
            }
            #expect(input.recognizedText == CardSamples.bankCardFront, "Kept as read, to check answers against")
            for prompt in [OnDeviceModelExtractor.kindPrompt(text: input.text, guess: kind),
                           OnDeviceModelExtractor.factsPrompt(.bankCard, text: input.text)] {
                #expect(!CardSamples.holdsTestNumber(prompt))
            }
        }
        // On a bank card, strictly: a misread digit doesn't let the rest through.
        let misread = modelInput("4111 1111 1111 1112\nVALID THRU 08/28", kind: .bankCard)
        #expect(!misread.text.contains("4111 1111 1111"))
        #expect(misread.text.contains("1112"))
    }

    @Test func aCardOnAnyOtherPaperIsMaskedAndTheRestStays() {
        let receipt = modelInput("BON FISCAL\nPlătit cu cardul \(CardSamples.mastercard)\nTotal 45,00", kind: .fiscalReceipt)
        #expect(!CardSamples.holdsTestNumber(receipt.text))
        #expect(receipt.text.contains("\(PaymentCardNumbers.mask) 4444"))
        #expect(receipt.text.contains("Total 45,00"))
    }

    @Test func aMicrochipThePhoneReadStaysWholeForTheModel() {
        let text = "Microcip \(CardSamples.chip)\nPlată cu cardul \(CardSamples.visa)"
        let read = CaptureField(key: .microchip, value: .text(CardSamples.chip), confidence: 0.85, sourceText: "Microcip \(CardSamples.chip)", tier: .heuristic)
        let given = modelInput(text, kind: .veterinaryRecord, known: [read])
        #expect(given.text == "Microcip \(CardSamples.chip)\nPlată cu cardul \(CardSamples.visaMasked)")
        // Nothing read as a microchip: the digits are a card's for all anyone knows.
        let unread = modelInput(text, kind: .veterinaryRecord)
        #expect(!unread.text.contains(CardSamples.chip))
        // The same rule as capture's result, which keeps it in the text it hands out.
        let result = CaptureResult(kind: .veterinaryRecord, kindConfidence: 0.9, fields: [read], suggestions: [], reminder: nil,
                                   recognizedText: text, barcodes: [], document: nil, notices: []).withoutCardNumbers()
        #expect(result.recognizedText == given.text)
    }

    @Test func aBankCardsLastFourComeBackFromTheMaskedText() {
        let input = modelInput(CardSamples.bankCardFront, kind: .bankCard)
        let answer: JSONValue = ["cardLastFour": "1111", "cardNetwork": .string(PaymentCardNetwork.visa), "expiryDate": "2028-08-31"]
        for grounding in [input.recognizedText, input.text] {
            let fields = ModelAnswerMapper.fields(from: answer, asked: ModelQuestions(kind: .bankCard, reader: .text), recognizedText: grounding,
                                                  today: CalendarDay(printedYear: 2026, month: 11, day: 10)!, resolver: CatalogComponentResolver())
            #expect(fields.first { $0.key == .cardLastFour }?.value.text == "1111")
            #expect(fields.first { $0.key == .cardNetwork }?.value.text == PaymentCardNetwork.visa)
        }
    }

    @Test func theProviderIsSentTheQuestionsAndThePictureNeverTheText() throws {
        for kind in CaptureDocumentKind.allCases {
            let request = CloudCaptureExtractor.request(CloudSchema(kind: kind), jpeg: Data())
            let schema = String(decoding: try JSONEncoder().encode(request.schema), as: UTF8.self)
            #expect(!CardSamples.holdsTestNumber(request.instructions + schema), "\(kind)")
            #expect(!PaymentCardNumbers.containsCardNumber(request.instructions + schema), "\(kind)")
        }
    }

    // MARK: Through the engine

    @Test("The engine hands Apple's model the text masked", arguments: [
        CardSamples.bankCardFront,
        "Chitanță\nPlătit cu cardul \(CardSamples.mastercard)",
        "Microcip \(CardSamples.chip)\nPlată cu cardul \(CardSamples.visa)",
    ])
    func theEngineHandsTheModelMaskedText(_ text: String) async throws {
        let model = ReadingModel()
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: CaptureEngineTests.FixedRecognizer(text: text),
                                   normalizer: nil, onDeviceModel: model, cloudModel: nil, store: nil)
        _ = try await engine.capture(CaptureRequest(.text(text), options: CaptureOptions(useOnDeviceModel: true, storeDocument: false)))
        let seen = try #require(model.texts.first)
        #expect(!CardSamples.holdsTestNumber(seen))
        #expect(seen.contains(PaymentCardNumbers.mask))
    }
}
