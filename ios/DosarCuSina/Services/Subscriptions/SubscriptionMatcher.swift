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
///   whose own codes the document prints, else the one at the supply address it prints
///   (`house(at:among:)`), else the only home there is.
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

    /// A home, with the codes kept on it (`home.pod`, `home.clc`, `home.waterCode`) and its address.
    public struct Home: Hashable, Sendable {
        public var id: UUID
        public var values: FieldValues
        /// Where it is, as the person wrote it: `HomeFields.address` unless given.
        public var address: String?

        public init(id: UUID, values: FieldValues, address: String? = nil) {
            self.id = id
            self.values = values
            self.address = address ?? values[HomeFields.address]?.textValue
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
        /// Where the service is supplied ("Adresa locului de consum"), never the payer's
        /// billing address.
        public var supplyAddress: String?

        public init(provider: String?, service: String?, codes: [Code: String], isBill: Bool, supplyAddress: String? = nil) {
            self.provider = provider
            self.service = service
            self.codes = codes.filter { !SubscriptionMatcher.normalized($0.value, as: $0.key).isEmpty }
            self.isBill = isBill
            self.supplyAddress = supplyAddress
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

    /// Why the house a decision chose is worth a look ("Verifică").
    public enum HouseCheck: Hashable, Sendable {
        /// The supply address only partly agrees with the home's: nothing differs, but
        /// something is missing or nearly the same, or another home is close too.
        case addressPartlyAgrees
        /// The only home is at another address than the one the bill is supplied at.
        case addressDiffers
    }

    /// Where the document goes, and whether the house it was put in needs a look.
    public struct Placement: Hashable, Sendable {
        public var decision: Decision
        /// Set only when the supply address chose the house without being sure.
        public var check: HouseCheck?

        public init(_ decision: Decision, check: HouseCheck? = nil) {
            self.decision = decision
            self.check = check
        }
    }

    /// Where the document goes. `within`, when given, limits the search to what is filed
    /// under that asset (the person chose the home): its subscriptions, or a new one there.
    public static func match(_ reading: Reading, subscriptions: [Subscription], homes: [Home], within: UUID? = nil) -> Decision {
        place(reading, subscriptions: subscriptions, homes: homes, within: within).decision
    }

    /// The one rule for which home a supply address picks, when no code decides:
    /// - a home at the same place (`PostalAddress.Agreement.same`) is picked by itself only
    ///   when it is the only one, and no other home is even likely;
    /// - with another home likely too, or when only one home is likely, that home is
    ///   suggested, marked "Verifică";
    /// - two homes at the same place, or two likely ones, or none: the address can't tell.
    /// Nil when the address can't tell; the caller then falls back as it did without one.
    public static func house(at address: String?, among homes: [Home]) -> (id: UUID, check: HouseCheck?)? {
        guard let address = address.flatMap(PostalAddress.init) else { return nil }
        let rated = homes.compactMap { home in
            home.address.flatMap(PostalAddress.init).map { (id: home.id, agreement: address.agreement(with: $0)) }
        }
        let same = rated.filter { $0.agreement == .same }, likely = rated.filter { $0.agreement == .likely }
        if same.count == 1 { return (same[0].id, likely.isEmpty ? nil : HouseCheck.addressPartlyAgrees) }
        if same.isEmpty, likely.count == 1 { return (likely[0].id, .addressPartlyAgrees) }
        return nil
    }

    /// `match`, with what the person should check about the house it chose.
    public static func place(_ reading: Reading, subscriptions: [Subscription], homes: [Home], within: UUID? = nil) -> Placement {
        let candidates = within.map { parent in subscriptions.filter { $0.parentID == parent } } ?? subscriptions
        let compatible = candidates.filter { isCompatible($0, with: reading) }

        // 1. The codes. A client code alone covers every place a customer has with the
        // provider, so with several homes it can't tell them apart.
        let scored = compatible.map { ($0, score($0, reading)) }.filter { $0.1 > 0 }
        let clientCodeOnly = (scored.map(\.1).max() ?? 0) < Code.contractNumber.weight
        if let best = scored.map(\.1).max(), !(clientCodeOnly && reading.isTiedToHome && homes.count > 1 && within == nil) {
            let top = scored.filter { $0.1 == best }
            if top.count == 1 { return Placement(.existing(top[0].0.id)) }
            return Placement(.undecided)
        }

        // 2. The house: its own codes, else the supply address, else the only home.
        let house: UUID?
        var check: HouseCheck?
        if let within {
            house = within
        } else if reading.isTiedToHome {
            if let named = homeNamed(by: reading, among: homes) {
                house = named
            } else if let found = Self.house(at: reading.supplyAddress, among: homes) {
                house = found.id
                check = found.check
            } else if homes.count == 1 {
                house = homes[0].id
                // The only home, but the bill is supplied somewhere else: worth a look.
                let supplied = reading.supplyAddress.flatMap(PostalAddress.init)
                let kept = homes[0].address.flatMap(PostalAddress.init)
                if let supplied, let kept, supplied.agreement(with: kept) == .different { check = .addressDiffers }
            } else {
                house = nil
            }
        } else {
            house = nil
        }
        let decision = decide(reading, compatible: compatible, house: house, within: within, homes: homes)
        switch decision {
        case .existing, .newUnder: return Placement(decision, check: check)
        case .newStandalone, .undecided: return Placement(decision)
        }
    }

    /// Steps 3 and 4: the provider inside the house, or a new subscription.
    private static func decide(_ reading: Reading, compatible: [Subscription], house: UUID?, within: UUID?, homes: [Home]) -> Decision {
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
