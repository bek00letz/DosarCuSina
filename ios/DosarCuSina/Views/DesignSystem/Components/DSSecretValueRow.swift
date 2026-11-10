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
    /// How long "Copiat" stays under the row after a copy.
    static let copiedNoteFor: Duration = .seconds(4)

    @State private var shown: String?
    @State private var message: String?
    @State private var isOpening = false
    @State private var copied = 0
    @State private var copiedNote = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            DSValueWithActions {
                VStack(alignment: .leading, spacing: 2) {
                    title.dsFont(.footnote)
                    value
                }
                .accessibilityElement(children: .combine)
            } actions: {
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
            try? await Task.sleep(for: Self.copiedNoteFor)
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
        Group {
            Button {
                if shown != nil { shown = nil } else { Task { await reveal() } }
            } label: {
                DSValueActionLabel(title: shown == nil ? "Arată" : "Ascunde", systemImage: shown == nil ? "eye" : "eye.slash")
            }
            Button {
                Task { await copy() }
            } label: {
                DSValueActionLabel(title: "Copiază", systemImage: "doc.on.doc")
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
        Clipboard.copy(code, .personal)
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
