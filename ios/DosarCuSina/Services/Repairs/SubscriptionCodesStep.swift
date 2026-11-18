import Foundation
import SwiftData

// MARK: - A subscription's code kept under another code's name

/// Before subscriptions kept the codes their service has (`ServiceKind.Service.codes`), a bill's
/// billing account („Cont de facturare”, „Cont client”) was read and kept as its client code, and
/// a water or heating bill's place code („Cod loc consum”) as a gas CLC or an electricity POD,
/// which a water subscription no longer shows. Since then each code has its own field
/// (`SubscriptionFields.account`, `placeCode`).
///
/// Nothing is guessed from the value alone: a client code and a billing account look alike. A
/// code moves only where the subscription's own papers say what it is: its bills' and contracts'
/// kept text, read again by today's reader (`ContractReader.identifierFields`) and kept as
/// capture keeps it for the subscription's service (`SubscriptionCode.keeping`), names the same
/// value, compared as values are, as exactly one other code the service has, and never under the
/// field it is kept in; and that code's own field is empty or holds the same value. Everything
/// else stays as it is: a subscription typed by hand, a paper whose text is gone, a value two
/// labels claim. It asks first, as every correction does: it changes where a value the person
/// sees is listed.
struct SubscriptionCodesStep: DataRepairStep {
    static let id = DataRepairStepID.subscriptionCodes
    var title: String { String(localized: "Coduri de abonament", comment: "Repair group: a subscription's code kept under another code's name by an earlier version.") }

    struct Candidate {
        let asset: Asset
        /// Where it is kept, and where its papers say it belongs.
        let from: SubscriptionCode
        let to: SubscriptionCode
        let value: String

        var key: String { "\(asset.id.uuidString):\(from.rawValue):\(to.rawValue):\(RomanianText.compact(value))" }
    }

    static func candidates(in context: ModelContext) throws -> [Candidate] {
        let templates = try TemplateStore(context: context).templatesByKey()
        var found: [Candidate] = []
        for asset in try context.fetch(FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.createdAt)])) {
            guard !asset.isExample, templates.plays(.subscription, asset.templateKey),
                  let service = ServiceKind.service(SubscriptionFields.service(of: asset.values)) else { continue }
            let read = codesRead(onPapersOf: asset, service: service.key)
            guard !read.isEmpty else { continue }
            let values = asset.values
            var moves: [Candidate] = []
            for code in SubscriptionCode.allCases {
                guard let kept = values[code.fieldKey]?.textValue, !RomanianText.compact(kept).isEmpty else { continue }
                let readAs = Set(read.filter { $0.value == RomanianText.compact(kept) }.map(\.code))
                guard !readAs.contains(code), readAs.count == 1, let target = readAs.first, service.codes.contains(target) else { continue }
                if let there = values[target.fieldKey]?.textValue, RomanianText.compact(there) != RomanianText.compact(kept) { continue }
                moves.append(Candidate(asset: asset, from: code, to: target, value: kept))
            }
            // Two kept codes said to be the same one: neither is certain.
            let targets = moves.map(\.to)
            found += moves.filter { move in targets.filter { $0 == move.to }.count == 1 }
        }
        return found
    }

    /// The codes the subscription's papers name, read again from their kept text as capture
    /// reads and keeps them for `service`, each value compared as values are.
    static func codesRead(onPapersOf asset: Asset, service: String) -> [(code: SubscriptionCode, value: String)] {
        var papers: [UUID: Attachment] = [:]
        for paper in (asset.attachments ?? []) + (asset.history ?? []).flatMap({ $0.attachments ?? [] }) where !paper.isDeleted {
            papers[paper.id] = paper
        }
        return papers.values.flatMap { paper -> [(code: SubscriptionCode, value: String)] in
            guard let text = paper.extractedText, !text.isEmpty else { return [] }
            return SubscriptionCode.keeping(ContractReader.identifierFields(in: CaptureText(text)), service: service).compactMap { field in
                guard let code = SubscriptionCode(captureKey: field.key), let value = field.value.text else { return nil }
                return (code, RomanianText.compact(value))
            }
        }
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        try Self.candidates(in: scan.context).map { candidate in
            DataRepairFinding(
                id: "\(Self.id.rawValue):\(candidate.key)",
                step: Self.id,
                message: String(localized: "La „\(candidate.asset.name)”, „\(candidate.value)” e păstrat la „\(candidate.from.label)”, dar documentele lui din dosar îl numesc „\(candidate.to.label)”. Îl mut acolo?",
                                comment: "Repair: a subscription's code kept under another code's name by an earlier version (a billing account kept as the client code). The arguments: the subscription, the code, the field it is kept in, the field its papers say."),
                subject: .subscriptionCode(assetID: candidate.asset.id, from: candidate.from.rawValue, to: candidate.to.rawValue)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let approved = Set(findings.compactMap { finding -> String? in
            guard case .subscriptionCode(let id, let from, let to) = finding.subject else { return nil }
            return "\(id.uuidString):\(from):\(to)"
        })
        // Checked again: a code changed since the list was made stays.
        for candidate in try Self.candidates(in: context)
        where approved.contains("\(candidate.asset.id.uuidString):\(candidate.from.rawValue):\(candidate.to.rawValue)") {
            var values = candidate.asset.values
            values[candidate.to.fieldKey] = values[candidate.to.fieldKey] ?? .text(candidate.value)
            values[candidate.from.fieldKey] = nil
            candidate.asset.values = values
        }
    }
}
