import SwiftUI
import UniformTypeIdentifiers

/// A secret value, such as a PIN code, shown masked. "Arată" and "Copiază" each
/// ask for Face ID (or the passcode) first, every time, through `open`. A shown
/// code hides again after `visibleFor`, and at once when the app leaves the
/// screen. A copied code stays on this phone's clipboard for a minute only.
struct DSSecretValueRow: View {
    let title: Text
    var footnote: Text?
    /// Whether a code is kept at all.
    let isSet: Bool
    /// Authenticates and opens the code.
    let open: @MainActor () async -> SecretReveal.Outcome

    /// How long a shown code stays on screen.
    static let visibleFor: Duration = .seconds(30)
    /// How long a copied code stays on the clipboard.
    static let clipboardLifetime: TimeInterval = 60

    @State private var shown: String?
    @State private var message: String?
    @State private var isOpening = false
    @State private var copied = 0
    @State private var copiedNote = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s))
                : AnyLayout(HStackLayout(spacing: DS.Space.s))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    title.dsFont(.footnote)
                    value
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if isSet { buttons }
            }
            if let footnote { footnote.dsFont(.footnote) }
            if copiedNote {
                Label {
                    Text("Copiat. Se șterge singur din memorie într-un minut.", comment: "Note after copying a secret code.")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DSStatus.done.color)
                }
                .dsFont(.footnote)
                .transition(.opacity)
            }
            if let message {
                Text(verbatim: message)
                    .dsFont(.footnote)
                    .foregroundStyle(DSStatus.overdue.textColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DS.Space.xs)
        .sensoryFeedback(.success, trigger: copied)
        .animation(DS.Motion.animation(DS.Motion.quick, reduceMotion: reduceMotion), value: shown)
        .task(id: shown) {
            guard shown != nil else { return }
            try? await Task.sleep(for: Self.visibleFor)
            guard !Task.isCancelled else { return }
            shown = nil
        }
        .animation(DS.Motion.animation(DS.Motion.quick, reduceMotion: reduceMotion), value: copiedNote)
        .task(id: copied) {
            guard copied > 0 else { return }
            copiedNote = true
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            copiedNote = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { shown = nil }
        }
    }

    @ViewBuilder
    private var value: some View {
        if let shown {
            Text(verbatim: shown)
                .dsFont(.headline, numeric: true)
                .monospaced()
                .privacySensitive()
                .contentTransition(.opacity)
        } else if isSet {
            Text(verbatim: SecretFields.mask)
                .dsFont(.headline)
                .accessibilityLabel(Text("Ascuns", comment: "VoiceOver label of a hidden secret code."))
        } else {
            Text("Nescris", comment: "A secret field with no code kept.")
                .dsFont(.headline)
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
    }

    private var buttons: some View {
        HStack(spacing: DS.Space.xs) {
            Button {
                if shown != nil { shown = nil } else { Task { await reveal() } }
            } label: {
                Label(shown == nil ? LocalizedStringKey("Arată") : LocalizedStringKey("Ascunde"),
                      systemImage: shown == nil ? "eye" : "eye.slash")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            Button {
                Task { await copy() }
            } label: {
                Label("Copiază", systemImage: "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .disabled(isOpening)
    }

    private func reveal() async {
        guard let code = await opened() else { return }
        shown = code
    }

    private func copy() async {
        guard let code = await opened() else { return }
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: code]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(Self.clipboardLifetime)]
        )
        copied += 1
        AccessibilityNotification.Announcement(String(localized: "Copiat. Se șterge singur din memorie într-un minut.", comment: "Note after copying a secret code.")).post()
        message = nil
    }

    private func opened() async -> String? {
        isOpening = true
        defer { isOpening = false }
        switch await open() {
        case .revealed(let code):
            message = nil
            return code
        case .notAuthenticated:
            return nil
        case .failed(let error):
            message = error.errorDescription
            return nil
        }
    }
}
