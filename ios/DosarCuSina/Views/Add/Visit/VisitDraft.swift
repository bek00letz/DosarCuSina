import Foundation
import SwiftData

/// A visit being filled in: the ticked checklist rows, anything else done, a note, the date,
/// the counter, the total and who did it. Its form (`VisitForm`, by the category's visit kind)
/// says which of these are asked; saving keeps only those (`filing`), in exactly one
/// `HistoryActions.recordVisit` call.
struct VisitDraft: Equatable {
    struct Part: Equatable {
        var cost: Decimal?
        var brand: String = ""
    }

    struct Extra: Identifiable, Equatable {
        var id = UUID()
        var name: String
        var cost: Decimal?
    }

    enum ProviderChoice: Equatable {
        case none
        case existing(UUID)
        case new(String)
    }

    var date: Date
    /// Ticked rows by component key, in the order they were ticked.
    var ticked: [String] = []
    var parts: [String: Part] = [:]
    var extras: [Extra] = []
    /// The counter as typed or read off the invoice; nil until then. The estimate is only a
    /// greyed placeholder (`odometerEstimate`) and is never saved.
    var odometer: Double?
    /// Where `odometer` came from: the invoice, until the person types over it.
    var odometerSource: ReadingSource = .person
    var odometerEstimate: Double?
    var total: Decimal?
    var currency: String = Money.defaultCurrency
    /// What it was for, or what was fixed (`VisitShape.note`).
    var note: String = ""
    var provider: ProviderChoice = .none
    var rating: Int?
    /// The captured invoice, filed with the visit: new pages, or a copy the binder already
    /// keeps (it moves to the visit).
    var document: CapturedDocumentRef?
    var documentTitle: String?
    var documentText: String?
    /// The CUI read off the invoice, for finding who did the job.
    var providerTaxID: String?
    /// The invoice's number as read, by which another photo of it is known (`PaperIdentity`).
    var reference: String?
    /// The person said this invoice is another one, when it only looked like one already in
    /// the binder by its day and total ("E altă factură"). A new invoice asks again.
    var isAnotherInvoice = false
    /// The invoice's kind when its photo is kept only on request (`CaptureResult.photoIsOnRequest`:
    /// it shows a whole card number); nil when it is kept as any invoice is.
    var photoOnRequestKind: CaptureDocumentKind?
    /// The person asked to keep that photo ("Păstrează și poza actului"). A new invoice asks again.
    var keepsPhotoOnRequest = false

    /// Saving keeps the invoice's photo: always, unless it is kept only on request and the person hasn't asked.
    var keepsPhoto: Bool {
        photoOnRequestKind == nil || keepsPhotoOnRequest
    }

    init(date: Date) {
        self.date = date
    }

    /// Whether anything was filled in, so leaving the form asks first: the draft differs from
    /// a new one of the same day in any value it holds (a row ticked, a counter typed, a
    /// provider chosen, a rating, a paper), compared whole, so a value added to the draft
    /// later counts by itself (`VisitDiscardGuardTests`). Only what holds nothing is left out first
    /// (`content`): the counter's greyed estimate, a part, a row or a note left blank.
    var hasContent: Bool {
        content != VisitDraft(date: date).content
    }

    /// The draft without what holds nothing the person gave: the estimate is a placeholder,
    /// never saved; a part with no cost and no brand, a row with no name and no cost and a
    /// note of spaces are empty; where the counter came from says nothing without one.
    private var content: VisitDraft {
        var content = self
        content.odometerEstimate = nil
        content.parts = parts.filter { $0.value != Part() }
        content.extras = extras.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.cost != nil }
        content.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if odometer == nil { content.odometerSource = .person }
        return content
    }

    private var hasRows: Bool { extras.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty } }
    private var hasNote: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Whether `field` is filled in.
    func fills(_ field: VisitShape.Field) -> Bool {
        switch field {
        case .paper: document != nil
        case .work: !ticked.isEmpty || hasRows
        case .note: hasNote
        case .counter: odometer != nil
        case .cost: total != nil
        case .provider: provider != .none
        }
    }

    /// Whether the form can save: any one of what its kind requires is filled in, or the kind
    /// requires nothing (a doctor's visit saves with its day alone).
    func satisfies(_ form: VisitForm) -> Bool {
        guard let requirement = form.shape.requirement else { return true }
        return requirement.fields.contains { form.fields.contains($0) && fills($0) }
    }

    func isTicked(_ key: String) -> Bool { ticked.contains(key) }

    mutating func toggle(_ key: String) {
        if let index = ticked.firstIndex(of: key) {
            ticked.remove(at: index)
        } else {
            ticked.append(key)
        }
    }

    // MARK: To the engine

    var checklistItems: [HistoryActions.ChecklistItem] {
        ticked.map { key in
            let part = parts[key]
            let brand = part?.brand.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return HistoryActions.ChecklistItem(
                componentKey: key,
                cost: part?.cost.map { Money($0, currency: currency) },
                partBrandOrCode: brand.isEmpty ? nil : brand
            )
        }
    }

    var extraItems: [LineItemDraft] {
        extras.compactMap { extra in
            let name = extra.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return LineItemDraft(name: name, cost: extra.cost.map { Money($0, currency: currency) })
        }
    }

    /// The total written: the one typed, else nothing (the parts add up on their own).
    var totalMoney: Money? { total.map { Money($0, currency: currency) } }

    /// The sum of the parts' costs, shown as a hint under the total.
    var partsSum: Decimal? {
        let costs = ticked.compactMap { parts[$0]?.cost } + extras.compactMap(\.cost)
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }

    // MARK: To the filer

    /// The visit saving files, from the draft as it stands: only what the form asks, so a value
    /// its kind doesn't ask (a doctor's counter, a repair's parts) is never written.
    @MainActor
    func filing(on asset: Asset, form: VisitForm, provider: CaptureFiler.Visit.ProviderChoice) -> CaptureFiler.Visit {
        let asks = form.fields
        let checklist = asks.contains(.work) && form.hasChecklist
            ? checklistItems.map { item in form.shape.asksBrand ? item : HistoryActions.ChecklistItem(componentKey: item.componentKey, cost: item.cost) }
            : []
        let extras = asks.contains(.work) ? extraItems : []
        return CaptureFiler.Visit(
            asset: asset,
            kind: form.shape.historyKind,
            title: form.entryTitle(for: checklist.map { item in form.components.first { $0.key == item.componentKey }?.name ?? item.componentKey } + extras.map(\.name)),
            occurredAt: date,
            checklist: checklist,
            extraItems: extras,
            totalCost: totalMoney,
            odometer: asks.contains(.counter) ? odometer : nil,
            odometerSource: odometerSource,
            provider: asks.contains(.provider) ? provider : .none,
            rating: asks.contains(.provider) ? rating : nil,
            note: asks.contains(.note) && hasNote ? note.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            document: asks.contains(.paper) ? document : nil,
            documentTitle: documentTitle,
            documentText: documentText,
            reference: reference,
            isAnotherInvoice: isAnotherInvoice,
            paper: form.shape.paper ?? .invoice,
            keepsPhoto: keepsPhoto
        )
    }

    // MARK: From a paper

    /// Fills the draft from a captured paper, as its form asks: ticks the rows its lines match,
    /// with their costs; lines the catalog doesn't know become rows of one's own ("Altceva");
    /// the total, the date, the counter and the provider's name fill in when empty. What the
    /// form doesn't ask is left out: a doctor's visit takes the day, the total and who. Returns
    /// which of the paper's day, total and issuer it filled in, for the note that says so
    /// (`VisitForm.readNote`).
    @discardableResult
    mutating func apply(_ result: CaptureResult, form: VisitForm, calendar: Calendar = .dosar) -> [VisitShape.Paper.Fact] {
        var filled: [VisitShape.Paper.Fact] = []
        let fields = Dictionary(result.fields.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        let asks = form.fields
        let components = form.components
        for line in asks.contains(.work) ? fields[.lineItems]?.lineItems ?? [] : [] {
            let cost = line.amount?.amount
            if let currency = line.amount?.currency { self.currency = currency }
            let key = line.componentKey.flatMap { key in components.contains { $0.key == key } ? key : nil }
                ?? (line.isLabour ? nil : ComponentCatalog.match(line.description, in: components)?.key)
            if let key {
                if !isTicked(key) { ticked.append(key) }
                var part = parts[key] ?? Part()
                if let cost { part.cost = (part.cost ?? 0) + cost }
                parts[key] = part
            } else {
                let name = line.description.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !extras.contains(where: { $0.name == name }) else { continue }
                extras.append(Extra(name: name, cost: cost))
            }
        }
        if total == nil, let money = fields[.total]?.money {
            total = money.amount
            currency = money.currency
            filled.append(.total)
        }
        if let day = (fields[.issueDate] ?? fields[.purchaseDate])?.day {
            self.date = day.noonDate(in: calendar)
            filled.append(.day)
        }
        if asks.contains(.counter), odometer == nil, case .metric(let value, _)? = fields[.odometer] {
            odometer = RomanianNumber.double(value)
            odometerSource = .document
        }
        if asks.contains(.provider), provider == .none, let name = fields[.provider]?.text, !name.isEmpty {
            provider = .new(name)
            filled.append(.issuer)
        }
        if asks.contains(.paper), let document = result.document {
            if document != self.document {
                isAnotherInvoice = false
                keepsPhotoOnRequest = false
            }
            self.document = document
            photoOnRequestKind = result.photoIsOnRequest ? result.kind : nil
        }
        if let taxID = fields[.providerTaxID]?.text { providerTaxID = taxID }
        if let number = fields[.invoiceNumber]?.text, !number.trimmingCharacters(in: .whitespaces).isEmpty { reference = number }
        documentText = result.recognizedText.isEmpty ? nil : result.recognizedText
        return filled
    }
}

/// What the visit changed, for the screen after saving: each part with when it
/// was last done before, so "Plăcuțe frână față" reads "azi · înainte în martie 2024".
struct VisitChange: Identifiable, Equatable {
    var id: String { componentKey }
    var componentKey: String
    var name: String
    var cost: Money?
    /// When it was done before this visit, if ever.
    var previous: Date?

    @MainActor
    static func changes(of entry: HistoryEntry, on asset: Asset) -> [VisitChange] {
        let items = HistoryItemSnapshot.items(of: asset).filter { $0.entryId != entry.id }
        return (entry.items ?? []).compactMap { item in
            guard let key = item.componentKey else { return nil }
            let previous = MaintenanceLog.lastOccurrence(of: key, in: items)?.date
            return VisitChange(componentKey: key, name: item.name, cost: item.totalCost, previous: previous)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// What the visit form shows greyed in the empty counter field: the last reading of the
/// cleaned series, moved on by the usual pace since then, to the nearest hundred but never
/// below that reading. A placeholder only: it is never saved (`ReadingSource.estimate`).
enum OdometerEstimate {
    static func value(readings: [CadenceCalculator.TelemetryReading], fallback: Double?, now: Date) -> Double? {
        guard let latest = ReadingSeries(readings).latest else { return fallback }
        guard let rate = MaintenanceLog.monthlyRate(readings) else { return latest.metric }
        let days = max(0, now.timeIntervalSince(latest.date) / 86_400)
        return max(latest.metric, ((latest.metric + rate * days / 30) / 100).rounded() * 100)
    }
}
