package com.ar.dosarcusina.archive

import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.binder.BinderAsset
import com.ar.dosarcusina.archive.binder.BinderAttachment
import com.ar.dosarcusina.archive.binder.BinderChanges
import com.ar.dosarcusina.archive.binder.BinderHistoryEntry
import com.ar.dosarcusina.archive.binder.BinderIssuerLesson
import com.ar.dosarcusina.archive.binder.BinderMeasurement
import com.ar.dosarcusina.archive.binder.BinderObligation
import com.ar.dosarcusina.archive.binder.BinderProvider
import com.ar.dosarcusina.archive.binder.BinderServiceItem
import com.ar.dosarcusina.archive.binder.BinderTemplate
import com.ar.dosarcusina.archive.binder.BuiltInDefinition
import com.ar.dosarcusina.archive.binder.BuiltIns
import com.ar.dosarcusina.archive.binder.Removed
import com.ar.dosarcusina.archive.binder.UntilTheSharedCatalog
import com.ar.dosarcusina.archive.v3.AttachmentRecord
import com.ar.dosarcusina.archive.v3.CategoryBehavior
import com.ar.dosarcusina.archive.v3.ChangeTime
import com.ar.dosarcusina.archive.v3.ComponentDefinition
import com.ar.dosarcusina.archive.v3.CustomFact
import com.ar.dosarcusina.archive.v3.DossierPackage
import com.ar.dosarcusina.archive.v3.DossierV3
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldSection
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.Ids
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.StoredFile
import com.ar.dosarcusina.archive.v3.TemplateRecord
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.KeptList
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.core.values.Money
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** What an import decided: what to write, and what it counted. */
data class ImportPlan(val changes: BinderChanges, val result: ArchiveImportResult)

/**
 * Decides what a decoded archive writes into the binder, as the iOS app's `DossierImporter`
 * (ios/DosarCuSina/Services/Archive/DossierImporter.swift), without the store: it reads the
 * binder as it is ([binder], read once) and gives what to write ([ImportPlan]), which the store
 * then writes everything or nothing ([com.ar.dosarcusina.archive.binder.ArchiveTarget.apply]).
 *
 * An archive brings the household's records and the choices a person can make themselves. It
 * never changes what the app defines, whatever it says:
 * - a built-in category takes the app's own definition ([BuiltIns]; until the shared catalog,
 *   the definition the archive carries), and an archive brings only its order, whether it shows
 *   on the binder, its box and its lock;
 * - a lock is never made weaker: a category or a field locked on this phone stays locked;
 * - secrets (PIN codes, secret rows) never come from an archive, and the ones this phone keeps
 *   for the same records stay, in both modes ([SecretRules]);
 * - parents follow the one rule of "Mută la…", so nothing is filed under itself;
 * - no record's last change is later than now;
 * - a record both here and in the archive is merged by one rule, whatever its type ([ArchiveMerge]);
 * - what a newer build wrote that this one can't read comes in raw and is kept.
 *
 * "Înlocuiește tot" replaces the binder in place: a record both here and in the archive is the
 * same record, with the archive's values, and only what the archive doesn't have goes.
 *
 * Left for later phases, each named where it would run: the household's own deadlines worked
 * out again after an import (`HouseholdRules.reconcile`, with the catalog in Phase 2), and the
 * card numbers every save masks (`FreeText`, in Phase 2's unit of work, which [ArchiveTarget]
 * saves through).
 */
// One function per kind of record, as the iOS importer has.
@Suppress("TooManyFunctions")
class DossierImporter(
    private val pack: DossierPackage,
    private val binder: Binder,
    private val mode: ArchiveImportMode,
    private val now: Instant,
    /** The time zone the app counts days in: a snooze's moment becomes its day here. */
    private val zone: ZoneId,
    private val builtIns: BuiltIns = UntilTheSharedCatalog,
    /** False for a binder that syncs: a backup's examples stay out. Android's binder doesn't sync yet. */
    private val keepsExamples: Boolean = true,
) {
    private var inserted = 0
    private var updated = 0
    private var skipped = 0
    private var movedToTop = 0
    private val locks = LinkedHashMap<String, Boolean>()
    private val phone = PhoneKeeps.capture(binder, builtIns)

    private val templates = Table(binder.templates, BinderTemplate::key, BinderTemplate::updatedAt)
    private val assets = Table(binder.assets, BinderAsset::id, BinderAsset::updatedAt)
    private val obligations = Table(binder.obligations, BinderObligation::id, BinderObligation::updatedAt)
    private val providers = Table(binder.providers, BinderProvider::id, BinderProvider::updatedAt)
    private val entries = Table(binder.historyEntries, BinderHistoryEntry::id, BinderHistoryEntry::updatedAt)
    private val items = Table(binder.serviceItems, BinderServiceItem::id, BinderServiceItem::updatedAt)
    private val readings = Table(binder.measurements, BinderMeasurement::id, BinderMeasurement::updatedAt)
    private val documents = Table(binder.attachments, BinderAttachment::id, BinderAttachment::updatedAt)
    private val lessons = Table(binder.issuerLessons, BinderIssuerLesson::id, BinderIssuerLesson::updatedAt)

    fun run(): ImportPlan {
        importTemplates()
        importAssets()
        importProviders()
        importObligations()
        importHistory()
        importServiceItems()
        importMeasurements()
        importAttachments()
        importIssuerLessons()
        val removed = if (mode == ArchiveImportMode.REPLACE) whatTheArchiveLacks() else Removed()
        // What capture learned, as the binder and the backup learned it together: a label the two
        // give two different values goes (`IssuerLessons.settle`'s rule, inside the import's step).
        val contradicted = dropContradictedLessons(removed.issuerLessons)
        val written = Binder(
            templates = templates.written(),
            assets = assets.written(),
            obligations = obligations.written(),
            historyEntries = entries.written(),
            serviceItems = items.written(),
            providers = providers.written(),
            measurements = readings.written(),
            attachments = documents.written(),
            issuerLessons = lessons.written().filter { it.id !in contradicted },
        )
        val out = removed.copy(issuerLessons = removed.issuerLessons + contradicted.filter { it in lessons.onThePhone })
        return ImportPlan(
            BinderChanges(Links.without(written, out), out, locks),
            ArchiveImportResult(inserted, updated, skipped, movedToTop),
        )
    }

    // The merge rule

    /** A kind of record, by its key: the phone's copies, the ones this import writes, and the ones it keeps. */
    private class Table<K, R>(existing: List<R>, private val keyOf: (R) -> K, val changedAt: (R) -> Instant) {
        val byKey = LinkedHashMap<K, R>().apply { for (record in existing) putIfAbsent(keyOf(record), record) }
        val onThePhone: Set<K> = byKey.keys.toSet()
        private val writes = LinkedHashMap<K, R>()
        val kept = HashSet<K>()

        operator fun get(key: K): R? = byKey[key]

        operator fun contains(key: K): Boolean = key in byKey

        fun write(record: R) {
            val key = keyOf(record)
            byKey[key] = record
            writes[key] = record
            kept += key
        }

        fun written(): List<R> = writes.values.toList()
    }

    /**
     * What the one merge rule ([ArchiveMerge]) does with the archive's copy of [key]: the phone's
     * copy the archive's is written over (null for a new record), or no write at all when the
     * phone's copy stays. Every type of record comes through here, in both modes.
     */
    private sealed interface Placement<out R> {
        data class Write<R>(val here: R?) : Placement<R>

        data object Keep : Placement<Nothing>
    }

    private fun <K, R> place(key: K, changedAt: Instant?, table: Table<K, R>): Placement<R> {
        val here = table[key]
        return when (ArchiveMerge.outcome(changeTime(changedAt), here?.let(table.changedAt), mode)) {
            ArchiveMerge.Outcome.KEEP_HERE -> {
                skipped += 1
                table.kept += key
                Placement.Keep
            }
            ArchiveMerge.Outcome.UPDATE -> {
                updated += 1
                Placement.Write(here)
            }
            ArchiveMerge.Outcome.INSERT -> {
                inserted += 1
                Placement.Write(null)
            }
        }
    }

    /** An archive's timestamp, never later than now. */
    private fun clamped(time: Instant): Instant = if (time.isAfter(now)) now else time

    /** An archive's change time for a record: never later than now, and unknown when it carries none. */
    private fun changeTime(time: Instant?): Instant = clamped(time ?: ChangeTime.UNKNOWN)

    private fun id(raw: String, path: String): UUID = Ids.parse(raw) ?: throw ArchiveError.BrokenReference(path)

    /** The id of a record of [table] the archive points at; none when there is no such record. */
    private fun <R> link(raw: String?, table: Table<UUID, R>): UUID? = raw?.let(Ids::parse)?.takeIf { it in table }

    private fun keeps(isExample: Boolean): Boolean = keepsExamples || !isExample

    // Categories

    private fun importTemplates() {
        val mentioned = pack.templates.map(TemplateRecord::key).toSet()
        for (dto in pack.templates) importTemplate(dto)
        // Built-ins the archive didn't mention: added when missing, and in "Înlocuiește tot" as if
        // just installed, on the record already here.
        val placed = templates.byKey.filterKeys { it in mentioned || mode == ArchiveImportMode.MERGE }
        var order = CategoryOrder.after(placed.values.map { it.homeOrder })
        val missing =
            builtIns.all.filter { it.key !in mentioned && (it.key !in templates || mode == ArchiveImportMode.REPLACE) }
        for (definition in missing) {
            val here = templates[definition.key]
            val made = catalogTemplate(definition, here, createdAt = here?.createdAt ?: now).copy(
                homeOrder = order, isOnHome = definition.isOnHomeByDefault, boxGrouping = null,
                // Installed from the catalog, not changed by anyone.
                updatedAt = ChangeTime.UNKNOWN,
            )
            templates.write(made)
            setLock(
                definition.key,
                phone.lock(definition.key, archive = false, fallback = definition.isSensitiveByDefault),
            )
            order += 1
        }
    }

    private fun importTemplate(dto: TemplateRecord) {
        val catalog = builtIns.definition(dto.key)
        val isBuiltIn = catalog != null || builtIns.isBuiltIn(dto.key)
        val isLocked = phone.lock(dto.key, archive = dto.isSensitive, fallback = catalog?.isSensitiveByDefault ?: false)
        val here = when (val placement = place(dto.key, dto.updatedAt, templates)) {
            Placement.Keep -> {
                // The phone's copy stays, but a lock the backup has still locks it here: a lock
                // isn't in the record, so it doesn't wait for a newer copy.
                if (dto.isSensitive) setLock(dto.key, true)
                return
            }
            is Placement.Write -> placement.here
        }
        // Replaced in place, or new, it was made when the archive's was.
        val createdAt =
            if (here == null || mode == ArchiveImportMode.REPLACE) clamped(dto.createdAt) else here.createdAt
        val defined = catalog?.let { catalogTemplate(it, here, createdAt) }
            ?: archiveTemplate(dto, isBuiltIn, createdAt)
        templates.write(
            defined.copy(
                // Its place as the archive has it, within the places a binder gives.
                homeOrder = CategoryOrder.place(dto.homeOrder),
                isOnHome = dto.isOnHome,
                // As written: a choice from a newer build goes out again unchanged.
                boxGrouping = dto.boxGrouping,
                updatedAt = changeTime(dto.updatedAt),
            ),
        )
        // Never opens what is locked here now.
        setLock(dto.key, isLocked || (binder.locks[dto.key] ?: false))
    }

    /**
     * A category as the archive defines it: its own sections, deadlines and parts, with any this
     * build can't read, a field locked here kept locked; its tint, hero and pockets as the archive
     * has them.
     */
    private fun archiveTemplate(dto: TemplateRecord, isBuiltIn: Boolean, createdAt: Instant): BinderTemplate {
        // A category of one's own is named as one thing already: its sections take its name,
        // whatever an archive says one of them is called.
        val behavior =
            if (isBuiltIn) dto.behavior else dto.behavior?.let { it.replacingValue(it.value.copy(singular = null)) }
        return BinderTemplate(
            key = dto.key, name = dto.name, summary = dto.summary, symbol = dto.symbol, tint = dto.tint,
            heroStyle = dto.heroStyle, isBuiltIn = isBuiltIn, version = if (isBuiltIn) dto.version else 0,
            homeOrder = 0, isOnHome = dto.isOnHome,
            sections = dto.sections.replacingItems(phone.guarding(dto.key, dto.sections.items)),
            blueprints = dto.blueprints.replacingItems(dto.blueprints.items),
            components = (dto.components ?: emptyComponents()).let { it.replacingItems(it.items) },
            pockets = dto.pockets ?: STANDARD_POCKETS, behavior = behavior, boxGrouping = null,
            createdAt = createdAt, updatedAt = ChangeTime.UNKNOWN,
        )
    }

    /** A built-in as the catalog defines it, on the record already here when there is one. */
    private fun catalogTemplate(definition: BuiltInDefinition, here: BinderTemplate?, createdAt: Instant) =
        BinderTemplate(
        key = definition.key, name = definition.name, summary = definition.summary, symbol = definition.symbol,
        tint = definition.tint, heroStyle = definition.heroStyle, isBuiltIn = true, version = definition.version,
        homeOrder = here?.homeOrder ?: 0, isOnHome = here?.isOnHome ?: definition.isOnHomeByDefault,
        sections = KeptList.made(definition.sections, FieldSection.codec, FieldSection::key),
        blueprints = KeptList.made(definition.blueprints, ObligationBlueprint.codec, ObligationBlueprint::key),
        components = KeptList.made(definition.components, ComponentDefinition.codec, ComponentDefinition::key),
        pockets = definition.pockets,
        behavior = KeptObject.made(definition.behavior, CategoryBehavior.codec).omitted(CategoryBehavior::isStandard),
        boxGrouping = here?.boxGrouping, createdAt = createdAt, updatedAt = here?.updatedAt ?: ChangeTime.UNKNOWN,
    )

    /** A category's lock after the import: raised, or set for one new here; never lowered. */
    private fun setLock(key: String, locked: Boolean) {
        val now = locks[key] ?: binder.locks[key]
        if (now == locked || now == true) return
        locks[key] = locked
    }

    /** Every field of each category after the import, by its key. */
    private val fieldsByCategory: Map<String, List<FieldDefinition>> by lazy {
        templates.byKey.mapValues { (_, template) -> template.sections.items.flatMap(FieldSection::fields) }
    }

    // Sections

    private fun importAssets() {
        val written = ArrayList<Pair<BinderAsset, String?>>()
        for (dto in pack.assets.filter { keeps(it.isExample) }) {
            val id = id(dto.id, DossierV3.Path.ASSETS)
            val here = when (val placement = place(id, dto.updatedAt, assets)) {
                Placement.Keep -> continue
                is Placement.Write -> placement.here
            }
            // Choice values written as display text (v2 backups, older builds) become option keys.
            val fields = fieldsByCategory[dto.templateKey]
            val values = fields?.let { dto.values.replacingValue(ChoiceKeys.normalizing(dto.values.value, it)) }
                ?: dto.values
            val asset = BinderAsset(
                id = id, templateKey = dto.templateKey, name = dto.name, parentId = here?.parentId,
                symbolOverride = dto.symbolOverride, tintOverride = dto.tintOverride, notes = dto.notes,
                // Secrets this phone keeps for the record stay; an archive never brings any.
                values = SecretRules.keepingLocalSecrets(values, phone.secrets[id] ?: FieldValues(), fields),
                customFacts = SecretRules.keepingLocalSecretFacts(
                    dto.customFacts ?: emptyFacts(),
                    phone.secretFacts[id] ?: emptyFacts(),
                ),
                photo = dto.photoPath?.let(pack.files::file),
                isExample = dto.isExample, createdAt = clamped(dto.createdAt), updatedAt = changeTime(dto.updatedAt),
            )
            assets.write(asset)
            written += asset to dto.parentId
        }
        linkParents(written)
    }

    /**
     * Parents are linked once every section exists, so order in the file doesn't matter, and by
     * the app's one rule, so nothing is filed under itself. A parent that can't be used leaves the
     * section at the top of the binder.
     */
    private fun linkParents(written: List<Pair<BinderAsset, String?>>) {
        val parentOf = HashMap<UUID, UUID?>()
        for ((key, asset) in assets.byKey) parentOf[key] = asset.parentId
        for ((asset, raw) in written) {
            val parent = link(raw, assets)
            val linked = parent?.takeIf { canFile(asset.id, it, parentOf) }
            parentOf[asset.id] = linked
            if (linked == null && raw != null) movedToTop += 1
            assets.write(asset.copy(parentId = linked))
        }
    }

    /** Never under itself, nor under anything filed under it (`AssetActions.canFile`). */
    private fun canFile(child: UUID, parent: UUID, parentOf: Map<UUID, UUID?>): Boolean {
        val seen = HashSet<UUID>()
        var current: UUID? = parent
        while (current != null) {
            if (current == child || !seen.add(current)) return false
            current = parentOf[current]
        }
        return true
    }

    // Deadlines, firms, history, line items, readings

    private fun importObligations() {
        for (dto in pack.obligations.filter { keeps(it.isExample) }) {
            val id = id(dto.id, DossierV3.Path.OBLIGATIONS)
            if (place(id, dto.updatedAt, obligations) == Placement.Keep) continue
            obligations.write(
                BinderObligation(
                    id = id, assetId = link(dto.assetId, assets), title = dto.title, notes = dto.notes,
                    blueprintKey = dto.blueprintKey,
                    // Kept as the archive has it: a kind or a status from a newer build reads as the loudest.
                    kind = dto.kind, dueDay = dto.dueDate, dueMetric = dto.dueMetric, reminders = dto.reminders,
                    remindersCustomized = dto.remindersCustomized ?: false,
                    // Within the day, as the page shows it and the reminder fires (`ReminderClock`).
                    reminderMinuteOfDay = dto.reminderMinuteOfDay?.coerceIn(0, LAST_MINUTE_OF_DAY),
                    recurrence = dto.recurrence, estimatedCost = dto.estimatedCost, provider = dto.provider,
                    reference = dto.reference, status = dto.status,
                    snoozedUntil = dto.snoozedUntil?.let(::snoozeDay),
                    isExample = dto.isExample, createdAt = clamped(dto.createdAt),
                    updatedAt = changeTime(dto.updatedAt),
                    // A backup doesn't carry since when its cycle is known: it reads as known since its change time.
                    cycleKnownAt = null,
                ),
            )
        }
    }

    /**
     * The day a snooze ends: the moment an archive writes is that day's start (`StoredDay.day(of:storedAs:
     * .startOfDay)`).
     */
    private fun snoozeDay(moment: Instant): CalendarDay = CalendarDay.of(moment.plusSeconds(HALF_A_DAY), zone)

    private fun importProviders() {
        for (dto in pack.providers.filter { keeps(it.isExample) }) {
            val id = id(dto.id, DossierV3.Path.PROVIDERS)
            val archivedSections = dto.assetIds.mapNotNull { link(it, assets) }
            // Both copies of a firm meet by one rule (`FirmCopies`): the newer one's details stand,
            // and what only the other knows comes along. In "Înlocuiește tot" the archive's copy is the firm.
            val here = providers[id]?.takeIf { mode == ArchiveImportMode.MERGE }
            when (val placement = place(id, dto.updatedAt, providers)) {
                Placement.Keep -> {
                    val phoneCopy = providers[id] ?: continue
                    val gathered = FirmCopies.gather(FirmCopies.details(dto), phoneCopy)
                    val sections = FirmCopies.sections(phoneCopy.assetIds, archivedSections)
                    val grew = sections.size != phoneCopy.assetIds.size
                    val joined = gathered.copy(assetIds = if (grew) sections else phoneCopy.assetIds)
                    if (joined != phoneCopy) providers.write(joined)
                }
                is Placement.Write -> {
                    val archived = BinderProvider(
                        id = id, name = dto.name, trades = dto.trades, phone = dto.phone, email = dto.email,
                        address = dto.address, notes = dto.notes, manualRating = dto.manualRating,
                        wouldCallAgain = dto.wouldCallAgain, assetIds = archivedSections, isExample = dto.isExample,
                        createdAt = clamped(dto.createdAt), updatedAt = changeTime(dto.updatedAt),
                        taxID = ProviderTaxID.normalized(dto.taxID),
                        contactIdentifier = placement.here?.contactIdentifier,
                    )
                    providers.write(
                        if (here == null) {
                            archived
                        } else {
                            FirmCopies.gather(FirmCopies.details(here), archived)
                                .copy(assetIds = FirmCopies.sections(archived.assetIds, here.assetIds))
                        },
                    )
                }
            }
        }
    }

    private fun importHistory() {
        for (dto in pack.historyEntries.filter { keeps(it.isExample) }) {
            val id = id(dto.id, DossierV3.Path.HISTORY)
            if (place(id, dto.updatedAt, entries) == Placement.Keep) continue
            entries.write(
                BinderHistoryEntry(
                    // Kept as the archive has it: a kind from a newer build reads as a note.
                    id = id, assetId = link(dto.assetId, assets), obligationId = link(dto.obligationId, obligations),
                    kind = dto.kind, title = dto.title, occurredAt = dto.occurredAt, metricReading = dto.metricReading,
                    totalCost = dto.totalCost, note = dto.note, rating = dto.rating, cycleDueDay = dto.cycleDueDate,
                    nextDueDay = dto.nextDueDate, previousStatus = dto.previousStatus,
                    previousDueMetric = dto.previousDueMetric,
                    providerIds = dto.providerIds.mapNotNull { link(it, providers) },
                    isExample = dto.isExample, reference = dto.reference, updatedAt = changeTime(dto.updatedAt),
                ),
            )
        }
    }

    private fun importServiceItems() {
        for (dto in pack.serviceItems.filter { keeps(it.isExample) }) {
            val id = id(dto.id, DossierV3.Path.SERVICE_ITEMS)
            if (place(id, dto.updatedAt, items) == Placement.Keep) continue
            items.write(
                BinderServiceItem(
                    id = id, entryId = link(dto.entryId, entries), componentKey = dto.componentKey, name = dto.name,
                    group = dto.group, partBrandOrCode = dto.partBrandOrCode, partSerialNumber = dto.partSerialNumber,
                    currency = (dto.cost ?: dto.laborCost ?: dto.partsCost)?.currency ?: Money.DEFAULT_CURRENCY,
                    costAmount = dto.cost?.amount, laborCostAmount = dto.laborCost?.amount,
                    partsCostAmount = dto.partsCost?.amount, supplierId = link(dto.supplierId, providers),
                    batchOrTicket = dto.batchOrTicket, locationDetail = dto.locationDetail,
                    daysInService = dto.daysInService, warrantyMonths = dto.warrantyMonths, notes = dto.notes,
                    isExample = dto.isExample, updatedAt = changeTime(dto.updatedAt),
                ),
            )
        }
    }

    private fun importMeasurements() {
        for (dto in pack.measurements.filter { keeps(it.isExample) }) {
            val id = id(dto.id, DossierV3.Path.MEASUREMENTS)
            if (place(id, dto.updatedAt, readings) == Placement.Keep) continue
            readings.write(
                BinderMeasurement(
                    // Kept as the archive has it: a kind from a newer build reads as custom.
                    id = id, assetId = link(dto.assetId, assets), kind = dto.kind, name = dto.name, value = dto.value,
                    secondaryValue = dto.secondaryValue,
                    // Any label an earlier version wrote ("m³", "mc", "kWh") is kept as its key; no unit stays none.
                    unit = MeasurementUnit.storedKey(dto.unit), recordedAt = dto.recordedAt,
                    unitPriceAmount = dto.unitPrice?.amount, unitPriceCurrency = dto.unitPrice?.currency,
                    isSelfRead = dto.isSelfRead, referenceMin = dto.referenceMin, referenceMax = dto.referenceMax,
                    source = dto.source, notes = dto.notes, isExample = dto.isExample,
                    updatedAt = changeTime(dto.updatedAt),
                    // An archive from before version 10 says nothing: one counter, as it was.
                    startsCounter = dto.startsCounter ?: false,
                    // An archive from before version 14 says nothing about how a reading was taken.
                    basis = dto.basis,
                ),
            )
        }
    }

    // Documents and lessons

    private fun importAttachments() {
        val written = ArrayList<Pair<BinderAttachment, String?>>()
        for (dto in pack.attachments.filter { keeps(it.isExample) }) {
            val id = id(dto.id, DossierV3.Path.ATTACHMENTS)
            val original = dto.path?.let { pack.files.file(it) ?: throw ArchiveError.MissingFile(it) }
            val here = when (val placement = place(id, dto.updatedAt, documents)) {
                Placement.Keep -> continue
                is Placement.Write -> placement.here
            }
            val document = document(dto, id, here, original)
            documents.write(document)
            written += document to dto.supersededById
        }
        // Once every document exists, so order in the file doesn't matter.
        for ((document, raw) in written) documents.write(document.copy(supersededById = link(raw, documents)))
    }


    /** The archive's copy of a document, written over [here] when the phone has one. */
    private fun document(
        dto: AttachmentRecord,
        id: UUID,
        here: BinderAttachment?,
        original: StoredFile?,
    ): BinderAttachment {
        val incoming = dto.pagePaths.map { pack.files.file(it) ?: throw ArchiveError.MissingFile(it) }
        // The archive's pages in place of the ones here, when they differ. Pages this phone made
        // smaller that the archive replaces aren't the ones it made smaller any more.
        val current = here?.pages.orEmpty()
        val samePages = current.map(StoredFile::sha256) == incoming.map(StoredFile::sha256)
        return BinderAttachment(
            id = id, title = dto.title, fileName = dto.fileName,
            // Kept as the archive has it: a kind from a newer build reads as other.
            kind = dto.kind, contentType = dto.contentType, byteCount = dto.byteCount,
            sha256 = dto.sha256 ?: original?.sha256, file = original,
            pages = if (samePages) current else incoming,
            thumbnail = dto.thumbnailPath?.let(pack.files::file),
            // A backup brings no card number into a document's text: the unit that writes it masks it.
            extractedText = dto.extractedText, documentDay = dto.documentDate, validUntil = dto.validUntil,
            framing = dto.framing, isArchived = dto.isArchived, supersededById = here?.supersededById,
            createdAt = clamped(dto.createdAt), isExample = dto.isExample,
            assetId = link(dto.assetId, assets), obligationId = link(dto.obligationId, obligations),
            historyEntryId = link(dto.historyEntryId, entries), serviceItemId = link(dto.serviceItemId, items),
            measurementId = link(dto.measurementId, readings), providerId = link(dto.providerId, providers),
            updatedAt = changeTime(dto.updatedAt),
            compactedAt = if (samePages || current.isEmpty()) here?.compactedAt else null,
        )
    }

    /**
     * What capture learned of each issuer's papers. A lesson whose label isn't shaped like one stays out, whatever the
     * backup says.
     */
    private fun importIssuerLessons() {
        for (dto in pack.issuerLessons.filter { LessonRules.isLabelShaped(it.label) }) {
            val named = dto.issuerKey.isNotEmpty() && dto.kind.isNotEmpty() && dto.field.isNotEmpty()
            val id = Ids.parse(dto.id)?.takeIf { named }
                ?: throw ArchiveError.BrokenReference(DossierV3.Path.ISSUER_LESSONS)
            if (place(id, dto.updatedAt, lessons) == Placement.Keep) continue
            lessons.write(
                BinderIssuerLesson(
                    // Kept as the archive has it: a kind from a newer build stays, unread.
                    id = id, issuerKey = dto.issuerKey, issuerName = dto.issuerName, kind = dto.kind, field = dto.field,
                    label = dto.label, categoryKey = dto.categoryKey, createdAt = clamped(dto.createdAt),
                    updatedAt = changeTime(dto.updatedAt),
                ),
            )
        }
    }

    /** The lessons that contradict each other once the import is in, of those the binder keeps. */
    private fun dropContradictedLessons(removed: Set<UUID>): Set<UUID> = LessonRules.contradicted(
        lessons.byKey.values.filter {
            it.id !in removed
        }.map { LessonRules.Lesson(it.id, it.issuerKey, it.kind, it.field, it.label) },
    )

    // Replace

    /**
     * "Înlocuiește tot", once every record of the archive is written: what the phone has and the archive doesn't goes.
     */
    private fun whatTheArchiveLacks(): Removed {
        fun <K, R> lacking(table: Table<K, R>): Set<K> = table.onThePhone.filter { it !in table.kept }.toSet()
        return Removed(
            templates = lacking(templates), assets = lacking(assets), obligations = lacking(obligations),
            historyEntries = lacking(entries), serviceItems = lacking(items), providers = lacking(providers),
            measurements = lacking(readings), attachments = lacking(documents), issuerLessons = lacking(lessons),
        )
    }

    private companion object {
        /** What a page of a section shows when nothing else is said. */
        val STANDARD_POCKETS = listOf("upcoming", "documents", "history", "people", "money", "keyFacts")
        const val LAST_MINUTE_OF_DAY = 24 * 60 - 1
        const val HALF_A_DAY = 12L * 60 * 60

        fun emptyFacts() = KeptList.made(emptyList(), CustomFact.codec, CustomFact::id)

        fun emptyComponents() = KeptList.made(emptyList(), ComponentDefinition.codec, ComponentDefinition::key)
    }
}

/**
 * What stays as this phone has it, whatever the archive says, as the iOS importer's
 * `PhoneKeeps`. Read before anything changes, so replacing everything keeps it too.
 */
internal class PhoneKeeps private constructor(
    /** Category key → whether it is locked here. */
    private val locks: Map<String, Boolean>,
    /** Category key → its fields that are secret or sensitive here, for a definition the archive gives. */
    private val guardedFields: Map<String, Map<String, FieldDefinition>>,
    /** Section id → its sealed values, read or not. */
    val secrets: Map<UUID, FieldValues>,
    /** Section id → its secret rows as stored here, read or not. */
    val secretFacts: Map<UUID, KeptList<CustomFact>>,
) {
    /** A category's lock after the import: on if it was on here or in the archive. */
    fun lock(key: String, archive: Boolean, fallback: Boolean): Boolean = archive || (locks[key] ?: fallback)

    /** A category's fields with every field locked here kept locked. */
    fun guarding(key: String, sections: List<FieldSection>): List<FieldSection> {
        val guarded = guardedFields[key] ?: return sections
        return sections.map { section ->
            section.copy(
                fields = section.fields.map { field ->
                    val here = guarded[field.key] ?: return@map field
                    field.copy(
                        type = if (here.isSecret) FieldDefinition.SECRET else field.type,
                        isSensitive = field.isSensitive || here.isSensitive,
                    )
                },
            )
        }
    }

    companion object {
        fun capture(binder: Binder, builtIns: BuiltIns): PhoneKeeps {
            val guarded = HashMap<String, Map<String, FieldDefinition>>()
            for (template in binder.templates) {
                // A built-in's definition is the app's (none to guard); one the archive gives is guarded.
                if (builtIns.definition(template.key) != null) continue
                val fields =
                    template.sections.items.flatMap(FieldSection::fields).filter { it.isSecret || it.isSensitive }
                if (fields.isNotEmpty()) guarded[template.key] = fields.associateBy(FieldDefinition::key)
            }
            val secrets = HashMap<UUID, FieldValues>()
            val secretFacts = HashMap<UUID, KeptList<CustomFact>>()
            for (asset in binder.assets) {
                val sealed = SecretRules.sealedValues(asset.values.value)
                if (sealed != FieldValues()) secrets[asset.id] = sealed
                val facts = SecretRules.secretFacts(asset.customFacts)
                if (facts.items.isNotEmpty() || !facts.isFullyRead) secretFacts[asset.id] = facts
            }
            return PhoneKeeps(binder.locks, guarded, secrets, secretFacts)
        }
    }
}
