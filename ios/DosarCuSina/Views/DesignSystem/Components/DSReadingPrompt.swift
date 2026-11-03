import SwiftUI

extension View {
    /// Asks "Kilometrajul e mai mic decât ultima dată. Corectez citirea veche?" when a save
    /// threw `LowerReadingQuestion`. "Corectează citirea veche" saves again with `.correctOld`
    /// (the earlier readings go), "Lasă citirea veche" with `.keepAside` (the new one is kept
    /// aside), and "Anulează" goes back to the form to fix the number; nothing was saved yet.
    func readingPrompt(_ question: Binding<LowerReadingQuestion?>, onAnswer: @escaping (LowerReadingAnswer) -> Void) -> some View {
        modifier(DSReadingPromptModifier(question: question, onAnswer: onAnswer))
    }
}

private struct DSReadingPromptModifier: ViewModifier {
    @Binding var question: LowerReadingQuestion?
    let onAnswer: (LowerReadingAnswer) -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                Text(verbatim: question?.question ?? ""),
                isPresented: Binding(get: { question != nil }, set: { if !$0 { question = nil } }),
                presenting: question
            ) { _ in
                Button("Corectează citirea veche") { onAnswer(.correctOld) }
                Button("Lasă citirea veche") { onAnswer(.keepAside) }
                Button("Anulează", role: .cancel) {}
            } message: { question in
                Text(verbatim: question.explanation)
            }
            .sensoryFeedback(.warning, trigger: question)
    }
}
