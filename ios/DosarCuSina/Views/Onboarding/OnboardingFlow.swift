import SwiftUI

/// First run, including the share-from-another-app practice. Placeholder
/// until the intake screens land; the shell shows it once and calls `onFinish`.
struct OnboardingFlow: View {
    let onFinish: () -> Void

    var body: some View {
        Button("Începe", action: onFinish)
    }
}
