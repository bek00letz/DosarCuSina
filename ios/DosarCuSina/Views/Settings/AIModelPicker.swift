import SwiftUI

/// Picks the model a provider reads documents with: the recommended one, any
/// model the person's key can use (asked from the provider, newest first), or a
/// name typed by hand. The choice is saved straight away.
struct AIModelPicker: View {
    let provider: AIProvider
    @Binding var model: String

    private let settings = AIProviderSettings.standard
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Equatable {
        case loading
        case loaded([AIModel])
        case needsKey
        case failed(AIProviderError)
    }

    @State private var phase: Phase = .loading
    @State private var typed = ""

    /// What the Settings row shows: the chosen model, or the recommended one.
    static func summary(model: String, provider: AIProvider) -> String {
        if !model.isEmpty { return model }
        if provider.defaultModel.isEmpty {
            return String(localized: "Alege un model", comment: "AI setting: no model chosen yet for a custom service.")
        }
        return String(localized: "Recomandat (\(provider.defaultModel))", comment: "AI setting: the recommended model is used. The argument is its name.")
    }

    var body: some View {
        List {
            if !provider.defaultModel.isEmpty {
                Section {
                    row(provider.defaultModel, detail: nil, isChosen: model.isEmpty || model == provider.defaultModel) { choose("") }
                } header: {
                    Text("Recomandat", comment: "AI model picker: the recommended model.")
                } footer: {
                    Text("Merge bine pentru acte și facturi, la un cost mic.", comment: "AI model picker: why the recommended model.")
                }
            }

            Section {
                switch phase {
                case .loading:
                    DSDelayedProgress(label: "Întreb \(provider.pickerName) ce modele poți folosi…")
                        .frame(maxWidth: .infinity, minHeight: 44)
                case .needsKey where provider == .openAICompatible:
                    Text("Scrie întâi adresa serviciului și apasă „Testează”. Apoi îți arăt modelele lui.", comment: "AI model picker: the custom service's address is missing.")
                        .dsFont(.footnote)
                case .needsKey:
                    Text("Pune întâi cheia și apasă „Testează”. Apoi îți arăt modelele pe care le poate folosi.", comment: "AI model picker: no key saved yet.")
                        .dsFont(.footnote)
                case .failed(let error):
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text(verbatim: error.message(provider: provider)).dsFont(.footnote)
                        Button {
                            Task { await load() }
                        } label: {
                            Text("Încearcă din nou", comment: "Retries listing the AI models.").frame(minHeight: 44)
                        }
                    }
                case .loaded(let models) where models.isEmpty:
                    Text("Cheia nu are acces la modele care citesc poze. Poți scrie numele unui model mai jos.", comment: "AI model picker: the key lists no usable models.")
                        .dsFont(.footnote)
                case .loaded(let models):
                    ForEach(models.filter { $0.id != provider.defaultModel }) { option in
                        row(option.id, detail: option.displayName, isChosen: model == option.id) { choose(option.id) }
                    }
                }
            } header: {
                Text("Modelele cheii tale", comment: "AI model picker: the models the person's key can use.")
            }

            Section {
                DSTextField("Numele modelului", text: $typed, prompt: "de exemplu gemini-3.8-pro")
                Button {
                    choose(typed.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: {
                    Text("Folosește acest model", comment: "Uses the typed AI model name.").frame(minHeight: 44)
                }
                .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Scriu eu numele", comment: "AI model picker: type a model name by hand.")
            }
        }
        .navigationTitle(Text("Model", comment: "AI model picker title."))
        .navigationBarTitleDisplayMode(.inline)
        .dsAnimation(value: phase)
        .task { await load() }
    }

    private func row(_ id: String, detail: String?, isChosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: id).dsFont(.body).foregroundStyle(DS.Palette.label)
                    if let detail, detail != id {
                        Text(verbatim: detail).dsFont(.footnote)
                    }
                }
                Spacer(minLength: DS.Space.s)
                if isChosen {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.Palette.accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    /// Saves the choice; the recommended model is saved as "no choice", so it follows future updates.
    private func choose(_ id: String) {
        let saved = id == provider.defaultModel ? "" : id
        settings.setCustomModel(saved, for: provider)
        model = saved
        dismiss()
    }

    private func load() async {
        guard let config = settings.connection(for: provider) else {
            phase = .needsKey
            return
        }
        phase = .loading
        do {
            phase = .loaded(try await AIClient().listModels(config: config))
        } catch {
            phase = .failed(AIProviderError(transport: error))
        }
    }
}
