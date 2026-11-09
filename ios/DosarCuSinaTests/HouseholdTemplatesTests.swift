import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

@MainActor
@Suite("Purchases, subscriptions, tenancies and members")
struct HouseholdTemplatesTests {
    private func template(_ key: String, in context: ModelContext) throws -> CategoryTemplate {
        try #require(try TemplateStore(context: context).template(forKey: key))
    }

    @Test func purchasesGetTheLegalGuaranteeByDefault() throws {
        let context = try makeContext()
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        var values = FieldValues()
        values["purchase.date"] = .date(CalendarDay("2026-03-10"))
        values["purchase.price"] = .money(Money(1_350))
        let cooker = try actions.create(name: "Aragaz", template: try template(BuiltInTemplates.Key.purchase, in: context), values: values,
                                        obligations: actions.plannedObligations(for: try template(BuiltInTemplates.Key.purchase, in: context), values: values))
        #expect(cooker.value("purchase.warrantyMonths") == .number(24))
        #expect(cooker.value("purchase.warrantyUntil") == .date(CalendarDay("2028-03-10")))
        let ends = try #require(cooker.activeObligations.first)
        #expect(ends.dueDay(in: .bucharest) == CalendarDay("2028-03-10"))
        #expect(ends.reminders.leadDays == [30])
        #expect(!ends.followUpAfterLapse)

        // Editing the months moves the end date; an end date typed by hand stays.
        var edited = cooker.values
        edited["purchase.warrantyMonths"] = .number(36)
        try actions.update(cooker, name: "Aragaz", values: edited, notes: nil)
        #expect(cooker.value("purchase.warrantyUntil") == .date(CalendarDay("2029-03-10")))
        var manual = cooker.values
        manual["purchase.warrantyUntil"] = .date(CalendarDay("2030-01-01"))
        try actions.update(cooker, name: "Aragaz", values: manual, notes: nil)
        #expect(cooker.value("purchase.warrantyUntil") == .date(CalendarDay("2030-01-01")))
    }

    @Test func subscriptionsRemindOnlyAboutYearlyRenewalsAndContractEnds() throws {
        let context = try makeContext()
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        let subscription = try template(BuiltInTemplates.Key.subscription, in: context)
        var monthly = FieldValues()
        monthly["subscription.cycle"] = .text(BillingCycle.monthly)
        monthly["subscription.renewalDate"] = .date(CalendarDay("2026-12-01"))
        #expect(!actions.plannedObligations(for: subscription, values: monthly).contains { $0.blueprint.key == "subscription.renewal" })
        var yearly = monthly
        yearly["subscription.cycle"] = .text(BillingCycle.yearly)
        let planned = actions.plannedObligations(for: subscription, values: yearly)
        #expect(planned.first { $0.blueprint.key == "subscription.renewal" }?.firstDue == CalendarDay("2026-12-01"))
    }

    @Test func monthlyEquivalentStaysPerCurrency() {
        var internet = FieldValues()
        internet["subscription.price"] = .money(Money(45))
        internet["subscription.cycle"] = .text(BillingCycle.monthly)
        var storage = FieldValues()
        storage["subscription.price"] = .money(Money(120, currency: "EUR"))
        storage["subscription.cycle"] = .text(BillingCycle.yearly)
        var insurance = FieldValues()
        insurance["subscription.price"] = .money(Money(90))
        insurance["subscription.cycle"] = .text("Trimestrial")
        let total = SubscriptionMath.monthlyTotal([internet, storage, insurance])
        #expect(total.amount(in: "RON") == 75)
        #expect(total.amount(in: "EUR") == 10)
    }

    @Test("While a tenancy exists there is exactly one rental income declaration")
    func rentalDeclarationFollowsTenancies() throws {
        let context = try makeContext()
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        let home = try actions.create(name: "Garsonieră", template: try template(BuiltInTemplates.Key.home, in: context), values: FieldValues())
        let tenancyTemplate = try template(BuiltInTemplates.Key.tenancy, in: context)
        var lease = FieldValues()
        lease["tenancy.end"] = .date(CalendarDay("2027-06-30"))

        func declarations() throws -> [Obligation] {
            let key = HouseholdRules.rentalDeclarationKey
            return try context.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.blueprintKey == key }))
        }

        #expect(try declarations().isEmpty)
        let first = try actions.create(name: "Chiriaș 1", template: tenancyTemplate, values: lease, parent: home)
        let second = try actions.create(name: "Chiriaș 2", template: tenancyTemplate, values: lease, parent: home)
        let declaration = try #require(try declarations().first)
        #expect(try declarations().count == 1)
        #expect(declaration.asset == nil, "It belongs to the household, not to one property")
        #expect(declaration.dueDay(in: .bucharest) == CalendarDay("2027-05-25"))
        #expect(declaration.reminders == ReminderProfile(leadDays: [30, 7], consequence: .legal, followUpAfterLapse: true))

        try actions.delete(first)
        #expect(try declarations().count == 1)
        try actions.delete(second)
        #expect(try declarations().isEmpty)
    }

    @Test func documentsAreFiledUnderTheirHolder() throws {
        let context = try makeContext()
        try ExampleDataService(context: context, calendar: .bucharest, now: { noon("2026-11-02") }).loadExamples()
        let me = try #require(try context.fetch(FetchDescriptor<Asset>()).first { $0.templateKey == BuiltInTemplates.Key.member })
        let documents = (me.children ?? []).filter { $0.templateKey == BuiltInTemplates.Key.documents }
        #expect(Set(documents.map(\.name)) == ["Pașaport", "Carte de identitate"])
        #expect(BuiltInTemplates.member.allFields.map(\.key) == [MemberFields.bonusMalus],
                "Members are a name and their bonus-malus class; their documents are filed under them, never as fields")

        let loose = try AssetActions(context: context).create(name: "Permis", template: try template(BuiltInTemplates.Key.documents, in: context), values: FieldValues())
        let groups = try DocumentHolders.groups(in: context)
        #expect(groups.first?.holder?.id == me.id)
        #expect(groups.first?.documents.map(\.name) == ["Pașaport", "Carte de identitate"], "Soonest expiry first")
        #expect(groups.last?.holder == nil)
        #expect(groups.last?.documents.map(\.id) == [loose.id])
        #expect(!BuiltInTemplates.documents.allFields.contains { $0.key == "document.holder" })
    }

    @Test func earlierCatalogsMoveToTheNewTemplates() throws {
        let context = ModelContext(try makeInMemoryContainer())
        var oldWarranty = BuiltInTemplates.purchase
        oldWarranty.key = "warranty"
        context.insert(CategoryTemplate(definition: oldWarranty, isBuiltIn: true, homeOrder: 0))
        var oldRental = BuiltInTemplates.other
        oldRental.key = "rental"
        context.insert(CategoryTemplate(definition: oldRental, isBuiltIn: true, homeOrder: 1))
        var values = FieldValues()
        values["warranty.purchaseDate"] = .date(CalendarDay("2025-01-01"))
        values["warranty.expiry"] = .date(CalendarDay("2027-01-01"))
        context.insert(Asset(name: "Mașina de spălat", templateKey: "warranty", values: values))
        context.insert(Asset(name: "Garsonieră veche", templateKey: "rental"))
        try context.save()

        try TemplateStore(context: context).installBuiltIns()
        let assets = try context.fetch(FetchDescriptor<Asset>())
        let washer = try #require(assets.first { $0.name == "Mașina de spălat" })
        #expect(washer.templateKey == BuiltInTemplates.Key.purchase)
        #expect(washer.value("purchase.date") == .date(CalendarDay("2025-01-01")))
        #expect(washer.value("purchase.warrantyUntil") == .date(CalendarDay("2027-01-01")))
        let templates = try TemplateStore(context: context).templatesByKey()
        #expect(templates["warranty"] == nil)
        #expect(templates["rental"]?.isCustom == true, "A retired category with assets stays, as the person's own")
    }
}
