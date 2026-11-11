import CoreData
import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

private func field(_ key: CaptureFieldKey, _ value: CaptureValue) -> CaptureField {
    CaptureField(key: key, value: value, confidence: 0.9, sourceText: nil, tier: .heuristic)
}

private func day(_ iso: String) -> CaptureValue {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    return .day(CalendarDay(printedYear: parts[0], month: parts[1], day: parts[2])!)
}

/// A gas bill with its meter index and how the bill says it was taken, routed the way the
/// engine routes it. Placeholder provider and codes.
private func gasBill(meter: Decimal, issued: String, basis: ReadingBasis? = nil) -> CaptureResult {
    var fields = [
        field(.provider, .text("ENGIE Romania S.A.")),
        field(.serviceKind, .text(ServiceKind.gas)),
        field(.clientCode, .text("1000000000")),
        field(.clcCode, .text("DEG0000000000001")),
        field(.issueDate, day(issued)),
        field(.total, .money(Money(245, currency: "RON"))),
        field(.meterIndex, .number(meter)),
    ]
    if let basis { fields.append(field(.meterReading, .text(basis.rawValue))) }
    let routing = CaptureRouter.route(kind: .utilityInvoice, kindConfidence: 0.9, fields: fields)
    return CaptureResult(kind: .utilityInvoice, kindConfidence: 0.9, fields: fields, suggestions: routing.suggestions, reminder: routing.reminder,
                         recognizedText: "", barcodes: [], document: nil, notices: [])
}

/// A lower index on a utility bill is most often the real reading after months of estimated
/// ones (a regularisation), not a new meter. A bill says which of its indexes are estimated;
/// a real one a little below estimates corrects them without asking; a drop of about a year's
/// use or down to nothing asks with "Contor nou" first; in between, or with too little
/// history, it asks with "Era o estimare" first. One rule for every counter: a car's
/// kilometres are never estimated, so only the drop decides the order there.
@MainActor
@Suite("Estimated readings")
struct EstimatedReadingTests {

    // MARK: Reading it off the bill

    private func analyze(_ text: String) -> CaptureAnalyzer.Analysis {
        CaptureAnalyzer(specializedParsers: [UtilityInvoiceParser()]).analyze(text: text, referenceDate: noon("2026-11-06"))
    }

    private func basis(_ text: String) -> String? {
        analyze(text).fields.first { $0.key == .meterReading }?.value.text
    }

    private func bill(_ lines: String) -> String {
        """
        ENGIE Romania S.A.
        Factura seria EXM nr. 0000001
        Data emiterii: 05.10.2026
        Data scadentei: 25.10.2026
        Cod client: 1000000000
        \(lines)
        Total de plata: 245,30 lei
        """
    }

    @Test("A bill's index is estimated when the bill says so", arguments: [
        "Index nou estimat: 12.345",
        "Index estimat: 12.345 mc",
        "Index nou: 12.345 (E)",
        "Index nou: 12.345 E",
        "Index nou: 12.345 Tip citire: estimată",
        "Index nou: 12.345\nTip citire: E",
        "Index nou: 12.345\nMod de citire: citire estimată",
    ])
    func estimated(lines: String) {
        #expect(basis(bill(lines)) == ReadingBasis.estimated.rawValue)
        #expect(analyze(bill(lines)).fields.first { $0.key == .meterIndex }?.value == .number(12_345), "The index itself is read as before")
    }

    @Test("A bill's index is read when the bill says so, or is a regularisation", arguments: [
        "Index nou autocitit: 12.345",
        "Index citit de distribuitor: 12.345",
        "Index nou: 12.345 (R)",
        "Index nou: 12.345 Tip citire: citire reală",
        "Index nou: 12.345\nTip citire: autocitire",
        "FACTURĂ DE REGULARIZARE\nIndex nou: 12.345",
        "REGULARIZARE\nIndex nou: 12.345",
        "Tip factură: regularizare\nIndex nou: 12.345",
    ])
    func read(lines: String) {
        #expect(basis(bill(lines)) == ReadingBasis.read.rawValue)
    }

    @Test("A bill that doesn't say, or says both, says nothing", arguments: [
        "Index nou: 12.345",
        "Index nou: 12.345 mc",
        "Index nou: 12.345\nTip citire: E = estimat, R = citire reală",
        "Index nou: 12.345\nRegularizarea se face la următoarea citire.",
    ])
    func notSaid(lines: String) {
        #expect(basis(bill(lines)) == nil)
    }

    @Test func onlyABillCarriesIt() {
        #expect(CaptureDocumentKind.utilityInvoice.allows(.meterReading))
        #expect(!CaptureDocumentKind.rcaPolicy.allows(.meterReading))
        #expect(!CaptureMapping.isShownInReview(.meterReading, among: [.meterIndex, .meterReading]), "It goes with the index, said in its line")
    }

    // MARK: Asked of the models

    @Test func bothModelsAreAskedAndTheirAnswersFollowTheBillsWords() throws {
        for reader in [ModelQuestions.Reader.page, .text] {
            let asked = ModelQuestions(kind: .utilityInvoice, reader: reader)
            let question = try #require(asked.fields.first { $0.key == .meterReading })
            #expect(question.format == .meterReading)
            #expect(question.description.contains("estimated") && question.description.contains("regularisation"))
        }
        let answer = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"documentKind":"utilityInvoice","meterReading":"estimated"}"#.utf8))
        let onDevice = ModelQuestions(kind: .utilityInvoice, reader: .text)
        let today = CalendarDay(printedYear: 2026, month: 11, day: 6)!
        let said = ModelAnswerMapper.fields(from: answer, asked: onDevice, recognizedText: "Index nou estimat: 12.345", today: today,
                                            resolver: CatalogComponentResolver())
        #expect(said.first { $0.key == .meterReading }?.value == .text("estimated"))
        let unsaid = ModelAnswerMapper.fields(from: answer, asked: onDevice, recognizedText: "Index nou: 12.345", today: today,
                                              resolver: CatalogComponentResolver())
        #expect(!unsaid.contains { $0.key == .meterReading }, "Apple's model can't have read what the text doesn't say")
        let page = ModelAnswerMapper.fields(from: answer, asked: CloudSchema(kind: .utilityInvoice).questions, recognizedText: "", today: today,
                                            resolver: CatalogComponentResolver())
        #expect(page.first { $0.key == .meterReading }?.value == .text("estimated"), "The AI provider saw the page")
        let unknown = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"documentKind":"utilityInvoice","meterReading":"maybe"}"#.utf8))
        #expect(!ModelAnswerMapper.fields(from: unknown, asked: CloudSchema(kind: .utilityInvoice).questions, recognizedText: "", today: today,
                                          resolver: CatalogComponentResolver()).contains { $0.key == .meterReading })
    }

    // MARK: A subscription's meter

    private func home(_ context: ModelContext) throws -> Asset {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.home))
        var values = FieldValues()
        values["home.address"] = .text("Strada Exemplu nr. 1")
        return try AssetActions(context: context).create(name: "Casa Exemplu", template: template, values: values)
    }

    private func file(_ result: CaptureResult, _ context: ModelContext, on iso: String, answer: LowerReadingAnswer? = nil) async throws -> CaptureFiler.Outcome {
        var filer = CaptureFiler(context: context, store: CaptureDocumentStore(), calendar: .bucharest, now: { noon(iso) })
        filer.lowerReading = answer
        let review = CaptureReview(result: result, assets: try context.fetch(FetchDescriptor<Asset>()), context: context)
        return try await filer.save(review)
    }

    private func readings(of asset: Asset) -> [MeasurementLog] {
        (asset.measurements ?? []).filter { !$0.isDeleted }.sorted { $0.recordedAt < $1.recordedAt }
    }

    private func question(_ result: CaptureResult, _ context: ModelContext, on iso: String) async throws -> LowerReadingQuestion {
        do {
            _ = try await file(result, context, on: iso)
        } catch let question as LowerReadingQuestion {
            #expect(context.hasChanges == false, "Asked before anything is written")
            return question
        }
        Issue.record("No question was asked")
        throw CancellationError()
    }

    /// Read in June, then three months the provider estimated, as a gas meter often goes.
    private func estimatedSummer(_ context: ModelContext) async throws -> Asset {
        _ = try home(context)
        let gas = try #require(try await file(gasBill(meter: 10_000, issued: "2026-06-05", basis: .read), context, on: "2026-06-06").asset)
        _ = try await file(gasBill(meter: 10_100, issued: "2026-07-05", basis: .estimated), context, on: "2026-07-06")
        _ = try await file(gasBill(meter: 10_200, issued: "2026-08-05", basis: .estimated), context, on: "2026-08-06")
        _ = try await file(gasBill(meter: 10_300, issued: "2026-09-05", basis: .estimated), context, on: "2026-09-06")
        #expect(readings(of: gas).map(\.basis) == [.read, .estimated, .estimated, .estimated], "Each reading keeps how its bill says it was taken")
        #expect(SubscriptionMeter.last(on: gas, calendar: .bucharest)?.isEstimate == true, "Ultimul index says it is an estimate")
        return gas
    }

    @Test func aRegularisationBelowTheEstimatesAsksNothingAndCorrectsThem() async throws {
        let context = try makeContext()
        let gas = try await estimatedSummer(context)

        // The regularisation: 150 m³ below the last estimate, about a month and a half of this meter's use.
        let outcome = try await file(gasBill(meter: 10_150, issued: "2026-10-05", basis: .read), context, on: "2026-10-06")
        #expect(readings(of: gas).map(\.value) == [10_000, 10_100, 10_200, 10_300, 10_150], "The estimates stay in the history")
        #expect(readings(of: gas).map(\.basis) == [.read, .estimated, .estimated, .estimated, .read])
        let series = HouseholdMutations.readingSeries(of: gas, unit: .cubicMetres)
        #expect(series.readings.map(\.metric) == [10_000, 10_100, 10_150], "The estimates above the real index count no more")
        #expect(series.corrected.map(\.metric) == [10_200, 10_300])
        #expect(series.setAside.isEmpty, "Nothing breaks the order")
        #expect(SubscriptionMeter.last(on: gas, calendar: .bucharest)?.value == 10_150, "Ultimul index is the real one")
        #expect(SubscriptionMeter.last(on: gas, calendar: .bucharest)?.isEstimate == false)

        // The next bill compares with the real index, not with the corrected estimates.
        _ = try await file(gasBill(meter: 10_250, issued: "2026-11-05"), context, on: "2026-11-06")
        #expect(SubscriptionMeter.last(on: gas, calendar: .bucharest)?.value == 10_250)

        // "Anulează" on the regularisation's filing: its reading goes and the estimates count again.
        let context2 = try makeContext()
        let gas2 = try await estimatedSummer(context2)
        let regularisation = try await file(gasBill(meter: 10_150, issued: "2026-10-05", basis: .read), context2, on: "2026-10-06")
        try #require(regularisation.receipt).undo()
        #expect(readings(of: gas2).map(\.value) == [10_000, 10_100, 10_200, 10_300])
        #expect(SubscriptionMeter.last(on: gas2, calendar: .bucharest)?.value == 10_300)
        _ = outcome
    }

    @Test func aReadingNearZeroAsksWithANewCounterFirst() async throws {
        let context = try makeContext()
        _ = try await estimatedSummer(context)
        let asked = try await question(gasBill(meter: 15, issued: "2026-10-05", basis: .read), context, on: "2026-10-06")
        #expect(asked.answers == [.newCounter, .wasEstimate])
        #expect(asked.question == "Citirea e mai mică decât ultima dată. E un contor nou?")
        #expect(asked.explanation.hasSuffix("Dacă e un contor nou, cele vechi rămân în istoric. Dacă era o estimare, rămâne în istoric, dar nu se mai socotește."))
    }

    @Test func aDropOfMoreThanAYearsUseAsksWithANewCounterFirst() async throws {
        let context = try makeContext()
        _ = try home(context)
        _ = try await file(gasBill(meter: 10_000, issued: "2026-06-05"), context, on: "2026-06-06")
        _ = try await file(gasBill(meter: 10_300, issued: "2026-09-05"), context, on: "2026-09-06")
        // About 3 m³ a day; 2.300 m³ is two years of it, but not down to nothing.
        let asked = try await question(gasBill(meter: 8_000, issued: "2026-10-05"), context, on: "2026-10-06")
        #expect(asked.answers == [.newCounter, .wasEstimate])
        #expect(ReadingDrop(from: 99_999, to: 0, series: ReadingSeries([])).size == .large, "A meter that went round")
    }

    @Test func belowAReadingNotKnownAsAnEstimateItAsksWithEraOEstimareFirst() async throws {
        let context = try makeContext()
        _ = try home(context)
        let gas = try #require(try await file(gasBill(meter: 10_000, issued: "2026-06-05"), context, on: "2026-06-06").asset)
        _ = try await file(gasBill(meter: 10_300, issued: "2026-09-05"), context, on: "2026-09-06")
        let lower = gasBill(meter: 10_050, issued: "2026-10-05")
        let asked = try await question(lower, context, on: "2026-10-06")
        #expect(asked.answers == [.wasEstimate, .newCounter], "Never Corectează nor Lasă on a bill's meter")
        #expect(asked.question == "Citirea e mai mică decât ultima dată. Cea veche era o estimare?")

        let outcome = try await file(lower, context, on: "2026-10-06", answer: .wasEstimate)
        #expect(readings(of: gas).map(\.value) == [10_000, 10_300, 10_050], "The bill's index stays in the history")
        #expect(readings(of: gas).map(\.basis) == [nil, .estimated, nil])
        #expect(SubscriptionMeter.last(on: gas, calendar: .bucharest)?.value == 10_050)

        // Undone, the earlier reading is as it was.
        try #require(outcome.receipt).undo()
        #expect(readings(of: gas).map(\.value) == [10_000, 10_300])
        #expect(readings(of: gas).map(\.basis) == [nil, nil])
    }

    @Test func anEstimateFarAboveTheRealIndexStillAsks() async throws {
        let context = try makeContext()
        _ = try home(context)
        _ = try await file(gasBill(meter: 10_000, issued: "2026-01-05", basis: .read), context, on: "2026-01-06")
        _ = try await file(gasBill(meter: 10_600, issued: "2026-07-05", basis: .read), context, on: "2026-07-06")
        _ = try await file(gasBill(meter: 13_000, issued: "2026-10-05", basis: .estimated), context, on: "2026-10-06")
        // 2.300 m³ below the estimate is more than half a year of this meter's use (about 11 m³ a day, the estimate included), less than a year.
        let asked = try await question(gasBill(meter: 10_700, issued: "2026-11-05", basis: .read), context, on: "2026-11-06")
        #expect(asked.answers == [.wasEstimate, .newCounter], "Only the estimate is higher: a correction is still likelier")
        #expect(asked.previous == 13_000)
    }

    // MARK: A car

    private func car(_ context: ModelContext) throws -> Asset {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        var values = FieldValues()
        values["vehicle.odometer"] = .number(100_000)
        let golf = try AssetActions(context: context, calendar: .bucharest, now: { noon("2026-01-10") }).create(name: "VW Golf 2018", template: template, values: values)
        try edit(golf, km: 103_000, in: context, on: "2026-04-10")
        return golf
    }

    private func edit(_ car: Asset, km: Double, in context: ModelContext, on day: String, answer: LowerReadingAnswer? = nil) throws {
        var values = car.values
        values["vehicle.odometer"] = .number(km)
        try AssetActions(context: context, calendar: .bucharest, now: { noon(day) })
            .update(car, name: car.name, values: values, notes: car.notes, lowerReading: answer)
    }

    private func carQuestion(_ golf: Asset, km: Double, _ context: ModelContext) throws -> LowerReadingQuestion {
        do {
            try edit(golf, km: km, in: context, on: "2026-05-10")
        } catch let question as LowerReadingQuestion {
            return question
        }
        Issue.record("No question was asked")
        throw CancellationError()
    }

    @Test func aCarAlwaysAsksAndTheDropDecidesTheOrder() throws {
        let context = try makeContext()
        let golf = try car(context)
        #expect(readings(of: golf).allSatisfy { $0.basis == .read }, "The person read the dashboard")

        // A little lower: a typo is likelier. Kilometres are never estimates, so it always asks.
        let small = try carQuestion(golf, km: 102_900, context)
        #expect(small.answers == [.correctOld, .keepAside, .newCounter])
        #expect(small.question == "Kilometrajul e mai mic decât ultima dată. Corectez citirea veche?")

        // Down to nothing, or more than a year of driving: a new dashboard is likelier.
        let replaced = try carQuestion(golf, km: 1_000, context)
        #expect(replaced.answers == [.newCounter, .correctOld, .keepAside])
        #expect(replaced.question == "Kilometrajul e mai mic decât ultima dată. E un contor nou?")
        let far = try carQuestion(golf, km: 80_000, context)
        #expect(far.answers.first == .newCounter, "23.000 km below is more than a year at about 33 km a day")
        #expect(context.hasChanges == false)
    }

    // MARK: The series

    @Test func anEstimateCountsUntilALowerReadingComes() {
        let readings: [CadenceCalculator.TelemetryReading] = [
            .init(date: noon("2026-06-05"), metric: 10_000),
            .init(date: noon("2026-07-05"), metric: 10_100, isEstimate: true),
            .init(date: noon("2026-08-05"), metric: 10_200, isEstimate: true),
        ]
        #expect(ReadingSeries(readings).current == 10_200, "Until a real reading comes, the estimate is the best known")
        let corrected = ReadingSeries(readings + [.init(date: noon("2026-09-05"), metric: 10_150)])
        #expect(corrected.current == 10_150)
        #expect(corrected.corrected.map(\.metric) == [10_200])
        #expect(ReadingSeries(corrected.readings).current == 10_150, "A series made again from its readings counts the same")
        // On another counter, a lower reading corrects nothing.
        let newMeter = ReadingSeries(readings + [.init(date: noon("2026-09-05"), metric: 5, startsCounter: true)])
        #expect(newMeter.corrected.isEmpty)
        #expect(newMeter.counters.map { $0.map(\.metric) } == [[10_000, 10_100, 10_200], [5]])
    }

    // MARK: Backups and the database

    @Test func aBackupCarriesHowEachReadingWasTakenBothWays() async throws {
        let source = try makeInMemoryContainer()
        let context = ModelContext(source)
        try TemplateStore(context: context).installBuiltIns()
        let gas = try await estimatedSummer(context)
        _ = try await file(gasBill(meter: 10_150, issued: "2026-10-05", basis: .read), context, on: "2026-10-06")
        _ = gas
        let data = try DossierArchiveService(container: source, calendar: .bucharest).exportData(exportedAt: noon("2026-11-02"))

        let target = try makeInMemoryContainer()
        try DossierArchiveService(container: target, calendar: .bucharest).importArchive(data, mode: .replace)
        let copy = try #require(try ModelContext(target).fetch(FetchDescriptor<Asset>()).first { !(($0.measurements ?? []).isEmpty) })
        #expect(readings(of: copy).map(\.basis) == [.read, .estimated, .estimated, .estimated, .read])
        #expect(HouseholdMutations.readingSeries(of: copy, unit: .cubicMetres).current == 10_150)

        let plain = DossierV3.Measurement(id: UUID().uuidString, kind: "gas", name: "", value: 1, unit: "m3", recordedAt: noon("2026-01-01"),
                                          isSelfRead: true, isExample: false)
        let json = try #require(String(data: try JSONEncoder().encode(plain), encoding: .utf8))
        #expect(!json.contains("basis"), "A reading nothing is known about writes nothing")
    }

    @Test func aStoreFromVersionThirteenOpensWithNothingSaidAboutItsReadings() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v13.store")
        let edited = noon("2026-10-01")

        // Written by version 13: a gas subscription with two indexes.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV13.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let gas = DosarSchemaV13.Asset(name: "Gaz Casa Exemplu", templateKey: BuiltInTemplates.Key.subscription)
            context.insert(gas)
            for (value, iso) in [(10_000.0, "2026-06-05"), (10_300.0, "2026-09-05")] {
                let log = DosarSchemaV13.MeasurementLog(name: "", value: value)
                log.kindRaw = MeasurementKind.gas.rawValue
                log.unit = MeasurementUnit.cubicMetres.key
                log.recordedAt = noon(iso)
                log.updatedAt = edited
                context.insert(log)
                log.asset = gas
            }
            try context.save()
        }

        // Opened by this version: every reading as it was, nothing said about how it was taken.
        let container = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let kept = try context.fetch(FetchDescriptor<MeasurementLog>()).sorted { $0.recordedAt < $1.recordedAt }
        #expect(kept.map(\.value) == [10_000, 10_300])
        #expect(kept.allSatisfy { $0.basisRaw == nil && $0.updatedAt == edited }, "Nothing guessed, and an upgrade isn't a change")

        kept[1].basis = .estimated
        try UnitOfWork.save(context)
        let reopened = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        #expect(try reopened.fetch(FetchDescriptor<MeasurementLog>()).sorted { $0.recordedAt < $1.recordedAt }.map(\.basis) == [nil, .estimated])
    }

    @Test func versionFourteenChangesOnlyReadings() throws {
        let thirteen = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV13.models))
        let fourteen = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV14.models))
        for (entity, hash) in thirteen.entityVersionHashesByName where entity != "MeasurementLog" {
            #expect(fourteen.entityVersionHashesByName[entity] == hash, "\(entity) is as version 13 shipped it")
        }
        let before = Set(thirteen.entitiesByName["MeasurementLog"]?.attributesByName.keys.map { $0 } ?? [])
        let after = try #require(fourteen.entitiesByName["MeasurementLog"]?.attributesByName)
        #expect(Set(after.keys).subtracting(before) == ["basisRaw"])
        #expect(after["basisRaw"]?.isOptional == true, "Optional, as CloudKit needs")
        // The frozen version 13 is version 12 with which copy each record is, nothing more.
        let twelve = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV12.models))
        for (entity, description) in thirteen.entitiesByName {
            let added = Set(description.attributesByName.keys).subtracting(twelve.entitiesByName[entity]?.attributesByName.keys.map { $0 } ?? [])
            #expect(added == ["copyID"], "\(entity)")
        }
    }

    // MARK: Bills kept before

    @Test func aBillWhoseKeptTextSaysEstimatedIsOfferedAndMarkedOnceApproved() async throws {
        let context = try makeContext()
        _ = try home(context)
        let gas = try #require(try await file(gasBill(meter: 10_000, issued: "2026-06-05"), context, on: "2026-06-06").asset)
        _ = try await file(gasBill(meter: 10_300, issued: "2026-09-05"), context, on: "2026-09-06")
        let estimated = try #require(readings(of: gas).last)
        let paper = DosarCuSina.Attachment(id: UUID(), fileName: "factura.pdf", contentType: "com.adobe.pdf", data: Data("%PDF-1.7".utf8), kind: .invoice)
        paper.extractedText = "ENGIE Romania S.A.\nData emiterii: 05.09.2026\nIndex nou estimat: 10.300\nTotal de plata: 245,30 lei"
        context.insert(paper)
        paper.asset = gas
        paper.measurement = estimated
        let other = DosarCuSina.Attachment(id: UUID(), fileName: "factura-iunie.pdf", contentType: "com.adobe.pdf", data: Data("%PDF-1.7".utf8), kind: .invoice)
        other.extractedText = "Index nou: 10.000"
        context.insert(other)
        other.asset = gas
        other.measurement = readings(of: gas).first
        try UnitOfWork.save(context)

        var scan = DataRepairScan(context: context, calendar: .bucharest)
        let findings = try EstimatedBillReadingsStep().findings(&scan)
        #expect(findings.count == 1, "Only the bill that says its index was estimated")
        #expect(findings.first?.message.contains("10.300 m³") == true)
        try DataRepairs(context: context, calendar: .bucharest).apply(findings)
        #expect(readings(of: gas).map(\.basis) == [nil, .estimated])
        var again = DataRepairScan(context: context, calendar: .bucharest)
        #expect(try EstimatedBillReadingsStep().findings(&again).isEmpty)
    }
}
