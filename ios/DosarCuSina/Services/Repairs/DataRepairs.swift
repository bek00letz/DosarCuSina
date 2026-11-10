import Foundation
import SwiftData

/// The repair list: data an earlier version saved wrongly, found by an ordered registry of
/// steps and changed only with the owner's OK.
///
/// - Every step is idempotent and has a stored id (`DataRepairStepID`); its findings carry
///   ids built from it, so a dismissal is remembered and an applied repair isn't found again.
/// - `detect` runs after the built-in categories are installed at launch and after every
///   import. Steps that only change how a value is stored, never what it says
///   (`runsByItself`), run then; every other step only lists what it would change.
/// - `apply` changes what the owner approved, one finding, or all of one kind, in one
///   `UnitOfWork`, and works hero values out from the readings again.
/// - Both are the app's own steps (`ChangeOrigin.app`), the owner's OK included: what a repair
///   changes keeps its change time, so a copy changed by the person on another phone still
///   comes in with "Adaugă", and the list finds the repair again after that import.
@MainActor
struct DataRepairs {
    let context: ModelContext
    var calendar: Calendar = .dosar
    var ledger: DataRepairLedger = .standard

    /// The registry, in the order the steps run. A new repair is a new step at the end.
    static let steps: [any DataRepairStep] = [
        ChoiceKeysStep(),
        FirstVersionDeadlinesStep(),
        StaleDocumentLinksStep(),
        VisitsWithoutInvoiceStep(),
        DuplicateProvidersStep(),
        DoubleCompletionsStep(),
        CounterOutliersStep(),
        EstimatedVisitReadingsStep(),
        HeroFromReadingsStep(),
        CascoInRCAFieldsStep(),
        HomePolicyWithoutDeadlineStep(),
        TravelCutoffStep(),
        HomePolicySetsStep(),
        UnitKeysStep(),
        PolicyNumberPartsStep(),
        BillNumbersStep(),
        SameBillTwiceStep(),
        CardNumbersStep(),
    ]

    static func step(_ id: DataRepairStepID) -> any DataRepairStep {
        steps.first { type(of: $0).id == id }!
    }

    /// Runs the steps that change nothing anyone sees, then lists what waits for the owner,
    /// leaving out what they chose to leave as it is.
    func detect() throws -> [DataRepairFinding] {
        try UnitOfWork.perform(in: context, origin: .app) {
            for step in Self.steps where step.runsByItself { try step.runByItself(in: context) }
        }
        var scan = DataRepairScan(context: context, calendar: calendar)
        var found: [DataRepairFinding] = []
        for step in Self.steps where !step.runsByItself {
            found += try step.findings(&scan)
        }
        let dismissed = ledger.dismissed
        return found.filter { !dismissed.contains($0.id) }
    }

    /// Makes the approved changes, in one step: all of them, or none.
    func apply(_ findings: [DataRepairFinding]) throws {
        // A finding that only says what to do changes nothing.
        let findings = findings.filter(\.isFixable)
        guard !findings.isEmpty else { return }
        let byStep = Dictionary(grouping: findings, by: \.step)
        try UnitOfWork.perform(in: context, origin: .app) {
            for step in Self.steps {
                guard let mine = byStep[type(of: step).id], !mine.isEmpty else { continue }
                try step.apply(mine, in: context, calendar: calendar)
            }
            try UnitOfWork.save(context)
        }
    }

    /// "Lasă așa": remembered, so the finding isn't offered again.
    func dismiss(_ findings: [DataRepairFinding]) {
        ledger.dismiss(findings.map(\.id))
    }
}

/// The stored ids of the registry's steps. Never renamed: dismissals are kept by them.
enum DataRepairStepID: String, CaseIterable, Sendable, Hashable {
    case choiceKeys = "choice-keys"
    case firstVersionDeadlines = "first-version-deadlines"
    case staleDocumentLinks = "stale-document-links"
    case visitsWithoutInvoice = "visits-without-invoice"
    case duplicateProviders = "duplicate-providers"
    case doubleCompletions = "double-completions"
    case counterOutliers = "counter-outliers"
    case estimatedVisitReadings = "estimated-visit-readings"
    case heroFromReadings = "hero-from-readings"
    case cascoInRCAFields = "casco-in-rca-fields"
    case homePolicyWithoutDeadline = "home-policy-without-deadline"
    case travelCutoff = "travel-cutoff"
    case homePolicySets = "home-policy-sets"
    case unitKeys = "unit-keys"
    case policyNumberParts = "policy-number-parts"
    case billNumbers = "bill-numbers"
    case sameBillTwice = "same-bill-twice"
    case cardNumbers = "card-numbers"
}

/// One thing a repair would change, in plain words, with what applying it needs.
struct DataRepairFinding: Identifiable, Hashable, Sendable {
    /// `<step>:<record>:<value>`: the same finding keeps its id; a new value makes a new one.
    let id: String
    let step: DataRepairStepID
    /// What looks wrong and what the repair does, as a question: "Kilometrajul la VW Golf
    /// pare greșit: 457 km. Corectez la 45.724?"
    let message: String
    let subject: Subject
    /// The repair can make the change. When false the finding only says what the person
    /// can do (read a policy again), and "Am înțeles" puts it away.
    var isFixable = true

    enum Subject: Hashable, Sendable {
        case blueprint(obligationID: UUID, blueprintKey: String)
        case staleLinks(CaptureRepairs.StaleDocumentLinks)
        case visitInvoice(CaptureRepairs.VisitWithoutInvoice)
        case duplicateProviders(CaptureRepairs.DuplicateProviders)
        case doubleCompletion(LikelyDoubleCompletions.Candidate)
        /// A wrong reading: corrected to `to`, or removed when nil.
        case reading(logID: UUID, value: Double, to: Double?)
        /// A visit's estimated reading: the reading goes, the visit stays.
        case estimatedVisitReading(entryID: UUID, value: Double)
        /// The hero value worked out from the readings again.
        case hero(assetID: UUID, from: Double?, to: Double)
        /// A car's RCA fields hold the facts of a CASCO policy filed on it: they move to CASCO's.
        case cascoInRCA(assetID: UUID, policyNumber: String)
        /// A home policy filed without its deadline: the deadline is made on the policy's end.
        case homePolicyDeadline(assetID: UUID, attachmentID: UUID, blueprintKey: String, day: CalendarDay)
        /// A deadline gets its document type's travel margin and the leads counted from it.
        case travelCutoff(obligationID: UUID, marginDays: Int)
        /// A home's policy facts, kept where PAD's are, move to its optional policy's.
        case homePolicySet(assetID: UUID, policyNumber: String)
        /// A policy number kept with only its series: completed to `to`, when the filed policy gives it.
        case policyNumberParts(assetID: UUID, field: String, to: String?)
        /// The same bill logged more than once in a subscription's history: `merge` join `keep`.
        case sameBill(keep: UUID, merge: [UUID])
        /// A record whose words hold a whole card number: kept as its last four digits.
        case cardNumbers(RecordRef)
    }
}

/// A step of the registry.
@MainActor
protocol DataRepairStep {
    static var id: DataRepairStepID { get }
    /// What a group of these findings is called in the list: "Kilometraj și contoare".
    var title: String { get }
    /// Changes only how something is stored, never what it says: runs without asking.
    var runsByItself: Bool { get }
    func runByItself(in context: ModelContext) throws
    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding]
    /// Applies approved findings without saving. Checks each one again first, so a finding
    /// that no longer holds changes nothing.
    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws
}

extension DataRepairStep {
    var runsByItself: Bool { false }
    func runByItself(in context: ModelContext) throws {}
    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] { [] }
    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {}
}

/// What one detection pass knows so far, so a later step doesn't offer a second repair for
/// what an earlier one already covers (a reading corrected doesn't also fix its hero value).
struct DataRepairScan {
    let context: ModelContext
    let calendar: Calendar
    var flaggedReadings = Set<UUID>()
    var flaggedAssets = Set<UUID>()
}

/// What the owner chose to leave as it is, and what the calm prompt already announced.
/// Kept on this phone: a repair is about this phone's data.
struct DataRepairLedger {
    let defaults: UserDefaults
    private static let dismissedKey = "dataRepairs.dismissed"
    private static let announcedKey = "dataRepairs.announced"

    static var standard: DataRepairLedger { DataRepairLedger(defaults: .standard) }

    var dismissed: Set<String> { Set(defaults.stringArray(forKey: Self.dismissedKey) ?? []) }
    var announced: Set<String> { Set(defaults.stringArray(forKey: Self.announcedKey) ?? []) }

    func dismiss(_ ids: [String]) {
        defaults.set(Array(dismissed.union(ids)).sorted(), forKey: Self.dismissedKey)
    }

    /// The findings the prompt hasn't announced yet; marks them announced.
    func unannounced(_ findings: [DataRepairFinding]) -> [DataRepairFinding] {
        let known = announced
        let new = findings.filter { !known.contains($0.id) }
        guard !new.isEmpty else { return [] }
        // Only what is still pending is kept, so the list never grows without end.
        defaults.set(Array(known.intersection(findings.map(\.id)).union(new.map(\.id))).sorted(), forKey: Self.announcedKey)
        return new
    }

    func markAnnounced(_ findings: [DataRepairFinding]) {
        defaults.set(Array(announced.union(findings.map(\.id))).sorted(), forKey: Self.announcedKey)
    }
}
