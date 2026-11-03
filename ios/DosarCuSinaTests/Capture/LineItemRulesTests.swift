import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// "Ce s-a făcut": only on documents that list lines, only real lines, and editable in the review.
@Suite("Bill lines")
struct LineItemRulesTests {

    @Test func policiesBillsAndReportsHaveNoLines() {
        for kind: CaptureDocumentKind in [.insurancePolicy, .rcaPolicy, .utilityInvoice, .itpReport, .warrantyCertificate, .medicalResult, .identityCard] {
            #expect(!kind.allows(.lineItems), "\(kind)")
        }
        for kind: CaptureDocumentKind in [.serviceInvoice, .fiscalReceipt, .veterinaryRecord] {
            #expect(kind.allows(.lineItems), "\(kind)")
        }
    }

    @Test func proseAndZeroAmountsAreNotLines() {
        let ron = { (amount: Decimal) in CaptureMoney(amount: amount, currencyCode: "RON") }
        let lines = [
            CaptureLineItem(description: "Plăcuțe frână față", amount: ron(320)),
            CaptureLineItem(description: "În scopul respectării și îndeplinirii obligațiilor legale", amount: ron(0)),
            CaptureLineItem(description: "Soluționarea reclamațiilor și a solicitărilor din partea clienților și a potențialelor litigii, înaintate instanțelor", amount: ron(120)),
            CaptureLineItem(description: "Filtru ulei", amount: nil, componentKey: "engine.oil"),
            CaptureLineItem(description: "123", amount: ron(5)),
        ]
        #expect(CaptureDocumentKind.realLineItems(lines).map(\.description) == ["Plăcuțe frână față", "Filtru ulei"])
    }

    @MainActor
    @Test func linesCanBeCorrectedAddedAndRemovedInTheReview() throws {
        let context = try makeContext()
        var review = CaptureReview(
            result: CaptureResult(kind: .fiscalReceipt, kindConfidence: 0.9, fields: [], suggestions: [], reminder: nil,
                                  recognizedText: "", barcodes: [], document: nil, notices: []),
            assets: [], context: context
        )
        #expect(review.showsLineItems, "A receipt offers lines even when none were read")
        review.lineItems = [CaptureLineItem(description: "Aragaz Exemplu", amount: CaptureMoney(amount: 1899, currencyCode: "RON"))]
        #expect(review.value(.lineItems)?.lineItems?.count == 1)
        #expect(review.fields.first { $0.key == .lineItems }?.tier == .deterministic, "What the person typed is certain")
        review.lineItems = []
        #expect(review.value(.lineItems) == nil)
    }
}
