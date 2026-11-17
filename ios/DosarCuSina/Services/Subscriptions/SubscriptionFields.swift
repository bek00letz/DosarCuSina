import Foundation

/// The subscription template's field and blueprint keys, named once for the template
/// (`BuiltInTemplates.subscription`), capture's filing and the engines that read them.
public enum SubscriptionFields {
    public static let provider = "subscription.provider"
    public static let service = "subscription.service"
    /// Where it is listed in Abonamente (`SubscriptionGroup`): its service's group until the
    /// person moves it.
    public static let group = "subscription.group"
    public static let price = "subscription.price"
    public static let cycle = "subscription.cycle"
    public static let clientCode = "subscription.clientCode"
    public static let contractNumber = "subscription.contractNumber"
    public static let account = "subscription.account"
    public static let pod = "subscription.pod"
    public static let clc = "subscription.clc"
    public static let placeCode = "subscription.placeCode"
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

    /// How long one billing cycle lasts (`BillingCycle.interval`).
    public static func cycle(of values: FieldValues) -> RecurrenceInterval {
        BillingCycle.interval(values[cycle]?.textValue)
    }
}

/// A code an ongoing contract's papers are identified by, declared once: the subscription's
/// field that keeps it, what it is called, what capture reads it as, and how much it says about
/// which contract a paper belongs to. Which codes a service has is the service's
/// (`ServiceKind.Service.codes`): only those are read, shown in its edit form and offered in the
/// review. The order is the one the edit form lists them in.
public enum SubscriptionCode: String, CaseIterable, Hashable, Sendable {
    case clientCode, contractNumber, account, pod, clc, placeCode, phoneNumber

    /// What kind of code it is: a paper read for one service under another's name keeps its
    /// value as that service's code of the same family (a gas bill's "POD gaz" is its CLC).
    public enum Family: Hashable, Sendable {
        /// Names the place supplied: a POD, a CLC, a water or heating place code.
        case consumptionPoint
        /// Names the customer: a client code, a billing account.
        case customer
        case contract
        case line
    }

    public var family: Family {
        switch self {
        case .pod, .clc, .placeCode: .consumptionPoint
        case .clientCode, .account: .customer
        case .contractNumber: .contract
        case .phoneNumber: .line
        }
    }

    /// The subscription field that keeps it.
    public var fieldKey: String {
        switch self {
        case .clientCode: SubscriptionFields.clientCode
        case .contractNumber: SubscriptionFields.contractNumber
        case .account: SubscriptionFields.account
        case .pod: SubscriptionFields.pod
        case .clc: SubscriptionFields.clc
        case .placeCode: SubscriptionFields.placeCode
        case .phoneNumber: SubscriptionFields.phoneNumber
        }
    }

    /// What capture reads it as.
    public var captureKey: CaptureFieldKey {
        switch self {
        case .clientCode: .clientCode
        case .contractNumber: .contractNumber
        case .account: .account
        case .pod: .podCode
        case .clc: .clcCode
        case .placeCode: .placeCode
        case .phoneNumber: .phoneNumber
        }
    }

    /// The code a capture field is, if it is one.
    public init?(captureKey: CaptureFieldKey) {
        guard let code = Self.allCases.first(where: { $0.captureKey == captureKey }) else { return nil }
        self = code
    }

    /// Its name, on the subscription's page, its edit form and the review.
    public var label: String {
        switch self {
        case .clientCode: String(localized: "Cod client")
        case .contractNumber: String(localized: "Număr contract")
        case .account: String(localized: "Cont de facturare")
        case .pod: String(localized: "Cod loc de consum (POD)")
        case .clc: String(localized: "Cod loc de consum gaze (CLC)")
        case .placeCode: String(localized: "Cod loc de consum")
        case .phoneNumber: String(localized: "Număr de telefon")
        }
    }

    /// One short line under its field: where to find it.
    public var footnote: String? {
        switch self {
        case .pod: String(localized: "Începe cu RO. E pe factura de curent.")
        case .clc: String(localized: "Poate apărea și ca POD gaz. E pe factura de gaze.")
        case .placeCode: String(localized: "E pe factură, lângă codul de client.")
        case .account: String(localized: "E pe factură, uneori în locul codului de client.")
        case .clientCode, .contractNumber, .phoneNumber: nil
        }
    }

    /// A home's own field for the same code, when homes keep it.
    var homeFieldKeys: [String] {
        switch self {
        case .pod: [HomeFields.pod]
        case .clc: [HomeFields.clc]
        case .clientCode: ["home.waterCode"]
        case .placeCode, .phoneNumber, .contractNumber, .account: []
        }
    }

    /// Names one consumption point or one line: a different one is a different contract.
    var namesOnePoint: Bool { family == .consumptionPoint || family == .line }

    /// How strongly an agreeing code says it is the same contract.
    var weight: Int {
        switch family {
        case .consumptionPoint, .line: 100
        case .contract: 50
        case .customer: 20
        }
    }

    /// The condition under which the subscription's edit form shows and keeps it: while its
    /// service is one that has it, and, for the codes any contract has, while no service is
    /// chosen yet (`ServiceKind.codes(of:)`).
    var fieldCondition: BlueprintCondition {
        BlueprintCondition(field: SubscriptionFields.service, oneOf: ServiceKind.keys(carrying: self),
                           orWhenEmpty: ServiceKind.codes(of: nil).contains(self))
    }

    /// The codes a paper read as one service keeps: the ones it has, and a code read under
    /// another service's name as its own code of the same family when it read none of those
    /// itself (a gas bill's "POD gaz" is its CLC; a water bill's "cod loc consum" its place
    /// code). Anything else goes, so a service is never asked or given a code it doesn't have.
    /// A paper whose service isn't known keeps every code it read.
    static func keeping(_ fields: [CaptureField], service: String?) -> [CaptureField] {
        guard let service = ServiceKind.service(service) else { return fields }
        let read = fields.compactMap { field in SubscriptionCode(captureKey: field.key) }
        var kept: [CaptureField] = []
        var given: Set<SubscriptionCode> = []
        for field in fields {
            guard let code = SubscriptionCode(captureKey: field.key) else {
                kept.append(field)
                continue
            }
            if service.codes.contains(code) {
                kept.append(field)
                given.insert(code)
            } else if let own = service.codes.first(where: { $0.family == code.family && !read.contains($0) && !given.contains($0) }) {
                kept.append(CaptureField(key: own.captureKey, value: field.value, confidence: field.confidence, sourceText: field.sourceText, tier: field.tier))
                given.insert(own)
            }
        }
        return kept
    }
}
