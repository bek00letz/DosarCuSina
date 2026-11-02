import Foundation
import SwiftData

/// What subscriptions cost per month, so the Abonamente box can say
/// "≈ 120 RON pe lună". Amounts stay per currency.
public enum SubscriptionMath {
    /// The monthly equivalent of one subscription's price, or nil without a price.
    public static func monthlyEquivalent(_ values: FieldValues) -> Money? {
        guard let price = values["subscription.price"]?.moneyValue else { return nil }
        let cycle = values["subscription.cycle"]?.textValue.flatMap { BillingCycle.options.option(for: $0)?.key } ?? BillingCycle.monthly
        let months: Decimal
        switch cycle {
        case BillingCycle.yearly: months = 12
        case BillingCycle.quarterly: months = 3
        default: months = 1
        }
        return Money((price.amount / months).rounded(scale: 2), currency: price.currency)
    }

    public static func monthlyTotal<S: Sequence>(_ subscriptions: S) -> MoneyTotals where S.Element == FieldValues {
        MoneyTotals(subscriptions.compactMap(monthlyEquivalent))
    }

    /// The monthly total of every subscription in the binder (examples excluded unless asked).
    @MainActor
    public static func monthlyTotal(in context: ModelContext, includeExamples: Bool = false) throws -> MoneyTotals {
        let key = BuiltInTemplates.Key.subscription
        let assets = try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.templateKey == key }))
        return monthlyTotal(assets.filter { includeExamples || !$0.isExample }.map(\.values))
    }
}
