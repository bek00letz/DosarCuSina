import Foundation
import Testing
@testable import DosarCuSina

/// Sample values for the card tests, the same everywhere: the networks' published test
/// numbers, and a microchip made up from obviously fake digits, never written out.
enum CardSamples {
    static let visa = "4111 1111 1111 1111"
    static let visaInOnePiece = "4111111111111111"
    static let mastercard = "5555555555554444"
    static let visaMasked = "\(PaymentCardNumbers.mask) 1111"

    /// A Romanian microchip's shape (642, then obviously fake digits) that passes the Luhn
    /// check: alone, its digits read as a Maestro card.
    static let chip = withCheckDigit("642" + String(repeating: "0", count: 8) + "123")

    static let bankCardFront = """
    Banca Transilvania
    DEBIT
    \(visa)
    VALID THRU 08/28
    ION EXEMPLU
    VISA
    """

    /// The digits with the Luhn check digit added.
    static func withCheckDigit(_ digits: String) -> String {
        let values = digits.compactMap(\.wholeNumberValue)
        let sum = values.reversed().enumerated().reduce(0) { total, item in
            let doubled = item.offset.isMultiple(of: 2) ? item.element * 2 : item.element
            return total + (doubled > 9 ? doubled - 9 : doubled)
        }
        return digits + String((10 - sum % 10) % 10)
    }

    /// Whether `text` holds either test number, however it is spaced.
    static func holdsTestNumber(_ text: String) -> Bool {
        let digits = text.filter { $0.isNumber || $0 == "•" }
        return digits.contains("4111111111111111") || digits.contains("5555555555554444")
    }
}

/// A card-shaped number names a bank card only beside the card's own cues (`CardNumberCues`),
/// so a vet record with a microchip that passes as a Maestro card stays a vet record, and a
/// bank card is still one. Placeholder data only (`CardSamples`).
@Suite("A card number with its cues")
struct CardNumberCuesTests {
    static let cues = CaptureKindProfile.bankCardCues

    private func kind(of text: String) -> CaptureDocumentKind {
        DocumentClassifier.classify(text: CaptureText(text), mrz: nil).kind
    }

    private func evidence(_ text: String) -> CardNumberCues.Evidence {
        Self.cues.evidence(in: CaptureText(text))
    }

    // MARK: The bank card's cues

    @Test func theCuesAreTheBankCardsOwnData() {
        #expect(CaptureDocumentKind.bankCard.profile.cardNumberCues != nil)
        for kind in CaptureDocumentKind.allCases where kind != .bankCard {
            #expect(kind.profile.cardNumberCues == nil, "\(kind)")
        }
        #expect(Self.cues.pageWords.contains("visa") && Self.cues.pageWords.contains("maestro"), "Its networks, from PaymentCardNetwork")
        #expect(Self.cues.nearbyWords == IdentityTemplates.cardExpiryCaptions)
        #expect(!Self.cues.nearbyWords.contains("valabil pana la"), "A vaccine's or an inspection's caption too")
        #expect(IdentityTemplates.labels(of: .expiryDate, for: .bankCard).contains(.words("valabil pana la")), "It still reads a card's expiry")
    }

    @Test func aCardNumberWithItsCues() {
        #expect(evidence("Plată") == .noNumber)
        #expect(evidence(CardSamples.visa) == .withCues, "Printed in a card's grouping")
        #expect(evidence("\(CardSamples.visaInOnePiece)\nVALID THRU") == .withCues, "A caption only a card prints, near it")
        #expect(evidence("\(CardSamples.visaInOnePiece)\nION EXEMPLU 08/28") == .withCues, "An expiry as a card prints it, near it")
        #expect(evidence("Mastercard\n\n\n\n\(CardSamples.visaInOnePiece)") == .withCues, "A network's name, anywhere on the page")
        #expect(evidence(CardSamples.visaInOnePiece) == .bare)
        #expect(evidence("\(CardSamples.visaInOnePiece)\nExp 03/2027") == .bare, "A vaccine's month and year in four digits")
        #expect(evidence("\(CardSamples.visaInOnePiece)\nValabil până la 12.03.2027") == .bare)
        #expect(evidence("08/28\nA\nB\nC\n\(CardSamples.visaInOnePiece)") == .bare, "Too far from the number")
        #expect(evidence("Microcip \(CardSamples.chip)") == .bare)
    }

    @Test func aBankCardIsStillABankCard() {
        #expect(kind(of: CardSamples.bankCardFront) == .bankCard)
        #expect(kind(of: CardSamples.visa) == .bankCard, "Its number in fours, nothing else read")
        #expect(kind(of: "\(CardSamples.visaInOnePiece)\n08/28") == .bankCard)
        #expect(kind(of: "VISA\n\(CardSamples.visaInOnePiece)") == .bankCard)
        #expect(kind(of: CardSamples.visaInOnePiece) == .bankCard, "A page that shows nothing else")
        #expect(kind(of: "BANCA EXEMPLU\nVALID THRU 08/28\nION EXEMPLU") == .bankCard, "Its words without its number")
    }

    @Test func aVetRecordWithAMicrochipThatLooksLikeACardStaysAVetRecord() {
        #expect(PaymentCardNumbers.containsCardNumber(CardSamples.chip), "Alone, the digits look like a Maestro card")
        #expect(kind(of: "Microcip \(CardSamples.chip)") == .veterinaryRecord)
        #expect(kind(of: "Microcip: \(CardSamples.chip)\nValabil până la 12.03.2027") == .veterinaryRecord)
        #expect(kind(of: "Microcip \(CardSamples.chip)\nVaccin Exemplu Exp 03/2027") == .veterinaryRecord)
        #expect(kind(of: "Cabinet veterinar Exemplu\nMicrocip\n\(CardSamples.chip)\nVaccin antirabic\nMedic veterinar Exemplu Ana") == .veterinaryRecord)
        // A bare number gives a hint only where no kind has a word of its own.
        #expect(kind(of: "Vaccin\n\(CardSamples.chip)") == .veterinaryRecord)
    }

    @Test func aVetRecordIsReadAsOneAndKeepsItsMicrochip() async throws {
        let text = "Cabinet veterinar Exemplu\nMicrocip \(CardSamples.chip)\nVaccin antirabic"
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: CaptureEngineTests.FixedRecognizer(text: text),
                                   normalizer: nil, onDeviceModel: nil, cloudModel: nil, store: nil)
        let result = try await engine.capture(CaptureRequest(.text(text), options: CaptureOptions(useOnDeviceModel: false, storeDocument: false)))
        #expect(result.kind == .veterinaryRecord)
        #expect(result.field(.microchip)?.value.text == CardSamples.chip)
        #expect(result.recognizedText.contains(CardSamples.chip), "Not masked strictly as a card")
    }
}
