import Foundation
import Testing
@testable import DosarCuSina

/// One source for each thing capture decides: a model's numbers are read by the one number
/// reader, a kind's labels live in its tables, what a kind is and keeps is its profile's,
/// and values are compared one way. All names, firms, codes and numbers are placeholders.
@Suite("Capture, one profile")
struct CaptureOneProfileTests {

    static let today = CalendarDay(printedYear: 2026, month: 11, day: 10)!

    // MARK: A model's numbers

    @Test("A model's number is read one way, as printed or as a JSON number")
    func modelNumbersReadOneWay() {
        #expect(ModelQuestions.number(.string("1.234,56"), as: .money)?.value == Decimal(string: "1234.56"))
        #expect(ModelQuestions.number(.string("1234.56"), as: .money)?.value == Decimal(string: "1234.56"))
        #expect(ModelQuestions.number(.string("350 lei"), as: .money)?.value == 350)
        // A JSON number keeps its digits: no detour through floating point arithmetic.
        #expect(ModelQuestions.number(.number(19.99), as: .money)?.value == Decimal(string: "19.99"))
        #expect(ModelQuestions.number(.number(1240), as: .money)?.value == 1240)
        #expect(ModelQuestions.number(.int(45724), as: .kilometres)?.value == 45724)
        // A number that could read two ways is marked, as on the phone's own reading.
        let doubtful = ModelQuestions.number(.string("3,750"), as: .money)
        #expect(doubtful?.value == Decimal(string: "3.75"))
        #expect(doubtful?.needsCheck == true)
        // Whole kinds are never cut short; text that isn't a number is refused.
        #expect(ModelQuestions.number(.string("45,7"), as: .kilometres) == nil)
        #expect(ModelQuestions.number(.number(45.7), as: .count) == nil)
        #expect(ModelQuestions.number(.string("cinci"), as: .money) == nil)
        #expect(ModelQuestions.number(.null, as: .money) == nil)
        #expect(ModelQuestions.number(nil, as: .money) == nil)
        #expect(ModelQuestions.number(.string("12.345,678"), as: .meterIndex)?.value == Decimal(string: "12345.678"))
    }

    @Test("Text in an answer is never read as a number by the JSON value itself")
    func jsonTextIsNoNumber() {
        #expect(JSONValue.string("12.5").double == nil)
        #expect(JSONValue.number(12.5).double == 12.5)
        #expect(JSONValue.int(12).double == 12)
    }

    @Test("A money answer written the Romanian way is kept, its lines too")
    func romanianMoneyAnswersAreKept() {
        let text = """
        SERVICE EXEMPLU S.R.L.
        Factura nr. EXM 0000001 din 03.11.2026
        Schimb ulei 350,50
        Total de plată 1.234,56 lei
        """
        let answer: JSONValue = [
            "total": ["amount": "1.234,56", "currency": "RON"],
            "lineItems": [["description": "Schimb ulei", "amount": "350,50"]],
        ]
        let fields = ModelAnswerMapper.fields(from: answer, asked: ModelQuestions(kind: .serviceInvoice, reader: .page), recognizedText: text,
                                              today: Self.today, resolver: CatalogComponentResolver())
        let total = fields.first { $0.key == .total }
        #expect(total?.value == .money(Money(Decimal(string: "1234.56")!, currency: "RON")))
        #expect(total?.confidence == ModelAnswerMapper.grounded, "The amount is printed on the page")
        let lines = fields.first { $0.key == .lineItems }?.value.lineItems
        #expect(lines?.first?.amount == Money(Decimal(string: "350.5")!, currency: "RON"))
    }

    // MARK: Labels in their tables

    @Test("A policy's number and policyholder rows are its table's, read by both readers")
    func policyRowsAreThePolicyTable() {
        for kind in [CaptureDocumentKind.rcaPolicy, .insurancePolicy] {
            for key in [CaptureFieldKey.policyNumber, .policyholder, .policyholderPersonalNumber] {
                #expect(!CaptureKindProfile.labels(for: key, in: kind.profile.labels).isEmpty, "\(kind): \(key)")
            }
        }
        let numberWords = Set(CompositeLabels.policy.filter { $0.0 == .value }.flatMap { $0.1 }.compactMap(\.words))
        #expect(numberWords.isSuperset(of: CaptureKindProfile.labels(for: .policyNumber, in: CaptureKindProfile.policyLabels)))
        #expect(numberWords.isSuperset(of: CompositeLabels.greenCardNumber.compactMap(\.words)), "An RCA printed with its green card")
        let holderWords = Set(PolicyholderReader.labels.filter { $0.0 == .name }.flatMap { $0.1 }.compactMap(\.words))
        #expect(holderWords == Set(CaptureKindProfile.labels(for: .policyholder, in: CaptureKindProfile.policyLabels)))
    }

    @Test("The capture lexicon is written folded")
    func lexiconIsFolded() {
        let lists = [CaptureLexicon.nonItemWords, CaptureLexicon.buyerLabels, CaptureLexicon.issuerPrefixes,
                     CaptureLexicon.policyholderNeighbourLabels, CaptureLexicon.identityWords, Array(CaptureLexicon.wholeSignalWords)]
            + CaptureLexicon.supplyAddressLabels.map { $0.1 } + CaptureKindProfile.contractLabels.map { $0.1 }
        for word in lists.flatMap({ $0 }) {
            #expect(RomanianText.fold(word) == word, "\"\(word)\" is written folded")
        }
    }

    @Test("An issuer's prefix is taken off whatever its letters")
    func issuerPrefixesAreFolded() {
        for line in ["Vânzător: EXEMPLU COMERȚ S.R.L.", "Vanzator: EXEMPLU COMERȚ S.R.L.", "FURNIZOR: EXEMPLU COMERȚ S.R.L."] {
            #expect(RomanianFieldExtractor.issuerName(in: CaptureText(line))?.name == "EXEMPLU COMERȚ S.R.L.", "\(line)")
        }
    }

    // MARK: What a kind is and keeps

    @Test("Every field a kind is asked for is kept", arguments: CaptureDocumentKind.allCases)
    func askedFieldsAreKept(kind: CaptureDocumentKind) {
        for key in kind.expectedKeys {
            #expect(kind.allows(key), "\(kind) is asked for \(key) and keeps it")
        }
        for field in ModelQuestions(kind: kind, reader: .page).fields {
            if let key = field.key { #expect(kind.allows(key), "\(kind): \(key)") }
        }
    }

    @Test("A personal document with a machine-readable zone keeps what the zone gives")
    func zoneFieldsAreKept() {
        for kind in [CaptureDocumentKind.passport, .identityCard] {
            for key in CaptureAnalyzer.machineReadableKeys {
                #expect(kind.allows(key), "\(kind): \(key)")
            }
        }
        #expect(CaptureDocumentKind.criminalRecord.allows(.expiryDate), "A cazier is asked for its expiry, so it keeps one")
        #expect(!CaptureDocumentKind.bankCard.allows(.personalNumber))
        #expect(!CaptureDocumentKind.drivingLicence.allows(.lineItems))
    }

    @Test("What a kind is comes from its profile alone")
    func kindFactsAreTheProfile() {
        for kind in CaptureDocumentKind.allCases {
            let profile = kind.profile
            #expect(profile.isBill == (kind == .utilityInvoice), "\(kind)")
            #expect(profile.isIdentityDocument == [.passport, .identityCard, .drivingLicence].contains(kind), "\(kind)")
            #expect(profile.essentialKeys.isEmpty != profile.isIdentityDocument, "\(kind): an identity document is judged by its essentials")
            #expect(profile.hasMachineReadableBack == (kind == .identityCard), "\(kind)")
            #expect(profile.readsPaymentCode == [.utilityInvoice, .serviceInvoice, .other].contains(kind), "\(kind)")
            #expect(kind.isIdentityDocument == profile.isIdentityDocument)
            #expect(kind.essentialKeys == profile.essentialKeys)
        }
        #expect(CaptureDocumentKind.identityCard.essentialKeys == [.surname, .documentNumber, .expiryDate])
    }

    // MARK: Compared one way

    @Test("Values are compared folded, in capitals, letters and digits only")
    func compactIsOneWay() {
        #expect(RomanianText.compact("B-123 abc") == "B123ABC")
        #expect(RomanianText.compact("Ștefan Exemplu S.R.L.") == "STEFANEXEMPLUSRL")
        #expect(RomanianText.compact("RO49 AAAA 1B31 0075 9384 0000") == "RO49AAAA1B31007593840000")
        #expect(RomanianText.compact(" - / ") == "")
        #expect(PaperIdentity.comparable("exm 0000001") == "EXM0000001")
        #expect(PaperIdentity.comparable(" - ") == nil)
        #expect(FieldFormatter.formatPlate("b 123 abc") == "B-123-ABC")
        // A stored code has no diacritics; one read with them still matches it.
        #expect(SubscriptionMatcher.normalized("RO005E000000001", as: .pod) == SubscriptionMatcher.normalized("ro 005e 000 000 001", as: .pod))
        #expect(SubscriptionMatcher.normalized("CLC-ÎNC-01", as: .clc) == SubscriptionMatcher.normalized("CLCINC01", as: .clc))
    }
}
