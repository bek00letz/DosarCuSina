import SwiftUI
import SwiftData

/// A situation's checklist (`AppRoute.readiness`): the trip, selling the car, a claim.
/// It reads the binder through `ReadinessEngine`, which decides every outcome; while a
/// category it reads is behind Face ID and closed, it names nothing.
struct ReadinessScreen: View {
    let route: ReadinessRoute

    @Environment(BiometricVaultManager.self) private var vault
    @Query private var assets: [Asset]
    @Query private var templates: [CategoryTemplate]

    var body: some View {
        // Reading the models here keeps the checklist current: a deadline renewed or a
        // document added on another screen redraws it when it comes back.
        let byKey = Dictionary(templates.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let readiness = ReadinessAsset.make(from: assets, templates: byKey)
        Group {
            // A sale or a claim needs its section; a trip opened from a member who is gone opens for everyone.
            if let id = route.assetID, route.situation != .trip, !readiness.contains(where: { $0.id == id }) {
                MissingRecordView()
            } else if ReadinessEngine.readsSensitive(route, assets: readiness), vault.isLocked(sectionIsSensitive: true) {
                LockedSectionView(checklist: route.situation.title)
            } else {
                switch route {
                case .trip(let holderID):
                    TripChecklistView(holderID: holderID, assets: readiness, holderTemplateKey: byKey.key(withRole: .holder))
                case .sale(let id):
                    SaleChecklistView(assetID: id, assets: readiness)
                case .claim(let id):
                    ClaimChecklistView(assetID: id, assets: readiness)
                }
            }
        }
        .navigationTitle(Text(verbatim: route.situation.title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared pieces

/// The page every checklist sits on: one column, readable width, grouped background.
struct ReadinessPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                content
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.top, DS.Space.s)
            .padding(.bottom, DS.Space.xxl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Palette.background)
    }
}

/// A checklist's one-line verdict: "Totul e pregătit", or how many things need the person.
struct ReadinessSummaryLine: View {
    let checklist: ReadinessChecklist

    var body: some View {
        DSStatusLine(text: text, tone: tone)
    }

    private var tone: DSBoxTone {
        if checklist.items.contains(where: { $0.status == .problem }) { return .alarming }
        return checklist.isAllReady ? .allGood : .pending
    }

    private var text: String {
        let attention = checklist.attentionCount
        let missing = checklist.missingCount
        switch (attention, missing) {
        case (0, 0):
            return String(localized: "Totul e pregătit", comment: "Readiness summary: nothing needs the person.")
        case (_, 0):
            return String(localized: "\(attention) lucruri de rezolvat", comment: "Readiness summary: how many checks need the person.")
        case (0, _):
            return String(localized: "\(missing) lucruri nu sunt în dosar", comment: "Readiness summary: how many things aren't in the binder.")
        default:
            return String(localized: "\(attention) lucruri de rezolvat", comment: "Readiness summary: how many checks need the person.")
                + " · " + String(localized: "\(missing) lucruri nu sunt în dosar", comment: "Readiness summary: how many things aren't in the binder.")
        }
    }
}

/// The groups of a checklist, one card each. A check is a row that says why and opens or
/// adds what it is about; something to bring or do is a row the person ticks off here.
struct ReadinessGroupsView: View {
    let groups: [ReadinessGroup]
    @Binding var ticked: Set<String>
    let perform: (ReadinessAction) -> Void

    var body: some View {
        ForEach(groups) { group in
            DSPocketCard(group.title) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { DSRowSeparator() }
                    row(item)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: ReadinessItem) -> some View {
        if item.status == .reminder, item.action == nil {
            DSCheckRow(title: Text(verbatim: item.title), subtitle: Text(verbatim: item.detail), isOn: ticked.contains(item.id)) {
                if ticked.contains(item.id) { ticked.remove(item.id) } else { ticked.insert(item.id) }
            }
        } else {
            DSReadinessRow(
                status: item.status,
                title: Text(verbatim: item.title),
                detail: Text(verbatim: item.detail),
                actionTitle: item.action?.adds == true ? Text("Adaugă", comment: "Readiness row: adds what is missing.") : nil,
                isTappable: item.action != nil
            ) {
                if let action = item.action { perform(action) }
            }
        }
    }
}

// MARK: - Acting on a check

extension View {
    /// Carries out what a checklist row asks: opens what is there, or adds what is missing
    /// through the one flow that adds it (a person's document photo first, the section's
    /// paper photo first, the deadline form, the section's edit sheet).
    func readinessActions(_ request: Binding<ReadinessAction?>, toast: Binding<DSToast?>) -> some View {
        modifier(ReadinessActionsModifier(request: request, toast: toast))
    }
}

private struct ReadinessActionsModifier: ViewModifier {
    @Binding var request: ReadinessAction?
    @Binding var toast: DSToast?

    @Environment(ShellRouter.self) private var router
    @State private var photoAssetID: UUID?
    @State private var isChoosingPhoto = false
    @State private var deadline: DeadlineRequest?
    @State private var editing: EditRequest?

    struct DeadlineRequest: Identifiable {
        var assetID: UUID
        var blueprintKey: String
        var id: String { assetID.uuidString + blueprintKey }
    }

    struct EditRequest: Identifiable {
        var id: UUID
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, action in
                guard let action else { return }
                request = nil
                handle(action)
            }
            .photoFirstCapture(
                isPresented: $isChoosingPhoto,
                title: Text("Adaugă o poză a actului", comment: "Title of the photo source choice for a paper a checklist asks for."),
                assetID: photoAssetID
            ) { message in
                toast = DSToast(title: message, actionTitle: nil, action: nil)
            } onError: { message in
                toast = DSToast(title: LocalizedStringResource(stringLiteral: message), systemImage: "exclamationmark.triangle.fill", tint: DSStatus.overdue.color, actionTitle: nil, feedback: .error)
            }
            .sheet(item: $deadline) { request in
                NavigationStack {
                    DeadlineForm(assetID: request.assetID, startsWithBlueprint: request.blueprintKey) { message in
                        deadline = nil
                        toast = DSToast(title: message, actionTitle: nil, action: nil)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
                    }
                }
            }
            .sheet(item: $editing) { request in
                SectionEditSheet(assetID: request.id) { toast = $0 }
            }
    }

    private func handle(_ action: ReadinessAction) {
        switch action {
        case .open(let route):
            router.push(route)
        case .addPersonalDocument(let holderID):
            router.present(.addPersonalDocument(holderID: holderID))
        case .addDocument(let assetID):
            photoAssetID = assetID
            isChoosingPhoto = true
        case .addDeadline(let assetID, let blueprintKey):
            deadline = DeadlineRequest(assetID: assetID, blueprintKey: blueprintKey)
        case .editSection(let assetID):
            editing = EditRequest(id: assetID)
        }
    }
}

/// A section's edit sheet, found by its id.
private struct SectionEditSheet: View {
    let assetID: UUID
    let announce: (DSToast) -> Void
    @Query private var matches: [Asset]
    @Query private var templates: [CategoryTemplate]

    init(assetID: UUID, announce: @escaping (DSToast) -> Void) {
        self.assetID = assetID
        self.announce = announce
        let id = assetID
        _matches = Query(filter: #Predicate<Asset> { $0.id == id })
    }

    var body: some View {
        if let asset = matches.first {
            let definition = templates.first { $0.key == asset.templateKey }?.definition
                ?? BuiltInTemplates.definition(for: asset.templateKey) ?? BuiltInTemplates.other
            AssetEditSheet(asset: asset, definition: definition, announce: announce)
        } else {
            NavigationStack { MissingRecordView() }
        }
    }
}
