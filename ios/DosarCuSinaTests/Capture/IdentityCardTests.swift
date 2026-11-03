import Foundation
import Testing
@testable import DosarCuSina

/// Romanian identity card fronts, both layouts, read from their printed labels.
/// Names are placeholders. The CNPs are fabricated with county code 99, which no
/// county has, so they can't belong to anyone; their control digits are valid.
@Suite("Identity card front")
struct IdentityCardTests {

    let analyzer = CaptureAnalyzer()
    let today = Date(timeIntervalSince1970: 1_793_577_600)

    private func fields(_ analysis: CaptureAnalyzer.Analysis) -> [CaptureFieldKey: CaptureField] {
        Dictionary(analysis.fields.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    @Test("Electronic card: bilingual labels, values under them, CNP beside its label")
    func electronicCard() throws {
        let analysis = analyzer.analyze(text: """
        ROMANIA
        CARTE DE IDENTITATE IDENTITY CARD
        Nume / Surname
        EXEMPLU
        Prenume / Given names
        ION-ANDREI
        Sex / Sex
        M
        Cetățenie / Nationality
        ROMÂNĂ / ROU
        Data nașterii / Date of birth
        01.01.1980
        CNP / PIN 1800101990006
        Nr. document / Document no.
        XY123456
        Data emiterii / Date of issue
        15.03.2022
        Data expirării / Date of expiry
        15.03.2032
        Semnătura titularului / Holder's signature
        """, referenceDate: today)

        #expect(analysis.kind == .identityCard)
        let byKey = fields(analysis)
        #expect(byKey[.surname]?.value.text == "EXEMPLU")
        #expect(byKey[.givenNames]?.value.text == "ION-ANDREI")
        #expect(byKey[.holderName]?.value.text == "ION-ANDREI EXEMPLU")
        #expect(byKey[.personalNumber]?.value.text == "1800101990006")
        #expect(byKey[.personalNumber]?.tier == .deterministic)
        #expect(byKey[.birthDate]?.value.day == CaptureDay(year: 1980, month: 1, day: 1))
        #expect(byKey[.documentNumber]?.value.text == "XY123456")
        #expect(byKey[.issueDate]?.value.day == CaptureDay(year: 2022, month: 3, day: 15))
        #expect(byKey[.expiryDate]?.value.day == CaptureDay(year: 2032, month: 3, day: 15))
        #expect(byKey[.sex]?.value.text == "M")
        #expect(byKey[.lineItems] == nil)
        #expect(byKey[.total] == nil)
    }

    @Test("A birth date is never taken for the issue or expiry date")
    func birthDateStaysABirthDate() {
        let analysis = analyzer.analyze(text: """
        CARTE DE IDENTITATE IDENTITY CARD
        Nume / Surname
        EXEMPLU
        Data nașterii / Date of birth
        31.12.1985
        CNP / PIN 2851231990018
        Valabilitate / Validity
        """, referenceDate: today)

        let byKey = fields(analysis)
        #expect(byKey[.birthDate]?.value.day == CaptureDay(year: 1985, month: 12, day: 31))
        #expect(byKey[.issueDate] == nil)
        #expect(byKey[.expiryDate] == nil)
    }

    @Test("Older card: trilingual labels, series and number on top, validity as a range")
    func olderCard() throws {
        let analysis = analyzer.analyze(text: """
        ROMANIA ROUMANIE ROMANIA
        CARTE DE IDENTITATE
        SERIA XT NR 123456
        CNP 2851231990018
        Nume/Nom/Last name
        EXEMPLU
        Prenume/Prenom/First name
        MARIA
        Cetatenie/Nationalite/Nationality
        Română / ROU
        Loc nastere/Lieu de naissance/Place of birth
        Jud. Exemplu Mun. Exemplu
        Domiciliu/Adresse/Address
        Str. Exemplului nr. 1
        Emisa de/Delivree par/Issued by
        SPCLEP Exemplu
        Valabilitate/Validite/Validity
        12.03.18-31.12.2028
        """, referenceDate: today)

        #expect(analysis.kind == .identityCard)
        let byKey = fields(analysis)
        #expect(byKey[.surname]?.value.text == "EXEMPLU")
        #expect(byKey[.givenNames]?.value.text == "MARIA")
        #expect(byKey[.documentNumber]?.value.text == "XT123456")
        #expect(byKey[.birthDate]?.value.day == CaptureDay(year: 1985, month: 12, day: 31))
        #expect(byKey[.issueDate]?.value.day == CaptureDay(year: 2018, month: 3, day: 12))
        #expect(byKey[.expiryDate]?.value.day == CaptureDay(year: 2028, month: 12, day: 31))
        #expect(byKey[.issuer]?.value.text == "SPCLEP Exemplu")
    }

    @Test("The CNP control digit is checked")
    func cnpControlDigit() {
        #expect(RomanianFieldExtractor.isValidCNP("1800101990006"))
        #expect(!RomanianFieldExtractor.isValidCNP("1800101990007"))
        #expect(!RomanianFieldExtractor.isValidCNP("180010199000"))
        #expect(RomanianFieldExtractor.birthDate(fromCNP: "5050505990000") == CaptureDay(year: 2005, month: 5, day: 5))
    }

    @Test("Identifiers are never money, and never a billed line")
    func identifiersAreNotMoney() {
        #expect(RomanianFieldExtractor.amount("1800101990006") == nil)
        #expect(RomanianFieldExtractor.amount("1250")?.value == 1250)
        #expect(RomanianFieldExtractor.amount("1.250,50")?.value == Decimal(string: "1250.50"))
        let items = RomanianFieldExtractor.lineItems(
            in: CaptureText("CNP / PIN 1800101990006\nPlăcuțe frână față 320,00"),
            currency: "RON", resolver: CatalogComponentResolver()
        )
        #expect(items.map(\.description) == ["Plăcuțe frână față"])
    }

    @Test("Each kind of document keeps only the fields that belong on it")
    func fieldsBelongToTheirKind() {
        #expect(!CaptureDocumentKind.identityCard.allows(.lineItems))
        #expect(!CaptureDocumentKind.identityCard.allows(.total))
        #expect(CaptureDocumentKind.identityCard.allows(.personalNumber))
        #expect(!CaptureDocumentKind.serviceInvoice.allows(.personalNumber))
        #expect(!CaptureDocumentKind.other.allows(.birthDate))
        #expect(CaptureDocumentKind.drivingLicence.allows(.licenceCategories))
        #expect(CaptureDocumentKind.serviceInvoice.allows(.lineItems))
    }
}

@Suite("Labels printed in three languages")
struct TrilingualLabelTests {

    @Test("A label's translations after it are part of the label, not its value", arguments: [
        ("/Authority/Autorité", ""),
        ("/Authority/Autorité SPCEEPS EXEMPLU", "SPCEEPS EXEMPLU"),
        (" / Authority / Autorité  SPCEEPS EXEMPLU", "SPCEEPS EXEMPLU"),
        (" 12.03.2031", " 12.03.2031"),
        (" SPCEEPS EXEMPLU", " SPCEEPS EXEMPLU"),
    ])
    func translationsAreDropped(rest: String, value: String) {
        #expect(LabelledLayout<String>.droppingTranslations(rest).trimmingCharacters(in: .whitespaces) == value.trimmingCharacters(in: .whitespaces))
    }

    @Test func thePassportAuthorityIsReadUnderItsTrilingualLabel() {
        let analysis = CaptureAnalyzer().analyze(text: """
        ROMÂNIA PAȘAPORT PASSPORT PASSEPORT
        Nume/Surname/Nom
        EXEMPLU
        Data eliberării/Date of issue/Date de délivrance
        15.03.2022
        Autoritatea/Authority/Autorité
        SPCEEPS EXEMPLU
        Data expirării/Date of expiry/Date d'expiration
        15.03.2032
        """, referenceDate: Date(timeIntervalSince1970: 1_793_577_600))
        #expect(analysis.kind == .passport)
        #expect(analysis.fields.first { $0.key == .issuer }?.value.text == "SPCEEPS EXEMPLU")
    }
}
