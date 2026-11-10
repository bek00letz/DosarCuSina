import Foundation
import FoundationModels
import Testing
@testable import DosarCuSina

/// Apple's on-device model asks one question per session, each carrying as much of the text
/// as its budget leaves: the model's context, less a margin, the instructions, the schema,
/// the question and room for the answer. The model doesn't run in tests; the arithmetic, the
/// estimate and the prompts are pinned here. Text is placeholders only.
@Suite("On-device prompt budget")
struct OnDevicePromptBudgetTests {

    @Test("The text a question carries is what its context leaves")
    func budgetArithmetic() {
        let budget = OnDevicePromptBudget(contextSize: 4096, questionTokens: 900, answerTokens: 400)
        // 4096, less a tenth (410 rounded up), the question and the answer.
        #expect(budget.textTokens == 4096 - 410 - 900 - 400)
        #expect(budget.fits)
        #expect(budget.characters() == Int(Double(2386) * OnDevicePromptBudget.estimatedCharactersPerToken))
        // Never more than the most a question reads, however large the context.
        #expect(OnDevicePromptBudget(contextSize: 1_000_000, questionTokens: 900, answerTokens: 400).characters() == OnDevicePromptBudget.maxCharacters)
        // No room for text: the question isn't asked.
        let full = OnDevicePromptBudget(contextSize: 1024, questionTokens: 900, answerTokens: 400)
        #expect(full.textTokens == 0)
        #expect(!full.fits)
        #expect(full.characters() == 0)
        #expect(!OnDevicePromptBudget(contextSize: 4096, questionTokens: 3100, answerTokens: 500).fits, "Under the minimum")
    }

    @Test("Counted text is kept whole when it fits, else cut in proportion")
    func measuredBudget() {
        let budget = OnDevicePromptBudget(contextSize: 4096, questionTokens: 900, answerTokens: 400)
        #expect(budget.characters(measuredCharacters: 3000, measuredTokens: 1200) == 3000)
        let cut = budget.characters(measuredCharacters: 6000, measuredTokens: 3000)
        #expect(cut == Int((6000 * (Double(2386) / 3000 * 0.95)).rounded(.down)))
        #expect(cut < 6000)
        #expect(OnDevicePromptBudget(contextSize: 1024, questionTokens: 900, answerTokens: 400).characters(measuredCharacters: 3000, measuredTokens: 10) == 0)
    }

    @Test("The answer's room grows with the fields asked, and a list of lines takes the most")
    func answerRoom() {
        let bill = ModelQuestions(kind: .utilityInvoice, reader: .text)
        #expect(OnDevicePromptBudget.answerTokens(for: bill)
                == OnDevicePromptBudget.answerOverhead + bill.fields.count * OnDevicePromptBudget.tokensPerField)
        let invoice = ModelQuestions(kind: .serviceInvoice, reader: .text)
        #expect(OnDevicePromptBudget.answerTokens(for: invoice)
                == OnDevicePromptBudget.answerOverhead + (invoice.fields.count - 1) * OnDevicePromptBudget.tokensPerField
                + OnDeviceSchema.maximumLines * OnDevicePromptBudget.tokensPerLine)
        #expect(OnDevicePromptBudget.estimatedTokens(characters: 10) == 4)
        #expect(OnDevicePromptBudget.retryLength(after: 3000) == 1500)
    }

    @Test("A long bill's facts fit the smallest context with room for the answer")
    func longBillFits() throws {
        let questions = ModelQuestions(kind: .utilityInvoice, reader: .text)
        let schema = try OnDeviceSchema.facts(questions)
        let question = OnDeviceModelExtractor.factsPrompt(.utilityInvoice, text: "")
        let fixed = OnDeviceTokenCounter.estimatedTokens(instructions: OnDeviceModelExtractor.instructions, schema: schema, question: question)
        let budget = OnDevicePromptBudget(contextSize: 4096, questionTokens: fixed, answerTokens: OnDevicePromptBudget.answerTokens(for: questions))
        #expect(budget.fits, "A bill's 14 questions leave room for its text")
        let used = fixed + OnDevicePromptBudget.estimatedTokens(characters: budget.characters()) + OnDevicePromptBudget.answerTokens(for: questions)
        #expect(used <= 4096, "Instructions, schema, text and answer fit the context: \(used)")
    }

    @Test("Each question carries its own text, and text is cut at a line's end")
    func promptsCarryTheirText() {
        let prompt = OnDeviceModelExtractor.factsPrompt(.rcaPolicy, text: "Poliță RCA Seria RO/00/X00/XX nr. 012345678")
        #expect(prompt.contains("Poliță RCA Seria RO/00/X00/XX nr. 012345678"))
        #expect(prompt.contains(CaptureDocumentKind.rcaPolicy.profile.modelDescription))
        let text = "Prima linie\nA doua linie\nA treia"
        #expect(OnDevicePromptBudget.cut(text, to: 20) == "Prima linie")
        #expect(OnDevicePromptBudget.cut(text, to: 100) == text)
    }
}
