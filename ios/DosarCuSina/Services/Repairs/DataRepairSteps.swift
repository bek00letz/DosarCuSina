import Foundation
import SwiftData

// The registry's steps, in `DataRepairs.steps` order. Each says what looks wrong in plain
// words and changes only what was approved.

// MARK: - Choice keys (runs by itself)

/// Choice values stored as display text (from builds before option keys) become option
/// keys. What the person sees doesn't change, so it runs without asking.
struct ChoiceKeysStep: DataRepairStep {
    static let id = DataRepairStepID.choiceKeys
    var title: String { String(localized: "Alegeri salvate ca text", comment: "Repair group: choice values from older builds.") }
    var runsByItself: Bool { true }

    /// How many sections changed.
    @discardableResult
    func migrate(in context: ModelContext) throws -> Int {
        let templates = try TemplateStore(context: context).templatesByKey()
        var changed = 0
        for asset in try context.fetch(FetchDescriptor<Asset>()) {
            guard let definition = templates[asset.templateKey]?.definition ?? BuiltInTemplates.definition(for: asset.templateKey) else { continue }
            let values = asset.values
            let normalized = values.normalizingChoices(for: definition)
            if normalized != values {
                asset.valuesData = StoredJSON.encode(normalized)
                changed += 1
            }
        }
        return changed
    }

    func runByItself(in context: ModelContext) throws {
        try migrate(in: context)
    }
}

// MARK: - Deadlines from a first-version copy

/// Deadlines brought from a first-version backup have no blueprint and a plain interval:
/// an ITP doesn't follow the legal rule (counted by the car's age), and nothing keyed by
/// the blueprint (what to bring, the policy facts) finds them. One whose title and kind
/// match one of its category's blueprints gets that blueprint and its rule.
struct FirstVersionDeadlinesStep: DataRepairStep {
    static let id = DataRepairStepID.firstVersionDeadlines
    var title: String { String(localized: "Termene din copii vechi", comment: "Repair group: deadlines imported from a first-version backup.") }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        let templates = try TemplateStore(context: scan.context).templatesByKey()
        return try scan.context.fetch(FetchDescriptor<Obligation>()).compactMap { obligation in
            guard let blueprint = Self.blueprint(for: obligation, templates: templates), let asset = obligation.asset else { return nil }
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(obligation.id.uuidString):\(blueprint.key)",
                step: Self.id,
                message: String(localized: "„\(obligation.title)” la \(asset.name) a venit dintr-o copie veche, fără regula lui. Îi pun regula obișnuită?", comment: "Repair: a deadline from a first-version backup gets its blueprint and rule."),
                subject: .blueprint(obligationID: obligation.id, blueprintKey: blueprint.key)
            )
        }
    }

    /// The blueprint a blueprint-less deadline still running is: same kind and the same
    /// title, and not already used by another deadline of the same section.
    static func blueprint(for obligation: Obligation, templates: [String: CategoryTemplate]) -> ObligationBlueprint? {
        guard obligation.blueprintKey == nil, obligation.status == .active || obligation.status == .paused, !obligation.isExample,
              let asset = obligation.asset, let template = templates[asset.templateKey] else { return nil }
        let title = SearchText.normalize(obligation.title)
        let used = Set((asset.obligations ?? []).compactMap(\.blueprintKey))
        return template.blueprints.first {
            $0.kind == obligation.kind && SearchText.normalize($0.title) == title && !used.contains($0.key)
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let templates = try TemplateStore(context: context).templatesByKey()
        let obligations = Dictionary(try context.fetch(FetchDescriptor<Obligation>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for finding in findings {
            guard case .blueprint(let id, let key) = finding.subject, let obligation = obligations[id],
                  let blueprint = Self.blueprint(for: obligation, templates: templates), blueprint.key == key else { continue }
            obligation.blueprintKey = blueprint.key
            obligation.recurrence = blueprint.recurrence
            obligation.updatedAt = Date()
        }
    }
}

// MARK: - Capture repairs

/// Documents moved here that still point at another section's deadline or visit.
struct StaleDocumentLinksStep: DataRepairStep {
    static let id = DataRepairStepID.staleDocumentLinks
    var title: String { String(localized: "Acte mutate", comment: "Repair group: documents moved with their old links.") }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        let documents = Dictionary(try scan.context.fetch(FetchDescriptor<Attachment>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return try CaptureRepairs(context: scan.context).staleDocumentLinkCandidates().map { candidate in
            let document = documents[candidate.attachmentID]
            let name = document?.title ?? document?.fileName ?? ""
            let place = document?.asset?.name ?? ""
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(candidate.attachmentID.uuidString)",
                step: Self.id,
                message: String(localized: "„\(name)” din \(place) e încă legat de locul de unde l-ai mutat. Îl dezleg de acolo?", comment: "Repair: a moved document keeps links to its old place."),
                subject: .staleLinks(candidate)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let approved = findings.compactMap { if case .staleLinks(let candidate) = $0.subject { candidate } else { nil } }
        try CaptureRepairs(context: context).dropStaleDocumentLinks(approved)
    }
}

/// Visits saved without their invoice, while the one invoice that fits sits loose beside them.
struct VisitsWithoutInvoiceStep: DataRepairStep {
    static let id = DataRepairStepID.visitsWithoutInvoice
    var title: String { String(localized: "Vizite fără factură", comment: "Repair group: visits saved without their invoice.") }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        let entries = Dictionary(try scan.context.fetch(FetchDescriptor<HistoryEntry>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return try CaptureRepairs(context: scan.context).visitsWithoutInvoiceCandidates(calendar: scan.calendar).map { candidate in
            let entry = entries[candidate.visitID]
            let day = entry.map { DosarFormat.day($0.occurredAt, calendar: scan.calendar) } ?? ""
            let place = entry?.asset?.name ?? ""
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(candidate.visitID.uuidString):\(candidate.invoiceID.uuidString)",
                step: Self.id,
                message: String(localized: "Vizita din \(day) la \(place) s-a salvat fără factura ei, care e alături. O leg de vizită?", comment: "Repair: a visit saved without its invoice."),
                subject: .visitInvoice(candidate)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let approved = findings.compactMap { if case .visitInvoice(let candidate) = $0.subject { candidate } else { nil } }
        try CaptureRepairs(context: context).linkInvoices(approved)
    }
}

/// The same firm kept twice.
struct DuplicateProvidersStep: DataRepairStep {
    static let id = DataRepairStepID.duplicateProviders
    var title: String { String(localized: "Firme salvate de mai multe ori", comment: "Repair group: the same firm kept twice.") }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        let providers = Dictionary(try scan.context.fetch(FetchDescriptor<Provider>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return try CaptureRepairs(context: scan.context).duplicateProviderCandidates().map { group in
            let name = providers[group.keptID]?.name ?? ""
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(group.keptID.uuidString):\(group.duplicateIDs.map(\.uuidString).sorted().joined(separator: ","))",
                step: Self.id,
                message: String(localized: "„\(name)” apare de mai multe ori în Agendă (același nume sau același CUI). Le unesc într-una?", comment: "Repair: the same firm kept twice."),
                subject: .duplicateProviders(group)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let approved = findings.compactMap { if case .duplicateProviders(let group) = $0.subject { group } else { nil } }
        try CaptureRepairs(context: context).mergeDuplicateProviders(approved)
    }
}

// MARK: - Deadlines closed twice

/// Deadlines an old reminder button may have closed twice.
struct DoubleCompletionsStep: DataRepairStep {
    static let id = DataRepairStepID.doubleCompletions
    var title: String { String(localized: "Termene închise de două ori", comment: "Repair group: deadlines an old reminder may have closed twice.") }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        let obligations = Dictionary(try scan.context.fetch(FetchDescriptor<Obligation>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return try LikelyDoubleCompletions.find(in: scan.context, calendar: scan.calendar).map { candidate in
            let obligation = obligations[candidate.obligationId]
            let title = obligation?.title ?? ""
            let place = obligation?.asset?.name ?? ""
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(candidate.historyEntryId.uuidString)",
                step: Self.id,
                message: String(localized: "„\(title)” la \(place) pare închis de două ori, la câteva zile distanță. Anulez a doua oară?", comment: "Repair: a deadline closed twice by an old reminder."),
                subject: .doubleCompletion(candidate)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        for finding in findings {
            guard case .doubleCompletion(let candidate) = finding.subject else { continue }
            try LikelyDoubleCompletions.undoSecond(candidate, in: context, calendar: calendar)
        }
    }
}

// MARK: - Counter readings

/// Words for a counter, by its unit.
enum CounterWording {
    /// "Kilometrajul la VW Golf" or "Contorul la Apartament".
    static func subject(unit: String, asset: String) -> String {
        unit == "km"
            ? String(localized: "Kilometrajul la \(asset)", comment: "Repair: the subject of a kilometre reading.")
            : String(localized: "Contorul la \(asset)", comment: "Repair: the subject of another counter reading.")
    }

    static func amount(_ value: Double, unit: String) -> String {
        let number = RomanianNumber.format(Decimal(value), fractionDigits: 0...1)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

/// Counter readings 10 or more times off both their neighbours, or equal to a neighbour
/// divided by a power of ten (457 next to 45724: the number lost its thousands).
struct CounterOutliersStep: DataRepairStep {
    static let id = DataRepairStepID.counterOutliers
    var title: String { String(localized: "Kilometraj și contoare", comment: "Repair group: counter readings that look wrong.") }

    /// What a series says about one reading: corrected to a neighbour, removed, or fine.
    enum Verdict: Equatable {
        case correct(to: Double)
        case remove
    }

    /// The verdict for each reading of one counter, oldest first. A reading that lost its
    /// digits is lower than the one before it (a counter only goes up), so a small first
    /// reading of a new car next to a later, larger one is never offered.
    static func verdicts(_ values: [Double]) -> [Int: Verdict] {
        var found: [Int: Verdict] = [:]
        for index in values.indices {
            let value = values[index]
            let neighbours = [index - 1, index + 1].filter(values.indices.contains).map { values[$0] }
            let breaksOrder = index > 0 && value < values[index - 1]
            if breaksOrder, let source = neighbours.first(where: { lostDigits(value, of: $0) }) {
                found[index] = .correct(to: source)
            } else if neighbours.count == 2, neighbours.allSatisfy({ $0 > 0 }),
                      neighbours.allSatisfy({ value >= $0 * 10 }) || neighbours.allSatisfy({ value * 10 <= $0 }) {
                found[index] = .remove
            }
        }
        return found
    }

    /// Whether `value` is `neighbour` with its last digits lost: 457 for 45724 (÷100).
    static func lostDigits(_ value: Double, of neighbour: Double) -> Bool {
        guard value > 0, neighbour >= value * 10 else { return false }
        var divisor = 10.0
        while divisor <= 1_000_000, neighbour / divisor >= 1 {
            let shrunk = neighbour / divisor
            if value == shrunk.rounded(.down) || value == shrunk.rounded() || abs(value - shrunk) < 0.05 { return true }
            divisor *= 10
        }
        return false
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        var found: [DataRepairFinding] = []
        for asset in try scan.context.fetch(FetchDescriptor<Asset>()) where !asset.isExample {
            let counters = (asset.measurements ?? []).filter { $0.kind.isCumulative }
            for (unit, logs) in Dictionary(grouping: counters, by: \.unit) {
                let ordered = logs.sorted { ($0.recordedAt, $0.value) < ($1.recordedAt, $1.value) }
                for (index, verdict) in Self.verdicts(ordered.map(\.value)).sorted(by: { $0.key < $1.key }) {
                    let log = ordered[index]
                    let subject = CounterWording.subject(unit: unit, asset: asset.name)
                    let shown = CounterWording.amount(log.value, unit: unit)
                    let message: String
                    let target: Double?
                    switch verdict {
                    case .correct(let to):
                        target = to
                        let corrected = RomanianNumber.format(Decimal(to), fractionDigits: 0...1)
                        message = String(localized: "\(subject) pare greșit: \(shown). Corectez la \(corrected)?", comment: "Repair: a reading that lost its last digits, with the corrected value.")
                    case .remove:
                        target = nil
                        let day = DosarFormat.day(log.recordedAt, calendar: scan.calendar)
                        message = String(localized: "\(subject) pare greșit: \(shown), pe \(day). Îl scot din citiri?", comment: "Repair: a reading ten times off its neighbours.")
                    }
                    scan.flaggedReadings.insert(log.id)
                    scan.flaggedAssets.insert(asset.id)
                    found.append(DataRepairFinding(
                        id: "\(Self.id.rawValue):\(log.id.uuidString):\(log.value)",
                        step: Self.id, message: message,
                        subject: .reading(logID: log.id, value: log.value, to: target)
                    ))
                }
            }
        }
        return found
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let logs = Dictionary(try context.fetch(FetchDescriptor<MeasurementLog>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var touched: [UUID: Asset] = [:]
        for finding in findings {
            guard case .reading(let id, let value, let target) = finding.subject,
                  let log = logs[id], !log.isDeleted, log.value == value, let asset = log.asset else { continue }
            if let target {
                // The visit that logged the wrong number gets the right one too.
                for entry in asset.history ?? [] where entry.occurredAt == log.recordedAt && entry.metricReading == value {
                    entry.metricReading = target
                }
                log.value = target
            } else {
                HouseholdMutations.removeReading(log, from: asset, in: context)
            }
            touched[asset.id] = asset
        }
        for asset in touched.values { HouseholdMutations.syncHeroMetric(of: asset, in: context) }
    }
}

/// Visit readings that look like the visit form's old estimate: a round hundred above the
/// next real reading. The form used to save its guess when nobody changed it.
struct EstimatedVisitReadingsStep: DataRepairStep {
    static let id = DataRepairStepID.estimatedVisitReadings
    var title: String { String(localized: "Estimări salvate ca citiri", comment: "Repair group: visit readings that were the form's estimate.") }

    /// The visit's reading log, when it looks like an estimate: a whole hundred, and the
    /// next reading after the visit is lower.
    static func estimatedLog(for entry: HistoryEntry) -> MeasurementLog? {
        guard entry.obligation == nil, let reading = entry.metricReading, reading > 0,
              reading.truncatingRemainder(dividingBy: 100) == 0, let asset = entry.asset else { return nil }
        let logs = (asset.measurements ?? []).filter { !$0.isDeleted && $0.kind.isCumulative }
        guard let log = logs.first(where: { $0.recordedAt == entry.occurredAt && $0.value == reading }) else { return nil }
        let next = logs.filter { $0.unit == log.unit && $0.recordedAt > log.recordedAt }.min { $0.recordedAt < $1.recordedAt }
        guard let next, next.value < reading else { return nil }
        return log
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        var found: [DataRepairFinding] = []
        for entry in try scan.context.fetch(FetchDescriptor<HistoryEntry>()) where !entry.isExample {
            guard let log = Self.estimatedLog(for: entry), !scan.flaggedReadings.contains(log.id), let asset = entry.asset else { continue }
            scan.flaggedReadings.insert(log.id)
            scan.flaggedAssets.insert(asset.id)
            let subject = CounterWording.subject(unit: log.unit, asset: asset.name)
            let shown = CounterWording.amount(log.value, unit: log.unit)
            let day = DosarFormat.day(entry.occurredAt, calendar: scan.calendar)
            found.append(DataRepairFinding(
                id: "\(Self.id.rawValue):\(entry.id.uuidString):\(log.value)",
                step: Self.id,
                message: String(localized: "\(subject) la vizita din \(day), \(shown), pare o estimare: e mai mare decât citirea de după. O scot din citiri?", comment: "Repair: a visit reading that was the form's estimate."),
                subject: .estimatedVisitReading(entryID: entry.id, value: log.value)
            ))
        }
        return found
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let entries = Dictionary(try context.fetch(FetchDescriptor<HistoryEntry>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for finding in findings {
            guard case .estimatedVisitReading(let id, let value) = finding.subject, let entry = entries[id],
                  let log = Self.estimatedLog(for: entry), log.value == value, let asset = entry.asset else { continue }
            HouseholdMutations.removeReading(log, from: asset, in: context)
            HouseholdMutations.syncHeroMetric(of: asset, in: context)
        }
    }
}

/// A hero value (the kilometres on the section) that isn't what the readings say, after an
/// earlier version saved it wrongly: worked out from the readings again.
struct HeroFromReadingsStep: DataRepairStep {
    static let id = DataRepairStepID.heroFromReadings
    var title: String { String(localized: "Kilometraj și contoare", comment: "Repair group: counter readings that look wrong.") }

    /// The hero field's value and what the readings say it should be, when they differ.
    static func mismatch(of asset: Asset, templates: [String: CategoryTemplate]) -> (field: FieldDefinition, shown: Double?, current: Double)? {
        guard let template = templates[asset.templateKey],
              let field = HouseholdMutations.heroMetricField(of: template.definition),
              let current = HouseholdMutations.readingSeries(of: asset, unit: field.unit).current else { return nil }
        let shown = asset.values[field.key]?.numberValue
        return shown == current ? nil : (field, shown, current)
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        let templates = try TemplateStore(context: scan.context).templatesByKey()
        return try scan.context.fetch(FetchDescriptor<Asset>()).compactMap { asset in
            guard !asset.isExample, !scan.flaggedAssets.contains(asset.id),
                  let mismatch = Self.mismatch(of: asset, templates: templates) else { return nil }
            let unit = mismatch.field.unit ?? ""
            let subject = CounterWording.subject(unit: unit, asset: asset.name)
            let corrected = RomanianNumber.format(Decimal(mismatch.current), fractionDigits: 0...1)
            let message: String
            if let shown = mismatch.shown {
                message = String(localized: "\(subject) pare greșit: \(CounterWording.amount(shown, unit: unit)). Corectez la \(corrected)?", comment: "Repair: the section's counter differs from its readings, with the corrected value.")
            } else {
                message = String(localized: "\(subject) lipsește, deși are citiri. Pun \(corrected)?", comment: "Repair: the section's counter is empty though it has readings.")
            }
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(asset.id.uuidString):\(mismatch.shown ?? -1):\(mismatch.current)",
                step: Self.id, message: message,
                subject: .hero(assetID: asset.id, from: mismatch.shown, to: mismatch.current)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let assets = Dictionary(try context.fetch(FetchDescriptor<Asset>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for finding in findings {
            guard case .hero(let id, let from, let to) = finding.subject, let asset = assets[id] else { continue }
            let templates = try TemplateStore(context: context).templatesByKey()
            guard let mismatch = Self.mismatch(of: asset, templates: templates), mismatch.shown == from, mismatch.current == to else { continue }
            HouseholdMutations.syncHeroMetric(of: asset, in: context)
        }
    }
}
