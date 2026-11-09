import SwiftData
import SwiftUI

/// The Adaugă tab: every way in. Four big buttons (camera, photos, files,
/// typing it in), the card that teaches sharing from Mail or WhatsApp, and
/// "De verificat" with what arrived from other apps.
///
/// It lives in the shell's navigation stack for this tab. What it shows of De verificat
/// counts as seen (`InboxLanding.markSeen`), so opening the app lands here only for
/// what arrived since.
struct AddRoot: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(BiometricVaultManager.self) private var vault

    @Query(filter: #Predicate<CategoryTemplate> { $0.isSensitive }) private var lockedTemplates: [CategoryTemplate]
    @State private var isOnScreen = false

    @State private var source: CaptureSource?
    @State private var flow: CaptureFlowInput?
    @State private var isAddingManually = false
    @State private var isPracticingShare = false
    @State private var toast: DSToast?
    @State private var practiceItem: InboxItem?
    @State private var unreadableItem: UnreadableInboxItem?

    private var inbox: IntakeInbox { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                if !pending.isEmpty || !inbox.unreadable.isEmpty { reviewSection }
                waysIn
                shareCard
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.background)
        .navigationTitle("Adaugă")
        .dsAnimation(value: pending.map(\.id))
        .dsAnimation(value: inbox.unreadable.map(\.id))
        .dsAnimation(value: inbox.previews)
        .onAppear {
            isOnScreen = true
            markSeen()
        }
        .onDisappear { isOnScreen = false }
        .onChange(of: inbox.items) { _, _ in markSeen() }
        .onChange(of: scenePhase) { _, _ in markSeen() }
        .dsToast($toast)
        .captureSourcePicker($source) { payload in
            flow = CaptureFlowInput(payload: payload)
        } onError: { error in
            toast = UpcomingActions.failureToast(error)
        }
        .sheet(item: $flow) { input in
            CaptureFlowView(input: input) { result in
                flow = nil
                show(result)
            }
        }
        .confirmationDialog(
            Text("E factura de probă"),
            isPresented: Binding(get: { practiceItem != nil }, set: { if !$0 { practiceItem = nil } }),
            titleVisibility: .visible,
            presenting: practiceItem
        ) { item in
            Button("Deschide-o ca să vezi cum se citește") { read(item) }
            Button("Șterge-o", role: .destructive) { inbox.remove(item) }
            Button("Renunță", role: .cancel) {}
        } message: { _ in
            Text("Ai văzut cum ajunge aici o factură. Datele de pe ea nu sunt reale.")
        }
        .confirmationDialog(
            Text("Nu am putut deschide ce ai trimis"),
            isPresented: Binding(get: { unreadableItem != nil }, set: { if !$0 { unreadableItem = nil } }),
            titleVisibility: .visible,
            presenting: unreadableItem
        ) { item in
            Button("Șterge", role: .destructive) { inbox.remove(item) }
            Button("Renunță", role: .cancel) {}
        } message: { _ in
            Text("S-a stricat pe drum sau vine de la o versiune mai nouă a aplicației. Trimite-l din nou din aplicația din care a venit.")
        }
        .sheet(isPresented: $isAddingManually) {
            ManualAddFlow { message in
                isAddingManually = false
                if let message { toast = DSToast(title: message, actionTitle: nil, action: nil) }
            }
        }
        .sheet(isPresented: $isPracticingShare) {
            NavigationStack {
                SharePracticeView(isOnboarding: false) { isPracticingShare = false }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Închide") { isPracticingShare = false }
                        }
                    }
            }
        }
    }

    private var pending: [InboxItem] {
        inbox.waiting
    }

    // MARK: Ways in

    private var waysIn: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            if CaptureSource.isCameraAvailable {
                DSActionCard("Fotografiază un act", subtitle: "Pagina se îndreaptă singură. Poți face mai multe pagini.", systemImage: "camera.fill") {
                    source = .camera
                }
            }
            DSActionCard("Alege din poze", subtitle: "O poză cu actul, făcută mai demult.", systemImage: "photo.on.rectangle") {
                source = .photos
            }
            DSActionCard("Din Fișiere", subtitle: "Un PDF sau o poză salvată pe telefon.", systemImage: "folder.fill") {
                source = .files
            }
            DSActionCard("Scriu eu", subtitle: "Alegi secțiunea, apoi ce adaugi: un termen, o vizită, un act.", systemImage: "square.and.pencil") {
                isAddingManually = true
            }
        }
    }

    private var shareCard: some View {
        Button { isPracticingShare = true } label: {
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    HStack(alignment: .top, spacing: DS.Space.s) {
                        DSIconWell(systemImage: "square.and.arrow.up", tint: DS.Palette.accent)
                        Text("Ai primit o factură pe mail sau WhatsApp? Trimite-o direct aici.")
                            .dsFont(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("Apeși „Trimite” în aplicația unde ai primit-o și alegi Dosar cu Șină. Îți arăt cum, cu o factură de probă.")
                        .dsFont(.subheadline)
                    Text("Arată-mi cum")
                        .font(.headline)
                        .foregroundStyle(DS.Palette.accent)
                        .frame(minHeight: 44)
                }
            }
        }
        .buttonStyle(.dsPressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: De verificat

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader("De verificat", subtitle: "Ce ai trimis din alte aplicații.", count: pending.count + inbox.unreadable.count)
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(Array(pending.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { DS.Hairline() }
                        inboxRow(item)
                    }
                    ForEach(Array(inbox.unreadable.enumerated()), id: \.element.id) { index, item in
                        if index > 0 || !pending.isEmpty { DS.Hairline() }
                        unreadableRow(item)
                    }
                }
            }
        }
        .transition(DS.Motion.transition(from: .top, reduceMotion: reduceMotion))
    }

    /// The categories behind Face ID, by key.
    private var lockedCategories: Set<String> {
        Set(lockedTemplates.map(\.key))
    }

    private func row(_ item: InboxItem) -> InboxWording.Row {
        inbox.row(for: item, lockedCategories: lockedCategories, isSessionUnlocked: vault.isSessionUnlocked)
    }

    private func inboxRow(_ item: InboxItem) -> some View {
        let row = row(item)
        let picture = row.showsThumbnail ? inbox.thumbnails[item.id].map { Image(uiImage: $0) } : nil
        return Button { open(item) } label: {
            DSListRow(
                title: Text(verbatim: row.title),
                subtitle: Text(verbatim: row.detail),
                thumbnail: DSThumbnailWell(image: picture, systemImage: row.symbol),
                showsChevron: true,
                trailing: {
                    if item.isPractice { Text("Exercițiu") }
                }
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Verifică", systemImage: "doc.text.magnifyingglass") { open(item) }
            Button("Șterge", systemImage: "trash", role: .destructive) { dismiss(item) }
        }
        .accessibilityAction(named: Text("Șterge")) { dismiss(item) }
        .accessibilityHint(row.isProtected ? Text("Deschide după deblocare, ca să verifici și să salvezi.") : Text("Deschide ca să verifici și să salvezi."))
    }

    /// Something that arrived but couldn't be opened: said calmly, with a way to remove it.
    private func unreadableRow(_ item: UnreadableInboxItem) -> some View {
        Button { unreadableItem = item } label: {
            DSListRow(
                title: Text("Nu am putut deschide"),
                subtitle: Text(verbatim: InboxWording.received(item.setAsideAt)),
                thumbnail: DSThumbnailWell(image: nil, systemImage: "questionmark.folder"),
                showsChevron: true,
                trailing: { EmptyView() }
            )
        }
        .buttonStyle(.plain)
        .accessibilityAction(named: Text("Șterge")) { inbox.remove(item) }
        .accessibilityHint(Text("Spune ce poți face cu el."))
    }

    // MARK: Actions

    private func open(_ item: InboxItem) {
        if item.isPractice {
            practiceItem = item
        } else if row(item).isProtected {
            // It belongs to a locked category: what it is shows only after unlocking.
            Task {
                guard await vault.unlock(reason: String(localized: "Deschide ce ai trimis", comment: "Face ID reason: open something shared that belongs to a locked section.")) == .success else { return }
                read(item)
            }
        } else {
            read(item)
        }
    }

    /// What De verificat shows now counts as seen, while it is on screen.
    private func markSeen() {
        guard isOnScreen, scenePhase == .active else { return }
        InboxLanding.shared.markSeen(pending)
    }

    private func read(_ item: InboxItem) {
        do {
            let payload = try CaptureInput.payload(inboxItem: item, files: inbox.fileURLs(of: item))
            flow = CaptureFlowInput(payload: payload, inboxItem: item)
        } catch {
            toast = UpcomingActions.failureToast(error)
        }
    }

    /// Hides the item at once and removes it for good once its toast is gone.
    private func dismiss(_ item: InboxItem) {
        inbox.setAside(item)
        // Outside the database: the item only leaves the inbox once the undo can't come any more.
        let title = row(item).title
        var leaving = DSToast(title: "Am scos „\(title)” din De verificat.", action: { inbox.keep(item) })
        leaving.whenGone = { inbox.remove(item) }
        toast = leaving
    }

    private func show(_ result: CaptureFlowResult) {
        switch result {
        case .filed(let toast, _), .visitSaved(let toast):
            self.toast = toast
        case .dismissed:
            break
        }
    }
}
