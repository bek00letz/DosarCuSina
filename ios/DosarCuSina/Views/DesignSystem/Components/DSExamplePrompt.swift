import SwiftData
import SwiftUI

extension View {
    /// Asks "Păstrezi „VW Golf” ca a ta?" when the person added something of their own to an
    /// example section (an action threw `ExampleSectionQuestion`). Yes makes the section and
    /// everything in it theirs (`ExampleDataService.adopt`), then runs `onKeep` to save again.
    /// No leaves the example as it was, and nothing is saved.
    func examplePrompt(_ question: Binding<ExampleSectionQuestion?>, onKeep: @escaping () -> Void) -> some View {
        modifier(DSExamplePromptModifier(question: question, onKeep: onKeep))
    }
}

private struct DSExamplePromptModifier: ViewModifier {
    @Binding var question: ExampleSectionQuestion?
    let onKeep: () -> Void

    @Environment(\.modelContext) private var context
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .alert(
                Text(verbatim: question?.question ?? ""),
                isPresented: Binding(get: { question != nil }, set: { if !$0 { question = nil } }),
                presenting: question
            ) { question in
                Button("Da, păstrez") { keep(question) }
                Button("Nu", role: .cancel) {}
            } message: { question in
                Text(verbatim: question.explanation)
            }
            .alert("Nu am putut păstra exemplul", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: failure ?? "")
            }
            .sensoryFeedback(.selection, trigger: question?.sectionID)
    }

    private func keep(_ question: ExampleSectionQuestion) {
        do {
            try ExampleDataService(context: context).adopt(sectionID: question.sectionID)
            onKeep()
        } catch {
            failure = SaveFailure.message(for: error, formKept: true)
        }
    }
}
