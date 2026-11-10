import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// The green card, the national health card and the qualified electronic signature, from a
/// photo's text to the binder: each a template read by the shared reader, a kind profile and
/// a document type. Placeholder data only: the CNPs use county code 99 with a valid control
/// digit, plates and firms are made up.
@Suite("Green card, national health card and electronic signature")
@MainActor
struct MorePersonalDocumentsTests {
    static let referenceDate = noon("2026-11-10")
    static let today = CalendarDay("2026-11-10")

    /// As the Council of Bureaux model lays it out, with BAAR's Romanian captions beside the English ones.
    static let greenCard = """
    CARTE VERDE / GREEN CARD
    CARTE INTERNAȚIONALĂ DE ASIGURARE DE AUTOVEHICULE / INTERNATIONAL MOTOR INSURANCE CARD
    3. Valabilitate / Valid
    De la / From 01.11.2026 Până la / To 31.10.2027
    4. Codul țării / Codul asigurătorului / Numărul
    RO/00/X00/XX 123456789
    5. Nr. de înmatriculare
    B 123 ABC
    6. Categoria și marca vehiculului
    A VW
    9. Numele și adresa asiguratului
    EXEMPLU ION, Str. Exemplului nr. 1, București
    10. Această carte a fost emisă de
    EXEMPLU ASIGURĂRI SRL
    """

    static let nationalHealthCard = """
    CARD NAȚIONAL DE ASIGURĂRI SOCIALE DE SĂNĂTATE
    Nume
    EXEMPLU
    Prenume
    ION
    CNP
    1800101990006
    Număr card
    80642000000000000002
    5. Data expirării
    31/12/2031
    """

    static let electronicSignature = """
    CERTIFICAT CALIFICAT PENTRU SEMNĂTURĂ ELECTRONICĂ CALIFICATĂ
    Furnizor de servicii de încredere calificat: EXEMPLU TRUST SRL
    Titular: EXEMPLU MARIA
    CNP: 2850615990011
    Număr serial: 4E 2A 00 00 00 12 34 56
    Valabil de la 01.02.2026 până la 31.01.2029
    """

    static let rcaPolicy = """
    POLIȚĂ DE ASIGURARE OBLIGATORIE DE RĂSPUNDERE CIVILĂ AUTO (RCA)
    Asigurător: Exemplu Asigurări S.A.
    Seria RO/00/X00/XX Nr. 123456789
    Nr. înmatriculare B 123 ABC
    Valabilă de la 01.11.2026 până la 31.10.2027
    Cartea Verde este inclusă în această poliță.
    Total de plată: 1.150,00 lei
    """

    private func read(_ text: String) async throws -> CaptureResult {
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: CaptureEngineTests.FixedRecognizer(text: text),
                                   normalizer: nil, onDeviceModel: nil, cloudModel: nil, store: nil)
        return try await engine.capture(CaptureRequest(.text(text), options: CaptureOptions(useOnDeviceModel: false, storeDocument: false,
                                                                                            referenceDate: Self.referenceDate)))
    }

    private func filer(_ context: ModelContext) -> CaptureFiler {
        CaptureFiler(context: context, store: .shared(), calendar: .bucharest, now: { Self.referenceDate })
    }

    private func kind(of text: String) -> CaptureDocumentKind {
        DocumentClassifier.classify(text: CaptureText(text), mrz: nil).kind
    }

    // MARK: Green card

    @Test("A green card: who it insures, its number, the car's plate, its days and the insurer")
    func greenCardIsRead() async throws {
        let result = try await read(Self.greenCard)
        #expect(result.kind == .greenCard)
        #expect(result.kind.isPersonalDocument)
        #expect(result.field(.holderName)?.value.text == "EXEMPLU ION", "The name, without the address printed after it")
        #expect(result.field(.documentNumber)?.value.text == "RO/00/X00/XX 123456789")
        #expect(result.field(.licensePlate)?.value.text == "B 123 ABC")
        #expect(result.field(.startDate)?.value.day == CalendarDay(printedYear: 2026, month: 11, day: 1))
        #expect(result.field(.expiryDate)?.value.day == CalendarDay(printedYear: 2027, month: 10, day: 31))
        #expect(result.field(.issuer)?.value.text == "EXEMPLU ASIGURĂRI SRL")
        #expect(result.field(.policyNumber) == nil, "A green card's number is its own, not a policy filed on the car")
        #expect(result.field(.total) == nil)
    }

    @Test("Filed under who it insures as „Carte verde – Exemplu Ion”, with its car's plate, reminded before it ends")
    func greenCardIsFiled() async throws {
        let context = try makeContext()
        let review = CaptureReview(result: try await read(Self.greenCard), assets: [], context: context)
        #expect(review.title == DocumentNaming.name(document: "Carte verde", holder: "Exemplu Ion"))
        #expect(review.title == "Carte verde – Exemplu Ion")

        let outcome = try await filer(context).save(review)
        let card = try #require(outcome.asset)
        #expect(card.name == "Carte verde – Exemplu Ion")
        #expect(card.parent?.name == "Exemplu Ion", "Filed under its holder")
        #expect(card.templateKey == BuiltInTemplates.Key.documents)
        #expect(card.value(DocumentType.typeFieldKey) == .text(DocumentType.greenCard))
        #expect(card.value(DocumentFields.vehiclePlate) == .text("B 123 ABC"))
        #expect(card.value(DocumentFields.number) == .text("RO/00/X00/XX 123456789"))
        #expect(card.value(DocumentFields.expiry) == .date(CalendarDay("2027-10-31")))
        let renewal = try #require(card.activeObligations.first)
        #expect(renewal.blueprintKey == BuiltInBlueprints.documentRenew)
        #expect(renewal.dueDay(in: .bucharest) == CalendarDay("2027-10-31"))
        #expect(renewal.reminders.leadDays == [30, 7], "Its type's reminders, from the catalog")
        #expect(renewal.reminders.consequence == .legal)
    }

    @Test("A green card that names an insurer's firm files under no one made up")
    func aFirmIsNoOnesName() {
        #expect(IdentityDocumentReader.nameBeforeAddress("EXEMPLU ION, Str. Exemplului nr. 1, București") == "EXEMPLU ION")
        #expect(IdentityDocumentReader.nameBeforeAddress("EXEMPLU ION STR. EXEMPLULUI NR. 1") == "EXEMPLU ION", "The address stacked under the name")
        #expect(IdentityDocumentReader.nameBeforeAddress("EXEMPLU ION 012345 BUCUREȘTI") == "EXEMPLU ION")
        #expect(IdentityDocumentReader.nameBeforeAddress("EXEMPLU LEASING IFN S.A., Bd. Exemplu 1") == nil, "A leasing firm is no one's name")
        #expect(IdentityDocumentReader.nameBeforeAddress("EXEMPLU LEASING SRL") == nil)
        #expect(IdentityDocumentReader.nameBeforeAddress("EXEMPLU, Str. Exemplului 1") == nil, "One word isn't a person's name")
        #expect(IdentityDocumentReader.nameBeforeAddress("Str. Exemplului nr. 1") == nil)
    }

    @Test("A green card is never filed into a car by a number it shares with the car's RCA")
    func aGreenCardStaysADocument() async throws {
        let context = try makeContext()
        let vehicle = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let car = try AssetActions(context: context, calendar: .bucharest, now: { Self.referenceDate }).create(
            name: "VW Golf 2018", template: vehicle,
            values: FieldValues([VehicleFields.plate: .text("B-123-ABC"), VehicleFields.policyNumber: .text("RO/00/X00/XX 123456789")]))
        let review = CaptureReview(result: try await read(Self.greenCard), assets: [car], context: context)
        #expect(review.destination != .asset(car.id))
        let outcome = try await filer(context).save(review)
        #expect(outcome.asset?.templateKey == BuiltInTemplates.Key.documents)
        #expect(car.values[DocumentFields.vehiclePlate] == nil, "Nothing of the card lands on the car")
    }

    @Test("Pleci din țară pairs a filed green card with the car whose plate it names")
    func greenCardPairsWithItsCar() {
        var golfValues = FieldValues()
        golfValues[VehicleFields.plate] = .text("B-123-ABC")
        let golf = ReadinessAsset.car(values: golfValues, dues: [BuiltInBlueprints.vehicleRCA: "2026-12-30"])
        var otherValues = FieldValues()
        otherValues[VehicleFields.plate] = .text("CJ 12 XYZ")
        let other = ReadinessAsset.car("Dacia Logan 2020", values: otherValues, dues: [BuiltInBlueprints.vehicleRCA: "2026-12-30"])
        var card = ReadinessAsset.personalDocument(DocumentType.greenCard, expires: "2027-10-31")
        card.values[DocumentFields.vehiclePlate] = .text("B 123 ABC")

        let assets = [golf, other, card]
        let plan = TripPlan.everyone(start: "2026-12-20", end: "2027-01-05", region: .europeanUnion, driving: true, in: assets)
        let items = ReadinessEngine.check(.trip(plan), assets: assets, calendar: .bucharest)
        #expect(items[id: "trip.greenCard.\(golf.id)"]?.status == .ok, "Its own card, valid through the trip")
        #expect(items[id: "trip.greenCard.\(golf.id)"]?.action == .open(.asset(card.id)))
        #expect(items[id: "trip.greenCard.\(other.id)"]?.status == .problem, "Another car's card doesn't count; its RCA ends mid-trip")

        // A card that names no plate counts for every car, as before.
        card.values[DocumentFields.vehiclePlate] = nil
        let unnamed = ReadinessEngine.check(.trip(plan), assets: [golf, other, card], calendar: .bucharest)
        #expect(unnamed[id: "trip.greenCard.\(other.id)"]?.status == .ok)
    }

    @Test("An RCA policy stays the policy, whatever green card it mentions or carries")
    func thePolicyStaysAPolicy() {
        #expect(kind(of: Self.greenCard) == .greenCard)
        #expect(kind(of: Self.rcaPolicy) == .rcaPolicy, "It says the green card is included")
        #expect(kind(of: Self.rcaPolicy + "\n" + Self.greenCard) == .rcaPolicy, "One PDF, the green card as its last page")
    }

    // MARK: National health card

    @Test("The national health card: its holder, CNP, number and expiry")
    func nationalHealthCardIsRead() async throws {
        let result = try await read(Self.nationalHealthCard)
        #expect(result.kind == .nationalHealthCard)
        #expect(result.field(.surname)?.value.text == "EXEMPLU")
        #expect(result.field(.givenNames)?.value.text == "ION")
        #expect(result.field(.personalNumber)?.value.text == "1800101990006")
        #expect(result.field(.documentNumber)?.value.text == "80642000000000000002")
        #expect(result.field(.expiryDate)?.value.day == CalendarDay(printedYear: 2031, month: 12, day: 31))
        #expect(result.recognizedText.contains("80642000000000000002"), "A health card's number isn't a bank card's")
    }

    @Test("Filed as the national card, reminded a month and a week before it ends")
    func nationalHealthCardIsFiled() async throws {
        let context = try makeContext()
        let review = CaptureReview(result: try await read(Self.nationalHealthCard), assets: [], context: context)
        #expect(review.title == "Card național de sănătate – Exemplu Ion")
        let outcome = try await filer(context).save(review)
        let card = try #require(outcome.asset)
        #expect(card.parent?.name == "Exemplu Ion")
        #expect(card.value(DocumentType.typeFieldKey) == .text(DocumentType.nationalHealthCard))
        #expect(card.value(DocumentFields.personalNumber) == .text("1800101990006"))
        #expect(card.value(DocumentFields.expiry) == .date(CalendarDay("2031-12-31")))
        let renewal = try #require(card.activeObligations.first)
        #expect(renewal.dueDay(in: .bucharest) == CalendarDay("2031-12-31"))
        #expect(renewal.reminders.leadDays == [30, 7])
        #expect(renewal.reminders.consequence == .health)
        #expect(DocumentType.keepsBackSide(DocumentType.nationalHealthCard))
    }

    @Test("The two health cards are never taken for each other")
    func healthCardsApart() async throws {
        #expect(kind(of: Self.nationalHealthCard) == .nationalHealthCard)
        #expect(kind(of: PersonalDocumentCaptureTests.europeanHealthCard) == .healthInsuranceCard)
        let european = try await read(PersonalDocumentCaptureTests.europeanHealthCard)
        let context = try makeContext()
        let review = CaptureReview(result: european, assets: [], context: context)
        let outcome = try await filer(context).save(review)
        #expect(outcome.asset?.value(DocumentType.typeFieldKey) == .text(DocumentType.euHealthCard))
    }

    // MARK: Electronic signature

    @Test("A qualified signature certificate: its holder, CNP, serial number, provider and days")
    func electronicSignatureIsRead() async throws {
        let result = try await read(Self.electronicSignature)
        #expect(result.kind == .electronicSignature)
        #expect(result.field(.holderName)?.value.text == "EXEMPLU MARIA")
        #expect(result.field(.personalNumber)?.value.text == "2850615990011")
        #expect(result.field(.documentNumber)?.value.text == "4E 2A 00 00 00 12 34 56")
        #expect(result.field(.issueDate)?.value.day == CalendarDay(printedYear: 2026, month: 2, day: 1))
        #expect(result.field(.expiryDate)?.value.day == CalendarDay(printedYear: 2029, month: 1, day: 31))
        #expect(result.field(.issuer)?.value.text == "EXEMPLU TRUST SRL")
    }

    @Test("Filed as „Semnătură electronică – Exemplu Maria”, reminded before it ends")
    func electronicSignatureIsFiled() async throws {
        let context = try makeContext()
        let review = CaptureReview(result: try await read(Self.electronicSignature), assets: [], context: context)
        #expect(review.title == "Semnătură electronică – Exemplu Maria")
        let outcome = try await filer(context).save(review)
        let certificate = try #require(outcome.asset)
        #expect(certificate.parent?.name == "Exemplu Maria")
        #expect(certificate.value(DocumentType.typeFieldKey) == .text(DocumentType.eSignature))
        #expect(certificate.value(DocumentFields.issuer) == .text("EXEMPLU TRUST SRL"))
        #expect(certificate.value(DocumentFields.issueDate) == .date(CalendarDay("2026-02-01")))
        let renewal = try #require(certificate.activeObligations.first)
        #expect(renewal.dueDay(in: .bucharest) == CalendarDay("2029-01-31"))
        #expect(renewal.reminders.leadDays == [30, 7])
    }

    // MARK: Nothing else is taken for them

    @Test("An identity card, a bill and a policy are none of these")
    func unrelatedDocuments() {
        let identityCard = """
        ROMÂNIA
        CARTE DE IDENTITATE / IDENTITY CARD
        Nume / Surname
        EXEMPLU
        Prenume / Given names
        ION
        CNP / PIN
        1800101990006
        Semnătura titularului / Holder's signature
        """
        let bill = "ENGIE Romania S.A.\nFactură fiscală\nTotal de plată 245,30 lei\nCod client 1234567890"
        let newKinds: Set<CaptureDocumentKind> = [.greenCard, .nationalHealthCard, .electronicSignature]
        for text in [identityCard, bill, Self.rcaPolicy, PersonalDocumentCaptureTests.cazier, PersonalDocumentCaptureTests.bankCard] {
            #expect(!newKinds.contains(kind(of: text)), "\(text.prefix(40))")
        }
    }

    // MARK: Questions and catalog

    @Test("Both models are asked what each template reads, with its captions")
    func modelQuestionsFollowTheTemplates() {
        let greenCard = CaptureDocumentKind.greenCard.expectedKeys
        #expect(Set(greenCard).isSuperset(of: [.holderName, .documentNumber, .licensePlate, .startDate, .expiryDate, .issuer]))
        let holder = ModelQuestions.fields(of: .greenCard, reader: .page).first { $0.key == .holderName }
        #expect(holder?.description.contains("numele si adresa asiguratului") == true, "\(holder?.description ?? "")")
        #expect(ModelQuestions.fields(of: .greenCard, reader: .page).first { $0.key == .licensePlate }?.format == .plate)
        #expect(Set(CaptureDocumentKind.nationalHealthCard.expectedKeys).isSuperset(of: [.surname, .givenNames, .personalNumber, .documentNumber, .expiryDate]))
        #expect(Set(CaptureDocumentKind.electronicSignature.expectedKeys).isSuperset(of: [.holderName, .personalNumber, .documentNumber, .issueDate, .expiryDate, .issuer]))
    }

    @Test("Each kind is its type's, and the plate is the green card's alone")
    func catalog() throws {
        #expect(CaptureDocumentKind.greenCard.profile.documentType == DocumentType.greenCard)
        #expect(CaptureDocumentKind.nationalHealthCard.profile.documentType == DocumentType.nationalHealthCard)
        #expect(CaptureDocumentKind.electronicSignature.profile.documentType == DocumentType.eSignature)
        #expect(TemplateDefinition.builtInCatalogVersion >= 16)
        let plate = try #require(BuiltInTemplates.documents.field(DocumentFields.vehiclePlate))
        #expect(plate.applies(to: FieldValues([DocumentType.typeFieldKey: .text(DocumentType.greenCard)])))
        #expect(!plate.applies(to: FieldValues([DocumentType.typeFieldKey: .text(DocumentType.idCard)])))
        #expect(!PhoneOnlyReading.isPhoneOnly(.greenCard) && !PhoneOnlyReading.isPhoneOnly(.electronicSignature))
    }
}
