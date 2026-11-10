import Foundation
import Testing
@testable import DosarCuSina

/// One way to fold Romanian text and one way to find a keyword in it, used by
/// search, choices, every capture reader and the classifier.
@Suite("Romanian text")
struct RomanianTextTests {
    @Test(arguments: [
        ("Poliță", "polita"), ("POLIŢĂ", "polita"), ("Ştefan Ţurcanu", "stefan turcanu"),
        ("Îndrumar  Auto", "indrumar  auto"), ("12\u{00A0}345", "12 345"), ("−5", "-5"), ("Ｂ-１２３", "b-123"),
    ])
    func foldsCaseDiacriticsAndSpacesTheSameEverywhere(text: String, folded: String) {
        #expect(RomanianText.fold(text) == folded)
        // Search, choices and capture agree on what two texts say.
        #expect(SearchText.normalize(text) == RomanianText.words(text).joined(separator: " "))
        #expect(ChoiceOption.fold(text) == RomanianText.fold(text).split(whereSeparator: \.isWhitespace).joined(separator: " "))
    }

    /// Near misses: a longer word that only contains the keyword is a different word.
    @Test(arguments: [
        ("paid", "Asigurare PAID obligatorie", true),
        ("paid", "Invoice unpaid", false),
        ("index", "Index nou: 12.345", true),
        ("pod", "Podea laminată", false),
        ("rca", "Poliță RCA nr. 123", true),
        ("rca", "Marca: VW", false),
        ("achitat", "Achitat integral", true),
        ("achitat", "Rest neachitat 20 lei", false),
        ("cont", "Cont IBAN RO49", true),
        ("cont", "Control frâne", false),
        ("pad", "Poliță PAD", true),
        ("pad", "Spadă", false),
        ("kwh", "Consum 120kWh", true),
    ])
    func keywordsMatchWholeWords(keyword: String, text: String, found: Bool) {
        #expect(RomanianText.containsWord(keyword, in: text) == found)
        #expect(CaptureText(text).containsWord(keyword) == found)
    }

    @Test(arguments: [
        ("garanti", "Certificat de garanție 24 luni", true),
        ("scadent", "Data scadentă: 15.11.2026", true),
        ("total de plata", "TOTAL DE PLATĂ 120,00", true),
        ("total de plata", "Total general de plată", false),
        ("bon fiscal", "BON  FISCAL", true),
        ("bon fiscal", "bonus fiscal", false),
        ("valabila pana la", "Valabilă până la: 01.03.2027", true),
    ])
    func phrasesAndEndings(keyword: String, text: String, found: Bool) {
        #expect(CaptureText(text).containsWord(keyword) == found)
    }

    @Test func linesAndLabelsUseTheSameMatch() {
        let text = CaptureText("Control frâne 120,00\nCont IBAN RO49AAAA1B31007593840000\nRest neachitat")
        #expect(text.lines(containing: ["cont"]) == [1])
        #expect(!text.contains(any: ["achitat"]))
    }

    @Test func classifierKeepsMeterIndexApartFromIndexation() {
        let bill = DocumentClassifier.classify(text: CaptureText("Furnizor gaze naturale\nIndex nou 12.345\nCod loc de consum 123"), mrz: nil)
        #expect(bill.kind == .utilityInvoice)
        #expect(!CaptureText.containsWord("index", inFolded: "indexare pret", as: CaptureLexicon.wholeSignalWords.contains("index") ? .word : nil))
    }
}
