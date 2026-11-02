import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// The subscription template: what a contract carries, the minimum period's
/// deadline, and the upgrade that brings it to existing installs.
@Suite("Subscription template")
@MainActor
struct SubscriptionTemplateTests {

    private func subscriptionTemplate(_ context: ModelContext) throws -> CategoryTemplate {
        try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.subscription))
    }

    @Test func serviceKindsAreStableKeysNotLabels() {
        let keys = ServiceKind.options.map(\.key)
        #expect(keys == ServiceKind.all)
        #expect(keys.allSatisfy { $0.hasPrefix("service.") })
        #expect(ServiceKind.options.option(for: "Gaze naturale")?.key == ServiceKind.gas, "Older or typed text finds its key")
        #expect(ServiceKind.isTiedToHome(ServiceKind.internetTV))
        #expect(!ServiceKind.isTiedToHome(ServiceKind.mobile), "A phone plan isn't tied to an address")
        #expect(ServiceKind.sendsRegularBills(ServiceKind.mobile))
        #expect(!ServiceKind.sendsRegularBills(ServiceKind.other))
    }

    @Test func theMinimumPeriodEndsFromItsStartAndLength() throws {
        let context = try makeContext()
        let template = try subscriptionTemplate(context)
        var values = FieldValues()
        values[SubscriptionFields.provider] = .text("Orange Romania S.A.")
        values[SubscriptionFields.service] = .text(ServiceKind.mobile)
        values[SubscriptionFields.startDate] = .date(CalendarDay("2026-03-15"))
        values[SubscriptionFields.minimumMonths] = .number(24)
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        let planned = actions.plannedObligations(for: template, values: values)
        let minimum = try #require(planned.first { $0.blueprint.key == SubscriptionFields.minimumEndsBlueprint })
        #expect(minimum.firstDue == CalendarDay("2028-03-15"))
        #expect(minimum.blueprint.reminders.leadDays == [30, 0], "A month before and on the day")
        #expect(minimum.blueprint.reminders.followUpAfterLapse == false)
        #expect(planned.first { $0.blueprint.key == SubscriptionFields.billBlueprint }?.isSelected == false, "Bills set their own dates")

        let plan = try actions.create(name: "Telefon – Orange", template: template, values: values, obligations: planned.filter { $0.firstDue != nil })
        #expect(plan.value(SubscriptionFields.minimumUntil) == .date(CalendarDay("2028-03-15")))
        #expect(plan.activeObligations.map(\.blueprintKey) == [SubscriptionFields.minimumEndsBlueprint])
    }

    @Test func identifiersShowOnlyForTheirService() throws {
        let definition = BuiltInTemplates.subscription
        var gas = FieldValues()
        gas[SubscriptionFields.service] = .text(ServiceKind.gas)
        #expect(definition.field(SubscriptionFields.clc)?.applies(to: gas) == true)
        #expect(definition.field(SubscriptionFields.pod)?.applies(to: gas) == false)
        #expect(definition.field(SubscriptionFields.phoneNumber)?.applies(to: gas) == false)
        #expect(definition.field(SubscriptionFields.clientCode)?.applies(to: gas) == true)
        #expect(definition.field(SubscriptionFields.clientCode)?.role == .keyFact, "Copied in one tap")
    }

    @Test func existingInstallsUpgradeAndKeepTheirSubscriptions() throws {
        let context = ModelContext(try makeInMemoryContainer())
        let store = TemplateStore(context: context)
        // The catalog before contracts and bills: version 7, the first section only.
        var older = BuiltInTemplates.subscription
        older.version = 7
        older.sections = Array(older.sections.prefix(1)).map { section in
            var section = section
            section.fields.removeAll { $0.key == SubscriptionFields.service }
            return section
        }
        older.blueprints.removeAll { [SubscriptionFields.minimumEndsBlueprint, SubscriptionFields.billBlueprint].contains($0.key) }
        try store.installBuiltIns(catalog: BuiltInTemplates.all.filter { $0.key != BuiltInTemplates.Key.subscription } + [older])
        let installed = try subscriptionTemplate(context)
        #expect(installed.builtInVersion == 7)
        #expect(installed.definition.field(SubscriptionFields.service) == nil)
        try store.setOnHome(installed, false)

        var values = FieldValues()
        values[SubscriptionFields.provider] = .text("Netflix")
        values[SubscriptionFields.price] = .money(Money(49))
        let netflix = try AssetActions(context: context).create(name: "Netflix", template: installed, values: values)

        #expect(try store.installBuiltIns())
        #expect(installed.builtInVersion == TemplateDefinition.builtInCatalogVersion)
        #expect(installed.definition.field(SubscriptionFields.service) != nil)
        #expect(installed.definition.field(SubscriptionFields.directDebit)?.type == .toggle)
        #expect(installed.blueprints.contains { $0.key == SubscriptionFields.minimumEndsBlueprint })
        #expect(installed.pockets.contains(.history), "Bills show in its history")
        #expect(installed.isOnHome == false, "Preferences survive the upgrade")
        #expect(netflix.value(SubscriptionFields.provider) == .text("Netflix"))
        #expect(netflix.value(SubscriptionFields.price) == .money(Money(49)))
    }

    @Test func aBillStandsInForThePriceOfAContractBilledByUse() {
        var gas = FieldValues()
        gas[SubscriptionFields.lastBill] = .money(Money(Decimal(string: "245.30")!))
        #expect(SubscriptionMath.monthlyEquivalent(gas) == Money(Decimal(string: "245.30")!))
        #expect(SubscriptionMath.monthlyEquivalent(gas, usingLastBill: false) == nil)
        gas[SubscriptionFields.price] = .money(Money(30))
        #expect(SubscriptionMath.monthlyEquivalent(gas) == Money(30), "A fixed price wins")
    }
}
