import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

@Suite("Key facts and purchases")
struct AssetFactsTests {
    @Test("How much did I pay for the cooker, and when did I buy the hood")
    func purchaseFactsWorkForAnyCategoryWithThem() {
        var goods = FieldValues()
        goods["warranty.purchaseDate"] = .date(CalendarDay("2025-06-15"))
        goods["warranty.price"] = .money(Money(1_899))
        goods["warranty.retailer"] = .text("Magazin exemplu")
        goods["warranty.expiry"] = .date(CalendarDay("2027-06-15"))
        let info = AssetFacts.purchase(goods, template: BuiltInTemplates.warranty)
        #expect(info.date == CalendarDay("2025-06-15"))
        #expect(info.price == Money(1_899))
        #expect(info.retailer == "Magazin exemplu")
        #expect(info.isUnderWarranty(on: CalendarDay("2026-11-02")) == true)

        var bike = FieldValues()
        bike["bike.purchasePrice"] = .money(Money(3_200))
        #expect(AssetFacts.purchase(bike, template: BuiltInTemplates.bike).price == Money(3_200))
        #expect(AssetFacts.purchase(FieldValues(), template: BuiltInTemplates.vehicle).isEmpty)
    }

    @Test func keyFactsAreOneTapAway() throws {
        var car = FieldValues()
        car["vehicle.plate"] = .text("B-123-ABC")
        car["vehicle.vin"] = .text("WVWZZZ1KZ8W123456")
        car["vehicle.policyNumber"] = .text("POL-000001")
        car["vehicle.claimsPhone"] = .text("+40210000000")
        let facts = AssetFacts.keyFacts(car, template: BuiltInTemplates.vehicle)
        #expect(facts.map(\.field.key) == ["vehicle.plate", "vehicle.vin", "vehicle.policyNumber", "vehicle.claimsPhone"])
        #expect(facts.last?.isCallable == true)

        var passport = FieldValues()
        passport["document.number"] = .text("050000000")
        passport["document.expiry"] = .date(CalendarDay("2030-01-01"))
        #expect(AssetFacts.keyFacts(passport, template: BuiltInTemplates.documents).first?.field.role == .documentNumber)
        #expect(AssetFacts.expiry(passport, template: BuiltInTemplates.documents) == CalendarDay("2030-01-01"))
    }

    @Test func everyMainstayHasItsKeyFacts() {
        for template in [BuiltInTemplates.vehicle, BuiltInTemplates.home, BuiltInTemplates.documents, BuiltInTemplates.pet] {
            #expect(!template.keyFactFields.isEmpty, "\(template.key) shows key facts")
        }
        #expect(BuiltInTemplates.documents.field(withRole: .holder) != nil)
        #expect(BuiltInTemplates.documents.field(withRole: .issuer) != nil)
        #expect(BuiltInTemplates.vehicle.field(withRole: .purchasePrice) != nil)
    }
}

@MainActor
@Suite("Documents")
struct DocumentTests {
    @Test func newPolicySupersedesTheOldOneWithoutLosingIt() throws {
        let context = try makeContext()
        let car = Asset(name: "Mașina", templateKey: BuiltInTemplates.Key.vehicle)
        context.insert(car)
        try context.save()
        let documents = AttachmentActions(context: context, calendar: .bucharest)
        let old = try documents.file(DocumentDraft(title: "RCA 2025", fileName: "rca-2025.pdf", kind: .policy, contentType: "com.adobe.pdf", originalData: Data("2025".utf8)), asset: car)
        let new = try documents.file(DocumentDraft(title: "RCA 2026", fileName: "rca-2026.pdf", kind: .policy, contentType: "com.adobe.pdf", originalData: Data("2026".utf8)), asset: car)
        try documents.supersede(old, with: new)
        #expect(old.isArchived)
        #expect(old.supersededBy?.id == new.id)
        #expect(new.supersedes?.map(\.id) == [old.id])
        #expect(car.attachments?.count == 2, "Nothing is thrown away")
    }

    @Test func theSameDocumentIsRecognized() throws {
        let context = try makeContext()
        let documents = AttachmentActions(context: context)
        let draft = DocumentDraft(fileName: "scan.heic", kind: .receipt, pageImages: [Data([1, 2, 3]), Data([4])])
        #expect(try documents.existing(matching: draft) == nil)
        let filed = try documents.file(draft)
        #expect(filed.sha256 == draft.sha256)
        #expect(try documents.existing(matching: draft)?.id == filed.id)
        #expect(filed.orderedPages.count == 2)
    }

    @Test func documentsFiledOnAJobBelongToTheAsset() throws {
        let context = try makeContext()
        let car = Asset(name: "Mașina", templateKey: BuiltInTemplates.Key.vehicle)
        context.insert(car)
        try context.save()
        let entry = try HistoryActions(context: context).record(on: car, kind: .repair, title: "Frâne")
        let invoice = try AttachmentActions(context: context).file(DocumentDraft(fileName: "factura.pdf", kind: .invoice, originalData: Data([1])), historyEntry: entry)
        #expect(invoice.asset?.id == car.id)
        #expect(entry.attachments?.map(\.id) == [invoice.id])
    }
}
