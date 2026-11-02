import Foundation

/// The subscription template's field and blueprint keys, named once for the template
/// (`BuiltInTemplates.subscription`), capture's filing and the engines that read them.
public enum SubscriptionFields {
    public static let provider = "subscription.provider"
    public static let service = "subscription.service"
    public static let price = "subscription.price"
    public static let cycle = "subscription.cycle"
    public static let clientCode = "subscription.clientCode"
    public static let contractNumber = "subscription.contractNumber"
    public static let pod = "subscription.pod"
    public static let clc = "subscription.clc"
    public static let phoneNumber = "subscription.phoneNumber"
    public static let startDate = "subscription.startDate"
    public static let minimumMonths = "subscription.minimumMonths"
    public static let minimumUntil = "subscription.minimumUntil"
    public static let directDebit = "subscription.directDebit"
    public static let lastBill = "subscription.lastBill"

    /// "Se termină perioada minimă", from `minimumUntil`.
    public static let minimumEndsBlueprint = "subscription.minimumEnds"
    /// "Factura de plătit": one per subscription, moved to each new bill's due date.
    public static let billBlueprint = "subscription.bill"

    /// Whether the bank pays this subscription's bills by itself.
    public static func paysByDirectDebit(_ values: FieldValues) -> Bool {
        values[directDebit]?.boolValue ?? false
    }

    /// The service's key ("service.gas"), when it is known.
    public static func service(of values: FieldValues) -> String? {
        values[service]?.textValue.flatMap { ServiceKind.options.option(for: $0)?.key }
    }
}
