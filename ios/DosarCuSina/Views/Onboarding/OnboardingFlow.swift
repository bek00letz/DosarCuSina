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
        .captureSourcePicker($source) { payload in
            flow = CaptureFlowInput(payload: payload)
        } onError: { error in
            errorMessage = error.localizedDescription
        }
        .sheet(item: $flow) { input in
            CaptureFlowView(input: input) { result in
                flow = nil
                switch result {
                case .filed(let message), .visitSaved(let message):
                    photoMessage = message
                case .dismissed:
                    break
                }
            }
        }
    }

    private var motion: Animation { DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion) }

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

/// One onboarding screen: a few symbols, a headline, one paragraph and its buttons.
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
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: DS.Space.s) { actions }
                .padding(DS.Space.m)
                .background(DS.Palette.background)
        }
        .background(DS.Palette.background)
    }
}
