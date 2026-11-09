import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A policy number kept with only its series is completed from the filed policy's text
/// when the rule can read the whole value there, and only listed otherwise; it asks
/// first, and runs twice without changing anything more. Every value is a placeholder.
@MainActor
@Suite("Repair: policy numbers without their number")
struct PolicyNumberPartsRepairTests {

    private func repairs(_ context: ModelContext, ledger: DataRepairLedger? = nil) -> DataRepairs {
        DataRepairs(context: context, calendar: .bucharest,
                    ledger: ledger ?? DataRepairLedger(defaults: UserDefaults(suiteName: "policy-parts-\(UUID().uuidString)")!))
    }

    private func car(_ context: ModelContext, rca: String?, casco: String? = nil) throws -> Asset {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        var values = FieldValues()
        values[VehicleFields.policyNumber] = rca.map(FieldValue.text)
        values[VehicleFields.cascoPolicyNumber] = casco.map(FieldValue.text)
        return try AssetActions(context: context).create(name: "VW Golf 2018", template: template, values: values)
    }

    private func file(_ text: String, on car: Asset, in context: ModelContext) throws {
        let policy = Attachment(fileName: "rca.pdf", contentType: "com.adobe.pdf", data: Data("x".utf8), kind: .policy)
        policy.title = "Poliță RCA"
        policy.extractedText = text
        context.insert(policy)
        policy.asset = car
        try UnitOfWork.save(context)
    }

    @Test("Only a series alone counts as missing its number", arguments: [
        ("RO/00/X00/XX", true), ("RO / 00 / X00 / XX", true),
        ("RO/00/X00/XX 123456789", false), ("123456789", false), ("CAS-000123", false), ("RO/00/X/000000000", false),
    ])
    func incomplete(value: String, missing: Bool) {
        #expect(PolicyNumberPartsStep.isMissingItsNumber(value) == missing, "\(value)")
    }

    @Test("Completed from the filed policy, asking first, and idempotent")
    func completedFromTheFiledPolicy() throws {
        let context = try makeContext()
        let golf = try car(context, rca: "RO/00/X00/XX")
        try file(RCAPages.certificate + "\n" + RCAPages.contract, on: golf, in: context)

        let list = repairs(context)
        let found = try list.detect().filter { $0.step == .policyNumberParts }
        try #require(found.count == 1)
        #expect(found[0].isFixable)
        #expect(found[0].message.contains("RO/00/X00/XX 123456789"))
        #expect(golf.value(VehicleFields.policyNumber) == .text("RO/00/X00/XX"), "Nothing changes before the owner says so")

        try list.apply(found)
        #expect(golf.value(VehicleFields.policyNumber) == .text("RO/00/X00/XX 123456789"))
        #expect(try list.detect().filter { $0.step == .policyNumberParts }.isEmpty, "Found nothing once applied")
        try list.apply(found)
        #expect(golf.value(VehicleFields.policyNumber) == .text("RO/00/X00/XX 123456789"))
        #expect(context.hasChanges == false, "A second apply changes nothing")
    }

    @Test("A different series on the filed policy is never used")
    func otherSeries() throws {
        let context = try makeContext()
        let golf = try car(context, rca: "RO/11/Y11/YY")
        try file(RCAPages.contract, on: golf, in: context)
        let found = try repairs(context).detect().filter { $0.step == .policyNumberParts }
        #expect(found.count == 1)
        #expect(found.first?.isFixable == false)
    }

    @Test("Without the policy's text it is only listed, saying to read it again, and changes nothing")
    func onlyListed() throws {
        let context = try makeContext()
        let golf = try car(context, rca: nil, casco: "RO/00/X00/XX")
        let list = repairs(context)
        let found = try list.detect().filter { $0.step == .policyNumberParts }
        try #require(found.count == 1)
        #expect(!found[0].isFixable)
        #expect(found[0].message.contains("Citește polița din nou"))
        try list.apply(found)
        #expect(golf.value(VehicleFields.cascoPolicyNumber) == .text("RO/00/X00/XX"))
        #expect(context.hasChanges == false)
        list.dismiss(found)
        #expect(try list.detect().filter { $0.step == .policyNumberParts }.isEmpty, "Put away once understood")
    }

    @Test("Whole numbers and examples are left alone")
    func leftAlone() throws {
        let context = try makeContext()
        _ = try car(context, rca: "RO/00/X00/XX 123456789", casco: "CAS-000123")
        #expect(try repairs(context).detect().filter { $0.step == .policyNumberParts }.isEmpty)
    }

    @Test("The step comes after the ones before it, with its own stored id")
    func registered() {
        let ids = DataRepairs.steps.map { type(of: $0).id }
        #expect(ids.firstIndex(of: .policyNumberParts) == ids.firstIndex(of: .unitKeys).map { $0 + 1 })
        #expect(DataRepairStepID.policyNumberParts.rawValue == "policy-number-parts")
    }
}
