import SwiftUI

/// "Pleci din țară": first a few questions (when, where, who goes, the car, a pet), then
/// what is ready, what is missing and what to bring, for those days. The trip is kept on
/// this phone until it is over, so the checklist opens where the person left it.
struct TripChecklistView: View {
    /// The member it was opened from; nil from Urmează.
    let holderID: UUID?
    let assets: [ReadinessAsset]
    /// The category of the household's members, for adding the first one.
    let holderTemplateKey: String?

    @Environment(\.calendar) private var calendar
    @State private var plan: TripPlan?
    @State private var draft = TripDraft()
    @State private var isEditing = false
    @State private var hasLoaded = false
    @State private var ticked: Set<String> = []
    @State private var request: ReadinessAction?
    @State private var toast: DSToast?
    /// "Vezi ce-ți trebuie" was pressed with a question left: the fields say what is missing.
    @State private var revealsQuestions = false

    private let store = TripPlanStore()

    var body: some View {
        Group {
            if hasLoaded, isEditing || plan == nil {
                // The questions, with "Vezi ce-ți trebuie" pinned to the bottom edge.
                ReadinessPage {
                    TripForm(draft: $draft, candidates: ReadinessEngine.tripCandidates(in: assets), holderTemplateKey: holderTemplateKey)
                }
                .environment(\.dsRevealsValidation, revealsQuestions)
                .dsPinnedAction {
                    DSPrimaryButton("Vezi ce-ți trebuie", systemImage: "checklist") { showChecklist() }
                } secondary: {
                    if plan != nil {
                        DSSecondaryButton("Renunță la schimbări") { isEditing = false }
                    }
                }
                .transition(.opacity)
            } else {
                ReadinessPage {
                    if let plan {
                        checklist(plan)
                    } else {
                        // The first frame only reserves the space; the plan loads at once.
                        Color.clear.frame(height: 1)
                    }
                }
                .transition(.opacity)
            }
        }
        .dsAnimation(value: isEditing)
        .dsAnimation(value: plan)
        .readinessActions($request, toast: $toast)
        .dsToast($toast)
        .task { load() }
    }

    // MARK: Plan

    private func load() {
        guard !hasLoaded else { return }
        let today = CalendarDay(Date(), calendar: calendar)
        let saved = store.load(today: today)
        if let saved, holderID.map({ saved.travellers.contains(.member($0)) }) ?? true {
            plan = saved
        } else {
            if var kept = saved, let holderID {
                // Opened from someone not in the kept trip: start from it, with them going.
                kept.travellers = [.member(holderID)]
                draft = TripDraft(kept, calendar: calendar)
            } else {
                // A new trip: who goes is chosen the usual way; the days are the person's to say.
                draft = TripDraft(ReadinessEngine.defaultTrip(start: today, end: today, holderID: holderID, assets: assets), calendar: calendar)
                draft.start = nil
                draft.end = nil
            }
            isEditing = true
        }
        hasLoaded = true
    }

    /// "Vezi ce-ți trebuie": the trip as answered, kept, and its checklist; or what is missing.
    private func showChecklist() {
        guard let newPlan = draft.plan(calendar: calendar) else {
            revealsQuestions = true
            return
        }
        store.save(newPlan)
        ticked = []
        plan = newPlan
        isEditing = false
        revealsQuestions = false
    }

    private func edit() {
        if let plan { draft = TripDraft(plan, calendar: calendar) }
        revealsQuestions = false
        isEditing = true
    }

    // MARK: Checklist

    @ViewBuilder
    private func checklist(_ plan: TripPlan) -> some View {
        let result = ReadinessEngine.checklist(.trip(plan), assets: assets, today: CalendarDay(Date(), calendar: calendar), calendar: calendar)
        TripHeader(plan: plan, checklist: result, onChange: edit)
        if result.groups.isEmpty {
            DSEmptyState(
                "Nimic de verificat încă",
                systemImage: "checklist",
                message: "Alege cine pleacă, cu ce mașină sau cu ce animal, și îți spun ce e pregătit.",
                actionTitle: "Schimbă călătoria",
                action: edit
            )
        } else {
            ReadinessGroupsView(groups: result.groups, ticked: $ticked) { request = $0 }
        }
    }
}

/// The trip at the top of its checklist: "Pleci pe 12 iulie · Grecia", the way back and
/// the region, the verdict, and "Schimbă călătoria".
private struct TripHeader: View {
    let plan: TripPlan
    let checklist: ReadinessChecklist
    let onChange: () -> Void

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(verbatim: departure)
                        .dsFont(.title)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Te întorci pe \(DosarFormat.dayMonth(plan.end)) · \(plan.region.title)", comment: "Trip header: the day back and the region.")
                        .dsFont(.subheadline)
                }
                .accessibilityElement(children: .combine)
                ReadinessSummaryLine(checklist: checklist)
                DSSecondaryButton("Schimbă călătoria", systemImage: "calendar") { onChange() }
            }
        }
    }

    private var departure: String {
        let day = String(localized: "Pleci pe \(DosarFormat.dayMonth(plan.start))", comment: "Trip header: the day of departure.")
        let place = plan.destination.trimmingCharacters(in: .whitespaces)
        return place.isEmpty ? day : "\(day) · \(place)"
    }
}

// MARK: - The questions

/// What the trip form edits, before it becomes a plan.
struct TripDraft: Equatable {
    var start: Date?
    var end: Date?
    var region: TripPlan.Region = .europeanUnion
    var destination = ""
    var travellers: Set<TripTraveller> = []
    var vehicles: Set<UUID> = []
    var pets: Set<UUID> = []

    init() {}

    init(_ plan: TripPlan, calendar: Calendar) {
        start = plan.start.startDate(in: calendar)
        end = plan.end.startDate(in: calendar)
        region = plan.region
        destination = plan.destination
        travellers = plan.travellers
        vehicles = plan.vehicles
        pets = plan.pets
    }

    /// The plan, when the days are given and the way back isn't before the way out.
    func plan(calendar: Calendar) -> TripPlan? {
        guard let start, let end else { return nil }
        let plan = TripPlan(start: CalendarDay(start, calendar: calendar), end: CalendarDay(end, calendar: calendar), region: region,
                            destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
                            travellers: travellers, vehicles: vehicles, pets: pets)
        return plan.isValid ? plan : nil
    }
}

private struct TripForm: View {
    @Binding var draft: TripDraft
    let candidates: TripCandidates
    let holderTemplateKey: String?

    @Environment(\.calendar) private var calendar
    @Environment(ShellRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            question("Când") {
                DSDateField("Pleci pe", date: $draft.start, isRequired: true)
                DSDateField("Te întorci pe", date: $draft.end, isRequired: true) { end in
                    guard let start = draft.start, CalendarDay(end, calendar: calendar) < CalendarDay(start, calendar: calendar) else { return .valid }
                    return .invalid("Întoarcerea e înainte de plecare. Alege o zi de după \(DosarFormat.dayMonth(CalendarDay(start, calendar: calendar))).")
                }
            }
            question("Unde") {
                ForEach(TripPlan.Region.allCases, id: \.self) { region in
                    DSCheckRow(title: Text(verbatim: region.title), subtitle: Text(verbatim: region.summary), isOn: draft.region == region) {
                        draft.region = region
                    }
                }
                DSTextField("Țara sau orașul", text: $draft.destination, prompt: "Grecia", footnote: "Doar pentru tine, ca să recunoști călătoria.")
            }
            question("Cine pleacă") {
                if candidates.travellers.isEmpty {
                    Text("Nu ai încă persoane în dosar. Adaugă-te, cu actele tale, ca să le verific.", comment: "Trip form: no household members yet.")
                        .dsFont(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let holderTemplateKey {
                        DSSecondaryButton("Adaugă o persoană", systemImage: "person.badge.plus") {
                            router.present(.addSection(AddSectionRequest(templateKey: holderTemplateKey)))
                        }
                    }
                } else {
                    ForEach(candidates.travellers) { candidate in
                        toggleRow(candidate.name, isOn: draft.travellers.contains(candidate.traveller)) {
                            draft.travellers.formSymmetricDifference([candidate.traveller])
                        }
                    }
                }
            }
            if !candidates.vehicles.isEmpty {
                question("Mergi cu mașina") {
                    ForEach(candidates.vehicles) { car in
                        toggleRow(car.name, isOn: draft.vehicles.contains(car.id)) {
                            draft.vehicles.formSymmetricDifference([car.id])
                        }
                    }
                }
            }
            if !candidates.pets.isEmpty {
                question("Vine și un animal") {
                    ForEach(candidates.pets) { pet in
                        toggleRow(pet.name, isOn: draft.pets.contains(pet.id)) {
                            draft.pets.formSymmetricDifference([pet.id])
                        }
                    }
                }
            }
        }
    }

    private func question<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader(title)
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    content()
                }
            }
        }
    }

    private func toggleRow(_ name: String, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        DSCheckRow(title: Text(verbatim: name), isOn: isOn, action: toggle)
    }
}
