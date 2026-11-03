import SwiftUI

/// What the last unlock attempt said, in plain words. A failed or cancelled
/// attempt only keeps this one place closed; the person stays in the app.
enum UnlockFeedback: Equatable {
    case none
    case cancelled
    case failed

    init(_ result: UnlockResult) {
        switch result {
        case .success: self = .none
        case .cancelled: self = .cancelled
        case .failed: self = .failed
        }
    }

    var message: String? {
        switch self {
        case .none: nil
        case .cancelled: String(localized: "Ai anulat. Restul aplicației merge normal; aici intri când vrei.", comment: "After cancelling Face ID on a locked section.")
        case .failed: String(localized: "Nu te-am recunoscut. Încearcă din nou sau folosește codul telefonului.", comment: "After a failed Face ID attempt.")
        }
    }
}

/// A locked section: calm, with one button that asks for Face ID. Nothing of
/// what is inside shows until it opens.
struct LockedSectionView: View {
    let title: String
    @Environment(BiometricVaultManager.self) private var vault
    @State private var feedback = UnlockFeedback.none
    @State private var attempts = 0

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.m) {
                DSLockedState(
                    title: Text("„\(title)” e protejat", comment: "Title of a locked section. The name is the section's."),
                    systemImage: vault.biometrySymbol,
                    message: Text("Deschide cu \(vault.biometryName) ca să vezi ce e înăuntru.", comment: "Message on a locked section."),
                    unlockTitle: Text("Deblochează", comment: "Button that asks for Face ID to open a locked section."),
                    isWorking: vault.isAuthenticating,
                    unlock: unlock
                )
                if let message = feedback.message {
                    Text(verbatim: message)
                        .dsFont(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Space.xl)
                        .transition(.opacity)
                }
            }
            .padding(.top, DS.Space.xxl)
            .dsAnimation(value: feedback)
        }
        .background(DS.Palette.background)
        .sensoryFeedback(.error, trigger: attempts) { _, _ in feedback == .failed }
    }

    private func unlock() {
        Task {
            let result = await vault.unlock(reason: String(localized: "Deschide secțiunea „\(title)”.", comment: "Face ID reason for opening a locked section."))
            feedback = UnlockFeedback(result)
            attempts += 1
        }
    }
}

/// Covers the whole app while the app lock is on and the session is closed.
/// It asks for Face ID as soon as it appears and whenever the app comes back.
struct AppLockView: View {
    @Environment(BiometricVaultManager.self) private var vault
    @Environment(\.scenePhase) private var scenePhase
    @State private var feedback = UnlockFeedback.none

    var body: some View {
        ZStack {
            DS.Palette.background.ignoresSafeArea()
            VStack(spacing: DS.Space.m) {
                DSLockedState(
                    title: Text("Dosar cu Șină e blocat", comment: "Title of the app lock screen."),
                    systemImage: vault.biometrySymbol,
                    message: Text("Deschide cu \(vault.biometryName).", comment: "Message on the app lock screen."),
                    unlockTitle: Text("Deblochează", comment: "Button that asks for Face ID to open a locked section."),
                    isWorking: vault.isAuthenticating,
                    unlock: unlock
                )
                if let message = feedback.message {
                    Text(verbatim: message)
                        .dsFont(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Space.xl)
                }
            }
        }
        .task { unlock() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, feedback == .none { unlock() }
        }
    }

    private func unlock() {
        guard !vault.isAuthenticating else { return }
        Task {
            let result = await vault.unlock(reason: String(localized: "Deschide Dosar cu Șină.", comment: "Face ID reason for the app lock."))
            feedback = UnlockFeedback(result)
        }
    }
}

/// Hides the screen in the app switcher (`LockCover.privacy`).
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(DS.Palette.secondaryLabel)
                .accessibilityHidden(true)
        }
    }
}
