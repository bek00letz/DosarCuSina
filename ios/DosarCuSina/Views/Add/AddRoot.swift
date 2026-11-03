import SwiftData
import SwiftUI

/// The Adaugă tab: every way in. Four big buttons (camera, photos, files,
/// typing it in), the card that teaches sharing from Mail or WhatsApp, and
/// "De verificat" with what arrived from other apps.
///
/// It lives in the shell's navigation stack for this tab.
struct AddRoot: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var source: CaptureSource?
    @State private var flow: CaptureFlowInput?
    @State private var isAddingManually = false
    @State private var isPracticingShare = false
    @State private var toast: DSToast?
    @State private var hiddenItems: Set<UUID> = []
    @State private var practiceItem: InboxItem?

    private var inbox: IntakeInbox { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                if !pending.isEmpty { reviewSection }
                waysIn
                shareCard
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.background)
        .navigationTitle("Adaugă")
        .dsAnimation(value: pending.map(\.id))
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
        inbox.items.filter { !hiddenItems.contains($0.id) }
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
            DSSectionHeader("De verificat", subtitle: "Ce ai trimis din alte aplicații.", count: pending.count)
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(Array(pending.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { DS.Hairline() }
                        inboxRow(item)
                    }
                }
            }
        }
        .transition(DS.Motion.transition(from: .top, reduceMotion: reduceMotion))
    }

    private func inboxRow(_ item: InboxItem) -> some View {
        Button { open(item) } label: {
            DSListRow(
                title: Text(verbatim: InboxWording.title(item)),
                subtitle: Text(verbatim: InboxWording.received(item.receivedAt)),
                systemImage: InboxWording.symbol(item),
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
        .accessibilityHint(Text("Deschide ca să verifici și să salvezi."))
    }

    // MARK: Actions

    private func open(_ item: InboxItem) {
        if item.isPractice {
            practiceItem = item
        } else {
            read(item)
        }
    }

    private func read(_ item: InboxItem) {
        do {
            let payload = try CaptureInput.payload(inboxItem: item, files: inbox.fileURLs(of: item))
            flow = CaptureFlowInput(payload: payload, inboxItem: item)
        } catch {
            toast = UpcomingActions.failureToast(error)
        }
    }

    /// Hides the item at once and removes it for good once the undo has passed.
    private func dismiss(_ item: InboxItem) {
        hiddenItems.insert(item.id)
        // Outside the database: the item only leaves the inbox once the toast has passed.
        toast = DSToast(title: "Am scos „\(InboxWording.title(item))” din De verificat.", action: {
            hiddenItems.remove(item.id)
        })
        Task {
            try? await Task.sleep(for: .seconds(11))
            if hiddenItems.contains(item.id) {
                inbox.remove(item)
                hiddenItems.remove(item.id)
            }
        }
    }

    private func show(_ result: CaptureFlowResult) {
        switch result {
        case .filed(let message, _), .visitSaved(let message):
            toast = DSToast(title: message, actionTitle: nil, action: nil)
        case .dismissed:
            break
        }
    }
}

/// How an item from another app reads in the list.
enum InboxWording {
    static func title(_ item: InboxItem) -> String {
        if item.isPractice { return String(localized: "Factură de probă") }
        if let name = item.originalName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return (name as NSString).deletingPathExtension
        }
        switch item.payload {
        case .images: return String(localized: "\(item.files.count) poze", comment: "Photos received from another app")
        case .pdf: return String(localized: "Un PDF")
        case .text: return String(localized: "Un text")
        }
    }

    static func symbol(_ item: InboxItem) -> String {
        switch item.payload {
        case .images: return "photo"
        case .pdf: return "doc.richtext"
        case .text: return "text.alignleft"
        }
    }

    static func received(_ date: Date) -> String {
        let time = DosarFormat.time(date)
        if Calendar.current.isDateInToday(date) { return String(localized: "Primit azi la \(time)") }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "Primit ieri la \(time)") }
        let day = DosarFormat.dayMonth(date)
        return String(localized: "Primit pe \(day)")
    }
}
