import Foundation

/// Finds the ongoing contract a bill or a contract belongs to, or says where a new one
/// goes. One record per contract: the first document from a provider makes it, and
/// later ones find it by the codes they print.
///
/// Pure: plain values in, a decision out, so every rule is pinned by tests.
///
/// - The codes decide first. A POD, a CLC or a phone number names one consumption
///   point or one line; a contract number names one contract; a client code can cover
///   several contracts with one provider. A subscription whose own POD, CLC or phone
///   number differs from the document's is never the one.
/// - Without a code, the provider (and the service, when both are known) decides, but
///   only inside one house: two homes with ENGIE gas never merge. The house is the one
///   whose own codes the document prints, or the only home there is.
/// - A new subscription for gas, electricity, water or fixed internet and TV goes under
///   its house; a mobile plan or anything else stands on its own. When the house can't
///   be told, nothing is guessed: the person picks.
public enum SubscriptionMatcher {

    /// An existing subscription, as plain values.
    public struct Subscription: Hashable, Sendable {
        public var id: UUID
        public var parentID: UUID?
        public var values: FieldValues

        public init(id: UUID, parentID: UUID?, values: FieldValues) {
            self.id = id
            self.parentID = parentID
            self.values = values
        }
    }

    /// A home, with the codes kept on it (`home.pod`, `home.clc`, `home.waterCode`).
    public struct Home: Hashable, Sendable {
        public var id: UUID
        public var values: FieldValues

        public init(id: UUID, values: FieldValues) {
            self.id = id
            self.values = values
        }
    }

    /// What a bill or a contract says about its contract.
    public struct Reading: Hashable, Sendable {
        public var provider: String?
        /// A `ServiceKind` key.
        public var service: String?
        public var codes: [Code: String]
        /// A bill (true) or a contract: a bill with no service named is still a utility's.
        public var isBill: Bool

        public init(provider: String?, service: String?, codes: [Code: String], isBill: Bool) {
            self.provider = provider
            self.service = service
            self.codes = codes.filter { !SubscriptionMatcher.normalized($0.value, as: $0.key).isEmpty }
            self.isBill = isBill
        }

        /// Whether the contract is supplied at an address and so belongs under a home.
        public var isTiedToHome: Bool {
            if let service { return ServiceKind.isTiedToHome(service) }
            if codes[.pod] != nil || codes[.clc] != nil { return true }
            if codes[.phoneNumber] != nil { return false }
            return isBill
        }
    }

    /// The codes a document can print, in the order they identify a contract.
    public enum Code: String, CaseIterable, Hashable, Sendable {
        case pod, clc, phoneNumber, contractNumber, clientCode

        /// The subscription field that keeps it.
        public var fieldKey: String {
            switch self {
            case .pod: SubscriptionFields.pod
            case .clc: SubscriptionFields.clc
            case .phoneNumber: SubscriptionFields.phoneNumber
            case .contractNumber: SubscriptionFields.contractNumber
            case .clientCode: SubscriptionFields.clientCode
            }
        }

        /// A home's own field for the same code, when homes keep it.
        var homeFieldKeys: [String] {
            switch self {
            case .pod: ["home.pod"]
            case .clc: ["home.clc"]
            case .clientCode: ["home.waterCode"]
            case .phoneNumber, .contractNumber: []
            }
        }

        /// Names one consumption point or one line: a different one is a different contract.
        var namesOnePoint: Bool { self == .pod || self == .clc || self == .phoneNumber }

        var weight: Int {
            switch self {
            case .pod, .clc, .phoneNumber: 100
            case .contractNumber: 50
            case .clientCode: 20
            }
        }
    }

    public enum Decision: Hashable, Sendable {
        /// The document belongs to this subscription.
        case existing(UUID)
        /// A new subscription under this home.
        case newUnder(home: UUID)
        /// A new subscription on its own, in Abonamente.
        case newStandalone
        /// It can't be told which house or which contract: the person picks.
        case undecided
    }

    /// Where the document goes. `within`, when given, limits the search to what is filed
    /// under that asset (the person chose the home): its subscriptions, or a new one there.
    public static func match(_ reading: Reading, subscriptions: [Subscription], homes: [Home], within: UUID? = nil) -> Decision {
        let candidates = within.map { parent in subscriptions.filter { $0.parentID == parent } } ?? subscriptions
        let compatible = candidates.filter { isCompatible($0, with: reading) }

        // 1. The codes. A client code alone covers every place a customer has with the
        // provider, so with several homes it can't tell them apart.
        let scored = compatible.map { ($0, score($0, reading)) }.filter { $0.1 > 0 }
        let clientCodeOnly = (scored.map(\.1).max() ?? 0) < Code.contractNumber.weight
        if let best = scored.map(\.1).max(), !(clientCodeOnly && reading.isTiedToHome && homes.count > 1 && within == nil) {
            let top = scored.filter { $0.1 == best }
            if top.count == 1 { return .existing(top[0].0.id) }
            return .undecided
        }

        // 2. The house.
        let house: UUID?
        if let within {
            house = within
        } else if reading.isTiedToHome {
            house = homeNamed(by: reading, among: homes) ?? (homes.count == 1 ? homes[0].id : nil)
        } else {
            house = nil
        }

        // 3. The provider, inside that house (or, for a phone plan, among those on their own).
        if let provider = reading.provider.map(providerWords), !provider.isEmpty {
            let place: [Subscription]
            if reading.isTiedToHome || within != nil {
                place = house.map { home in compatible.filter { $0.parentID == home } } ?? []
            } else {
                place = compatible.filter { $0.parentID == nil }
            }
            let sameProvider = place.filter { subscription in
                guard let theirs = subscription.values[SubscriptionFields.provider]?.textValue else { return false }
                return !providerWords(theirs).isDisjoint(with: provider)
            }
            if sameProvider.count == 1 { return .existing(sameProvider[0].id) }
            if sameProvider.count > 1 { return .undecided }
        }

        // 4. A new one.
        if reading.isTiedToHome || within != nil {
            if let house { return .newUnder(home: house) }
            return homes.isEmpty ? .newStandalone : .undecided
        }
        return .newStandalone
    }

    /// How strongly the codes say this is the document's contract; 0 when none agree.
    static func score(_ subscription: Subscription, _ reading: Reading) -> Int {
        Code.allCases.reduce(0) { total, code in
            guard let read = reading.codes[code],
                  let kept = subscription.values[code.fieldKey]?.textValue,
                  normalized(kept, as: code) == normalized(read, as: code) else { return total }
            return total + code.weight
        }
    }

    /// Never the one: a different consumption point or line, or another service.
    static func isCompatible(_ subscription: Subscription, with reading: Reading) -> Bool {
        for code in Code.allCases where code.namesOnePoint {
            if let read = reading.codes[code], let kept = subscription.values[code.fieldKey]?.textValue,
               normalized(kept, as: code) != normalized(read, as: code) { return false }
        }
        if let service = reading.service, let theirs = SubscriptionFields.service(of: subscription.values),
           service != theirs, service != ServiceKind.other, theirs != ServiceKind.other { return false }
        return true
    }

    /// The home whose own codes the document prints.
    static func homeNamed(by reading: Reading, among homes: [Home]) -> UUID? {
        let named = homes.filter { home in
            Code.allCases.contains { code in
                guard let read = reading.codes[code] else { return false }
                return code.homeFieldKeys.contains { key in
                    home.values[key]?.textValue.map { normalized($0, as: code) } == normalized(read, as: code)
                }
            }
        }
        return named.count == 1 ? named[0].id : nil
    }

    /// A code compared without spaces, dashes or case; a phone number in its national form.
    static func normalized(_ text: String, as code: Code) -> String {
        if code == .phoneNumber { return ContractReader.national(text) }
        return text.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The provider as people say it: "ENGIE Romania S.A." is "ENGIE".
    public static func shortProviderName(_ name: String) -> String {
        let kept = name.split(separator: " ").filter { word in
            let folded = RomanianText.fold(String(word)).replacingOccurrences(of: ".", with: "")
            return folded.contains(where: { $0.isLetter || $0.isNumber }) && !providerFillers.contains(folded)
        }
        return kept.isEmpty ? name : kept.joined(separator: " ")
    }

    /// Words in a provider's name that don't tell providers apart.
    static let providerFillers: Set<String> = ["sa", "srl", "s", "a", "romania", "energie", "energy", "furnizare", "servicii", "si", "de", "the"]

    /// The words that name a provider, without the company form or the country:
    /// "ENGIE Romania S.A." and "Engie" are the same provider.
    static func providerWords(_ name: String) -> Set<String> {
        return Set(RomanianText.fold(name).replacingOccurrences(of: ".", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !providerFillers.contains($0) })
    }
}
