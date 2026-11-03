import Foundation
import Observation
import SwiftData

/// What the repair list shows and whether the calm prompt has something new to say. The
/// app refreshes it after launch and after every import; the list in Settings and the
/// prompt read it. Nothing here changes data without the owner's tap.
@MainActor
@Observable
final class DataRepairCenter {
    static let shared = DataRepairCenter()

    /// Everything waiting for the owner, in registry order.
    private(set) var pending: [DataRepairFinding] = []
    /// Findings the prompt hasn't announced yet: the prompt shows while this isn't empty.
    var announcement: [DataRepairFinding] = []

    @ObservationIgnored private let ledger: DataRepairLedger

    init(ledger: DataRepairLedger = .standard) {
        self.ledger = ledger
    }

    /// Runs detection (and the steps that run by themselves). `announce` lets the prompt
    /// speak about findings it hasn't announced before; the list never announces.
    func refresh(in context: ModelContext, announce: Bool) throws {
        pending = try DataRepairs(context: context, ledger: ledger).detect()
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

    /// The groups of the list: findings of one kind together, in registry order.
    var groups: [(title: String, findings: [DataRepairFinding])] {
        var order: [String] = []
        var byTitle: [String: [DataRepairFinding]] = [:]
        for finding in pending {
            let title = DataRepairs.step(finding.step).title
            if byTitle[title] == nil { order.append(title) }
            byTitle[title, default: []].append(finding)
        }
        return order.map { ($0, byTitle[$0] ?? []) }
    }
}
