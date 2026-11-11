import Foundation
import SwiftData

extension DosarSchemaV13 {
    /// A category of assets (Car, Home, a user's own "Bikes") and its field and
    /// obligation definitions, plus this household's preferences for it.
    ///
    /// Built-in categories are installed from `BuiltInTemplates` and upgraded by
    /// `builtInVersion`; custom categories are created by the person. Both sync
    /// and travel in `.dosar` archives the same way.
    @Model
    public final class CategoryTemplate {
        public var key: String = ""
        /// Which copy of this record it is (`Asset.copyID`). Version 13.
        public var copyID: UUID?
        public var name: String = ""
        public var summary: String?
        public var symbol: String = "square.grid.2x2"
        public var tintRaw: String = TemplateTint.gray.rawValue
        public var heroStyleRaw: String = HeroStyle.standard.rawValue
        public var isBuiltIn: Bool = false
        /// Definition version installed from the catalog (0 for custom templates).
        public var builtInVersion: Int = 0

        // Household preferences
        public var homeOrder: Int = 0
        public var isOnHome: Bool = true
        /// The lock asked for before the category was first saved (made here, or brought by a
        /// backup), kept until it is (`SectionLocks`).
        @Transient private var lockBeforeSaved: Bool? = nil

        /// JSON `[FieldSection]`.
        public var sectionsData: Data?
        /// JSON `[ObligationBlueprint]`.
        public var blueprintsData: Data?
        /// JSON `[ComponentDefinition]`.
        public var componentsData: Data?
        /// `SectionPocket` raw values.
        public var pocketsRaw: [String] = SectionPocket.standard.map(\.rawValue)
        /// JSON `CategoryBehavior`: its box, its list, its part for other categories.
        /// Nil for a category from before version 3, which behaves as `standard`.
        public var behaviorData: Data?

        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()

        public init(definition: TemplateDefinition, isBuiltIn: Bool, homeOrder: Int) {
            self.copyID = UUID()
            self.key = definition.key
            self.isBuiltIn = isBuiltIn
            self.homeOrder = homeOrder
            self.isOnHome = definition.isOnHomeByDefault
            self.lockBeforeSaved = definition.isSensitiveByDefault
            apply(definition)
        }

        /// Replaces the definition (name, look, fields, blueprints) and keeps household preferences.
        /// A category of one's own keeps the sections, deadlines and parts a newer build wrote that
        /// this one can't read (`KeptList`); a built-in is always the app's own definition, whole.
        public func apply(_ definition: TemplateDefinition) {
            name = definition.name
            summary = definition.summary
            symbol = definition.symbol
            tintRaw = definition.tint.rawValue
            heroStyleRaw = definition.heroStyle.rawValue
            if isBuiltIn {
                sectionsData = StoredJSON.encode(KeptList(definition.sections))
                blueprintsData = StoredJSON.encode(KeptList(definition.blueprints))
                componentsData = StoredJSON.encode(KeptList(definition.components))
                keptBehavior = KeptObject(definition.behavior)
            } else {
                sectionsData = KeptList.writing(definition.sections, over: sectionsData)
                blueprintsData = KeptList.writing(definition.blueprints, over: blueprintsData)
                componentsData = KeptList.writing(definition.components, over: componentsData)
                behavior = definition.behavior
            }
            pocketsRaw = definition.pockets.map(\.rawValue)
            builtInVersion = isBuiltIn ? definition.version : 0
        }

        /// What the category does in the binder. Writing it keeps what a newer build wrote inside
        /// it that this one doesn't read (`KeptObject`).
        public var behavior: CategoryBehavior {
            get { KeptObject<CategoryBehavior>.value(in: behaviorData) ?? .standard }
            set { keptBehavior = (keptBehavior ?? KeptObject(.standard)).replacingValue(newValue) }
        }

        /// The behaviour as stored, with what this build doesn't read: what a backup carries. Nil,
        /// and nothing stored, for the standard behaviour with nothing more.
        public var keptBehavior: KeptObject<CategoryBehavior>? {
            get { KeptObject.stored(in: behaviorData, fallback: .standard) }
            set { behaviorData = KeptObject.data(newValue, omittedWhen: { $0 == .standard }) }
        }

        public var tint: TemplateTint {
            get { TemplateTint(rawValue: tintRaw) ?? .gray }
            set { tintRaw = newValue.rawValue }
        }

        public var heroStyle: HeroStyle {
            get { HeroStyle(rawValue: heroStyleRaw) ?? .standard }
            set { heroStyleRaw = newValue.rawValue }
        }

        /// The sections this build can read. Writing them keeps the ones it can't, and inside the
        /// ones it reads what it doesn't read there (`KeptList`).
        public var sections: [FieldSection] {
            get { KeptList.items(in: sectionsData) }
            set { sectionsData = KeptList.writing(newValue, over: sectionsData) }
        }

        public var blueprints: [ObligationBlueprint] {
            get { KeptList.items(in: blueprintsData) }
            set { blueprintsData = KeptList.writing(newValue, over: blueprintsData) }
        }

        public var components: [ComponentDefinition] {
            get { KeptList.items(in: componentsData) }
            set { componentsData = KeptList.writing(newValue, over: componentsData) }
        }

        /// The sections as stored, with any a newer build wrote that this one can't read:
        /// what a backup carries.
        public var keptSections: KeptList<FieldSection> {
            get { KeptList.stored(in: sectionsData) }
            set { sectionsData = StoredJSON.encode(newValue) }
        }

        public var keptBlueprints: KeptList<ObligationBlueprint> {
            get { KeptList.stored(in: blueprintsData) }
            set { blueprintsData = StoredJSON.encode(newValue) }
        }

        public var keptComponents: KeptList<ComponentDefinition> {
            get { KeptList.stored(in: componentsData) }
            set { componentsData = StoredJSON.encode(newValue) }
        }

        /// The pockets a section page shows, in the global order.
        public var pockets: [SectionPocket] {
            get { SectionPocket.ordered(pocketsRaw.compactMap(SectionPocket.init(rawValue:))) }
            set { pocketsRaw = SectionPocket.ordered(newValue).map(\.rawValue) }
        }

        public var isCustom: Bool { !isBuiltIn }

        /// Ask for Face ID before showing sections of this category, on this device: each device
        /// decides for itself, so the choice lives beside the store, never in it (`SectionLocks`).
        /// A category this device hasn't decided on is locked as the catalog says, or as it was made;
        /// while this device's locks couldn't be read, every category of one's own is locked too.
        /// Changed only through `setLock`.
        public var isSensitive: Bool {
            let byDefault = lockBeforeSaved ?? (isBuiltIn && SectionLocks.lockedByDefault.contains(key))
            guard let container = modelContext?.container else { return byDefault }
            return SectionLocks.of(container).isLocked(key, byDefault: byDefault, ownCategory: !isBuiltIn)
        }

        /// Locks or opens the category on this device. Opening one that is locked now takes the
        /// person's Face ID first, every time (`lowering`, from `BiometricVaultManager.confirmLowering`);
        /// without it, it throws `LockLowering.Needed` and nothing changes. Throws too when the choice
        /// can't be kept (`SectionLocks`). A category not saved yet only remembers the lock it is
        /// made with.
        func setLock(_ locked: Bool, lowering: LockLowering? = nil) throws {
            guard let container = modelContext?.container else {
                lockBeforeSaved = locked
                return
            }
            if !locked, lowering == nil, isSensitive { throw LockLowering.Needed() }
            try SectionLocks.of(container).set(locked, for: key)
            // The choice made now wins over the one asked for before saving.
            lockBeforeSaved = nil
        }

        /// Makes the lock asked for before the category was saved this device's choice, unless this
        /// device already chose one for its key (a built-in installed again after "Începe din nou",
        /// a category brought back by undo): before the save (`UnitOfWork`), so a category is never
        /// saved without the lock it was made with.
        func keepLockAskedBeforeSaving() throws {
            guard let lock = lockBeforeSaved, let container = modelContext?.container else { return }
            try SectionLocks.of(container).adopt([key: lock])
        }

        /// The plain definition, as archives and the catalog describe it.
        public var definition: TemplateDefinition {
            TemplateDefinition(
                key: key,
                name: name,
                summary: summary,
                symbol: symbol,
                tint: tint,
                heroStyle: heroStyle,
                isOnHomeByDefault: isOnHome,
                isSensitiveByDefault: isSensitive,
                sections: sections,
                blueprints: blueprints,
                components: components,
                pockets: pockets,
                behavior: behavior,
                version: builtInVersion
            )
        }
    }
}
