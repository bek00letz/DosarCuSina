import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Another photo or PDF of a visit's invoice, filed through the visit form, is the same
/// invoice (`PaperIdentity`, as for a bill): it updates the visit it was filed with, becomes
/// its newer copy and leaves the first one archived beside it. Placeholder data only.
@Suite("The same invoice through the visit form")
@MainActor
struct InvoiceFiledAgainTests {

    private let today = "2026-06-01"

    /// A car with 45.724 km read on 10 January.
    private func car(_ context: ModelContext) throws -> Asset {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        var values = FieldValues()
        values[VehicleFields.odometer] = .number(45_724)
        return try AssetActions(context: context, calendar: .bucharest, now: { noon("2026-01-10") })
            .create(name: "VW Golf 2018", template: template, values: values)
    }

    private func filer(_ context: ModelContext, store: CaptureDocumentStore) -> CaptureFiler {
        CaptureFiler(context: context, store: store, calendar: .bucharest, now: { noon(today) })
    }

    private func photo(_ store: CaptureDocumentStore, seed: UInt8) async throws -> CapturedDocumentRef {
        try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 900, height: 640, seed: seed)], kind: .serviceInvoice)).ref
    }

    private func visit(on car: Asset, number: String?, cost: Decimal? = 480, odometer: Double? = 48_000,
                       firm: String = "Service Exemplu SRL", day: String = "2026-05-30", document: CapturedDocumentRef?) -> CaptureFiler.Visit {
        CaptureFiler.Visit(asset: car, kind: .maintenance, occurredAt: noon(day), checklist: [],
                           extraItems: [LineItemDraft(name: "Ulei și filtru")], totalCost: cost.map { Money($0) }, odometer: odometer,
                           odometerSource: .document, provider: .named(firm, trade: .mechanic), document: document,
                           documentTitle: "Factură service", reference: number)
    }

    private func visits(on car: Asset) -> [HistoryEntry] {
        PaperIdentity.visits(of: car)
    }

    @Test func anotherPhotoWithTheSameNumberUpdatesItsVisit() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let store = CaptureDocumentStore()
        let first = try await filer(context, store: store).file(.visit(visit(on: golf, number: "SRV 0000001", document: try await photo(store, seed: 80))))
        let entry = try #require(first.visit)
        let older = try #require(first.attachment)
        #expect(entry.reference == "SRV 0000001", "The invoice's number is the visit's own")
        let before = try UndoReceiptTests.database(context)

        // The PDF the service sent later, its number written another way and the total read right.
        let again = visit(on: golf, number: "srv-0000001", cost: 520, odometer: nil, document: try await photo(store, seed: 81))
        let filed = try #require(again.filedBefore(keptDocumentID: nil, calendar: .bucharest))
        #expect(filed.entry.id == entry.id)
        #expect(filed.paper.match == .number)
        #expect(filed.paper.section == golf.name)
        #expect(!filed.paper.mayBeAnother, "A number is certain")

        let second = try await filer(context, store: store).file(.visit(again))
        #expect(visits(on: golf).map(\.id) == [entry.id], "One visit")
        #expect(second.visit?.id == entry.id)
        #expect(entry.totalCost == Money(520), "What was read now")
        #expect(entry.reference == "srv-0000001")
        #expect(entry.metricReading == 48_000, "The kilometres the new photo didn't give stay")
        #expect(golf.measurements?.map(\.value).sorted() == [45_724, 48_000], "Its reading, once")
        #expect(entry.items?.map(\.name) == ["Ulei și filtru"], "Its lines, once")
        #expect(golf.providers?.count == 1, "The same firm")
        let newer = try #require(second.attachment)
        #expect(newer.id != older.id)
        #expect(newer.historyEntry?.id == entry.id && !newer.isArchived, "The new copy is current")
        #expect(older.historyEntry?.id == entry.id && older.isArchived && older.supersededBy?.id == newer.id,
                "The first copy is archived beside it, never lost")

        try #require(second.receipt).undo()
        let left = UndoReceiptTests.differences(before, try UndoReceiptTests.database(context))
        #expect(left.isEmpty, "Still different after undo: \(left.map(\.description))")
    }

    @Test func withoutANumberTheDayTotalAndFirmDecide() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let store = CaptureDocumentStore()
        let first = try await filer(context, store: store).file(.visit(visit(on: golf, number: nil, document: try await photo(store, seed: 82))))
        let entry = try #require(first.visit)

        let same = visit(on: golf, number: "SRV 0000001", firm: "SERVICE EXEMPLU S.R.L.", document: try await photo(store, seed: 83))
        let filed = try #require(same.filedBefore(keptDocumentID: nil, calendar: .bucharest))
        #expect(filed.paper.match == .dayAndTotal)
        #expect(filed.paper.mayBeAnother, "The form offers „E altă factură”")

        var another = visit(on: golf, number: nil, document: try await photo(store, seed: 91))
        #expect(another.filedBefore(keptDocumentID: nil, calendar: .bucharest)?.paper.match == .dayAndTotal)
        another.isAnotherInvoice = true
        #expect(another.filedBefore(keptDocumentID: nil, calendar: .bucharest)?.paper == nil, "„E altă factură”")

        let otherFirm = visit(on: golf, number: nil, firm: "Vulcanizare Exemplu SRL", document: try await photo(store, seed: 84))
        #expect(otherFirm.filedBefore(keptDocumentID: nil, calendar: .bucharest)?.paper == nil, "Another firm: another invoice")
        let otherDay = visit(on: golf, number: nil, day: "2026-05-31", document: try await photo(store, seed: 85))
        #expect(otherDay.filedBefore(keptDocumentID: nil, calendar: .bucharest)?.paper == nil, "Another day: another invoice")

        _ = try await filer(context, store: store).file(.visit(same))
        #expect(visits(on: golf).map(\.id) == [entry.id])
        #expect(entry.reference == "SRV 0000001", "It takes the number read now")
        _ = try await filer(context, store: store).file(.visit(another))
        #expect(visits(on: golf).count == 2, "Said to be another invoice: a visit of its own")
    }

    @Test func anotherNumberIsAnotherVisitEvenOnTheSameDay() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let store = CaptureDocumentStore()
        _ = try await filer(context, store: store).file(.visit(visit(on: golf, number: "SRV 0000001", document: try await photo(store, seed: 86))))
        let other = visit(on: golf, number: "SRV 0000002", odometer: 48_000, document: try await photo(store, seed: 87))
        #expect(other.filedBefore(keptDocumentID: nil, calendar: .bucharest)?.paper == nil)
        _ = try await filer(context, store: store).file(.visit(other))
        #expect(visits(on: golf).count == 2)
    }

    @Test func aVisitTypedWithoutAnInvoiceIsNeverTakenForOne() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let store = CaptureDocumentStore()
        _ = try await filer(context, store: store).file(.visit(visit(on: golf, number: nil, document: try await photo(store, seed: 88))))
        let typed = visit(on: golf, number: nil, odometer: 48_000, document: nil)
        #expect(typed.filedBefore(keptDocumentID: nil, calendar: .bucharest)?.paper == nil, "No paper to compare")
        _ = try await filer(context, store: store).file(.visit(typed))
        #expect(visits(on: golf).count == 2)
    }

    @Test func theSameDocumentStillFindsItsVisit() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let store = CaptureDocumentStore()
        let first = try await filer(context, store: store).file(.visit(visit(on: golf, number: "SRV 0000001", document: try await photo(store, seed: 89))))
        let kept = try #require(first.attachment)
        let again = visit(on: golf, number: "SRV 0000009", cost: 1, document: .kept(attachmentID: kept.id))
        let filed = try #require(again.filedBefore(keptDocumentID: kept.id, calendar: .bucharest))
        #expect(filed.paper.match == .sameDocument, "Its own link, whatever was read")
        _ = try await filer(context, store: store).file(.visit(again))
        #expect(visits(on: golf).count == 1)
        #expect(!kept.isArchived, "The same copy: nothing to archive")
    }

    @Test func aBillIsNeverTakenForAVisit() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let bill = try HistoryActions(context: context, now: { noon(today) })
            .record(on: golf, kind: .payment, title: "Factură", occurredAt: noon("2026-05-30"), totalCost: Money(480), reference: "SRV 0000001")
        let store = CaptureDocumentStore()
        let invoice = visit(on: golf, number: "SRV 0000001", document: try await photo(store, seed: 90))
        #expect(invoice.filedBefore(keptDocumentID: nil, calendar: .bucharest)?.paper == nil)
        #expect(!visits(on: golf).contains { $0.id == bill.id })
    }

    @Test func theVisitFormReadsTheInvoiceNumber() {
        var draft = VisitDraft(date: noon(today))
        let fields = [
            CaptureField(key: .invoiceNumber, value: .text("SRV 0000001"), confidence: 0.9, sourceText: nil, tier: .heuristic),
            CaptureField(key: .total, value: .money(CaptureMoney(amount: 480, currencyCode: "RON")), confidence: 0.9, sourceText: nil, tier: .heuristic),
        ]
        let result = CaptureResult(kind: .serviceInvoice, kindConfidence: 0.9, fields: fields, suggestions: [], reminder: nil,
                                   recognizedText: "", barcodes: [], document: .kept(attachmentID: UUID()), notices: [])
        draft.isAnotherInvoice = true
        draft.apply(result, components: [])
        #expect(draft.reference == "SRV 0000001")
        #expect(!draft.isAnotherInvoice, "Another invoice asks again")
    }
}
