import SwiftUI

/// "Pleci din țară": first a few questions (when, where, who goes, the car, a pet), then
/// what is ready, what is missing and what to bring, for those days. Several trips can be
/// kept at once, each until it is over (`TripPlanStore`), so a checklist opens where the
/// person left it. From a member's page the screen is about their trips; from Urmează,
/// about everyone's. With one such trip its checklist opens at once; with more, the list of
/// them; with none, the questions for a new one.
struct TripChecklistView: View {
    /// The member it was opened from; nil from Urmează.
    let holderID: UUID?
    let assets: [ReadinessAsset]
    /// The category of the household's members, for adding the first one.
    let holderTemplateKey: String?

    /// What the screen shows.
    enum Mode: Hashable {
        case loading
        case questions
        case checklist(UUID)
        case list
    }

    /// Which trip the questions are about.
    enum Editing: Hashable {
        case new
        case trip(UUID)
    }

    @Environment(\.calendar) private var calendar
    /// Every trip kept on this phone that isn't over, the soonest first.
    @State private var trips: [TripPlan] = []
    /// The trip whose checklist shows; nil shows the list of trips.
    @State private var shownID: UUID?
    @State private var editing: Editing?
    @State private var draft = TripDraft()
    @State private var hasLoaded = false
    @State private var ticked: Set<String> = []
    @State private var request: ReadinessAction?
    @State private var toast: DSToast?
    @State private var isConfirmingRemoval = false
    /// "Vezi ce-ți trebuie" was pressed with a question left: the fields say what is missing.
    @State private var revealsQuestions = DSValidationReveal()

    private let store = TripPlanStore()

    private var today: CalendarDay { CalendarDay(Date(), calendar: calendar) }

    /// The trips this screen is about: the member's (opened from their page), or everyone's.
    private var relevant: [TripPlan] {
        trips.filter { trip in holderID.map { trip.travellers.contains(.member($0)) } ?? true }
    }

    private var shown: TripPlan? { trips.first { $0.id == shownID } }

    private var mode: Mode {
        if !hasLoaded { return .loading }
        if editing != nil { return .questions }
        if let shown { return .checklist(shown.id) }
        return .list
    }

    var body: some View {
        Group {
            switch mode {
            case .loading:
                // The first frame only reserves the space; the trips load at once.
                ReadinessPage { Color.clear.frame(height: 1) }
            case .questions:
                questions
                    .transition(.opacity)
            case .checklist:
                if let shown {
                    ReadinessPage { checklist(shown) }
                        .toolbar { DSMoreActionsToolbar(actions: moreActions) }
                        .transition(.opacity)
                }
            case .list:
                tripList
                    .transition(.opacity)
            }
        }
        .dsAnimation(value: mode)
        .readinessActions($request, toast: $toast)
        .dsToast($toast)
        .confirmationDialog(Text("Ștergi călătoria?", comment: "Asks before forgetting a kept trip."), isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button(role: .destructive) { removeShown() } label: {
                Text("Șterge călătoria", comment: "Forgets a kept trip and its checklist.")
            }
        } message: {
            Text("Actele și termenele rămân în dosar. Se șterge doar planul călătoriei.", comment: "What forgetting a trip removes.")
        }
        .task { load() }
    }

    // MARK: Trips

    private func load() {
        guard !hasLoaded else { return }
        trips = store.load(today: today)
        if relevant.count == 1 {
            shownID = relevant.first?.id
        } else if relevant.isEmpty {
            startNewTrip()
        }
        hasLoaded = true
    }

    /// The questions for a new trip: who goes is chosen the usual way; the days are the person's to say.
    private func startNewTrip() {
        draft = TripDraft(ReadinessEngine.defaultTrip(start: today, end: today, holderID: holderID, assets: assets), calendar: calendar)
        draft.start = nil
        draft.end = nil
        revealsQuestions.reset()
        editing = .new
    }

    private func edit(_ plan: TripPlan) {
        draft = TripDraft(plan, calendar: calendar)
        revealsQuestions.reset()
        editing = .trip(plan.id)
    }

    /// "Vezi ce-ți trebuie": the trip as answered, kept, and its checklist; or what is missing.
    private func showChecklist() {
        let id: UUID
        switch editing {
        case .trip(let existing): id = existing
        case .new, nil: id = UUID()
        }
        guard let plan = draft.plan(id: id, calendar: calendar) else {
            revealsQuestions.reveal()
            return
        }
        store.save(plan)
        trips = store.load(today: today)
        if shownID != plan.id { ticked = [] }
        shownID = plan.id
        editing = nil
        revealsQuestions.reset()
    }

    /// Back from the questions to where the person was: the trip, or the list.
    private func cancelQuestions() {
        editing = nil
        revealsQuestions.reset()
    }

    /// Whether the questions have somewhere to go back to.
    private var canCancelQuestions: Bool {
        if case .trip = editing { return true }
        return shown != nil || !relevant.isEmpty
    }

    private func show(_ plan: TripPlan) {
        if shownID != plan.id { ticked = [] }
        shownID = plan.id
    }

    private func removeShown() {
        guard let shownID else { return }
        store.remove(shownID)
        trips = store.load(today: today)
        ticked = []
        self.shownID = relevant.count == 1 ? relevant.first?.id : nil
        if relevant.isEmpty { startNewTrip() }
    }

    /// The trip's other actions, in its toolbar: every trip, another trip, forgetting this one.
    private var moreActions: [DSMoreAction] {
        var actions: [DSMoreAction] = []
        if relevant.count > 1 {
            actions.append(DSMoreAction(id: "all", title: Text("Toate călătoriile", comment: "Shows every kept trip."), systemImage: "list.bullet") {
                shownID = nil
            })
        }
        actions.append(DSMoreAction(id: "new", title: Text("Altă călătorie", comment: "Starts the questions for another trip."), systemImage: "plus") {
            startNewTrip()
        })
        actions.append(DSMoreAction(id: "remove", title: Text("Șterge călătoria", comment: "Forgets a kept trip and its checklist."), systemImage: "trash", role: .destructive) {
            isConfirmingRemoval = true
        })
        return actions
    }

    // MARK: Screens

    /// The questions, with "Vezi ce-ți trebuie" pinned to the bottom edge.
    private var questions: some View {
        ReadinessPage {
            TripForm(draft: $draft, candidates: ReadinessEngine.tripCandidates(in: assets), holderTemplateKey: holderTemplateKey)
        }
        .dsRevealsValidation(revealsQuestions)
        .dsPinnedAction {
            DSPrimaryButton("Vezi ce-ți trebuie", systemImage: "checklist") { showChecklist() }
        } secondary: {
            if case .trip = editing {
                DSSecondaryButton("Renunță la schimbări") { cancelQuestions() }
            } else if canCancelQuestions {
                DSSecondaryButton("Renunță") { cancelQuestions() }
            }
        }
    }

    @ViewBuilder
    private func checklist(_ plan: TripPlan) -> some View {
        let result = ReadinessEngine.checklist(.trip(plan), assets: assets, today: today, calendar: calendar)
        TripHeader(plan: plan, checklist: result) { edit(plan) }
        if result.groups.isEmpty {
            DSEmptyState(
                "Nimic de pregătit încă",
                systemImage: "checklist",
                message: "Alege cine pleacă, cu ce mașină sau cu ce animal, și îți spun ce e pregătit.",
                actionTitle: "Schimbă călătoria",
                action: { edit(plan) }
            )
        } else {
            ReadinessGroupsView(groups: result.groups, ticked: $ticked) { request = $0 }
        }
    }

    /// Every trip this screen is about, the soonest first, each with its verdict.
    private var tripList: some View {
        ReadinessPage {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                DSSectionHeader("Călătoriile tale")
                ForEach(relevant) { plan in
                    Button { show(plan) } label: {
                        TripRow(plan: plan, checklist: ReadinessEngine.checklist(.trip(plan), assets: assets, today: today, calendar: calendar))
                    }
                    .buttonStyle(.dsPressable)
                }
            }
        }
        .dsPinnedAction {
            DSPrimaryButton("Adaugă o călătorie", systemImage: "plus") { startNewTrip() }
        }
    }
}

/// The words a trip is known by: "Pleci pe 12 iulie · Grecia" and "Te întorci pe 20 iulie · În UE".
enum TripWording {
    static func departure(_ plan: TripPlan) -> String {
        let day = String(localized: "Pleci pe \(DosarFormat.dayMonth(plan.start))", comment: "Trip header: the day of departure.")
        let place = plan.destination.trimmingCharacters(in: .whitespaces)
        return place.isEmpty ? day : "\(day) · \(place)"
    }

    static func back(_ plan: TripPlan) -> String {
        String(localized: "Te întorci pe \(DosarFormat.dayMonth(plan.end)) · \(plan.region.title)", comment: "Trip header: the day back and the region.")
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
                    Text(verbatim: TripWording.departure(plan))
                        .dsFont(.title)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: TripWording.back(plan))
                        .dsFont(.subheadline)
                }
                .accessibilityElement(children: .combine)
                ReadinessSummaryLine(checklist: checklist)
                DSSecondaryButton("Schimbă călătoria", systemImage: "calendar") { onChange() }
            }
        }
    }
}

/// One trip in the list: its days, where to and its verdict; the whole card opens it.
private struct TripRow: View {
    let plan: TripPlan
    let checklist: ReadinessChecklist

    var body: some View {
        DSCard {
            HStack(spacing: DS.Space.s) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(verbatim: TripWording.departure(plan))
                            .dsFont(.headline)
                            .foregroundStyle(DS.Palette.label)
                        Text(verbatim: TripWording.back(plan))
                            .dsFont(.subheadline)
                    }
                    ReadinessSummaryLine(checklist: checklist)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                Image(systemName: "chevron.forward")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.Control.minimumHitTarget)
            .contentShape(.rect)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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

    /// The plan, as the trip `id`, when the days are given and the way back isn't before the way out.
    func plan(id: UUID, calendar: Calendar) -> TripPlan? {
        guard let start, let end else { return nil }
        let plan = TripPlan(id: id, start: CalendarDay(start, calendar: calendar), end: CalendarDay(end, calendar: calendar), region: region,
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
