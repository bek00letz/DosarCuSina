import Foundation
import Testing
@testable import DosarCuSina

/// Language-model answers are only kept when they're grounded in the recognized text.
@Suite("Model answer grounding")
struct ModelAnswerGroundingTests {

    let source = """
    Exemplu Asigurări S.A.
    Polița nr. AB 012345678
    Avizare daune: 0800 123 456
    Prima: 1.240,00 lei
    Valabilă până la 06.11.2027
    """

    @Test("Identifiers that appear in the text are kept")
    func groundedIdentifiers() {
        var answers = ModelAnswerMapper.Answers()
        answers.policyNumber = "AB 012345678"
        answers.claimsPhone = "0800 123 456"
        answers.totalAmount = "1240.00"
        answers.expiryDate = "2027-11-06"
        let extraction = ModelAnswerMapper.fields(from: answers, sourceText: source, tier: .onDeviceModel, resolver: KeywordComponentResolver())
        let keys = Set(extraction.fields.map(\.key))
        #expect(keys == [.policyNumber, .claimsPhone, .total, .expiryDate])
        #expect(extraction.fields.allSatisfy { $0.tier == .onDeviceModel })
    }

    @Test("Invented identifiers are dropped")
    func inventedIdentifiers() {
        var answers = ModelAnswerMapper.Answers()
        answers.policyNumber = "XY 999999999"
        answers.licensePlate = "B 999 ZZZ"
        answers.totalAmount = "5000"
        answers.expiryDate = "2027-02-30"
        let extraction = ModelAnswerMapper.fields(from: answers, sourceText: source, tier: .onDeviceModel, resolver: KeywordComponentResolver())
        #expect(extraction.fields.isEmpty)
    }

    @Test("The model's document kind is used only when it names a real kind")
    func kind() {
        var answers = ModelAnswerMapper.Answers()
        answers.kind = "insurancePolicy"
        #expect(ModelAnswerMapper.fields(from: answers, sourceText: source, tier: .onDeviceModel, resolver: KeywordComponentResolver()).kind == .insurancePolicy)
        answers.kind = "spaceship"
        #expect(ModelAnswerMapper.fields(from: answers, sourceText: source, tier: .onDeviceModel, resolver: KeywordComponentResolver()).kind == nil)
    }
}
