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
}

extension ProviderActions {
    /// Replaces a provider's details. Phone and e-mail are normalized the same way
    /// `create` does; empty text is stored as nil.
    public func update(_ provider: Provider, with details: ProviderDetails) throws {
        func clean(_ text: String?) -> String? {
            guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            return trimmed
        }
        provider.name = details.name.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.trades = details.trades
        provider.phone = clean(details.phone).map { FieldFormatter.normalize($0, as: .phone) }
        provider.email = clean(details.email).map { FieldFormatter.normalize($0, as: .email) }
        provider.address = clean(details.address)
        provider.notes = clean(details.notes)
        provider.contactIdentifier = details.contactIdentifier
        provider.updatedAt = Date()
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
