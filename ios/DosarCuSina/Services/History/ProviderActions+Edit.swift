import Foundation
import SwiftData

/// What the person can change on a provider's card.
public struct ProviderDetails: Equatable, Sendable {
    public var name: String
    public var trades: [String]
    public var phone: String?
    public var email: String?
    public var address: String?
    public var notes: String?
    public var contactIdentifier: String?

    public init(name: String, trades: [String] = [], phone: String? = nil, email: String? = nil, address: String? = nil, notes: String? = nil, contactIdentifier: String? = nil) {
        self.name = name
        self.trades = trades
        self.phone = phone
        self.email = email
        self.address = address
        self.notes = notes
        self.contactIdentifier = contactIdentifier
    }

    /// The details as they are kept: phone and e-mail normalized the same way `create` does,
    /// empty text as nil.
    var kept: ProviderDetails {
        func clean(_ text: String?) -> String? {
            guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            return trimmed
        }
        return ProviderDetails(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines), trades: trades,
            phone: clean(phone).map { FieldFormatter.normalize($0, as: .phone) },
            email: clean(email).map { FieldFormatter.normalize($0, as: .email) },
            address: clean(address), notes: clean(notes), contactIdentifier: contactIdentifier
        )
    }
}

extension ProviderActions {
    /// Writes a provider's details, as kept (`ProviderDetails.kept`). Only what the edit changed
    /// from the details it started from (`startedFrom`, else the provider as stored now) is
    /// written, detail by detail (`ThreeWay`): a detail left as it was read keeps what is stored
    /// now, so a phone number added meanwhile on another device stays.
    public func update(_ provider: Provider, with details: ProviderDetails, startedFrom start: ProviderDetails? = nil) throws {
        let edited = details.kept
        let base = (start ?? provider.details).kept
        let stored = provider.details
        func lay<Value: Equatable>(_ keyPath: KeyPath<ProviderDetails, Value>) -> Value {
            ThreeWay.value(edited[keyPath: keyPath], over: stored[keyPath: keyPath], startedFrom: base[keyPath: keyPath])
        }
        let name = lay(\.name), trades = lay(\.trades), phone = lay(\.phone), email = lay(\.email)
        let address = lay(\.address), notes = lay(\.notes), contact = lay(\.contactIdentifier)
        if provider.name != name { provider.name = name }
        if provider.trades != trades { provider.trades = trades }
        if provider.phone != phone { provider.phone = phone }
        if provider.email != email { provider.email = email }
        if provider.address != address { provider.address = address }
        if provider.notes != notes { provider.notes = notes }
        if provider.contactIdentifier != contact { provider.contactIdentifier = contact }
        try UnitOfWork.save(context, now: now())
    }
}

extension Provider {
    /// What the person can change on the card, as stored.
    var details: ProviderDetails {
        ProviderDetails(name: name, trades: trades, phone: phone, email: email, address: address, notes: notes, contactIdentifier: contactIdentifier)
    }
}
