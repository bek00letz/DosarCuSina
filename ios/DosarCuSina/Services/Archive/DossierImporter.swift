import Foundation
import SwiftData

/// Writes a decoded package into a context. The caller saves (once) or rolls back.
///
/// An archive brings the household's records and the choices a person can make
/// themselves. It never changes what the app defines, whatever it says:
/// - built-in categories always take the app's own definition (name, fields,
///   field types, reminders); an archive brings only their order, whether they
///   show on the binder and their lock;
/// - a lock is never made weaker: a category or field locked on this phone stays locked;
/// - secrets (PIN codes, secret rows) never come from an archive, and the ones
///   this phone keeps for the same records stay, in both modes;
/// - parents follow the same rule as "Mută la…", so nothing ends up filed under itself;
/// - no record's last change is later than now;
/// - a record that is both here and in the archive is merged by one rule, whatever its
///   type (`ArchiveMerge`): the archive's copy only when it changed later;
/// - what a newer build wrote that this one can't read (a recurrence, a template's
///   section, a row under Date importante, a field value) comes in raw and is kept.
///
/// It touches only the context it is given, so a backup is written away from the
/// main thread (`DossierArchiveService.importPackageAway`).
struct DossierImporter {
    let context: ModelContext
    let package: DossierV3.Package
    let mode: ArchiveImportMode
    let calendar: Calendar
    var now = Date()

    private func uuid(_ raw: String?) -> UUID? { raw.flatMap(UUID.init(uuidString:)) }

    /// An archive's timestamp, never later than now.
    private func clamped(_ date: Date) -> Date { min(date, now) }

    /// An archive's change time for a record: never later than now, and `ChangeTime.unknown`
    /// when it carries none (history, line items, readings and documents before version 8).
    private func changeTime(_ date: Date?) -> Date { clamped(date ?? ChangeTime.unknown) }

    func run() throws -> ArchiveImportResult {
        var result = ArchiveImportResult()
        let phone = try PhoneKeeps.capture(in: context)
        if mode == .replace { try deleteEverything() }

        let definitions = try importTemplates(&result, phone: phone)
        let assets = try importAssets(&result, definitions: definitions, phone: phone)
        let providers = try importProviders(&result, assets: assets)
        let obligations = try importObligations(&result, assets: assets)
        let entries = try importHistory(&result, assets: assets, obligations: obligations, providers: providers)
        let serviceItems = try importServiceItems(&result, entries: entries, providers: providers)
        let measurements = try importMeasurements(&result, assets: assets)
        try importAttachments(&result, assets: assets, obligations: obligations, entries: entries, serviceItems: serviceItems, measurements: measurements, providers: providers)
        // The app's own step inside the import's writer, which gives no change times: what it
        // changes keeps the time it had (the archive's, or the phone's), and the deadline it
        // makes has the time it was made, as at launch (`ChangeOrigin.app`).
        try HouseholdRules.reconcile(in: context, today: CalendarDay(now, calendar: calendar), calendar: calendar)
        return result
    }

    // MARK: What the phone keeps

    /// What stays as this phone has it, whatever the archive says. Read before
    /// anything changes, so replacing everything keeps it too.
    struct PhoneKeeps {
        /// Category key → whether it is locked here.
        var locks: [String: Bool] = [:]
        /// Custom category key → its fields that are secret or sensitive here.
        var guardedFields: [String: [String: FieldDefinition]] = [:]
        /// Record id → its sealed values.
        var secrets: [UUID: FieldValues] = [:]
        /// Record id → its secret rows.
        var secretFacts: [UUID: [CustomFact]] = [:]

        static func capture(in context: ModelContext) throws -> PhoneKeeps {
            var keeps = PhoneKeeps()
            for template in try context.fetch(FetchDescriptor<CategoryTemplate>()) {
                keeps.locks[template.key] = (keeps.locks[template.key] ?? false) || template.isSensitive
                guard template.isCustom else { continue }
                for field in template.definition.allFields where field.isSecret || field.isSensitive {
                    keeps.guardedFields[template.key, default: [:]][field.key] = field
                }
            }
            for asset in try context.fetch(FetchDescriptor<Asset>()) {
                let sealed = SecretFields.sealedValues(in: asset.values)
                if !sealed.isEmpty { keeps.secrets[asset.id] = sealed }
                let facts = asset.customFacts.filter(\.isSecret)
                if !facts.isEmpty { keeps.secretFacts[asset.id] = facts }
            }
            return keeps
        }

        /// A category's lock after the import: on if it was on here or in the archive.
        func lock(_ key: String, archive: Bool, default fallback: Bool) -> Bool {
            archive || (locks[key] ?? fallback)
        }

        /// A custom category's definition with every field locked here kept locked.
        func guarding(_ definition: TemplateDefinition) -> TemplateDefinition {
            guard let guarded = guardedFields[definition.key] else { return definition }
            var result = definition
            for (sectionIndex, section) in result.sections.enumerated() {
                for (fieldIndex, field) in section.fields.enumerated() {
                    guard let here = guarded[field.key] else { continue }
                    if here.isSecret { result.sections[sectionIndex].fields[fieldIndex].type = .secret }
                    if here.isSensitive { result.sections[sectionIndex].fields[fieldIndex].isSensitive = true }
                }
            }
            return result
        }
    }

    // MARK: Replace

    private func deleteEverything() throws {
        for item in try context.fetch(FetchDescriptor<Attachment>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<MeasurementLog>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<ServiceItem>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<HistoryEntry>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Provider>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Obligation>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Asset>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<CategoryTemplate>()) { context.delete(item) }
    }

    private func existing<T: PersistentModel>(_ type: T.Type, id: KeyPath<T, UUID>) throws -> [UUID: T] {
        guard mode == .merge else { return [:] }
        var map: [UUID: T] = [:]
        for item in try context.fetch(FetchDescriptor<T>()) where map[item[keyPath: id]] == nil {
            map[item[keyPath: id]] = item
        }
        return map
    }

    // MARK: The merge rule

    /// The record an archive's record is written onto, by the one merge rule (`ArchiveMerge`),
    /// or nil when the phone's own copy stays. A new record is made with `make` and inserted.
    /// Every type of record comes through here, in both modes.
    private func place<Key: Hashable, Record: ChangeTimed>(
        _ key: Key,
        changedAt: Date?,
        in map: inout [Key: Record],
        _ result: inout ArchiveImportResult,
        make: () -> Record
    ) -> Record? {
        switch ArchiveMerge.outcome(archive: changeTime(changedAt), here: map[key]?.updatedAt) {
        case .keepHere:
            result.skipped += 1
            return nil
        case .update:
            result.updated += 1
            return map[key]
        case .insert:
            let record = make()
            context.insert(record)
            map[key] = record
            result.inserted += 1
            return record
        }
    }

    // MARK: Templates

    /// Imports templates and returns every definition in effect after the import, by key.
    private func importTemplates(_ result: inout ArchiveImportResult, phone: PhoneKeeps) throws -> [String: TemplateDefinition] {
        var byKey: [String: CategoryTemplate] = [:]
        if mode == .merge {
            for template in try context.fetch(FetchDescriptor<CategoryTemplate>()) where byKey[template.key] == nil {
                byKey[template.key] = template
            }
        }
        for dto in package.templates {
            let catalog = BuiltInTemplates.definition(for: dto.key)
            // A built-in is the app's, whatever the archive says; anything else is the person's own.
            let definition = catalog ?? phone.guarding(TemplateDefinition(
                key: dto.key, name: dto.name, summary: dto.summary, symbol: dto.symbol,
                tint: TemplateTint(rawValue: dto.tint) ?? .gray, heroStyle: HeroStyle(rawValue: dto.heroStyle) ?? .standard,
                isOnHomeByDefault: dto.isOnHome, isSensitiveByDefault: dto.isSensitive,
                sections: dto.sections.items, blueprints: dto.blueprints.items, components: dto.components?.items ?? [],
                pockets: dto.pockets.map { $0.compactMap(SectionPocket.init(rawValue:)) } ?? SectionPocket.standard,
                behavior: dto.behavior?.value ?? .standard,
                version: 0
            ))
            let isLocked = phone.lock(dto.key, archive: dto.isSensitive, default: catalog?.isSensitiveByDefault ?? false)
            guard let template = place(dto.key, changedAt: dto.updatedAt, in: &byKey, &result, make: {
                let template = CategoryTemplate(definition: definition, isBuiltIn: catalog != nil, homeOrder: dto.homeOrder)
                template.createdAt = clamped(dto.createdAt)
                return template
            }) else { continue }
            template.isBuiltIn = catalog != nil
            template.apply(definition)
            if catalog == nil {
                // The archive's own sections, deadlines and parts, with any this build can't read.
                template.keptSections = dto.sections.replacingItems(definition.sections)
                template.keptBlueprints = dto.blueprints.replacingItems(definition.blueprints)
                template.keptComponents = (dto.components ?? KeptList()).replacingItems(definition.components)
                template.keptBehavior = dto.behavior
            }
            template.homeOrder = dto.homeOrder
            template.isOnHome = dto.isOnHome
            template.isSensitive = isLocked
            template.updatedAt = changeTime(dto.updatedAt)
        }
        // Built-ins the archive didn't mention.
        var order = (byKey.values.map(\.homeOrder).max() ?? -1) + 1
        for definition in BuiltInTemplates.all where byKey[definition.key] == nil {
            let template = CategoryTemplate(definition: definition, isBuiltIn: true, homeOrder: order)
            template.isSensitive = phone.lock(definition.key, archive: false, default: definition.isSensitiveByDefault)
            // Installed from the catalog, not changed by anyone (`ChangeTimes`).
            template.updatedAt = ChangeTime.unknown
            context.insert(template)
            byKey[definition.key] = template
            order += 1
        }
        return byKey.mapValues(\.definition)
    }

    // MARK: Records

    private func importAssets(_ result: inout ArchiveImportResult, definitions: [String: TemplateDefinition], phone: PhoneKeeps) throws -> [UUID: Asset] {
        var map = try existing(Asset.self, id: \.id)
        var written: [(Asset, DossierV3.Asset)] = []
        for dto in package.assets {
            guard let id = uuid(dto.id) else { throw ArchiveError.brokenReference(DossierV3.Path.assets) }
            guard let asset = place(id, changedAt: dto.updatedAt, in: &map, &result, make: {
                Asset(id: id, name: dto.name, templateKey: dto.templateKey)
            }) else { continue }
            asset.name = dto.name
            asset.templateKey = dto.templateKey
            asset.symbolOverride = dto.symbolOverride
            asset.tintOverrideRaw = dto.tintOverride
            asset.notes = dto.notes
            // Choice values written as display text (v2 backups, older builds) become option keys.
            let definition = definitions[dto.templateKey]
            // No card number comes in with a backup: the unit that writes it masks every one (`FreeText`).
            let values = definition.map { dto.values.replacingValue(dto.values.value.normalizingChoices(for: $0)) } ?? dto.values
            // Secrets this phone keeps for the record stay; an archive never brings any.
            asset.keptValues = SecretFields.keepingLocalSecrets(values, from: phone.secrets[id] ?? FieldValues(), definition: definition)
            asset.keptFacts = SecretFields.keepingLocalSecretFacts(dto.customFacts ?? KeptList(), from: phone.secretFacts[id] ?? [])
            asset.photoData = dto.photoPath.flatMap { package.files[$0] }
            asset.isExample = dto.isExample
            asset.createdAt = clamped(dto.createdAt)
            asset.updatedAt = changeTime(dto.updatedAt)
            written.append((asset, dto))
        }
        // Parents are linked once every asset exists, so order in the file doesn't
        // matter, and through the app's own rule, so nothing is filed under itself.
        // A parent that can't be used leaves the section at the top of the binder.
        for (asset, dto) in written {
            let parent = uuid(dto.parentId).flatMap { map[$0] }
            if let parent, AssetActions.canFile(asset, under: parent) {
                asset.parent = parent
            } else {
                asset.parent = nil
                if dto.parentId != nil { result.movedToTop += 1 }
            }
        }
        return map
    }

    private func importObligations(_ result: inout ArchiveImportResult, assets: [UUID: Asset]) throws -> [UUID: Obligation] {
        var map = try existing(Obligation.self, id: \.id)
        for dto in package.obligations {
            guard let id = uuid(dto.id) else { throw ArchiveError.brokenReference(DossierV3.Path.obligations) }
            guard let obligation = place(id, changedAt: dto.updatedAt, in: &map, &result, make: {
                Obligation(id: id, title: dto.title, kind: .routine, dueDay: dto.dueDate)
            }) else { continue }
            obligation.title = dto.title
            obligation.notes = dto.notes
            obligation.blueprintKey = dto.blueprintKey
            // Kept as the archive has it: a kind from a newer build reads as the loudest.
            obligation.kindRaw = dto.kind
            obligation.dueDay = dto.dueDate
            obligation.dueMetric = dto.dueMetric
            obligation.reminders = dto.reminders
            obligation.remindersCustomized = dto.remindersCustomized ?? false
            obligation.reminderMinuteOfDay = dto.reminderMinuteOfDay
            // A rule from a newer build is kept as it was written (`RecurrenceRule.unreadable`), and
            // so is what it wrote inside a rule this build reads (`KeptObject`).
            obligation.keptRecurrence = dto.recurrence
            obligation.estimatedCost = dto.estimatedCost
            obligation.provider = dto.provider
            obligation.reference = dto.reference
            obligation.statusRaw = ObligationStatus(rawValue: dto.status)?.rawValue ?? ObligationStatus.active.rawValue
            obligation.snoozedUntil = dto.snoozedUntil.map { StoredDay.day(of: $0, storedAs: .startOfDay, calendar: calendar) }
            obligation.isExample = dto.isExample
            obligation.createdAt = clamped(dto.createdAt)
            obligation.updatedAt = changeTime(dto.updatedAt)
            obligation.asset = uuid(dto.assetId).flatMap { assets[$0] }
        }
        return map
    }

    private func importProviders(_ result: inout ArchiveImportResult, assets: [UUID: Asset]) throws -> [UUID: Provider] {
        var map = try existing(Provider.self, id: \.id)
        for dto in package.providers {
            guard let id = uuid(dto.id) else { throw ArchiveError.brokenReference(DossierV3.Path.providers) }
            guard let provider = place(id, changedAt: dto.updatedAt, in: &map, &result, make: {
                Provider(id: id, name: dto.name)
            }) else { continue }
            provider.name = dto.name
            provider.trades = dto.trades
            provider.phone = dto.phone
            provider.email = dto.email
            provider.address = dto.address
            provider.notes = dto.notes
            provider.manualRating = dto.manualRating
            provider.wouldCallAgain = dto.wouldCallAgain
            provider.taxID = ProviderTaxID.normalized(dto.taxID) ?? provider.taxID
            provider.isExample = dto.isExample
            provider.createdAt = clamped(dto.createdAt)
            provider.updatedAt = changeTime(dto.updatedAt)
            provider.assets = dto.assetIds.compactMap { uuid($0).flatMap { assets[$0] } }
        }
        return map
    }

    private func importHistory(
        _ result: inout ArchiveImportResult,
        assets: [UUID: Asset],
        obligations: [UUID: Obligation],
        providers: [UUID: Provider]
    ) throws -> [UUID: HistoryEntry] {
        var map = try existing(HistoryEntry.self, id: \.id)
        for dto in package.historyEntries {
            guard let id = uuid(dto.id) else { throw ArchiveError.brokenReference(DossierV3.Path.history) }
            guard let entry = place(id, changedAt: dto.updatedAt, in: &map, &result, make: {
                HistoryEntry(id: id, kind: .note, title: dto.title, occurredAt: dto.occurredAt)
            }) else { continue }
            // Kept as the archive has it: a kind from a newer build reads as a note.
            entry.kindRaw = dto.kind
            entry.title = dto.title
            entry.occurredAt = dto.occurredAt
            entry.metricReading = dto.metricReading
            entry.totalCost = dto.totalCost
            entry.note = dto.note
            entry.reference = dto.reference
            entry.rating = dto.rating
            entry.cycleDueDay = dto.cycleDueDate
            entry.nextDueDay = dto.nextDueDate
            entry.previousStatusRaw = dto.previousStatus
            entry.previousDueMetric = dto.previousDueMetric
            entry.isExample = dto.isExample
            entry.updatedAt = changeTime(dto.updatedAt)
            entry.asset = uuid(dto.assetId).flatMap { assets[$0] }
            entry.obligation = uuid(dto.obligationId).flatMap { obligations[$0] }
            entry.providers = dto.providerIds.compactMap { uuid($0).flatMap { providers[$0] } }
        }
        return map
    }

    private func importServiceItems(_ result: inout ArchiveImportResult, entries: [UUID: HistoryEntry], providers: [UUID: Provider]) throws -> [UUID: ServiceItem] {
        var map = try existing(ServiceItem.self, id: \.id)
        for dto in package.serviceItems {
            guard let id = uuid(dto.id) else { throw ArchiveError.brokenReference(DossierV3.Path.serviceItems) }
            guard let item = place(id, changedAt: dto.updatedAt, in: &map, &result, make: {
                ServiceItem(id: id, name: dto.name, componentKey: dto.componentKey)
            }) else { continue }
            item.name = dto.name
            item.componentKey = dto.componentKey
            item.group = dto.group
            item.partBrandOrCode = dto.partBrandOrCode
            item.partSerialNumber = dto.partSerialNumber
            item.currency = (dto.cost ?? dto.laborCost ?? dto.partsCost)?.currency ?? Money.defaultCurrency
            item.costAmount = dto.cost?.amount
            item.laborCostAmount = dto.laborCost?.amount
            item.partsCostAmount = dto.partsCost?.amount
            item.batchOrTicket = dto.batchOrTicket
            item.locationDetail = dto.locationDetail
            item.daysInService = dto.daysInService
            item.warrantyMonths = dto.warrantyMonths
            item.notes = dto.notes
            item.isExample = dto.isExample
            item.updatedAt = changeTime(dto.updatedAt)
            item.entry = uuid(dto.entryId).flatMap { entries[$0] }
            item.supplier = uuid(dto.supplierId).flatMap { providers[$0] }
        }
        return map
    }

    private func importMeasurements(_ result: inout ArchiveImportResult, assets: [UUID: Asset]) throws -> [UUID: MeasurementLog] {
        var map = try existing(MeasurementLog.self, id: \.id)
        for dto in package.measurements {
            guard let id = uuid(dto.id) else { throw ArchiveError.brokenReference(DossierV3.Path.measurements) }
            guard let log = place(id, changedAt: dto.updatedAt, in: &map, &result, make: {
                MeasurementLog(id: id, kind: .custom, name: dto.name, value: dto.value, recordedAt: dto.recordedAt)
            }) else { continue }
            // Kept as the archive has it: a kind from a newer build reads as custom.
            log.kindRaw = dto.kind
            log.name = dto.name
            log.value = dto.value
            log.recordedAt = dto.recordedAt
            // Any label an earlier version wrote ("m³", "mc", "kWh") is kept as its key; no unit stays none.
            log.unit = MeasurementUnit.storedKey(for: dto.unit)
            log.secondaryValue = dto.secondaryValue
            log.unitPriceAmount = dto.unitPrice?.amount
            log.unitPriceCurrency = dto.unitPrice?.currency
            log.isSelfRead = dto.isSelfRead
            log.referenceMin = dto.referenceMin
            log.referenceMax = dto.referenceMax
            log.source = dto.source
            log.notes = dto.notes
            log.isExample = dto.isExample
            log.updatedAt = changeTime(dto.updatedAt)
            // An archive from before version 10 says nothing: one counter, as it was.
            log.startsCounter = dto.startsCounter ?? false
            log.asset = uuid(dto.assetId).flatMap { assets[$0] }
        }
        return map
    }

    private func importAttachments(
        _ result: inout ArchiveImportResult,
        assets: [UUID: Asset],
        obligations: [UUID: Obligation],
        entries: [UUID: HistoryEntry],
        serviceItems: [UUID: ServiceItem],
        measurements: [UUID: MeasurementLog],
        providers: [UUID: Provider]
    ) throws {
        var map = try existing(Attachment.self, id: \.id)
        var written: [(Attachment, DossierV3.Attachment)] = []
        for dto in package.attachments {
            guard let id = uuid(dto.id) else { throw ArchiveError.brokenReference(DossierV3.Path.attachments) }
            let original = try dto.path.map { path -> Data in
                guard let data = package.files[path] else { throw ArchiveError.missingFile(path) }
                return data
            }
            guard let attachment = place(id, changedAt: dto.updatedAt, in: &map, &result, make: {
                Attachment(id: id, fileName: dto.fileName, contentType: dto.contentType, data: original)
            }) else { continue }
            attachment.title = dto.title
            attachment.fileName = dto.fileName
            attachment.contentType = dto.contentType
            attachment.fileData = original
            // Kept as the archive has it: a kind from a newer build reads as other.
            attachment.kindRaw = dto.kind
            attachment.byteCount = dto.byteCount
            attachment.sha256 = dto.sha256 ?? original.map(Hashing.sha256)
            attachment.thumbnailData = dto.thumbnailPath.flatMap { package.files[$0] }
            // A backup from anywhere brings no card number into a document’s text: the unit that writes it masks it (`FreeText`).
            attachment.extractedText = dto.extractedText
            attachment.documentDay = dto.documentDate
            attachment.validUntil = dto.validUntil
            attachment.keptFraming = dto.framing
            attachment.isArchived = dto.isArchived
            attachment.createdAt = dto.createdAt
            attachment.isExample = dto.isExample
            attachment.updatedAt = changeTime(dto.updatedAt)
            replacePages(of: attachment, with: dto.pagePaths.map { package.files[$0] })
            attachment.asset = uuid(dto.assetId).flatMap { assets[$0] }
            attachment.obligation = uuid(dto.obligationId).flatMap { obligations[$0] }
            attachment.historyEntry = uuid(dto.historyEntryId).flatMap { entries[$0] }
            attachment.serviceItem = uuid(dto.serviceItemId).flatMap { serviceItems[$0] }
            attachment.measurement = uuid(dto.measurementId).flatMap { measurements[$0] }
            attachment.provider = uuid(dto.providerId).flatMap { providers[$0] }
            written.append((attachment, dto))
        }
        // Once every document exists, so order in the file doesn't matter.
        for (attachment, dto) in written {
            attachment.supersededBy = uuid(dto.supersededById).flatMap { map[$0] }
        }
    }

    /// The archive's pages in place of the ones here, when they differ. Pages this phone made
    /// smaller that the archive replaces aren't the ones it made smaller any more.
    private func replacePages(of attachment: Attachment, with images: [Data?]) {
        let current = attachment.orderedPages
        guard current.map(\.imageData) != images else { return }
        for page in current { context.delete(page) }
        for (index, data) in images.enumerated() {
            let page = AttachmentPage(index: index, imageData: data)
            context.insert(page)
            page.attachment = attachment
        }
        if !current.isEmpty { attachment.compactedAt = nil }
    }
}

/// The one rule an import follows for a record that is both on the phone and in the archive,
/// whatever its type: the archive's copy replaces the phone's only when it changed later.
/// A change time a record doesn't carry (an archive from before version 8 of the database,
/// for history, line items, readings and documents) is `ChangeTime.unknown`, older than any
/// change; on a tie the phone's own copy stays. "Înlocuiește tot" empties the phone first,
/// so every record comes from the archive by the same rule.
enum ArchiveMerge {
    enum Outcome: Equatable {
        /// Not on the phone: the archive's copy is added.
        case insert
        /// The archive's copy changed later: it replaces the phone's.
        case update
        /// The phone's copy is as new or newer: it stays.
        case keepHere
    }

    static func outcome(archive: Date, here: Date?) -> Outcome {
        guard let here else { return .insert }
        return archive > here ? .update : .keepHere
    }
}
