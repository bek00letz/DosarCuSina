import Foundation

/// Which places "Unde îl pun" offers first for a captured document: the sections a document of
/// its kind fits, by its profile (its category, a policy's by its cover, routing's categories) and
/// by the part a category plays (a bill's subscription or home, a personal document's person).
/// Everything else is one tap further, under "Altă secțiune…", so nothing is out of reach.
///
/// A new section is made only by `AddSectionFlow`, the one way to make one: started with the
/// category this document fits when there is one ("Secțiune nouă în „Mașini”"), else with the
/// catalog.
enum CaptureDestinations {
    /// The first version's "Secțiune nouă" listed every category (hidden ones too) and made a
    /// section from a name alone, a second way to make one. Off: it goes through
    /// `AddSectionFlow`. Kept as a way back until the new path is proven; remove it with the
    /// owner's OK.
    nonisolated static let makesSectionFromAName = false

    /// A section as the rule sees it: which it is and which category it belongs to.
    struct Place: Equatable {
        var id: UUID
        var templateKey: String
    }

    struct Offer: Equatable {
        /// The sections that fit, in the order given. Nil when the kind says nothing about where
        /// it goes: then every section is offered at once.
        var fitting: [UUID]?
        /// The category "Secțiune nouă" starts with, when the document fits one.
        var newSectionKey: String?
    }

    /// What fits a document of `kind`. `current` (the place shown) always fits, so the choice on
    /// screen is never hidden; `holdsPersonalDocuments` is a capture started from a person's documents.
    static func offer(
        kind: CaptureDocumentKind,
        cover: String?,
        suggestedKeys: [String],
        holdsPersonalDocuments: Bool,
        current: CaptureReview.Destination,
        places: [Place],
        behaviors: [String: CategoryBehavior]
    ) -> Offer {
        var roles: Set<CategoryBehavior.Role> = []
        if kind.profile.filing == .subscription { roles = [.subscription, .home] }
        let personal = kind.isPersonalDocument || holdsPersonalDocuments
        if personal { roles.insert(.holder) }

        // The categories the profile and routing name. A person's documents are reached through
        // the person, never listed one by one.
        let named = ([kind.profile.filedTemplateKey(cover: cover)].compactMap { $0 } + suggestedKeys)
            .filter { behaviors[$0]?.role != .personalDocument }
        let keys = Set(named)

        // A new person is "Persoană nouă", named after the holder read off the document.
        let newSectionKey: String? = personal ? nil : named.first(where: { key in
            guard let behavior = behaviors[key] else { return false }
            return behavior.role != .holder && !behavior.addedOnlyUnderParent
        })

        guard !roles.isEmpty || !keys.isEmpty else { return Offer(fitting: nil, newSectionKey: nil) }
        var shown: UUID?
        if case .asset(let id) = current { shown = id }
        let fitting = places.filter { place in
            if place.id == shown || keys.contains(place.templateKey) { return true }
            guard let role = behaviors[place.templateKey]?.role else { return false }
            return roles.contains(role)
        }
        return Offer(fitting: fitting.map(\.id), newSectionKey: newSectionKey)
    }

    /// What fits the document `review` files, among `assets`.
    @MainActor
    static func offer(for review: CaptureReview, assets: [Asset]) -> Offer {
        offer(
            kind: review.kind,
            cover: review.cover,
            suggestedKeys: CaptureReview.suggestedTemplateKeys(review.suggestions),
            holdsPersonalDocuments: review.filesAsPersonalDocument,
            current: review.destination,
            places: assets.map { Place(id: $0.id, templateKey: $0.templateKey) },
            behaviors: review.behaviors
        )
    }
}
