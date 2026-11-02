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
        /// Filed under nothing: a subscription taken out of its home, into Abonamente.
        case standalone
    }

    /// What a move changed, so it can be taken back.
    public struct MoveReceipt {
        public let child: Asset
        public let previousParent: Asset?
        public let previousName: String
        /// The household member made for the move, if any.
        public let createdParent: Asset?
    }

    /// The kind of parent `child` can be filed under: its current parent's
    /// category, or a household member for a personal document filed under no one.
    /// Nil when it isn't something filed under something else.
    public static func parentTemplateKey(for child: Asset) -> String? {
        // A subscription can go under a home (gas, internet) or stand on its own (a phone plan).
        if child.templateKey == BuiltInTemplates.Key.subscription { return BuiltInTemplates.Key.home }
        if let parent = child.parent { return parent.templateKey }
        return child.templateKey == BuiltInTemplates.Key.documents ? BuiltInTemplates.Key.member : nil
    }

    /// Whether "O persoană nouă" is offered: only personal documents go under people.
    public static func offersNewMember(for child: Asset) -> Bool {
        child.templateKey == BuiltInTemplates.Key.documents && parentTemplateKey(for: child) == BuiltInTemplates.Key.member
    }

    /// Whether "În Abonamente" is offered: a subscription filed under a home can stand on its own.
    public static func offersStandalone(for child: Asset) -> Bool {
        child.templateKey == BuiltInTemplates.Key.subscription && child.parent != nil
    }

    /// The other parents `child` can move to: the same kind as its parent, never
    /// its current parent, itself or anything filed under it. Examples and real
    /// records stay apart. Sorted by name.
    public static func moveDestinations(for child: Asset, among assets: [Asset]) -> [Asset] {
        guard let key = parentTemplateKey(for: child) else { return [] }
        let excluded = Set([child.id] + descendants(of: child).map(\.id) + [child.parent?.id].compactMap { $0 })
        return assets
            .filter { $0.templateKey == key && !excluded.contains($0.id) && $0.isExample == child.isExample }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The name a document would take under `newHolder`, when it is named after
    /// its current holder ("Carte de identitate – Manole Corina"). Nil otherwise.
    public static func renamedForHolder(_ child: Asset, newHolder: String) -> String? {
        DocumentNaming.renamed(child.name, from: child.parent?.name, to: newHolder)
    }

    /// Files `child` under `target` in one save, optionally renaming it. For a new
    /// household member, the person and the move are kept together or not at all.
    @discardableResult
    public func move(_ child: Asset, to target: MoveTarget, renamingTo newName: String? = nil) throws -> MoveReceipt {
        let previousParent = child.parent
        let previousName = child.name
        return try UnitOfWork.perform(in: context) {
            var created: Asset?
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
                guard let template = try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.member) else {
                    throw AssetActionError.missingDestination
                }
                parent = try create(name: name, template: template, values: FieldValues(), isExample: child.isExample)
                created = parent
            }
            try setParent(child, parent)
            if let newName = newName?.trimmingCharacters(in: .whitespacesAndNewlines), !newName.isEmpty, newName != child.name {
                try update(child, name: newName, values: child.values, notes: child.notes)
            }
            return MoveReceipt(child: child, previousParent: previousParent, previousName: previousName, createdParent: created)
        }
    }

    /// Takes a move back: the old parent and name return, and a person made only
    /// for the move goes away again. One save.
    public func undoMove(_ receipt: MoveReceipt) throws {
        try UnitOfWork.perform(in: context) {
            try setParent(receipt.child, receipt.previousParent)
            if receipt.child.name != receipt.previousName {
                try update(receipt.child, name: receipt.previousName, values: receipt.child.values, notes: receipt.child.notes)
            }
            if let created = receipt.createdParent, (created.children ?? []).allSatisfy({ $0.id == receipt.child.id }) {
                try delete(created, children: .keep)
            }
        }
    }
}
