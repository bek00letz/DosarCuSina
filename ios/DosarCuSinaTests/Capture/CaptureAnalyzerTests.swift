import Foundation
import Testing
@testable import DosarCuSina

/// End-to-end checks of the deterministic and heuristic tiers on synthetic documents.
/// All names, companies, plates and numbers are placeholders.
@Suite("Capture analyzer")
struct CaptureAnalyzerTests {

    let analyzer = CaptureAnalyzer()
    let today = Date(timeIntervalSince1970: 1_793_577_600)

    private func route(_ analysis: CaptureAnalyzer.Analysis) -> CaptureRouter.Routing {
        CaptureRouter.route(kind: analysis.kind, kindConfidence: analysis.kindConfidence, fields: analysis.fields)
    }

    @Test("Passport photo: expiry from the MRZ, warned about 9 months ahead")
    func passport() throws {
        let analysis = analyzer.analyze(text: """
        PAȘAPORT / PASSPORT
        UTOPIA
        P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
        L898902C36UTO7408122F3104150ZE184226B<<<<<16
        """, referenceDate: today)

        #expect(analysis.kind == .passport)
        let expiry = try #require(analysis.fields.first { $0.key == .expiryDate })
        #expect(expiry.value == .day(CalendarDay(printedYear: 2031, month: 4, day: 15)!))
        #expect(expiry.tier == .deterministic)
        #expect(expiry.confidence > 0.95)

        let routing = route(analysis)
        let reminder = try #require(routing.reminder)
        #expect(reminder.blueprintKey == BuiltInBlueprints.documentRenew)
        #expect(reminder.templateKey == BuiltInTemplates.Key.documents, "Lead times are the blueprint's: capture keeps none of its own")
        #expect(routing.suggestions.contains { $0.destination == .newAsset(templateKey: "documents") })
        #expect(routing.suggestions.contains { $0.destination == .obligation(blueprintKey: BuiltInBlueprints.documentRenew, templateKey: "documents") })
    }

    @Test("Car service invoice: provider, total, km and parts keyed by component")
    func serviceInvoice() throws {
        let analysis = analyzer.analyze(text: """
        EXEMPLU SERVICE AUTO S.R.L.
        CUI RO12345674
        Str. Exemplului nr. 1, București
        FACTURĂ FISCALĂ seria AUT nr. 004512
        Data facturii: 14.03.2025
        Client: Ion Exemplu
        Auto: VW Golf, Nr. înmatriculare B 123 ABC
        Km bord: 86.420
        Plăcuțe frână față Bosch 2 buc 320,00
        Ulei motor 5W30 4 l 180,00
        Filtru ulei 45,00
        Manoperă 1,5 ore 150,00
        Total de plată: 695,00 lei
        """, referenceDate: today)

        #expect(analysis.kind == .serviceInvoice)
        let byKey = Dictionary(analysis.fields.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(byKey[.provider]?.value.text == "EXEMPLU SERVICE AUTO S.R.L.")
        #expect(byKey[.providerTaxID]?.value.text == "RO12345674")
        #expect(byKey[.providerTaxID]?.tier == .deterministic)
        #expect(byKey[.total]?.value.money == Money(695, currency: "RON"))
        #expect(byKey[.licensePlate]?.value.text == "B 123 ABC")
        #expect(byKey[.odometer]?.value == .metric(value: 86_420, unit: .kilometres))
        #expect(byKey[.invoiceNumber]?.value.text == "AUT 004512")
        #expect(byKey[.issueDate]?.value.day == CalendarDay(printedYear: 2025, month: 3, day: 14))

        let items = try #require(byKey[.lineItems]?.value.lineItems)
        #expect(items.map(\.componentKey) == ["brakes.padsFront", "engine.oil", "engine.oil", nil])
        #expect(items.map(\.isLabour) == [false, false, false, true])
        #expect(items.first?.amount == Money(320, currency: "RON"))

        let routing = route(analysis)
        let history = try #require(routing.suggestions.first { $0.destination == .historyEntry(templateKey: "vehicle") })
        #expect(history.assetHints.contains(CaptureAssetHint(key: .licensePlate, value: "B 123 ABC")))
        #expect(routing.suggestions.contains { $0.destination == .provider(name: "EXEMPLU SERVICE AUTO S.R.L.", trade: ProviderTrade.mechanic.rawValue) })
        #expect(routing.reminder == nil)
    }

    @Test("RCA policy: insurer, policy number, claims phone, validity and a 30-day lead")
    func rcaPolicy() throws {
        let analysis = analyzer.analyze(text: """
        Groupama Asigurări S.A.
        POLIȚĂ DE ASIGURARE OBLIGATORIE RCA
        Seria și numărul poliței: RO/25/X25/AB 012345678
        Perioada de valabilitate: 07.11.2026 - 06.11.2027
        Vehicul: B 123 ABC, Serie șasiu WVWZZZAUZJW000000
        Clasa bonus-malus: B4
        Prima de asigurare: 1.240,00 lei
        Avizare daune nonstop: 0800 123 456
        """, referenceDate: today)

        #expect(analysis.kind == .rcaPolicy)
        let byKey = Dictionary(analysis.fields.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(byKey[.provider]?.value.text == "Groupama Asigurări")
        #expect(byKey[.policyNumber]?.value.text?.contains("012345678") == true)
        #expect(byKey[.claimsPhone]?.value.text == "0800123456")
        #expect(byKey[.startDate]?.value.day == CalendarDay(printedYear: 2026, month: 11, day: 7))
        #expect(byKey[.expiryDate]?.value.day == CalendarDay(printedYear: 2027, month: 11, day: 6))
        #expect(byKey[.total]?.value.money == Money(1240, currency: "RON"))
        #expect(byKey[.bonusMalusClass]?.value.text == "B4")
        #expect(byKey[.vin]?.value.text == "WVWZZZAUZJW000000")

        let routing = route(analysis)
        #expect(routing.reminder?.blueprintKey == BuiltInBlueprints.vehicleRCA)
        #expect(byKey[.coverageType]?.value.text == InsuranceCover.rca)
        #expect(routing.suggestions.first?.destination == .obligation(blueprintKey: BuiltInBlueprints.vehicleRCA, templateKey: "vehicle"))
    }

    @Test("Receipt with a warranty: purchase facts and the last day of warranty")
    func receiptWithWarranty() throws {
        let analysis = analyzer.analyze(text: """
        EXEMPLU ELECTRO S.R.L.
        CIF 98765438
        BON FISCAL
        Data: 10.06.2025
        Hotă bucătărie inox 60 cm 1 buc 899,99
        TOTAL 899,99 LEI
        Termen de garanție: 24 luni
        S/N HX60-2025-0001
        """, referenceDate: today)

        #expect(analysis.kind == .fiscalReceipt)
        let byKey = Dictionary(analysis.fields.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(byKey[.retailer]?.value.text == "EXEMPLU ELECTRO S.R.L.")
        #expect(byKey[.purchaseDate]?.value.day == CalendarDay(printedYear: 2025, month: 6, day: 10))
        #expect(byKey[.purchasePrice]?.value.money == Money(Decimal(string: "899.99")!, currency: "RON"))
        #expect(byKey[.warrantyUntil]?.value.day == CalendarDay(printedYear: 2027, month: 6, day: 10))
        #expect(byKey[.serialNumber]?.value.text == "HX60-2025-0001")
        #expect(byKey[.productName]?.value.text?.hasPrefix("Hotă bucătărie") == true)

        let routing = route(analysis)
        #expect(routing.suggestions.first?.destination == .newAsset(templateKey: BuiltInTemplates.Key.purchase))
        #expect(routing.reminder?.day == CalendarDay(printedYear: 2027, month: 6, day: 10))
        #expect(routing.reminder?.blueprintKey == BuiltInBlueprints.warrantyEnds)
    }

    @Test("Driving licence: numbered EU fields give the expiry; renewal warned two months ahead")
    func drivingLicence() throws {
        let analysis = analyzer.analyze(text: """
        PERMIS DE CONDUCERE
        ROMÂNIA
        1. EXEMPLU
        2. ION
        4a. 12.03.2021
        4b. 12.03.2031
        5. 123456789
        9. B
        """, referenceDate: today)

        #expect(analysis.kind == .drivingLicence)
        let byKey = Dictionary(analysis.fields.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(byKey[.expiryDate]?.value.day == CalendarDay(printedYear: 2031, month: 3, day: 12))
        #expect(byKey[.issueDate]?.value.day == CalendarDay(printedYear: 2021, month: 3, day: 12))
        #expect(byKey[.documentNumber]?.value.text == "123456789")
        #expect(byKey[.holderName]?.value.text == "ION EXEMPLU")
        #expect(route(analysis).reminder?.blueprintKey == BuiltInBlueprints.documentRenew)
    }

    @Test("Vet record: next vaccine date, warned only the day before")
    func veterinaryRecord() throws {
        let analysis = analyzer.analyze(text: """
        CABINET VETERINAR EXEMPLU S.R.L.
        Carnet de sănătate
        Microcip: 642 0000 0000 0001
        Vaccin antirabic administrat 18.11.2025
        Rapel: 18.11.2026
        """, referenceDate: today)

        #expect(analysis.kind == .veterinaryRecord)
        let byKey = Dictionary(analysis.fields.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(byKey[.microchip]?.value.text == "642000000000001")
        #expect(byKey[.nextDoseDate]?.value.day == CalendarDay(printedYear: 2026, month: 11, day: 18))
        let routing = route(analysis)
        #expect(routing.reminder?.blueprintKey == BuiltInBlueprints.petVaccine)
        #expect(routing.reminder?.templateKey == BuiltInTemplates.Key.pet)
    }

    @Test("ITP report: next inspection and odometer")
    func itpReport() throws {
        let analysis = analyzer.analyze(text: """
        STAȚIE ITP EXEMPLU S.R.L.
        Inspecția tehnică periodică
        Nr. înmatriculare: B 123 ABC
        Kilometraj: 86.420
        Valabilă până la: 14.03.2027
        """, referenceDate: today)

        #expect(analysis.kind == .itpReport)
        let byKey = Dictionary(analysis.fields.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(byKey[.expiryDate]?.value.day == CalendarDay(printedYear: 2027, month: 3, day: 14))
        #expect(byKey[.odometer]?.value == .metric(value: 86_420, unit: .kilometres))
        #expect(route(analysis).reminder?.blueprintKey == BuiltInBlueprints.vehicleITP)
    }

    @Test("A known utility invoice is claimed by the specialized parser")
    func specializedParserWins() {
        struct FixedParser: CaptureSpecializedParser {
            func parse(_ text: CaptureText) -> CaptureAnalyzer.SpecializedParse? {
                text.contains(any: ["exemplu energie"])
                    ? .init(kind: .utilityInvoice, fields: [CaptureField(key: .podCode, value: .text("RO000E000000001"), confidence: 0.9, tier: .deterministic)])
                    : nil
            }
        }
        let analysis = CaptureAnalyzer(specializedParsers: [FixedParser()]).analyze(text: """
        Exemplu Energie S.A.
        Total de plată 210,40 lei
        Data scadenței: 25.11.2026
        """, referenceDate: today)
        #expect(analysis.kind == .utilityInvoice)
        #expect(analysis.kindConfidence >= 0.9)
        #expect(analysis.fields.contains { $0.key == .podCode })
        #expect(analysis.fields.first { $0.key == .dueDate }?.value.day == CalendarDay(printedYear: 2026, month: 11, day: 25))
    }

    @Test("Classification is the same on every run, even when scores tie")
    func classificationIsStable() {
        let text = CaptureText("Certificat de garanție\nBon fiscal\nTotal 100,00 lei")
        let kinds = Set((0..<25).map { _ in DocumentClassifier.classify(text: text, mrz: nil).kind })
        #expect(kinds == [.fiscalReceipt])
    }

    @Test("Unreadable input says so instead of guessing")
    func littleText() {
        let analysis = analyzer.analyze(text: "12 / 4", referenceDate: today)
        #expect(analysis.kind == .other)
        #expect(analysis.notices.contains(.littleTextRecognized))
        #expect(route(analysis).suggestions.first?.destination == .attachOnly)
    }
}

@Suite("Merging tiers")
struct FieldMergerTests {

    @Test("A checksum-verified value is never replaced by a model")
    func deterministicWins() {
        let mrz = CaptureField(key: .expiryDate, value: .day(CalendarDay(printedYear: 2031, month: 4, day: 15)!), confidence: 0.99, tier: .deterministic)
        let model = CaptureField(key: .expiryDate, value: .day(CalendarDay(printedYear: 2013, month: 4, day: 15)!), confidence: 1, tier: .onDeviceModel)
        let merged = FieldMerger.merge([mrz], with: [model])
        #expect(merged == [mrz])
    }

    @Test("A model fills gaps and beats a weak pattern")
    func modelBeatsWeakHeuristic() {
        let heuristic = CaptureField(key: .provider, value: .text("Client Exemplu"), confidence: 0.45, tier: .heuristic)
        let model = CaptureField(key: .provider, value: .text("Exemplu Service S.R.L."), confidence: 0.72, tier: .onDeviceModel)
        let extra = CaptureField(key: .claimsPhone, value: .text("0800123456"), confidence: 0.72, tier: .onDeviceModel)
        let merged = FieldMerger.merge([heuristic], with: [model, extra])
        #expect(merged.first { $0.key == .provider }?.value == .text("Exemplu Service S.R.L."))
        #expect(merged.contains(extra))
    }

    @Test("Agreement raises confidence and keeps the original source text")
    func agreementBoosts() throws {
        let heuristic = CaptureField(key: .total, value: .money(Money(695, currency: "RON")), confidence: 0.6, sourceText: "Total de plată: 695,00 lei", tier: .heuristic)
        let model = CaptureField(key: .total, value: .money(Money(695, currency: "RON")), confidence: 0.72, tier: .onDeviceModel)
        let merged = try #require(FieldMerger.merge([heuristic], with: [model]).first)
        #expect(merged.confidence > 0.8)
        #expect(merged.sourceText == "Total de plată: 695,00 lei")
        // Read on the document and confirmed by the model: not a model-only guess, so no "Verifică".
        #expect(merged.tier == .heuristic)
        #expect(!merged.needsCheck)
    }
}
