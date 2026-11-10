import Foundation

/// What two copies of one firm bring together on the one that stays, by one rule, wherever two
/// copies meet: the repair list joining a firm kept twice (`CaptureRepairs.mergeDuplicateProviders`)
/// and a backup brought in with "Adaugă" whose copy of a firm meets the phone's (`DossierImporter`).
///
/// A firm's details are facts about a real firm that stay true (its phone, email, address, tax
/// ID), so an empty one means "not known here", never "removed": each detail the copy that stays
/// lacks comes from the other, its trades are both copies' trades, and so are the sections it
/// works on. Where both copies have a detail, the one that stays keeps its own (for a backup, the
/// newer copy, by the merge rule, `ArchiveMerge`). So a detail the join filled in on one phone is
/// never lost to the other phone's newer copy, which never had it.
///
/// With iCloud sync, the person's private database merges each field by itself, so a join made on
/// one phone reaches the other field by field; this rule is what a backup does with the same two
/// copies.
enum FirmCopies {
    /// The details one copy of a firm brings.
    struct Details: Equatable, Sendable {
        var trades: [String] = []
        var phone: String?
        var email: String?
        var address: String?
        var notes: String?
        var manualRating: Int?
        var wouldCallAgain: Bool?
        var taxID: String?
        /// The address book's link, which only the phone that made it reads: never in a backup.
        var contactIdentifier: String?
    }

    static func details(of provider: Provider) -> Details {
        Details(
            trades: provider.trades, phone: provider.phone, email: provider.email, address: provider.address,
            notes: provider.notes, manualRating: provider.manualRating, wouldCallAgain: provider.wouldCallAgain,
            taxID: provider.taxID, contactIdentifier: provider.contactIdentifier
        )
    }

    static func details(of archived: DossierV3.Provider) -> Details {
        Details(
            trades: archived.trades, phone: archived.phone, email: archived.email, address: archived.address,
            notes: archived.notes, manualRating: archived.manualRating, wouldCallAgain: archived.wouldCallAgain,
            taxID: ProviderTaxID.normalized(archived.taxID)
        )
    }

    /// Fills every detail `kept` lacks from `other`, and joins their trades. A detail `kept` has
    /// stays as it is; nothing is ever emptied.
    static func gather(_ other: Details, into kept: Provider) {
        let trades = kept.trades + other.trades.filter { !kept.trades.contains($0) }
        if trades != kept.trades { kept.trades = trades.sorted() }
        kept.phone = filled(kept.phone, other.phone)
        kept.email = filled(kept.email, other.email)
        kept.address = filled(kept.address, other.address)
        kept.notes = filled(kept.notes, other.notes)
        kept.manualRating = kept.manualRating ?? other.manualRating
        kept.wouldCallAgain = kept.wouldCallAgain ?? other.wouldCallAgain
        kept.taxID = filled(kept.taxID, other.taxID)
        kept.contactIdentifier = filled(kept.contactIdentifier, other.contactIdentifier)
    }

    /// The sections both copies work on, the kept copy's first.
    static func sections(_ kept: [Asset], _ other: [Asset]) -> [Asset] {
        kept + other.filter { asset in !kept.contains { $0.id == asset.id } }
    }

    /// `kept`, unless it says nothing (none, or only spaces).
    private static func filled(_ kept: String?, _ other: String?) -> String? {
        let empty = kept?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        return empty ? (other ?? kept) : kept
    }
}
