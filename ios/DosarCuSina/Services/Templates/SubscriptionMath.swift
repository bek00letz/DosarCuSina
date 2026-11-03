import Foundation
import SwiftData

/// What subscriptions cost per month, so the Abonamente box can say
/// "≈ 120 RON pe lună". Amounts stay per currency.
public enum SubscriptionMath {
    /// The monthly equivalent of one subscription's price, or nil without a price.
    /// A contract billed by use (gas, electricity) has no fixed price: with
    /// `usingLastBill`, its last bill stands in for it.
    public static func monthlyEquivalent(_ values: FieldValues, usingLastBill: Bool = true) -> Money? {
        guard let price = values["subscription.price"]?.moneyValue
                ?? (usingLastBill ? values["subscription.lastBill"]?.moneyValue : nil) else { return nil }
        let months = Decimal(BillingCycle.months(values["subscription.cycle"]?.textValue))
        return Money((price.amount / months).rounded(scale: 2), currency: price.currency)
    }

    public static func monthlyTotal<S: Sequence>(_ subscriptions: S) -> MoneyTotals where S.Element == FieldValues {
        MoneyTotals(subscriptions.compactMap { monthlyEquivalent($0) })
    }

    /// The monthly total of every subscription in the binder (examples excluded unless asked).
    @MainActor
    public static func monthlyTotal(in context: ModelContext, includeExamples: Bool = false) throws -> MoneyTotals {
        let key = BuiltInTemplates.Key.subscription
        let assets = try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.templateKey == key }))
        return monthlyTotal(assets.filter { includeExamples || !$0.isExample }.map(\.values))
    }
}
