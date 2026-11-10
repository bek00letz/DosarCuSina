import SwiftData
import SwiftUI

/// First run, short and skippable: what the app is, an optional first photo,
/// the share practice, and examples or an empty start. No permission is asked
/// here; notifications are asked the first time a reminder is saved, the
/// camera the first time it is opened. The shell decides when it shows and
/// calls `onFinish`; the Adaugă card replays the share practice on its own.
struct OnboardingFlow: View {
    let onFinish: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, photo, share, examples
    }

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .welcome
    @State private var source: CaptureSource?
    @State private var flow: CaptureFlowInput?
    @State private var photoMessage: LocalizedStringResource?
    @State private var errorMessage: String?
    @State private var isLoadingExamples = false
    /// The first photo's toast, with its "Anulează". Onboarding covers the whole screen, the
    /// shell's toast host with it, so it shows its own.
    @State private var toast: DSToast?

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcome
                case .photo: photo
                case .share: SharePracticeView(isOnboarding: true) { advance() }
                case .examples: examples
                }
            }
            .id(step)
            .transition(DS.Motion.transition(from: .trailing, reduceMotion: reduceMotion))
            .toolbar {
                if step != .examples {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Sari peste") { withAnimation(motion) { step = .examples } }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Pasul \(step.rawValue + 1) din \(Step.allCases.count)")
                        .dsFont(.footnote, numeric: true)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .dsToast($toast)
        .captureSourcePicker($source) { payload in
            flow = CaptureFlowInput(payload: payload)
        } onError: { error in
            errorMessage = SaveFailure.message(for: error, formKept: true)
        }
        .sheet(item: $flow) { input in
            CaptureFlowView(input: input) { result in
                flow = nil
                guard let filed = Self.photoFiled(result, takenBack: { withAnimation(motion) { photoMessage = nil } }) else { return }
                photoMessage = filed.message
                toast = filed.toast
            }
        }
    }

    private var motion: Animation { DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion) }

    /// What the photo step shows once its capture closes: the message under "Gata" and the
    /// toast that can take the filing back. Taken back, `takenBack` runs, so the step offers
    /// the photo again. Nil when nothing was saved.
    @MainActor
    static func photoFiled(_ result: CaptureFlowResult, takenBack: @escaping @MainActor () -> Void) -> (message: LocalizedStringResource, toast: DSToast)? {
        guard var toast = result.toast else { return nil }
        let afterUndo = toast.afterUndo
        toast.afterUndo = { takenBack(); afterUndo?() }
        return (toast.title, toast)
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return onFinish() }
        withAnimation(motion) { step = next }
    }

    // MARK: Steps

    private var welcome: some View {
        OnboardingPage(
            symbols: ["car.fill", "house.fill", "pawprint.fill", "doc.text.fill"],
            title: "Dosarul tău cu acte, care te anunță din timp",
            message: "ITP-ul și RCA-ul mașinii, pașaportul, verificarea centralei, vaccinul pisicii. Le ții aici, cu actele lor, și îți spun din timp ce urmează."
        ) {
            DSPrimaryButton("Începe", action: advance)
        }
    }

    private var photo: some View {
        OnboardingPage(
            symbols: ["camera.fill"],
            title: "Fotografiază un act",
            message: "O poliță, un pașaport, o factură. Îl citesc pe telefon și îți arăt ce am găsit înainte să salvez ceva."
        ) {
            if let photoMessage {
                DSNotice(.success, title: "Gata", message: LocalizedStringKey(String(localized: photoMessage)))
                DSPrimaryButton("Continuă", action: advance)
            } else {
                if let errorMessage {
                    DSNotice(.warning, title: "Nu s-a deschis", message: LocalizedStringKey(errorMessage))
                }
                DSPrimaryButton(CaptureSource.isCameraAvailable ? "Fotografiază acum" : "Alege o poză", systemImage: "camera.fill") {
                    source = CaptureSource.isCameraAvailable ? .camera : .photos
                }
                DSSecondaryButton("Mai târziu", action: advance)
            }
        }
    }

    private var examples: some View {
        OnboardingPage(
            symbols: ["sparkles"],
            title: "Cum vrei să începi?",
            message: "Cu exemple vezi cum arată un dosar plin: o mașină, o casă, un câine. Le ștergi cu o atingere din Setări."
        ) {
            if let errorMessage {
                DSNotice(.error, title: "Exemplele nu s-au încărcat", message: LocalizedStringKey(errorMessage))
            }
            DSPrimaryButton("Vreau să văd cu exemple", systemImage: "sparkles") { loadExamples() }
                .disabled(isLoadingExamples)
            DSSecondaryButton("Încep gol", action: onFinish)
        }
    }

    private func loadExamples() {
        isLoadingExamples = true
        do {
            try ExampleDataService(context: context).loadExamples()
            onFinish()
        } catch {
            isLoadingExamples = false
            errorMessage = String(localized: "Încearcă din nou. Poți începe și gol; exemplele se pot încărca oricând din Setări.")
        }
    }
}

/// One onboarding screen: a few symbols, a headline, one paragraph and its buttons, pinned
/// to the bottom edge (with the notice that goes with them) so they show at any text size.
private struct OnboardingPage<Actions: View>: View {
    let symbols: [String]
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder var actions: Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                HStack(spacing: DS.Space.s) {
                    ForEach(symbols, id: \.self) { symbol in
                        DSIconWell(systemImage: symbol)
                    }
                }
                .padding(.top, DS.Space.xl)
                Text(title)
                    .dsFont(.display)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .dsFont(.body)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            .padding(DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .dsPinnedAction { actions }
        .background(DS.Palette.background)
    }
}
