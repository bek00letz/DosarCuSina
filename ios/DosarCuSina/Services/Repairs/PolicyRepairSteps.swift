import Foundation
import SwiftData

// Policies an earlier version filed wrongly, found from the policies themselves (their
// read text) and changed only with the owner's OK.

// MARK: - CASCO facts in a car's RCA fields

/// A car whose RCA fields hold a CASCO policy's facts: a CASCO policy filed on the car
/// carries the number its RCA field shows. Earlier versions could file a CASCO read as
/// an RCA into RCA's fields. The repair moves the insurer, the number and the claims
/// phone to the fields CASCO keeps (`BlueprintFacts`), filling only what CASCO lacks.
struct CascoInRCAFieldsStep: DataRepairStep {
    static let id = DataRepairStepID.cascoInRCAFields
    var title: String { String(localized: "Polițe CASCO trecute la RCA", comment: "Repair group: CASCO facts kept in a car's RCA fields.") }

    struct Candidate {
        let asset: Asset
        let number: String
        let rca: BlueprintFacts
        let casco: BlueprintFacts
    }

    static func candidates(in context: ModelContext) throws -> [Candidate] {
        let templates = try TemplateStore(context: context).templatesByKey()
        return try context.fetch(FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.createdAt)])).compactMap { asset in
            guard !asset.isExample, let template = templates[asset.templateKey]?.definition,
                  let rca = template.blueprints.first(where: { $0.key == BuiltInBlueprints.vehicleRCA })?.facts,
                  let casco = template.blueprints.first(where: { $0.key == BuiltInBlueprints.vehicleCASCO })?.facts,
                  let field = rca.policyNumber, let number = asset.values[field]?.textValue else { return nil }
            let wanted = RomanianText.compact(number)
            guard wanted.count >= 4 else { return nil }
            // A CASCO policy on the car, and only CASCO (a page that also names RCA could be either).
            let filedAsCasco = (asset.attachments ?? []).contains { attachment in
                guard attachment.kind == .policy, let text = attachment.extractedText else { return false }
                return InsuranceCover.read(in: text, among: [InsuranceCover.casco]) != nil
                    && InsuranceCover.read(in: text, among: [InsuranceCover.rca]) == nil
                    && RomanianText.compact(text).contains(wanted)
            }
            return filedAsCasco ? Candidate(asset: asset, number: number, rca: rca, casco: casco) : nil
        }
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        try Self.candidates(in: scan.context).map { candidate in
            DataRepairFinding(
                id: "\(Self.id.rawValue):\(candidate.asset.id.uuidString):\(candidate.number)",
                step: Self.id,
                message: String(localized: "La \(candidate.asset.name), numărul \(candidate.number) e de pe polița CASCO, dar stă la RCA. Îl mut la CASCO, cu asigurătorul și telefonul de daune?",
                                comment: "Repair: a CASCO policy's facts kept in a car's RCA fields."),
                subject: .cascoInRCA(assetID: candidate.asset.id, policyNumber: candidate.number)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let approved = Set(findings.compactMap { finding -> String? in
            guard case .cascoInRCA(let id, let number) = finding.subject else { return nil }
            return "\(id.uuidString):\(number)"
        })
        for candidate in try Self.candidates(in: context) where approved.contains("\(candidate.asset.id.uuidString):\(candidate.number)") {
            var values = candidate.asset.values
            // Only the facts CASCO keeps move; one it doesn't keep (who RCA insures) stays.
            for role in BlueprintFactRole.allCases {
                guard let from = candidate.rca.field(for: role), let value = values[from], let to = candidate.casco.field(for: role) else { continue }
                if values[to] == nil { values[to] = value }
                values[from] = nil
            }
            candidate.asset.values = values
        }
    }
}

// MARK: - Home policies without their deadline

/// A home policy filed without a deadline: earlier versions made one only for a PAD,
/// so a home's optional policy was kept with no reminder. The policy's own text says
/// when it ends; the repair adds its deadline ("Adaugă termenul") on that day, while it
/// is still ahead.
struct HomePolicyWithoutDeadlineStep: DataRepairStep {
    static let id = DataRepairStepID.homePolicyWithoutDeadline
    var title: String { String(localized: "Polițe fără termen", comment: "Repair group: home policies kept without their deadline.") }

    struct Candidate {
        let asset: Asset
        let attachment: Attachment
        let blueprint: ObligationBlueprint
        let day: CalendarDay
    }

    static func candidates(in context: ModelContext, calendar: Calendar) throws -> [Candidate] {
        let templates = try TemplateStore(context: context).templatesByKey()
        let now = Date()
        let today = CalendarDay(now, calendar: calendar)
        let analyzer = CaptureAnalyzer()
        var found: [Candidate] = []
        for asset in try context.fetch(FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.createdAt)])) {
            guard !asset.isExample, templates.plays(.home, asset.templateKey), let template = templates[asset.templateKey]?.definition else { continue }
            let running = Set((asset.obligations ?? []).filter { $0.status == .active || $0.status == .paused }.compactMap(\.blueprintKey))
            for attachment in (asset.attachments ?? []).sorted(by: { $0.createdAt > $1.createdAt }) {
                guard attachment.kind == .policy, attachment.obligation == nil, !attachment.isArchived, !attachment.isExample,
                      let text = attachment.extractedText,
                      // A car's policy filed under the home isn't the home's.
                      InsuranceCover.read(in: text, among: [InsuranceCover.rca, InsuranceCover.casco]) == nil else { continue }
                let cover = InsuranceCover.read(in: text, among: [InsuranceCover.pad]) ?? InsuranceCover.home
                let key = cover == InsuranceCover.pad ? BuiltInBlueprints.homePAD : BuiltInBlueprints.homeInsurance
                guard !running.contains(key), !found.contains(where: { $0.asset.id == asset.id && $0.blueprint.key == key }),
                      let blueprint = template.blueprints.first(where: { $0.key == key }) else { continue }
                let analysis = analyzer.analyze(text: text, referenceDate: now, as: .insurancePolicy)
                guard let end = analysis.fields.first(where: { $0.key == .expiryDate })?.value.day,
                      blueprint.isWorthScheduling(on: end, today: today, values: asset.values) else { continue }
                found.append(Candidate(asset: asset, attachment: attachment, blueprint: blueprint, day: end))
            }
        }
        return found
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        try Self.candidates(in: scan.context, calendar: scan.calendar).map { candidate in
            let paper = candidate.attachment.displayTitle
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(candidate.attachment.id.uuidString):\(candidate.blueprint.key)",
                step: Self.id,
                message: String(localized: "Polița „\(paper)” de la \(candidate.asset.name) nu are termen. Adaug termenul „\(candidate.blueprint.title)” pe \(DosarFormat.longDay(candidate.day))?",
                                comment: "Repair: a home policy kept without its deadline."),
                subject: .homePolicyDeadline(assetID: candidate.asset.id, attachmentID: candidate.attachment.id,
                                             blueprintKey: candidate.blueprint.key, day: candidate.day)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let approved = Set(findings.compactMap { finding -> String? in
            guard case .homePolicyDeadline(_, let attachment, let key, _) = finding.subject else { return nil }
            return "\(attachment.uuidString):\(key)"
        })
        let today = CalendarDay(Date(), calendar: calendar)
        for candidate in try Self.candidates(in: context, calendar: calendar)
        where approved.contains("\(candidate.attachment.id.uuidString):\(candidate.blueprint.key)") {
            let obligation = try HouseholdMutations.makeObligation(from: candidate.blueprint, for: candidate.asset, firstDue: candidate.day,
                                                                   today: today, calendar: calendar, in: context)
            candidate.attachment.obligation = obligation
            candidate.attachment.validUntil = candidate.day.noonDate(in: calendar)
        }
    }
}

// MARK: - A home's policy facts, kept apart by cover

/// Earlier versions kept one insurer, policy number and claims phone for a home, which its
/// PAD and its optional policy shared. They now stay where PAD keeps them (the PAD
/// deadline's `BlueprintFacts`); this step finds homes whose facts belong to the optional
/// policy:
///
/// - a policy filed on the home that carries the number says which (its deadline, else its
///   text: PAD by name, any other home policy is the optional one);
/// - with no such paper, the home's running deadlines say it when only one of the two runs.
///
/// When the cover can be told and it is the optional policy, the repair moves the facts
/// there, filling only what the optional policy lacks. When it can't be told, the entry asks
/// the owner to check ("Verifică"): applying it moves them, "Lasă așa" keeps them as PAD's.
/// A home whose facts are PAD's, or that already keeps the two apart, isn't listed.
struct HomePolicySetsStep: DataRepairStep {
    static let id = DataRepairStepID.homePolicySets
    var title: String { String(localized: "Asigurările locuinței", comment: "Repair group: a home's shared policy facts split into PAD and the optional policy.") }

    enum Cover { case pad, optional, unknown }

    struct Candidate {
        let asset: Asset
        /// What names the facts in the list: the policy number, else the insurer, else the phone.
        let label: String
        let cover: Cover
        let pad: BlueprintFacts
        let optional: BlueprintFacts
    }

    static func candidates(in context: ModelContext) throws -> [Candidate] {
        let templates = try TemplateStore(context: context).templatesByKey()
        return try context.fetch(FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.createdAt)])).compactMap { asset in
            guard !asset.isExample, templates.plays(.home, asset.templateKey), let template = templates[asset.templateKey]?.definition,
                  let pad = template.blueprints.first(where: { $0.key == BuiltInBlueprints.homePAD })?.facts,
                  let optional = template.blueprints.first(where: { $0.key == BuiltInBlueprints.homeInsurance })?.facts,
                  pad != optional else { return nil }
            let values = asset.values
            func text(_ facts: BlueprintFacts, _ role: BlueprintFactRole) -> String? {
                facts.field(for: role).flatMap { values[$0]?.textValue }.flatMap { $0.isEmpty ? nil : $0 }
            }
            let held = BlueprintFactRole.allCases.compactMap { text(pad, $0) }
            // Nothing kept, or the two already apart: nothing to tell.
            guard let first = held.first, BlueprintFactRole.allCases.allSatisfy({ text(optional, $0) == nil }) else { return nil }
            let number = text(pad, .policyNumber)
            let cover = Self.cover(of: asset, number: number)
            guard cover != .pad else { return nil }
            return Candidate(asset: asset, label: number ?? first, cover: cover, pad: pad, optional: optional)
        }
    }

    /// Which policy the home's kept facts are: from the papers that carry its number, else
    /// from the deadlines running.
    static func cover(of asset: Asset, number: String?) -> Cover {
        let wanted = number.map(RomanianText.compact) ?? ""
        let papers = (asset.attachments ?? []).filter { attachment in
            guard attachment.kind == .policy, !attachment.isArchived, wanted.count >= 4 else { return false }
            return attachment.extractedText.map { RomanianText.compact($0).contains(wanted) } ?? false
        }
        let fromPapers = Set(papers.compactMap { paper -> Cover? in
            switch paper.obligation?.blueprintKey {
            case BuiltInBlueprints.homePAD?: return .pad
            case BuiltInBlueprints.homeInsurance?: return .optional
            default: break
            }
            guard let text = paper.extractedText,
                  // A car's policy filed under the home says nothing about the home's.
                  InsuranceCover.read(in: text, among: [InsuranceCover.rca, InsuranceCover.casco]) == nil else { return nil }
            return InsuranceCover.read(in: text, among: [InsuranceCover.pad]) != nil ? .pad : .optional
        })
        if fromPapers.count == 1, let only = fromPapers.first { return only }
        if fromPapers.count > 1 { return .unknown }
        let running = Set((asset.obligations ?? []).filter { $0.status == .active || $0.status == .paused }.compactMap(\.blueprintKey))
        switch (running.contains(BuiltInBlueprints.homePAD), running.contains(BuiltInBlueprints.homeInsurance)) {
        case (true, false): return .pad
        case (false, true): return .optional
        default: return .unknown
        }
    }

    func findings(_ scan: inout DataRepairScan) throws -> [DataRepairFinding] {
        try Self.candidates(in: scan.context).map { candidate in
            let name = candidate.asset.name
            let label = candidate.label
            let message = candidate.cover == .optional
                ? String(localized: "La \(name), „\(label)” e de la asigurarea facultativă, dar stă la PAD. O mut la asigurarea facultativă, cu asigurătorul și telefonul de daune?",
                         comment: "Repair: a home's optional policy facts kept where PAD's are.")
                : String(localized: "Verifică asigurarea de la \(name): „\(label)” stă la PAD și nu-mi dau seama dacă e PAD sau asigurarea facultativă. E cea facultativă? O mut acolo, cu asigurătorul și telefonul de daune.",
                         comment: "Repair: a home's policy facts whose cover can't be told. Applying moves them to the optional policy; leaving keeps them as PAD's.")
            return DataRepairFinding(
                id: "\(Self.id.rawValue):\(candidate.asset.id.uuidString):\(label)",
                step: Self.id,
                message: message,
                subject: .homePolicySet(assetID: candidate.asset.id, policyNumber: label)
            )
        }
    }

    func apply(_ findings: [DataRepairFinding], in context: ModelContext, calendar: Calendar) throws {
        let approved = Set(findings.compactMap { finding -> String? in
            guard case .homePolicySet(let id, let label) = finding.subject else { return nil }
            return "\(id.uuidString):\(label)"
        })
        for candidate in try Self.candidates(in: context) where approved.contains("\(candidate.asset.id.uuidString):\(candidate.label)") {
            var values = candidate.asset.values
            for role in BlueprintFactRole.allCases {
                guard let from = candidate.pad.field(for: role), let value = values[from] else { continue }
                if let to = candidate.optional.field(for: role), values[to] == nil { values[to] = value }
                values[from] = nil
            }
            candidate.asset.values = values
        }
    }
}
