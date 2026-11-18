import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// The sum a policy insures for is one of its deadline's own facts (`BlueprintFactRole.insuredSum`),
/// declared once for every policy that states one: a home's PAD and its optional policy, and a
/// car's CASCO. An RCA's limits are set by law, so it keeps none. Capture fills it like the other
/// facts, a new policy replaces it (or leaves none when it prints none), and the deadline's page shows
/// it as money.
@MainActor
@Suite("A policy's insured sum")
struct InsuredSumTests {
    private func facts(_ template: TemplateDefinition, _ key: String) throws -> BlueprintFacts {
        try #require(template.blueprints.first { $0.key == key }?.facts)
    }

    @Test("PAD, the home's optional policy and CASCO each keep their own sum, in a money field; an RCA keeps none")
    func declaredOnce() throws {
        let kept: [(TemplateDefinition, String, String)] = [
            (BuiltInTemplates.home, BuiltInBlueprints.homePAD, HomeFields.insuredSum),
            (BuiltInTemplates.home, BuiltInBlueprints.homeInsurance, HomeFields.optionalInsuredSum),
            (BuiltInTemplates.vehicle, BuiltInBlueprints.vehicleCASCO, VehicleFields.cascoInsuredSum),
        ]
        for (template, blueprint, field) in kept {
            #expect(try facts(template, blueprint).insuredSum == field, "\(blueprint)")
            #expect(template.field(field)?.type == .money, "\(field) is money")
        }
        #expect(try facts(BuiltInTemplates.vehicle, BuiltInBlueprints.vehicleRCA).insuredSum == nil, "An RCA's limits are the law's")
        #expect(CaptureMapping.factRole(of: .insuredSum) == .insuredSum)
    }

    // MARK: Filing

    private func policy(cover: String?, kind: CaptureDocumentKind = .insurancePolicy, sum: Decimal?, number: String? = "RO/00/X00/XX 000000001",
                        endsInDays days: Int = 375) -> CaptureResult {
        let expiry = CalendarDay(Calendar.current.date(byAdding: .day, value: days, to: Date())!)
        var fields = [CaptureField(key: .expiryDate, value: .day(expiry), confidence: 0.9, tier: .heuristic)]
        if let number { fields.append(CaptureField(key: .policyNumber, value: .text(number), confidence: 0.9, tier: .heuristic)) }
        if let cover { fields.append(CaptureField(key: .coverageType, value: .text(cover), confidence: 0.9, tier: .heuristic)) }
        if let sum { fields.append(CaptureField(key: .insuredSum, value: .money(Money(sum)), confidence: 0.9, tier: .heuristic)) }
        return CaptureResult(kind: kind, kindConfidence: 0.95, fields: fields, suggestions: [], reminder: nil,
                             recognizedText: "POLIȚĂ DE ASIGURARE", barcodes: [], document: nil, notices: [])
    }

    private func section(_ key: String, name: String, deadlines: [String], values: FieldValues = FieldValues(), in context: ModelContext) throws -> (Asset, [Obligation]) {
        let template = try #require(try TemplateStore(context: context).template(forKey: key))
        let asset = try AssetActions(context: context).create(name: name, template: template, values: values)
        let obligations = try deadlines.map { blueprintKey in
            let blueprint = try #require(template.definition.blueprints.first { $0.key == blueprintKey })
            return try ObligationActions(context: context).create(from: blueprint, for: asset, firstDue: CalendarDay(Date()).adding(days: 20, calendar: .current))
        }
        return (asset, obligations)
    }

    private func save(_ result: CaptureResult, into asset: Asset, in context: ModelContext) async throws {
        var review = CaptureReview(result: result, assets: [asset], context: context)
        review.destination = .asset(asset.id)
        _ = try await CaptureFiler(context: context, store: CaptureDocumentStore()).save(review)
    }

    @Test("A home's policy keeps its sum on its own deadline's field, and the page shows it as money after the number")
    func aHomePolicyKeepsItsSum() async throws {
        let context = try makeContext()
        let (home, deadlines) = try section(BuiltInTemplates.Key.home, name: "Apartament",
                                            deadlines: [BuiltInBlueprints.homePAD, BuiltInBlueprints.homeInsurance], in: context)
        try await save(policy(cover: InsuranceCover.pad, sum: 50_000), into: home, in: context)
        #expect(home.value(HomeFields.insuredSum) == .money(Money(50_000)))
        #expect(home.value(HomeFields.optionalInsuredSum) == nil, "PAD's sum is never the optional policy's")

        try await save(policy(cover: InsuranceCover.home, sum: 250_000, number: "RO/00/X00/XX 000000002"), into: home, in: context)
        #expect(home.value(HomeFields.optionalInsuredSum) == .money(Money(250_000)))
        #expect(home.value(HomeFields.insuredSum) == .money(Money(50_000)))

        let template = try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.home)?.definition
        let pad = try #require(deadlines.first)
        #expect(DeadlineFacts.of(pad, template: template).insuredSum == Money(50_000))
        let rows = DeadlinePageFacts.of(pad, template: template, in: context).policyRows
        let number = try #require(rows.firstIndex { if case .policyNumber = $0 { true } else { false } }, "The policy's number first")
        #expect(number == 0)
        try #require(rows.indices.contains(number + 1), "The sum is listed")
        #expect(rows[number + 1] == .insuredSum(Money(50_000)), "Right after the policy's number")
    }

    @Test("A new policy replaces the sum, from the review and from „Am rezolvat”")
    func aNewPolicyReplacesIt() async throws {
        let context = try makeContext()
        var values = FieldValues()
        values[VehicleFields.cascoInsuredSum] = .money(Money(60_000))
        let (car, deadlines) = try section(BuiltInTemplates.Key.vehicle, name: "VW Golf 2018",
                                           deadlines: [BuiltInBlueprints.vehicleCASCO, BuiltInBlueprints.vehicleRCA], values: values, in: context)
        let casco = try #require(deadlines.first)
        _ = try await CaptureFiler(context: context).file(.completion(.init(
            obligation: casco, date: Date(), cost: nil, document: policy(cover: InsuranceCover.casco, sum: 55_000))))
        #expect(car.value(VehicleFields.cascoInsuredSum) == .money(Money(55_000)), "„Am rezolvat” with the new CASCO updates it")

        try await save(policy(cover: InsuranceCover.casco, sum: 52_000, number: "RO/00/X00/XX 000000003"), into: car, in: context)
        #expect(car.value(VehicleFields.cascoInsuredSum) == .money(Money(52_000)), "So does a newer policy from the review")
    }

    @Test("What describes one policy is declared once: its number and its sum; who issued it, its claims line and who it insures carry over")
    func whatBelongsToThePolicy() {
        #expect(BlueprintFactRole.allCases.filter(\.belongsToThePolicy) == [.policyNumber, .insuredSum])
    }

    @Test("A newer policy that prints no sum leaves none of the earlier policy's; its claims line and insurer stay")
    func aNewerPolicyLeavesNoneOfTheEarlierSum() async throws {
        let context = try makeContext()
        var values = FieldValues()
        values[VehicleFields.cascoInsuredSum] = .money(Money(60_000))
        values[VehicleFields.cascoPolicyNumber] = .text("RO/00/X00/XX 000000001")
        values[VehicleFields.cascoInsurer] = .text("Asigurător Exemplu S.A.")
        values[VehicleFields.cascoClaimsPhone] = .text("0700000002")
        let (car, deadlines) = try section(BuiltInTemplates.Key.vehicle, name: "VW Golf 2018", deadlines: [BuiltInBlueprints.vehicleCASCO],
                                           values: values, in: context)
        let casco = try #require(deadlines.first)
        _ = try await CaptureFiler(context: context).file(.completion(.init(
            obligation: casco, date: Date(), cost: nil, document: policy(cover: InsuranceCover.casco, sum: nil, number: "RO/00/X00/XX 000000002"))))
        #expect(car.value(VehicleFields.cascoPolicyNumber) == .text("RO/00/X00/XX 000000002"))
        #expect(car.value(VehicleFields.cascoInsuredSum) == nil, "The earlier policy's sum never passes for the new one's")
        #expect(car.value(VehicleFields.cascoClaimsPhone) == .text("0700000002"), "The claims line carries over")
        #expect(car.value(VehicleFields.cascoInsurer) == .text("Asigurător Exemplu S.A."), "So does who issued it")
    }

    @Test("A renewing policy that prints no number leaves none of the earlier number; the same policy read again keeps what it doesn't print")
    func theSamePolicyKeepsItsFacts() async throws {
        let context = try makeContext()
        var values = FieldValues()
        values[HomeFields.insuredSum] = .money(Money(50_000))
        values[HomeFields.policyNumber] = .text("RO/00/X00/XX 000000001")
        let (home, _) = try section(BuiltInTemplates.Key.home, name: "Apartament", deadlines: [BuiltInBlueprints.homePAD], values: values, in: context)

        try await save(policy(cover: InsuranceCover.pad, sum: nil, number: "RO 00 X00 XX 000000001"), into: home, in: context)
        #expect(home.value(HomeFields.insuredSum) == .money(Money(50_000)), "The same number, written another way: the same policy")

        try await save(policy(cover: InsuranceCover.pad, sum: nil, number: nil, endsInDays: 10), into: home, in: context)
        #expect(home.value(HomeFields.policyNumber) == .text("RO/00/X00/XX 000000001"), "An older paper renews nothing: nothing goes")
        #expect(home.value(HomeFields.insuredSum) == .money(Money(50_000)))

        try await save(policy(cover: InsuranceCover.pad, sum: 52_000, number: nil, endsInDays: 740), into: home, in: context)
        #expect(home.value(HomeFields.insuredSum) == .money(Money(52_000)))
        #expect(home.value(HomeFields.policyNumber) == nil, "A renewing policy with no number read leaves none of the earlier one's")
    }

    @Test("An RCA keeps no sum, even when its paper prints one")
    func anRCAKeepsNone() async throws {
        let context = try makeContext()
        let (car, deadlines) = try section(BuiltInTemplates.Key.vehicle, name: "VW Golf 2018", deadlines: [BuiltInBlueprints.vehicleRCA], in: context)
        let rca = try #require(deadlines.first)
        _ = try await CaptureFiler(context: context).file(.completion(.init(
            obligation: rca, date: Date(), cost: nil, document: policy(cover: nil, kind: .rcaPolicy, sum: 1_000_000))))
        #expect(car.value(VehicleFields.cascoInsuredSum) == nil, "Never CASCO's")
        #expect(!car.values.contains { _, value in value.moneyValue == Money(1_000_000) })
        let template = try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle)?.definition
        #expect(DeadlineFacts.of(rca, template: template).insuredSum == nil)
    }
}
