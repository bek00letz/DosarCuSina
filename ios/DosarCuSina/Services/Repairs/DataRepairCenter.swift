import Foundation
import Observation
import SwiftData

/// What the repair list shows, what waits as suggestions, and whether the calm prompt has
/// something new to say. The app refreshes it after launch and after every import; the list in
/// Settings, the prompt and Urmează's "Din timp" read it. Nothing here changes data without the
/// owner's tap.
///
/// Corrections (data an earlier version saved wrongly) and suggestions (`DataRepairStep.isSuggestion`:
/// nothing wrong, something the app can now do better) are told apart once, here: corrections go
/// to the repair list and may be announced by the prompt; suggestions never are.
@MainActor
@Observable
final class DataRepairCenter {
    static let shared = DataRepairCenter()

    /// Every correction waiting for the owner, in registry order: the repair list.
    private(set) var pending: [DataRepairFinding] = []
    /// Every suggestion waiting for the owner, in registry order: one calm note in Urmează.
    private(set) var suggestions: [DataRepairFinding] = []
    /// Corrections the prompt hasn't announced yet: the prompt shows while this isn't empty.
    /// Never a suggestion.
    var announcement: [DataRepairFinding] = []

    @ObservationIgnored private let ledger: DataRepairLedger

    init(ledger: DataRepairLedger = .standard) {
        self.ledger = ledger
    }

    /// Runs detection (and the steps that run by themselves). `announce` lets the prompt
    /// speak about corrections it hasn't announced before; the list never announces.
    func refresh(in context: ModelContext, announce: Bool) throws {
        let found = try DataRepairs(context: context, ledger: ledger).detect()
        pending = found.filter { !DataRepairs.isSuggestion($0) }
        suggestions = found.filter(DataRepairs.isSuggestion)
        if announce {
            let new = ledger.unannounced(pending)
            if !new.isEmpty { announcement = new }
        } else {
            seen()
        }
    }

    /// The owner opened the list: nothing pending is news any more.
    func seen() {
        ledger.markAnnounced(pending)
        announcement = []
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext) throws {
        try DataRepairs(context: context, ledger: ledger).apply(findings)
        try refresh(in: context, announce: false)
    }

    func dismiss(_ findings: [DataRepairFinding], in context: ModelContext) throws {
        DataRepairs(context: context, ledger: ledger).dismiss(findings)
        try refresh(in: context, announce: false)
    }

    /// The groups of the repair list: corrections of one kind together, in registry order.
    var groups: [(title: String, findings: [DataRepairFinding])] {
        Self.groups(of: pending)
    }

    /// The groups of the suggestions' page, the same way.
    var suggestionGroups: [(title: String, findings: [DataRepairFinding])] {
        Self.groups(of: suggestions)
    }

    /// What the suggestions are about, for their note: each kind's title once, in registry order.
    var suggestionTopics: [String] {
        suggestionGroups.map(\.title)
    }

    private static func groups(of findings: [DataRepairFinding]) -> [(title: String, findings: [DataRepairFinding])] {
        var order: [String] = []
        var byTitle: [String: [DataRepairFinding]] = [:]
        for finding in findings {
            let title = DataRepairs.step(finding.step).title
            if byTitle[title] == nil { order.append(title) }
            byTitle[title, default: []].append(finding)
        }
        return order.map { ($0, byTitle[$0] ?? []) }
    }
}
