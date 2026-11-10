import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A cazier, the European health card and a bank card, from a photo's text to the
/// binder. Placeholder data only: the CNPs use county code 99 with a valid control digit,
/// and the card numbers are the networks' published test numbers.
@Suite("Cazier, health card and bank card")
@MainActor
struct PersonalDocumentCaptureTests {
    static let referenceDate = noon("2026-11-03")
    static let today = CalendarDay("2026-11-03")

    static let cazier = """
    ROMÂNIA
    MINISTERUL AFACERILOR INTERNE
    CERTIFICAT DE CAZIER JUDICIAR
    Nr. certificat: 123456/2026
    Numele: EXEMPLU
    Prenumele: ION
    Data nașterii: 01.01.1980
    CNP: 1800101990006
    NU FIGUREAZĂ ÎN CAZIERUL JUDICIAR
    Data eliberării: 15.10.2026
    Eliberat de: IPJ Exemplu
    """

    /// As Ordinul CNAS nr. 559/2006 and Decision No S2 print it: numbered captions, each value under its caption.
    static let europeanHealthCard = """
    CARD EUROPEAN DE ASIGURĂRI DE SĂNĂTATE
    3. Nume
    EXEMPLU
    4. Prenume
    MARIA
    5. Data nașterii
    15/06/1985
    6. Codul personal de identificare
    2850615990011
    7. Numărul de identificare al instituției
    1234567890 - CNAS
    8. Numărul de identificare al cardului
    80642000000000000001
    9. Data expirării
    31/12/2029
    """

    /// The Visa test number every payment provider publishes.
    static let testNumber = "4111 1111 1111 1111"
    static let bankCard = """
    Banca Transilvania
    DEBIT
    \(testNumber)
    VALID THRU 08/28
    ION EXEMPLU
    VISA
    """

    private func read(_ text: String) async throws -> CaptureResult {
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: CaptureEngineTests.FixedRecognizer(text: text),
                                   normalizer: nil, onDeviceModel: nil, cloudModel: nil, store: nil)
        return try await engine.capture(CaptureRequest(.text(text), options: CaptureOptions(useOnDeviceModel: false, storeDocument: false,
                                                                                            referenceDate: Self.referenceDate)))
    }

    private func filer(_ context: ModelContext, store: CaptureDocumentStore = .shared()) -> CaptureFiler {
        CaptureFiler(context: context, store: store, calendar: .bucharest, now: { Self.referenceDate })
    }

    // MARK: Cazier

    @Test("A cazier judiciar: its holder, CNP, number, dates, issuer and what it says, as printed")
    func cazierIsRead() async throws {
        let result = try await read(Self.cazier)
        #expect(result.kind == .criminalRecord)
        #expect(result.field(.documentVariant)?.value.text == DocumentType.Variant.criminalRecordJudicial)
        #expect(result.field(.surname)?.value.text == "EXEMPLU")
        #expect(result.field(.givenNames)?.value.text == "ION")
        #expect(result.field(.personalNumber)?.value.text == "1800101990006")
        #expect(result.field(.documentNumber)?.value.text == "123456/2026")
        #expect(result.field(.issueDate)?.value.day == CalendarDay(printedYear: 2026, month: 10, day: 15))
        #expect(result.field(.issuer)?.value.text == "IPJ Exemplu")
        #expect(result.field(.recordResult)?.value.text == "NU FIGUREAZĂ ÎN CAZIERUL JUDICIAR")
        #expect(result.field(.sex) == nil, "A cazier carries only what its template reads")
        #expect(result.field(.total) == nil)
    }

    @Test("A cazier judiciar is valid six months from its issue: the review says so, saving reminds")
    func cazierValidity() async throws {
        let context = try makeContext()
        let review = CaptureReview(result: try await read(Self.cazier), assets: [], context: context)
        #expect(review.title == "Cazier judiciar – Exemplu Ion")
        #expect(review.reminderDay == CalendarDay("2027-04-15"))
        let plan = try filer(context).plan(for: review)
        #expect(plan.deadline?.day == CalendarDay("2027-04-15"))
        let line = try #require(CaptureReminderPreview.text(for: review, plan: plan, today: Self.today))
        #expect(line.hasPrefix("E valabil până pe 15 aprilie 2027, la 6 luni de la eliberare."), "\(line)")

        let outcome = try await filer(context).save(review)
        let document = try #require(outcome.asset)
        #expect(document.name == "Cazier judiciar – Exemplu Ion")
        #expect(document.parent?.name == "Exemplu Ion", "Filed under its holder")
        #expect(document.value(DocumentFields.expiry) == .date(CalendarDay("2027-04-15")), "The category's own rule wrote the same day")
        #expect(document.value(DocumentFields.recordResult) == .text("NU FIGUREAZĂ ÎN CAZIERUL JUDICIAR"))
        let renewal = try #require(document.activeObligations.first)
        #expect(renewal.dueDay(in: .bucharest) == CalendarDay("2027-04-15"))
        #expect(renewal.reminders.consequence == .comfort, "A cazier is asked for a purpose, never crowds Acum")
    }

    @Test("Only the cazier judiciar has a validity rule; typing its issue date later sets its expiry")
    func validityIsData() throws {
        #expect(DocumentType.validityMonths(type: DocumentType.criminalRecord, variant: DocumentType.Variant.criminalRecordJudicial) == 6)
        #expect(DocumentType.validityMonths(type: DocumentType.criminalRecord, variant: DocumentType.Variant.criminalRecordFiscal) == nil)
        #expect(DocumentType.validityMonths(type: DocumentType.criminalRecord, variant: nil) == nil)
        #expect(DocumentType.validityMonths(type: DocumentType.idCard, variant: nil) == nil)
        // The last day of a shorter month.
        #expect(DocumentType.validUntil(issued: CalendarDay("2026-08-31"), type: DocumentType.criminalRecord,
                                        variant: DocumentType.Variant.criminalRecordJudicial, calendar: .bucharest) == CalendarDay("2027-02-28"))

        let context = try makeContext()
        let documents = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.documents))
        let actions = AssetActions(context: context, calendar: .bucharest, now: { Self.referenceDate })
        var values = FieldValues([DocumentType.typeFieldKey: .text(DocumentType.criminalRecord),
                                  DocumentType.variantFieldKey: .text(DocumentType.Variant.criminalRecordJudicial)])
        let cazier = try actions.create(name: "Cazier judiciar – Exemplu Ion", template: documents, values: values)
        #expect(cazier.activeObligations.isEmpty)
        values[DocumentFields.issueDate] = .date(CalendarDay("2026-10-15"))
        try actions.update(cazier, name: cazier.name, values: values, notes: nil)
        #expect(cazier.value(DocumentFields.expiry) == .date(CalendarDay("2027-04-15")))
        #expect(cazier.activeObligations.first?.dueDay(in: .bucharest) == CalendarDay("2027-04-15"))
    }

    @Test("An expired cazier read from a photo is only history")
    func anExpiredCazierSetsNoDeadline() async throws {
        let context = try makeContext()
        let old = Self.cazier.replacingOccurrences(of: "15.10.2026", with: "15.01.2025")
        let review = CaptureReview(result: try await read(old), assets: [], context: context)
        let plan = try filer(context).plan(for: review)
        #expect(plan.quiet == .dayPassed)
        let outcome = try await filer(context).save(review)
        #expect(outcome.asset?.activeObligations.isEmpty == true)
    }

    // MARK: European health card

    @Test("The European health card, field by field as CNAS prints it")
    func europeanHealthCardIsRead() async throws {
        let result = try await read(Self.europeanHealthCard)
        #expect(result.kind == .healthInsuranceCard)
        #expect(result.field(.surname)?.value.text == "EXEMPLU")
        #expect(result.field(.givenNames)?.value.text == "MARIA")
        #expect(result.field(.birthDate)?.value.day == CalendarDay(printedYear: 1985, month: 6, day: 15))
        #expect(result.field(.personalNumber)?.value.text == "2850615990011")
        #expect(result.field(.issuer)?.value.text == "1234567890 - CNAS")
        #expect(result.field(.documentNumber)?.value.text == "80642000000000000001")
        #expect(result.field(.expiryDate)?.value.day == CalendarDay(printedYear: 2029, month: 12, day: 31))
        #expect(result.recognizedText.contains("80642000000000000001"), "A health card's number isn't a bank card's")
    }

    @Test("Filed as the European health card, so Pleci din țară reads the same expiry")
    func europeanHealthCardServesTheTrip() async throws {
        let context = try makeContext()
        let review = CaptureReview(result: try await read(Self.europeanHealthCard), assets: [], context: context)
        #expect(review.title == "Card european de sănătate – Exemplu Maria")
        let outcome = try await filer(context).save(review)
        let card = try #require(outcome.asset)
        #expect(card.value(DocumentType.typeFieldKey) == .text(DocumentType.euHealthCard))
        #expect(card.value(DocumentFields.expiry) == .date(CalendarDay("2029-12-31")))
        let seen = ReadinessAsset(id: card.id, name: card.name, templateKey: card.templateKey, role: .personalDocument, values: card.values)
        #expect(ReadinessEngine.documents(of: DocumentType.euHealthCard, in: [seen]).count == 1, "The trip check finds it by its type")
        #expect(ReadinessEngine.expiry(seen) == CalendarDay("2029-12-31"), "and reads this very field")
        #expect(card.activeObligations.first?.dueDay(in: .bucharest) == CalendarDay("2029-12-31"))
    }

    // MARK: Bank cards

    @Test("A bank card: its bank, network, kind, last four digits and expiry; never its number")
    func bankCardIsRead() async throws {
        let result = try await read(Self.bankCard)
        #expect(result.kind == .bankCard)
        #expect(result.field(.cardLastFour)?.value.text == "1111")
        #expect(result.field(.cardNetwork)?.value.text == PaymentCardNetwork.visa)
        #expect(result.field(.issuer)?.value.text == "Banca Transilvania")
        #expect(result.field(.documentVariant)?.value.text == DocumentType.Variant.bankCardDebit)
        #expect(result.field(.expiryDate)?.value.day == CalendarDay(printedYear: 2028, month: 8, day: 31), "Valid through the end of the month")
        try expectNoCardNumber(in: result)
        #expect(result.recognizedText.contains("\(PaymentCardNumbers.mask) 1111"))
    }

    @Test("Saved: shown as „Visa •••• 1111, expiră 08/28”, reminded a month before and on the day, no photo unless asked")
    func bankCardIsFiled() async throws {
        let context = try makeContext()
        let store = CaptureDocumentStore()
        let pages = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 856, height: 540, seed: 41)], kind: .bankCard))
        let read = try await read(Self.bankCard)
        let result = CaptureResult(kind: read.kind, kindConfidence: read.kindConfidence, fields: read.fields, suggestions: read.suggestions,
                                   reminder: read.reminder, recognizedText: read.recognizedText, barcodes: [], document: pages.ref,
                                   notices: [], source: read.source)
        let review = CaptureReview(result: result, assets: [], context: context)
        #expect(!review.keepsPhoto, "Off by default")
        #expect(try filer(context, store: store).plan(for: review).keepsPhoto == false)

        let outcome = try await filer(context, store: store).save(review)
        let card = try #require(outcome.asset)
        #expect(outcome.attachment == nil, "The photo shows the whole number: not kept unless asked")
        #expect(try context.fetch(FetchDescriptor<DosarCuSina.Attachment>()).isEmpty)
        #expect(card.value(DocumentFields.cardLastFour) == .text("1111"))
        #expect(card.value(DocumentFields.cardNetwork) == .text(PaymentCardNetwork.visa))
        #expect(card.value(DocumentType.variantFieldKey) == .text(DocumentType.Variant.bankCardDebit))
        #expect(card.value(DocumentFields.issuer) == .text("Banca Transilvania"))
        #expect(DocumentSummary.line(card.values, today: Self.today) == "Visa •••• 1111, expiră 08/28")
        let renewal = try #require(card.activeObligations.first)
        #expect(renewal.dueDay(in: .bucharest) == CalendarDay("2028-08-31"))
        #expect(renewal.reminders.leadDays == [30, 0], "A month before, and on the day")
        #expect(SecretFields.fields(in: BuiltInTemplates.documents).allSatisfy { !$0.applies(to: card.values) }, "No PIN, ever")
    }

    @Test("Kept on request: the photo, with only a masked number in its text")
    func bankCardPhotoOnRequest() async throws {
        let context = try makeContext()
        let store = CaptureDocumentStore()
        let pages = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 856, height: 540, seed: 42)], kind: .bankCard))
        let read = try await read(Self.bankCard)
        let result = CaptureResult(kind: read.kind, kindConfidence: read.kindConfidence, fields: read.fields, suggestions: read.suggestions,
                                   reminder: read.reminder, recognizedText: read.recognizedText, barcodes: [], document: pages.ref,
                                   notices: [], source: read.source)
        var review = CaptureReview(result: result, assets: [], context: context)
        review.keepsPhotoOnRequest = true
        let outcome = try await filer(context, store: store).save(review)
        let photo = try #require(outcome.attachment)
        #expect(!Self.holdsTestNumber(photo.extractedText ?? ""))
        #expect(photo.extractedText?.contains("\(PaymentCardNumbers.mask) 1111") == true)
    }

    @Test("The full number never reaches the database, search, Spotlight or a backup")
    func theNumberNeverLeavesTheReading() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        try TemplateStore(context: context).installBuiltIns()
        let read = try await read(Self.bankCard)
        var review = CaptureReview(result: read, assets: [], context: context)
        // Even typed into the review by hand, in the last-four field and as a note on the number.
        if let index = review.fields.firstIndex(where: { $0.key == .cardLastFour }) { review.fields[index].confirm(.text(Self.testNumber)) }
        let outcome = try await CaptureFiler(context: context, calendar: .bucharest, now: { Self.referenceDate }).save(review)
        let card = try #require(outcome.asset)
        var values = card.values
        values[DocumentFields.number] = .text(Self.testNumber)
        try AssetActions(context: context, calendar: .bucharest).update(card, name: card.name, values: values, notes: nil)
        _ = try AttachmentActions(context: context, calendar: .bucharest)
            .file(DocumentDraft(title: "Extras de cont", fileName: "extras.pdf", kind: .other, extractedText: "Plată cu cardul \(Self.testNumber)"), asset: card)

        // The database.
        for value in card.values.storage.values {
            #expect(!Self.holdsTestNumber(value.textValue ?? ""))
        }
        #expect(card.value(DocumentFields.cardLastFour) == .text("1111"))
        for attachment in try context.fetch(FetchDescriptor<DosarCuSina.Attachment>()) {
            #expect(!Self.holdsTestNumber(attachment.extractedText ?? ""))
        }
        // Search, by the whole number or by its last four digits.
        let index = try SearchIndexBuilder(context: context).build()
        #expect(index.search("4111 1111 1111 1111").isEmpty)
        #expect(index.search("4111111111111111").isEmpty)
        #expect(index.search("1111").isEmpty)
        #expect(!index.search("Card de debit").isEmpty, "The card itself is still found by its name")
        // The iPhone's search.
        #expect(SearchPrivacy.outsideText("Card \(Self.testNumber)") == "Card")
        #expect(SearchPrivacy.outsideText("Visa •••• 1111") == "Visa")
        let withheld = SearchPrivacy.withheldValues(of: card, definition: BuiltInTemplates.documents)
        #expect(SearchPrivacy.outsideText("Cardul 1111", withholding: withheld) == "Cardul", "Not even the last four digits")
        // A backup.
        let data = try DossierArchiveService(container: container, calendar: .bucharest).exportData(exportedAt: Self.referenceDate)
        for entry in try DosarZipEngine.unpackArchive(data) {
            #expect(!Self.holdsTestNumber(String(decoding: entry.data, as: UTF8.self)), "\(entry.path)")
        }
    }

    @Test("The AI provider's answer keeps only four digits, wherever it puts the number")
    func theAIAnswerIsMasked() throws {
        let schema = CloudSchema(kind: .bankCard)
        #expect(schema.fields.contains { $0.key == .cardLastFour && $0.format == .cardLastFour })
        #expect(!schema.fields.contains { $0.name.lowercased().contains("cardnumber") }, "Never asked for the number")
        let answer = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"documentKind":"bankCard","cardLastFour":"4111111111111111","holderName":"ION EXEMPLU 4111 1111 1111 1111","expiryDate":"2028-08-31","cardNetwork":"cardNetwork.visa"}
        """.utf8))
        let fields = ModelAnswerMapper.fields(from: answer, asked: schema.questions, recognizedText: "", today: try #require(CalendarDay(printedYear: 2026, month: 11, day: 3)),
                                              resolver: CatalogComponentResolver())
        #expect(fields.first { $0.key == CaptureFieldKey.cardLastFour }?.value.text == "1111")
        let reading = CaptureResult(kind: .bankCard, kindConfidence: 0.9, fields: fields, suggestions: [], reminder: nil,
                                    recognizedText: "", barcodes: [], document: nil, notices: []).withoutCardNumbers()
        try expectNoCardNumber(in: reading)
    }

    @Test("A bank card or a cazier is never sent by itself (a bank card never at all: PhoneOnlyReadingTests)")
    func bankCardAsksFirst() async throws {
        let result = try await read(Self.bankCard)
        #expect(IdentitySignals.mayBeIdentity(result))
        let cazier = try await read(Self.cazier)
        #expect(IdentitySignals.mayBeIdentity(cazier))
    }

    // MARK: The rules

    @Test("Card numbers: masked by shape, never a CNP, an IMEI or a health card's number")
    func cardNumberRules() {
        #expect(PaymentCardNumbers.redact("Card 4111 1111 1111 1111 Visa") == "Card •••• 1111 Visa")
        #expect(PaymentCardNumbers.redact("5555-5555-5555-4444") == "•••• 4444")
        #expect(PaymentCardNumbers.redact("5555555555554444") == "•••• 4444")
        // Grouped in fours like a card, even with a misread check digit.
        #expect(PaymentCardNumbers.redact("4111 1111 1111 1112") == "•••• 1112")
        // Not cards: a CNP, an IMEI, a health card's 20 digits, a bill's payment code, an invoice number.
        // A made-up IMEI (prefix 99, no real maker) given its check digit here, so no
        // number that passes a card's check digit is written in the repository.
        let imei = Self.withCheckDigit("99000086247185")
        for text in ["CNP 1800101990006", "IMEI \(imei)", "80642000000000000001", "1234567890123456789012345678", "Factura 1234567"] {
            #expect(PaymentCardNumbers.redact(text) == text, "\(text)")
        }
        // On a bank card, any long run goes, whatever it starts with.
        #expect(PaymentCardNumbers.redact("1234 5678 9012 3456", strict: true) == "•••• 3456")
        #expect(PaymentCardNumbers.redact("1234 5678", strict: true) == "••••")
        #expect(PaymentCardNumbers.redact("VALID THRU 08/28", strict: true) == "VALID THRU 08/28")
        #expect(PaymentCardNumbers.lastFour(in: "•••• 4444") == "4444")
        #expect(PaymentCardNumbers.lastFour(of: Self.testNumber) == "1111")
        #expect(PaymentCardNumbers.network(ofNumber: "5555555555554444") == PaymentCardNetwork.mastercard)
        #expect(PaymentCardNumbers.network(ofNumber: "4111111111111111") == PaymentCardNetwork.visa)
    }

    @Test("A card number printed next to other digits is found inside the longer run")
    func cardNumberNextToOtherDigits() {
        let found = [
            "Nr. 12 4111 1111 1111 1111": "Nr. 12 •••• 1111",
            "Ref 3-5555555555554444": "Ref 3-•••• 4444",
            "4111-1111-1111-1111-27 lei": "•••• 1111-27 lei",
            "Rând 2 150 4111 1111 1111 1111": "Rând 2 150 •••• 1111",
            "4111 1111 1111 1111 0828": "•••• 1111 0828",
            // American Express prints 4-6-5.
            "Plată 7 3782 822463 10005": "Plată 7 •••• 0005",
            // Two cards side by side, and a CNP or a health card's 20 digits before one: only the cards go.
            "4111 1111 1111 1111-5555555555554444": "•••• 1111-•••• 4444",
            "CNP 1800101990006 4111111111111111": "CNP 1800101990006 •••• 1111",
            "80642000000000000001 4111111111111111": "80642000000000000001 •••• 1111",
        ]
        for (text, masked) in found {
            #expect(PaymentCardNumbers.redact(text) == masked, "\(text)")
            #expect(PaymentCardNumbers.containsCardNumber(text), "\(text)")
            #expect(PaymentCardNumbers.redact(text, strict: true).contains(PaymentCardNumbers.mask), "\(text)")
        }
        #expect(PaymentCardNumbers.lastFour(in: "Nr. 12 4111 1111 1111 1111") == "1111")
        // On a bank card, the card's own last four, not the digits printed after it.
        #expect(PaymentCardNumbers.lastFour(in: "4111 1111 1111 1111 0828", strict: true) == "1111")
        #expect(PaymentCardNumbers.lastFour(in: "Ref 3-5555555555554444", strict: true) == "4444")
    }

    @Test("A long number stays as written: no part of it is taken unless it is printed apart like a card")
    func longNumbersStayWhole() {
        let kept = [
            // Digits with nothing between them are one number, even when a part of it would pass as a card.
            "Index 41111111111111110000",
            "Contract 124111111111111111",
            // A long number printed in fours: a part grouped like a card, with a check digit that fails.
            "Cod 4111 1111 1111 1112 0000",
            // Small numbers side by side, an IBAN, a phone, a CNP.
            "2 4 6 8 10 12 14 16 18 20",
            "RO49 AAAA 1B31 0075 9384 0000",
            "0700 000 000",
            "1800101990006",
        ]
        for text in kept {
            #expect(PaymentCardNumbers.redact(text) == text, "\(text)")
            #expect(!PaymentCardNumbers.containsCardNumber(text), "\(text)")
        }
    }

    @Test("Every kind of personal document is filed under its holder and asked for its own fields")
    func personalKinds() {
        for kind in [CaptureDocumentKind.criminalRecord, .healthInsuranceCard, .bankCard] {
            #expect(kind.isPersonalDocument)
            #expect(!kind.isIdentityDocument, "No machine-readable zone, no back to add")
            #expect(kind.profile.documentKind == .identity, "Its read text is never searched")
        }
        #expect(!CaptureDocumentKind.bankCard.allows(.personalNumber))
        #expect(CaptureDocumentKind.criminalRecord.allows(.personalNumber))
        #expect(!CaptureDocumentKind.utilityInvoice.allows(.cardLastFour))
        #expect(CaptureDocumentKind.bankCard.profile.photoIsOptIn)
        #expect(!CaptureDocumentKind.criminalRecord.profile.photoIsOptIn)
    }

    // MARK: Helpers

    /// The test number, written with or without separators.
    static func holdsTestNumber(_ text: String) -> Bool {
        text.range(of: #"4111[ -]?1111[ -]?1111[ -]?1111"#, options: .regularExpression) != nil
    }

    /// Nothing anywhere in a capture result holds a whole card number.
    private func expectNoCardNumber(in result: CaptureResult) throws {
        let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        #expect(!Self.holdsTestNumber(encoded))
        #expect(!PaymentCardNumbers.containsCardNumber(encoded))
    }

    /// `digits` followed by the Luhn check digit that makes the whole number pass.
    static func withCheckDigit(_ digits: String) -> String {
        let values = digits.compactMap(\.wholeNumberValue)
        let sum = values.reversed().enumerated().reduce(0) { total, item in
            let (index, digit) = item
            let doubled = index.isMultiple(of: 2) ? digit * 2 : digit
            return total + (doubled > 9 ? doubled - 9 : doubled)
        }
        return digits + String((10 - sum % 10) % 10)
    }
}
