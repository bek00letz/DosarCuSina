import Testing
@testable import DosarCuSina

/// Onboarding's last step: examples are offered only to a binder with nothing of the person's
/// in it, and never while their binder may still be coming down from iCloud.
@Suite("Onboarding's last step")
@MainActor
struct OnboardingStartTests {
    @Test("Onboarding offers examples only while nothing of the person's is in the binder")
    func onboardingOffersExamplesOnlyToAnEmptyBinder() {
        #expect(OnboardingFlow.start(binderMayBeArriving: false, waitedForICloud: false, hasRealSection: false) == .choose)
        #expect(OnboardingFlow.start(binderMayBeArriving: false, waitedForICloud: false, hasRealSection: true) == .started,
                "A document filed in the photo step: no examples")
        #expect(OnboardingFlow.start(binderMayBeArriving: false, waitedForICloud: true, hasRealSection: true) == .arrived)
        #expect(OnboardingFlow.start(binderMayBeArriving: true, waitedForICloud: false, hasRealSection: true) == .arriving)
        #expect(OnboardingFlow.start(binderMayBeArriving: false, waitedForICloud: true, hasRealSection: false) == .choose)
    }
}
