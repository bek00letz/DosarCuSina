import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

private func field(_ key: CaptureFieldKey, _ value: CaptureValue, confidence: Double = 0.9) -> CaptureField {
    CaptureField(key: key, value: value, confidence: confidence, sourceText: nil, tier: .heuristic)
}

private func day(_ iso: String) -> CaptureValue {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    return .day(CalendarDay(printedYear: parts[0], month: parts[1], day: parts[2])!)
}

private func ron(_ amount: String) -> CaptureValue {
    .money(Money(Decimal(string: amount)!, currency: "RON"))
}

/// A capture result routed the way the engine routes it.
private func capture(_ kind: CaptureDocumentKind, _ fields: [CaptureField]) -> CaptureResult {
    let routing = CaptureRouter.route(kind: kind, kindConfidence: 0.9, fields: fields)
    return CaptureResult(kind: kind, kindConfidence: 0.9, fields: fields, suggestions: routing.suggestions, reminder: routing.reminder,
                         recognizedText: "", barcodes: [], document: nil, notices: [])
}

/// An ENGIE gas bill for one consumption point. Placeholder codes.
private func gasBill(clc: String = "DEG0000000000001", issued: String, due: String, total: String, number: String = "EX 000000001") -> CaptureResult {
    capture(.utilityInvoice, [
        field(.provider, .text("ENGIE Romania S.A.")),
        field(.serviceKind, .text(ServiceKind.gas)),
        field(.clientCode, .text("1000000000")),
        field(.clcCode, .text(clc)),
        field(.invoiceNumber, .text(number)),
        field(.issueDate, day(issued)),
        field(.dueDate, day(due)),
        field(.total, ron(total)),
    ])
}

/// Filing bills and contracts under the ongoing contract they belong to: one record per
/// contract, found again by its codes, never merged across two homes.
@Suite("Subscriptions from capture")
@MainActor
struct SubscriptionFilingTests {

    private let today = "2026-11-02"

    private func filer(_ context: ModelContext, on iso: String? = nil) -> CaptureFiler {
        let date = noon(iso ?? today)
        return CaptureFiler(context: context, calendar: .bucharest, now: { date })
    }

    private func template(_ key: String, _ context: ModelContext) throws -> CategoryTemplate {
        try #require(try TemplateStore(context: context).template(forKey: key))
    }

    private func home(_ name: String, _ context: ModelContext, clc: String? = nil) throws -> Asset {
        var values = FieldValues()
        values["home.address"] = .text("Strada Exemplu nr. 1")
        if let clc { values["home.clc"] = .text(clc) }
        return try AssetActions(context: context).create(name: name, template: try template(BuiltInTemplates.Key.home, context), values: values)
    }

    private func subscription(_ name: String, under parent: Asset?, _ values: [String: FieldValue], _ context: ModelContext) throws -> Asset {
        var fields = FieldValues()
        for (key, value) in values { fields[key] = value }
        return try AssetActions(context: context).create(name: name, template: try template(BuiltInTemplates.Key.subscription, context), values: fields, parent: parent)
    }

    private func assets(_ context: ModelContext) throws -> [Asset] {
        try context.fetch(FetchDescriptor<Asset>())
    }

    private func save(_ result: CaptureResult, _ context: ModelContext, on iso: String? = nil, edit: (inout CaptureReview) -> Void = { _ in }) async throws -> CaptureFiler.Outcome {
        var review = CaptureReview(result: result, assets: try assets(context), context: context)
        edit(&review)
        return try await filer(context, on: iso).save(review)
    }

    // MARK: Matching (pure)

    private typealias Reading = SubscriptionMatcher.Reading

    @Test func twoHomesWithTheSameProviderNeverMerge() {
        let houseA = UUID(), houseB = UUID(), gasA = UUID(), gasB = UUID()
        var a = FieldValues(), b = FieldValues()
        a[SubscriptionFields.provider] = .text("ENGIE Romania S.A.")
        a[SubscriptionFields.service] = .text(ServiceKind.gas)
        a[SubscriptionFields.clc] = .text("DEG0000000000001")
        a[SubscriptionFields.clientCode] = .text("1000000000")
        b = a
        b[SubscriptionFields.clc] = .text("DEG0000000000002")
        let subscriptions = [
            SubscriptionMatcher.Subscription(id: gasA, parentID: houseA, values: a),
            SubscriptionMatcher.Subscription(id: gasB, parentID: houseB, values: b),
        ]
        let homes = [SubscriptionMatcher.Home(id: houseA, values: FieldValues()), SubscriptionMatcher.Home(id: houseB, values: FieldValues())]
        func match(_ codes: [SubscriptionMatcher.Code: String]) -> SubscriptionMatcher.Decision {
            SubscriptionMatcher.match(Reading(provider: "ENGIE Romania", service: ServiceKind.gas, codes: codes, isBill: true),
                                      subscriptions: subscriptions, homes: homes)
        }
        #expect(match([.clc: "DEG 0000000000002"]) == .existing(gasB), "The CLC names the house")
        #expect(match([.clc: "DEG0000000000002", .clientCode: "1000000000"]) == .existing(gasB), "The CLC outranks a shared client code")
        #expect(match([:]) == .undecided, "The provider alone can't tell two houses apart")
        #expect(match([.clientCode: "1000000000"]) == .undecided, "One client code covers both houses")
        #expect(match([.clc: "DEG0000000000003"]) == .undecided, "A third consumption point: which house isn't known")
    }

    @Test func aFirstBillGoesUnderItsHouse() {
        let only = UUID(), other = UUID()
        let gas = Reading(provider: "ENGIE Romania", service: ServiceKind.gas, codes: [.clc: "DEG0000000000001"], isBill: true)
        #expect(SubscriptionMatcher.match(gas, subscriptions: [], homes: [.init(id: only, values: FieldValues())]) == .newUnder(home: only))
        var named = FieldValues()
        named["home.clc"] = .text("DEG0000000000001")
        #expect(SubscriptionMatcher.match(gas, subscriptions: [], homes: [.init(id: other, values: FieldValues()), .init(id: only, values: named)]) == .newUnder(home: only),
                "The home that keeps the same CLC")
        #expect(SubscriptionMatcher.match(gas, subscriptions: [], homes: []) == .newStandalone, "No home yet: it can be moved later")
    }

    @Test func aMobilePlanStandsOnItsOwnAndIsFoundByItsNumber() {
        let home = UUID(), lineA = UUID(), lineB = UUID()
        let homes = [SubscriptionMatcher.Home(id: home, values: FieldValues())]
        let mobile = Reading(provider: "Orange Romania", service: ServiceKind.mobile, codes: [.phoneNumber: "0700 000 001"], isBill: true)
        #expect(SubscriptionMatcher.match(mobile, subscriptions: [], homes: homes) == .newStandalone, "Never under the house")

        func line(_ id: UUID, _ number: String?) -> SubscriptionMatcher.Subscription {
            var values = FieldValues()
            values[SubscriptionFields.provider] = .text("Orange Romania S.A.")
            values[SubscriptionFields.service] = .text(ServiceKind.mobile)
            if let number { values[SubscriptionFields.phoneNumber] = .text(number) }
            return .init(id: id, parentID: nil, values: values)
        }
        let two = [line(lineA, "0700 000 000"), line(lineB, "+40 700 000 001")]
        #expect(SubscriptionMatcher.match(mobile, subscriptions: two, homes: homes) == .existing(lineB))
        let unnumbered = Reading(provider: "Orange", service: ServiceKind.mobile, codes: [:], isBill: true)
        #expect(SubscriptionMatcher.match(unnumbered, subscriptions: two, homes: homes) == .undecided, "Two lines, no number: the person picks")
        #expect(SubscriptionMatcher.match(mobile, subscriptions: [line(lineA, nil)], homes: homes) == .existing(lineA), "The only Orange plan")
        #expect(SubscriptionMatcher.match(mobile, subscriptions: [line(lineA, "0700 000 009")], homes: homes) == .newStandalone, "Another number is another line")
    }

    // MARK: Filing bills

    @Test func aBillMakesItsSubscriptionUnderTheHomeThenTheNextFindsIt() async throws {
        let context = try makeContext()
        let house = try home("Casa Pipera", context)

        let first = try await save(gasBill(issued: "2026-10-05", due: "2026-11-20", total: "245.30"), context)
        let gas = try #require(first.asset)
        #expect(gas.templateKey == BuiltInTemplates.Key.subscription)
        #expect(gas.parent?.id == house.id, "Gas lives under the house")
        #expect(gas.name == "Gaz – ENGIE Romania S.A.")
        #expect(gas.value(SubscriptionFields.service) == .text(ServiceKind.gas))
        #expect(gas.value(SubscriptionFields.clc) == .text("DEG0000000000001"))
        #expect(gas.value(SubscriptionFields.lastBill) == .money(Money(Decimal(string: "245.30")!)))
        let bill = try #require(first.obligation)
        #expect(bill.blueprintKey == SubscriptionFields.billBlueprint)
        #expect(bill.asset?.id == gas.id, "Attached to the subscription, not loose")
        #expect(bill.dueDay == CalendarDay("2026-11-20"))
        #expect(bill.estimatedCost == Money(Decimal(string: "245.30")!))
        #expect(bill.reference == "EX 000000001")
        #expect(first.bill?.totalCost == Money(Decimal(string: "245.30")!))
        #expect(first.bill?.kind == .payment)

        let second = try await save(gasBill(issued: "2026-11-05", due: "2026-11-28", total: "310.10", number: "EX 000000002"), context, on: "2026-11-06")
        #expect(second.asset?.id == gas.id, "The same contract, found by its CLC")
        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 2, "No second subscription")
        #expect(gas.activeObligations.filter { $0.blueprintKey == SubscriptionFields.billBlueprint }.count == 1, "One bill to pay at a time")
        #expect(gas.activeObligations.first?.dueDay == CalendarDay("2026-11-28"), "This bill's own due date")
        #expect(gas.activeObligations.first?.estimatedCost == Money(Decimal(string: "310.10")!))
        #expect(gas.value(SubscriptionFields.lastBill) == .money(Money(Decimal(string: "310.10")!)))
        #expect((gas.history ?? []).filter { $0.kind == .payment }.count == 2)

        // An older bill filed late moves nothing back.
        _ = try await save(gasBill(issued: "2026-09-05", due: "2026-09-25", total: "199.00", number: "EX 000000000"), context, on: "2026-11-07")
        #expect(gas.value(SubscriptionFields.lastBill) == .money(Money(Decimal(string: "310.10")!)), "The newest stays the last")
        #expect(gas.activeObligations.first?.dueDay == CalendarDay("2026-11-28"))
    }

    @Test func twoHomesBillsGoToTheirOwnSubscriptions() async throws {
        let context = try makeContext()
        let pipera = try home("Casa Pipera", context)
        let munte = try home("Casa de la munte", context)
        let gasPipera = try subscription("Gaz – ENGIE", under: pipera, [
            SubscriptionFields.provider: .text("ENGIE Romania S.A."), SubscriptionFields.service: .text(ServiceKind.gas),
            SubscriptionFields.clc: .text("DEG0000000000001"),
        ], context)
        let gasMunte = try subscription("Gaz – ENGIE", under: munte, [
            SubscriptionFields.provider: .text("ENGIE Romania S.A."), SubscriptionFields.service: .text(ServiceKind.gas),
            SubscriptionFields.clc: .text("DEG0000000000002"),
        ], context)

        let outcome = try await save(gasBill(clc: "DEG0000000000002", issued: "2026-10-05", due: "2026-11-20", total: "120.00"), context)
        #expect(outcome.asset?.id == gasMunte.id)
        #expect((gasPipera.history ?? []).isEmpty)

        let unknown = capture(.utilityInvoice, [field(.provider, .text("ENGIE Romania S.A.")), field(.serviceKind, .text(ServiceKind.gas)),
                                                field(.dueDate, day("2026-11-20"))])
        let review = CaptureReview(result: unknown, assets: try assets(context), context: context)
        #expect(review.destination == .none, "No code, two houses: the person picks")
        #expect(!filer(context).touchesReminders(review))
    }

    @Test func choosingAHomeFilesIntoItsSubscriptionThere() async throws {
        let context = try makeContext()
        let pipera = try home("Casa Pipera", context)
        _ = try home("Casa de la munte", context)
        let outcome = try await save(gasBill(issued: "2026-10-05", due: "2026-11-20", total: "120.00"), context) { review in
            #expect(review.destination == .none, "Two homes and no home keeps this CLC")
            review.destination = .asset(pipera.id)
        }
        let gas = try #require(outcome.asset)
        #expect(gas.parent?.id == pipera.id)
        #expect(gas.templateKey == BuiltInTemplates.Key.subscription)

        let next = try await save(gasBill(issued: "2026-11-05", due: "2026-11-28", total: "130.00", number: "EX 000000002"), context, on: "2026-11-06")
        #expect(next.asset?.id == gas.id, "Now the CLC finds it by itself")
    }

    @Test func directDebitMeansNoReminderToPay() async throws {
        let context = try makeContext()
        let house = try home("Casa Pipera", context)
        let gas = try subscription("Gaz – ENGIE", under: house, [
            SubscriptionFields.provider: .text("ENGIE Romania S.A."), SubscriptionFields.service: .text(ServiceKind.gas),
            SubscriptionFields.clc: .text("DEG0000000000001"), SubscriptionFields.directDebit: .bool(true),
        ], context)
        var review = CaptureReview(result: gasBill(issued: "2026-10-05", due: "2026-11-20", total: "245.30"), assets: try assets(context), context: context)
        #expect(review.destination == .asset(gas.id))
        #expect(review.paysByDirectDebit(assets: try assets(context)))
        #expect(!filer(context).touchesReminders(review), "Nothing to ask permission for")
        let templates = try TemplateStore(context: context).templatesByKey()
        #expect(CaptureReminderPreview.text(for: review, templates: templates, assets: try assets(context), calendar: .bucharest, today: CalendarDay(today))?
            .contains("debit direct") == true)
        review.remindsToPay = true
        let outcome = try await filer(context).save(review)
        #expect(outcome.asset?.id == gas.id)
        #expect(gas.activeObligations.isEmpty, "The bank pays it")
        #expect((gas.history ?? []).count == 1, "The bill is still logged")
    }

    @Test func aMobileBillGoesToAbonamenteNotUnderTheHouse() async throws {
        let context = try makeContext()
        _ = try home("Casa Pipera", context)
        let outcome = try await save(capture(.utilityInvoice, [
            field(.provider, .text("Orange Romania S.A.")),
            field(.serviceKind, .text(ServiceKind.mobile)),
            field(.phoneNumber, .text("0700 000 000")),
            field(.issueDate, day("2026-10-05")),
            field(.dueDate, day("2026-11-20")),
            field(.total, ron("45.00")),
        ]), context) { review in
            #expect(review.destination == .newAsset(templateKey: BuiltInTemplates.Key.subscription))
            #expect(review.newAssetName == "Telefon mobil – Orange Romania S.A.")
        }
        let plan = try #require(outcome.asset)
        #expect(plan.parent == nil, "A phone plan stands on its own")
        #expect(plan.value(SubscriptionFields.phoneNumber) == .text("0700 000 000"))
        #expect(plan.value(SubscriptionFields.service) == .text(ServiceKind.mobile))
    }

    @Test func aBillKeptWithoutAPlaceSetsNoLooseReminder() async throws {
        let context = try makeContext()
        let outcome = try await save(gasBill(issued: "2026-10-05", due: "2026-11-20", total: "245.30"), context) { review in
            review.destination = .none
        }
        #expect(outcome.asset == nil)
        #expect(outcome.obligation == nil)
        #expect(try context.fetchCount(FetchDescriptor<Obligation>()) == 0, "No loose \u{201E}Factură\u{201D} any more")
    }

    // MARK: Contracts, end to end

    @Test func aContractMakesItsSubscriptionWithTheMinimumPeriodsDeadline() async throws {
        let context = try makeContext()
        let house = try home("Casa Pipera", context)
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: CaptureEngineTests.FixedRecognizer(text: ""),
                                   normalizer: nil, onDeviceModel: nil, cloudModel: nil, store: nil)
        let result = try await engine.capture(CaptureRequest(.text(ContractCaptureTests.gasContract),
                                                              options: CaptureOptions(storeDocument: false, referenceDate: noon(today))))
        #expect(result.kind == .contract)
        let review = CaptureReview(result: result, assets: try assets(context), context: context)
        #expect(review.destination == .asset(house.id), "Gas: under the only house")
        #expect(review.blueprintKey == SubscriptionFields.minimumEndsBlueprint)
        #expect(filer(context).touchesReminders(review))
        let templates = try TemplateStore(context: context).templatesByKey()
        let preview = try #require(CaptureReminderPreview.text(for: review, templates: templates, assets: try assets(context), calendar: .bucharest, today: CalendarDay(today)))
        #expect(preview.hasPrefix("Perioada minimă se termină pe 15 martie 2028."))
        #expect(preview.contains("de regulă"))

        let outcome = try await filer(context).save(review)
        let gas = try #require(outcome.asset)
        #expect(gas.parent?.id == house.id)
        #expect(gas.value(SubscriptionFields.contractNumber) == .text("EX-2026-000123"))
        #expect(gas.value(SubscriptionFields.minimumMonths) == .number(24))
        #expect(gas.value(SubscriptionFields.minimumUntil) == .date(CalendarDay("2028-03-15")))
        let minimum = try #require(gas.activeObligations.first { $0.blueprintKey == SubscriptionFields.minimumEndsBlueprint })
        #expect(minimum.dueDay == CalendarDay("2028-03-15"))
        #expect(minimum.reminderLeadDays == [30, 0], "A month before and on the day")
        #expect(minimum.title == "Se termină perioada minimă")
        #expect(minimum.notes?.contains("fără penalități") == true)

        // The first bill finds the contract's subscription by its CLC.
        let bill = try await save(gasBill(issued: "2026-10-05", due: "2026-11-20", total: "245.30"), context)
        #expect(bill.asset?.id == gas.id)
    }

    @Test func anAddendumUpdatesTheTermsAndMovesTheDeadline() async throws {
        let context = try makeContext()
        let gas = try subscription("Telefon – Orange", under: nil, [
            SubscriptionFields.provider: .text("Orange Romania S.A."), SubscriptionFields.service: .text(ServiceKind.mobile),
            SubscriptionFields.phoneNumber: .text("0700 000 000"), SubscriptionFields.startDate: .date(CalendarDay("2025-02-01")),
            SubscriptionFields.minimumMonths: .number(12),
        ], context)
        let addendum = capture(.contract, [
            field(.provider, .text("Orange Romania S.A.")),
            field(.serviceKind, .text(ServiceKind.mobile)),
            field(.phoneNumber, .text("0700 000 000")),
            field(.startDate, day("2026-10-01")),
            field(.minimumMonths, .number(24)),
            field(.minimumPeriodEnd, day("2028-10-01")),
        ])
        let outcome = try await save(addendum, context)
        #expect(outcome.asset?.id == gas.id)
        #expect(gas.value(SubscriptionFields.minimumUntil) == .date(CalendarDay("2028-10-01")))
        #expect(gas.activeObligations.filter { $0.blueprintKey == SubscriptionFields.minimumEndsBlueprint }.map { $0.dueDay } == [CalendarDay("2028-10-01")])
    }

    @Test func aMinimumPeriodThatEndedSetsNoDeadline() async throws {
        let context = try makeContext()
        let old = capture(.contract, [
            field(.provider, .text("Orange Romania S.A.")),
            field(.serviceKind, .text(ServiceKind.mobile)),
            field(.startDate, day("2022-01-10")),
            field(.minimumMonths, .number(24)),
        ])
        let outcome = try await save(old, context)
        let plan = try #require(outcome.asset)
        #expect(plan.activeObligations.isEmpty, "Nothing overdue to chase: it ended in 2024")
    }

    // MARK: Moving

    @Test func anySubscriptionCanMoveBetweenHomesAndAbonamente() throws {
        let context = try makeContext()
        let pipera = try home("Casa Pipera", context)
        let munte = try home("Casa de la munte", context)
        let internet = try subscription("Internet – Digi", under: pipera, [SubscriptionFields.service: .text(ServiceKind.internetTV)], context)
        let phone = try subscription("Telefon – Orange", under: nil, [SubscriptionFields.service: .text(ServiceKind.mobile)], context)
        let all = try assets(context)

        #expect(AssetActions.moveDestinations(for: internet, among: all).map(\.id) == [munte.id])
        #expect(AssetActions.offersStandalone(for: internet))
        #expect(Set(AssetActions.moveDestinations(for: phone, among: all).map(\.id)) == [pipera.id, munte.id], "A phone plan can go under a home")
        #expect(!AssetActions.offersStandalone(for: phone), "It already stands on its own")

        let actions = AssetActions(context: context)
        let receipt = try actions.move(internet, to: .standalone)
        #expect(internet.parent == nil)
        try receipt.undo()
        #expect(internet.parent?.id == pipera.id)
    }

    // MARK: The person's edits

    @Test func theirEditsSurviveAReadingAgainAndDecideTheDeadline() async throws {
        let context = try makeContext()
        let read = capture(.contract, [
            field(.provider, .text("Orange Romania S.A.")),
            field(.serviceKind, .text(ServiceKind.mobile)),
            field(.contractNumber, .text("MOB-000123")),
            field(.startDate, day("2026-02-01")),
            field(.minimumMonths, .number(24)),
            field(.minimumPeriodEnd, day("2028-02-01")),
        ])
        var review = CaptureReview(result: read, assets: [], context: context)
        let months = try #require(review.fields.firstIndex { $0.key == .minimumMonths })
        review.fields[months].confirm(.number(12))
        #expect(review.reminderDay == CalendarDay("2027-02-01"), "The end follows their corrected length")

        // The AI reads it again and says 24: their 12 stays, the AI's is offered beside it.
        let again = CaptureResult(kind: .contract, kindConfidence: 0.9, fields: read.fields + [], suggestions: read.suggestions, reminder: read.reminder,
                                  recognizedText: "", barcodes: [], document: nil, notices: [],
                                  fieldAlternatives: [], readWithCloudModel: true)
        let merged = CaptureReview(result: again, assets: [], context: context).carryingEdits(from: review, assets: [])
        #expect(merged.value(.minimumMonths) == .number(12))
        #expect(merged.fields.first { $0.key == .minimumMonths }?.isEdited == true)
        #expect(merged.reminderDay == CalendarDay("2027-02-01"))

        let outcome = try await filer(context).save(merged)
        let plan = try #require(outcome.asset)
        #expect(plan.value(SubscriptionFields.minimumMonths) == .number(12))
        #expect(plan.value(SubscriptionFields.minimumUntil) == .date(CalendarDay("2027-02-01")))
        #expect(plan.activeObligations.first?.dueDay == CalendarDay("2027-02-01"))
    }
}
