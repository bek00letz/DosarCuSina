import Foundation
import SwiftData

/// Creating and editing the people and businesses the household relies on.
@MainActor
public final class ProviderActions {
    public let context: ModelContext
    private let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = { Date() }) {
        self.context = context
        self.now = now
    }

    @discardableResult
    public func create(
        name: String,
        trades: [ProviderTrade],
        phone: String? = nil,
        email: String? = nil,
        address: String? = nil,
        notes: String? = nil,
        contactIdentifier: String? = nil,
        linkedTo assets: [Asset] = []
    ) throws -> Provider {
        let provider = Provider(name: name, trades: trades, phone: phone.map { FieldFormatter.normalize($0, as: .phone) })
        provider.email = email.map { FieldFormatter.normalize($0, as: .email) }
        provider.address = address
        provider.notes = notes
        provider.contactIdentifier = contactIdentifier
        provider.isExample = !assets.isEmpty && assets.allSatisfy(\.isExample)
        context.insert(provider)
        provider.assets = assets
        try save()
        return provider
    }

    /// The one way capture and the visit form name who issued a document or did a job:
    /// the firm already in Oameni, or a new one. A firm is the same when its name reads
    /// the same once case, diacritics and spacing are set aside (`SearchText.normalize`).
    /// `taxID` (a checked CUI read off the document) is taken now so callers pass it
    /// already; firms don't keep their CUI yet, so today it doesn't decide the match.
    /// The firm is linked to `asset` either way.
    @discardableResult
    public func findOrCreate(name: String, taxID: String? = nil, trade: ProviderTrade, phone: String? = nil, linkedTo asset: Asset? = nil) throws -> Provider? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let wanted = SearchText.normalize(name)
        if let existing = try context.fetch(FetchDescriptor<Provider>()).first(where: { SearchText.normalize($0.name) == wanted }) {
            if let asset { try link(existing, to: asset) }
            return existing
        }
        return try create(name: name, trades: [trade], phone: phone, linkedTo: asset.map { [$0] } ?? [])
    }

    public func link(_ provider: Provider, to asset: Asset) throws {
        guard !(provider.assets ?? []).contains(where: { $0.id == asset.id }) else { return }
        provider.assets = (provider.assets ?? []) + [asset]
        provider.updatedAt = now()
        try save()
    }

    public func unlink(_ provider: Provider, from asset: Asset) throws {
        provider.assets = (provider.assets ?? []).filter { $0.id != asset.id }
        provider.updatedAt = now()
        try save()
    }

    /// The person's own 1–5 rating; job ratings take precedence when there are any.
    public func setRating(_ provider: Provider, _ rating: Int?) throws {
        provider.manualRating = rating.map { min(max($0, 1), 5) }
        provider.updatedAt = now()
        try save()
    }

    public func setWouldCallAgain(_ provider: Provider, _ value: Bool?) throws {
        provider.wouldCallAgain = value
        provider.updatedAt = now()
        try save()
    }

    public func delete(_ provider: Provider) throws {
        context.delete(provider)
        try save()
    }

    private func save() throws {
        try UnitOfWork.save(context)
    }
}

/// Answers about people: who to call for a trade, who worked on an asset, who
/// did a particular job.
@MainActor
public struct ProviderDirectory {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Everyone with `trade`, best first: would call again, then rating, then name.
    public func providers(withTrade trade: ProviderTrade) throws -> [Provider] {
        try context.fetch(FetchDescriptor<Provider>()).filter { $0.has(trade) }.sorted(by: Self.preference)
    }

    /// Everyone who looks after `asset` or did work on it, most recent work first.
    public func providers(for asset: Asset) -> [Provider] {
        var lastWork: [UUID: Date] = [:]
        var byId: [UUID: Provider] = [:]
        for provider in asset.providers ?? [] {
            byId[provider.id] = provider
            lastWork[provider.id] = lastWork[provider.id] ?? .distantPast
        }
        for entry in asset.history ?? [] {
            for provider in entry.providers ?? [] {
                byId[provider.id] = provider
                lastWork[provider.id] = max(lastWork[provider.id] ?? .distantPast, entry.occurredAt)
            }
        }
        return byId.values.sorted { lhs, rhs in
            let l = lastWork[lhs.id] ?? .distantPast, r = lastWork[rhs.id] ?? .distantPast
            return l != r ? l > r : Self.preference(lhs, rhs)
        }
    }

    /// Who did the last `componentKey` job on `asset` ("cine ți-a schimbat robinetul?").
    public func whoDid(_ componentKey: String, on asset: Asset) -> [Provider] {
        guard let last = MaintenanceLog.lastOccurrence(of: componentKey, in: HistoryItemSnapshot.items(of: asset)) else { return [] }
        let entry = (asset.history ?? []).first { $0.id == last.entryId }
        return (entry?.providers ?? []).sorted(by: Self.preference)
    }

    /// A provider's jobs, newest first.
    public func work(by provider: Provider) -> [HistoryEntry] {
        (provider.historyEntries ?? []).sorted { $0.occurredAt > $1.occurredAt }
    }

    static func preference(_ lhs: Provider, _ rhs: Provider) -> Bool {
        let l = (lhs.wouldCallAgain == true, lhs.rating ?? 0), r = (rhs.wouldCallAgain == true, rhs.rating ?? 0)
        if l.0 != r.0 { return l.0 }
        if l.1 != r.1 { return l.1 > r.1 }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
