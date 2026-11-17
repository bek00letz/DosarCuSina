import Foundation
import Testing
@testable import DosarCuSina

/// Leaving the visit form asks first whenever the draft holds anything the person gave,
/// whichever value it is: "has content" is the draft compared whole with a new one
/// (`VisitDraft.hasContent`), so a value added to the draft counts by itself. This suite lists
/// every value the draft holds and fails when one is added without saying what it is.
@MainActor
@Suite("The visit form's discard guard sees every value")
struct VisitDiscardGuardTests {
    let day = noon("2026-11-17")

    /// Each value the draft holds that the person gives, and a change of it.
    static let content: [(name: String, fill: (inout VisitDraft) -> Void)] = [
        ("ticked", { $0.ticked = ["vehicle.oil"] }),
        ("parts", { $0.parts = ["vehicle.oil": VisitDraft.Part(cost: 120)] }),
        ("extras", { $0.extras = [VisitDraft.Extra(name: "Ștergătoare")] }),
        ("odometer", { $0.odometer = 101_000 }),
        ("total", { $0.total = 450 }),
        ("currency", { $0.currency = "EUR" }),
        ("note", { $0.note = "Ulei schimbat" }),
        ("provider", { $0.provider = .new("Service Exemplu") }),
        ("rating", { $0.rating = 4 }),
        ("document", { $0.document = .kept(attachmentID: UUID()) }),
        ("documentTitle", { $0.documentTitle = "Factura" }),
        ("documentText", { $0.documentText = "FACTURA" }),
        ("providerTaxID", { $0.providerTaxID = "RO12345678" }),
        ("reference", { $0.reference = "0001" }),
        ("isAnotherInvoice", { $0.isAnotherInvoice = true }),
        ("photoOnRequestKind", { $0.photoOnRequestKind = .bankCard }),
        ("keepsPhotoOnRequest", { $0.keepsPhotoOnRequest = true }),
    ]

    /// The values that hold nothing the person gave on their own: the day (a visit always has
    /// one, and a day alone loses nothing worth asking about), the greyed estimate, and
    /// where the counter came from (said only with a counter).
    static let notContent: [(name: String, fill: (inout VisitDraft) -> Void)] = [
        ("date", { $0.date = noon("2026-11-10") }),
        ("odometerEstimate", { $0.odometerEstimate = 100_500 }),
        ("odometerSource", { $0.odometerSource = .document }),
    ]

    @Test("Every value the draft holds is listed here, as content or not")
    func everyValueIsListed() {
        let held = Set(Mirror(reflecting: VisitDraft(date: day)).children.compactMap(\.label))
        let listed = Set((Self.content + Self.notContent).map(\.name))
        #expect(held == listed, "Say whether each new value is content: \(held.symmetricDifference(listed).sorted())")
    }

    @Test("A new draft asks nothing; any one value the person gave asks first")
    func anyValueCounts() {
        #expect(!VisitDraft(date: day).hasContent)
        for value in Self.content {
            var draft = VisitDraft(date: day)
            value.fill(&draft)
            #expect(draft.hasContent, "\(value.name)")
        }
        for value in Self.notContent {
            var draft = VisitDraft(date: day)
            value.fill(&draft)
            #expect(!draft.hasContent, "\(value.name) alone")
        }
    }

    @Test("A counter typed, a provider chosen and a rating each ask first")
    func theOnesForgottenBefore() {
        var counter = VisitDraft(date: day)
        counter.odometer = 101_000
        var chosen = VisitDraft(date: day)
        chosen.provider = .existing(UUID())
        var rated = VisitDraft(date: day)
        rated.rating = 5
        #expect(counter.hasContent && chosen.hasContent && rated.hasContent)
    }

    @Test("What was left blank holds nothing")
    func blanksHoldNothing() {
        var draft = VisitDraft(date: day)
        draft.parts = ["vehicle.oil": VisitDraft.Part()]
        draft.extras = [VisitDraft.Extra(name: "   ")]
        draft.note = "  \n "
        #expect(!draft.hasContent)
        draft.extras = [VisitDraft.Extra(name: "", cost: 30)]
        #expect(draft.hasContent, "A row's cost alone is something typed")
    }
}
