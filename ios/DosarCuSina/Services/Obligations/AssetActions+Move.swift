import Foundation
import SwiftData

/// "Mută la…": filing something under another parent of the same kind (a
/// document under another household member, a tenancy or a product under
/// another home), as one step that can be taken back.
extension AssetActions {
    /// Where a moved asset goes.
    public enum MoveTarget: Hashable {
        /// An existing asset of the parent's kind.
        case asset(UUID)
        /// A new household member with this name, made in the same save (documents only).
        case newMember(name: String)
        /// Filed under nothing: a subscription or a plant taken out of its home, into its own box.
        case standalone
    }

    /// The categories by key, as `child`'s binder has them. Reading them isn't a change: a
    /// binder that can't be read offers nowhere to move.
    private static func categories(around child: Asset) -> [String: CategoryTemplate] {
        guard let context = child.modelContext else { return [:] }
        return (try? TemplateStore.templatesByKey(in: context)) ?? [:]
    }

    /// The categories of the parents `child` can be filed under, from what its category does
    /// (`CategoryBehavior`), never its key: every category that plays the part it may belong to
    /// (a subscription or a plant under a home), else its current parent's category, else the
    /// people a personal document filed under no one goes under. Empty when it isn't something
    /// filed under something else.
    public static func parentKeys(for child: Asset) -> Set<String> {
        let byKey = categories(around: child)
        let behavior = byKey.behavior(of: child.templateKey)
        if let role = behavior.mayBelongTo { return byKey.values.keys(playing: role) }
        if let parent = child.parent { return [parent.templateKey] }
        if behavior.role == .personalDocument, let holder = byKey.key(withRole: .holder) { return [holder] }
        return []
    }

    /// Whether "Mută la…" is offered: `child` is something that can be filed under something else.
    public static func canMove(_ child: Asset) -> Bool {
        !parentKeys(for: child).isEmpty
    }

    /// Whether "O persoană nouă" is offered: only personal documents go under people.
    public static func offersNewMember(for child: Asset) -> Bool {
        let byKey = categories(around: child)
        guard byKey.behavior(of: child.templateKey).role == .personalDocument, let holder = byKey.key(withRole: .holder) else { return false }
        return parentKeys(for: child).contains(holder)
    }

    /// Whether standing on its own is offered: something that may belong to a home (a
    /// subscription, a plant), filed under one now.
    public static func offersStandalone(for child: Asset) -> Bool {
        child.parent != nil && categories(around: child).behavior(of: child.templateKey).mayBelongTo != nil
    }

    /// The other parents `child` can move to: of a category it can be filed under, never
    /// its current parent, itself or anything filed under it. Examples and real
    /// records stay apart. Sorted by name.
    public static func moveDestinations(for child: Asset, among assets: [Asset]) -> [Asset] {
        let keys = parentKeys(for: child)
        guard !keys.isEmpty else { return [] }
        let excluded = Set([child.id] + descendants(of: child).map(\.id) + [child.parent?.id].compactMap { $0 })
        return assets
            .filter { keys.contains($0.templateKey) && !excluded.contains($0.id) && $0.isExample == child.isExample }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The sections a section of a category that may belong to another part (a plant, a
    /// subscription: a home) can be filed under, by name: every section whose category plays
    /// that part. Examples and real records stay apart. Empty for a category that doesn't say.
    public static func possibleParents(for behavior: CategoryBehavior, isExample: Bool = false, in context: ModelContext) -> [Asset] {
        guard let role = behavior.mayBelongTo else { return [] }
        let keys = ((try? TemplateStore.templatesByKey(in: context)) ?? [:]).values.keys(playing: role)
        let assets = (try? context.fetch(FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.name)]))) ?? []
        return assets.filter { keys.contains($0.templateKey) && $0.isExample == isExample && !$0.isDeleted }
    }

    /// Where a new section goes when the person didn't say: under the household's only section of
    /// the part its category may belong to (a plant into the only home), when its category says so
    /// (`CategoryBehavior.goesUnderTheOnlyOne`). With none or several, nil: it stands on its own,
    /// and "Mută la…" files it later.
    public static func automaticParent(for behavior: CategoryBehavior, isExample: Bool = false, in context: ModelContext) -> Asset? {
        guard behavior.goesUnderTheOnlyOne else { return nil }
        let parents = possibleParents(for: behavior, isExample: isExample, in: context)
        return parents.count == 1 ? parents.first : nil
    }

    /// The name a document would take under `newHolder`, when it is named after
    /// its current holder ("Carte de identitate – Manole Corina"). Nil otherwise.
    public static func renamedForHolder(_ child: Asset, newHolder: String) -> String? {
        DocumentNaming.renamed(child.name, from: child.parent?.name, to: newHolder)
    }

    /// Files `child` under `target` in one save, optionally renaming it. For a new
    /// household member, the person and the move are kept together or not at all.
    /// The receipt takes the move back: the old place and name return, and a person
    /// made for the move goes away again.
    @discardableResult
    public func move(_ child: Asset, to target: MoveTarget, renamingTo newName: String? = nil) throws -> UndoReceipt {
        try UnitOfWork.performUndoable(in: context, now: now()) {
            let parent: Asset?
            switch target {
            case .standalone:
                parent = nil
            case .asset(let id):
                var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                guard let found = try context.fetch(descriptor).first else { throw AssetActionError.missingDestination }
                parent = found
            case .newMember(let name):
                let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { throw AssetActionError.missingName }
                guard let template = try TemplateStore(context: context).template(withRole: .holder) else {
                    throw AssetActionError.missingDestination
                }
                parent = try create(name: name, template: template, values: FieldValues(), isExample: child.isExample)
            }
            try setParent(child, parent)
            if let newName = newName?.trimmingCharacters(in: .whitespacesAndNewlines), !newName.isEmpty, newName != child.name {
                try update(child, name: newName, values: child.values, notes: child.notes)
            }
        }.receipt
    }
}
