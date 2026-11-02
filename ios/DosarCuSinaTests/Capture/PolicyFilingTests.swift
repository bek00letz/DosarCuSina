import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Insurance policies: each cover in its own fields, policies never taken for bills,
/// and a corrected kind bringing its deadline along.
@Suite("Policies")
@MainActor
struct PolicyFilingTests {

    private func car(_ context: ModelContext) throws -> (Asset, TemplateDefinition) {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let car = try AssetActions(context: context).create(name: "VW Golf", template: template, values: FieldValues())
        return (car, template.definition)
    }

    @Test func aCascoPolicyFillsTheCascoFieldsNotRCAs() throws {
        let context = try makeContext()
        let (_, vehicle) = try car(context)
        #expect(CaptureMapping.fieldKey(for: .policyNumber, kind: .insurancePolicy, in: vehicle, coverage: "CASCO") == "vehicle.cascoPolicyNumber")
        #expect(CaptureMapping.fieldKey(for: .claimsPhone, kind: .insurancePolicy, in: vehicle, coverage: "CASCO") == "vehicle.cascoClaimsPhone")
        #expect(CaptureMapping.fieldKey(for: .provider, kind: .insurancePolicy, in: vehicle, coverage: "CASCO") == "vehicle.cascoInsurer")
        #expect(CaptureMapping.fieldKey(for: .policyNumber, kind: .rcaPolicy, in: vehicle) == "vehicle.policyNumber")
        #expect(CaptureMapping.fieldKey(for: .policyNumber, kind: .insurancePolicy, in: vehicle, coverage: "Facultativă") == nil, "An unknown cover never fills RCA's fields")
    }

    @Test func aPolicyMentioningDigitalIsNotADigiBill() {
        let analysis = CaptureAnalyzer().analyze(text: """
        POLIȚĂ DE ASIGURARE OBLIGATORIE RCA
        Răspundere civilă auto
        Asigurător: Exemplu Asigurări S.A., România
        Semnătură digitală
        Nr. înmatriculare B 123 ABC
        Valabilă de la 01.11.2026 până la 31.10.2027
        """, referenceDate: Date(timeIntervalSince1970: 1_793_577_600))
        #expect(analysis.kind == .rcaPolicy)
        #expect(RomanianUtilityParser.shared.detectProvider(in: "SEMNATURA DIGITALA ROMANIA") == .general)
        #expect(RomanianUtilityParser.shared.detectProvider(in: "DIGI ROMANIA S.A. FACTURA") == .digi)
    }

    @Test func correctingTheKindBringsItsDeadline() throws {
        let context = try makeContext()
        let (car, _) = try car(context)
        let expiry = try #require(CaptureDay(year: 2027, month: 10, day: 31))
        var review = CaptureReview(
            result: CaptureResult(kind: .utilityInvoice, kindConfidence: 0.95, fields: [
                CaptureField(key: .expiryDate, value: .day(expiry), confidence: 0.8, tier: .heuristic),
                CaptureField(key: .licensePlate, value: .text("B 123 ABC"), confidence: 0.8, tier: .heuristic),
            ], suggestions: [], reminder: nil, recognizedText: "", barcodes: [], documentID: nil, notices: []),
            assets: [car], context: context
        )
        #expect(review.blueprintKey == nil)
        review.kind = .rcaPolicy
        review.kindChanged(assets: [car])
        #expect(review.blueprintKey == "vehicle.rca")
        #expect(!review.remindsToPay, "Not a bill any more")
        #expect(review.reminderDay == CaptureMapping.calendarDay(expiry))
    }
}
