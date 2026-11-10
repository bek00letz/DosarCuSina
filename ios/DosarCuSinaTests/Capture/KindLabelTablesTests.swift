import Foundation
import Testing
@testable import DosarCuSina

/// Each kind's printed labels are data in its profile (`CaptureKindProfile.labels`), and what
/// every document prints the same way is one shared table (`commonLabels`). The readers are
/// told the table, so a wording added to it is read with no change to any reader. All
/// names, companies, plates and numbers are placeholders.
@Suite("Kinds' label tables")
struct KindLabelTablesTests {

    let analyzer = CaptureAnalyzer()
    let today = Date(timeIntervalSince1970: 1_793_577_600)

    /// The rows each kind keeps of its own, beside the bill's.
    static let ownRows: [(kind: CaptureDocumentKind, keys: [CaptureFieldKey])] = [
        (.rcaPolicy, [.validityPeriod, .expiryDate, .claimsPhone, .bonusMalusClass]),
        (.insurancePolicy, [.validityPeriod, .expiryDate, .claimsPhone, .bonusMalusClass]),
        (.itpReport, [.expiryDate]),
        (.veterinaryRecord, [.microchip, .vaccineName, .nextDoseDate]),
        (.fiscalReceipt, [.purchaseDate, .warrantyMonths, .serialNumber]),
        (.warrantyCertificate, [.purchaseDate, .warrantyMonths, .serialNumber]),
        (.vehicleRegistration, [.civNumber, .make, .model, .firstRegistrationDate]),
    ]

    // MARK: The tables

    @Test("Each kind's own labels are in its profile")
    func eachKindKeepsItsOwnLabels() {
        for (kind, keys) in Self.ownRows {
            let own = Set(kind.profile.labels.map { $0.0 })
            for key in keys {
                #expect(own.contains(key), "\(kind): \(key) is a row of its table")
                #expect(!kind.profile.labels(for: key).isEmpty, "\(kind): \(key)")
            }
        }
    }

    @Test("What every document prints the same way is one table, read by every kind without a row of its own")
    func invoicesReadTheCommonTable() {
        for key in [CaptureFieldKey.issueDate, .total, .vin, .odometer, .invoiceNumber, .providerTaxID] {
            #expect(!CaptureKindProfile.commonLabels(for: key).isEmpty, "\(key)")
        }
        for kind in [CaptureDocumentKind.serviceInvoice, .other, .medicalResult, .itpReport, .veterinaryRecord] {
            #expect(kind.profile.labels(for: .issueDate) == CaptureKindProfile.commonLabels(for: .issueDate), "\(kind)")
        }
        for kind in [CaptureDocumentKind.serviceInvoice, .utilityInvoice, .other, .rcaPolicy, .fiscalReceipt] {
            #expect(kind.profile.labels(for: .total) == CaptureKindProfile.commonLabels(for: .total), "\(kind)")
        }
        // A bill's own issue-date wordings are its layout's (`BillReader`), not the common ones.
        #expect(CaptureDocumentKind.utilityInvoice.profile.labels(for: .issueDate) != CaptureKindProfile.commonLabels(for: .issueDate))
    }

    @Test("Labels are folded and name only what their kind carries", arguments: CaptureDocumentKind.allCases)
    func labelsAreFoldedAndBelong(kind: CaptureDocumentKind) {
        // Labels of the table that are never fields of their own: they only find a line.
        let lineLabels: Set<CaptureFieldKey> = [.validityPeriod, .previousMeterIndex]
        for (key, wordings) in kind.profile.labels {
            #expect(!wordings.isEmpty, "\(kind): \(key) has wordings")
            for wording in wordings {
                #expect(RomanianText.fold(wording) == wording, "\(kind): \"\(wording)\" is written folded")
            }
            guard !lineLabels.contains(key) else { continue }
            #expect(kind.allows(key), "\(kind): \(key) is a field it may carry")
        }
        for (key, wordings) in CaptureKindProfile.commonLabels {
            for wording in wordings {
                #expect(RomanianText.fold(wording) == wording, "\(key): \"\(wording)\" is written folded")
            }
        }
    }

    // MARK: Every wording is read

    /// The date rows: each wording alone before a date gives that date.
    static let dateRows: [(kind: CaptureDocumentKind, key: CaptureFieldKey)] = [
        (.rcaPolicy, .expiryDate), (.insurancePolicy, .expiryDate), (.itpReport, .expiryDate),
        (.veterinaryRecord, .nextDoseDate), (.fiscalReceipt, .purchaseDate), (.warrantyCertificate, .purchaseDate),
    ]

    @Test("Every wording of a kind's date row is read")
    func everyWordingOfADateRowIsRead() throws {
        let day = try #require(CalendarDay(printedYear: 2027, month: 3, day: 14))
        for (kind, key) in Self.dateRows {
            for wording in kind.profile.labels(for: key) {
                let analysis = analyzer.analyze(text: "Exemplu\n\(wording) 14.03.2027", referenceDate: today, as: kind)
                #expect(analysis.fields.first { $0.key == key }?.value == .day(day), "\(kind): \"\(wording)\"")
            }
        }
    }

    // MARK: A new wording is data

    struct NewWording: Sendable, CustomTestStringConvertible {
        let kind: CaptureDocumentKind
        /// The row the wording is added to.
        let row: CaptureFieldKey
        let wording: String
        let text: String
        /// The field the row gives, and its value.
        let reads: CaptureFieldKey
        let value: CaptureValue

        var testDescription: String { "\(kind) \(row): \(wording)" }
    }

    static let newWordings: [NewWording] = [
        NewWording(kind: .itpReport, row: .expiryDate, wording: "termen itp",
                   text: "STAȚIE ITP EXEMPLU S.R.L.\nNr. înmatriculare: B 123 ABC\nTermen ITP: 14.03.2027",
                   reads: .expiryDate, value: .day(CalendarDay(printedYear: 2027, month: 3, day: 14)!)),
        NewWording(kind: .itpReport, row: .odometer, wording: "km la inspectie",
                   text: "STAȚIE ITP EXEMPLU S.R.L.\nKm la inspecție: 86.420",
                   reads: .odometer, value: .metric(value: 86_420, unit: .kilometres)),
        NewWording(kind: .veterinaryRecord, row: .nextDoseDate, wording: "urmatoarea doza",
                   text: "CABINET VETERINAR EXEMPLU S.R.L.\nUrmătoarea doză: 18.11.2026",
                   reads: .nextDoseDate, value: .day(CalendarDay(printedYear: 2026, month: 11, day: 18)!)),
        NewWording(kind: .veterinaryRecord, row: .vaccineName, wording: "imunizare",
                   text: "CABINET VETERINAR EXEMPLU S.R.L.\nImunizare Exemplu DHPPi",
                   reads: .vaccineName, value: .text("Imunizare Exemplu DHPPi")),
        NewWording(kind: .veterinaryRecord, row: .microchip, wording: "identificare",
                   text: "CABINET VETERINAR EXEMPLU S.R.L.\nIdentificare: 900 0000 0000 0002",
                   reads: .microchip, value: .text("900000000000002")),
        NewWording(kind: .rcaPolicy, row: .expiryDate, wording: "sfarsit acoperire",
                   text: "POLIȚĂ RCA\nSfârșit acoperire: 06.11.2027",
                   reads: .expiryDate, value: .day(CalendarDay(printedYear: 2027, month: 11, day: 6)!)),
        NewWording(kind: .rcaPolicy, row: .validityPeriod, wording: "interval",
                   text: "POLIȚĂ RCA\nInterval: 07.11.2026 - 06.11.2027",
                   reads: .startDate, value: .day(CalendarDay(printedYear: 2026, month: 11, day: 7)!)),
        NewWording(kind: .insurancePolicy, row: .claimsPhone, wording: "linie urgente",
                   text: "POLIȚĂ CASCO\nLinie urgențe: 0800 123 456",
                   reads: .claimsPhone, value: .text("0800123456")),
        NewWording(kind: .rcaPolicy, row: .bonusMalusClass, wording: "treapta",
                   text: "POLIȚĂ RCA\nTreapta: B4",
                   reads: .bonusMalusClass, value: .text("B4")),
        NewWording(kind: .fiscalReceipt, row: .purchaseDate, wording: "cumparat la",
                   text: "EXEMPLU ELECTRO S.R.L.\nTipărit 01.06.2025\nCumpărat la 10.06.2025",
                   reads: .purchaseDate, value: .day(CalendarDay(printedYear: 2025, month: 6, day: 10)!)),
        NewWording(kind: .fiscalReceipt, row: .warrantyMonths, wording: "acoperire",
                   text: "EXEMPLU ELECTRO S.R.L.\nAcoperire: 24 luni",
                   reads: .warrantyMonths, value: .number(24)),
        NewWording(kind: .warrantyCertificate, row: .serialNumber, wording: "cod produs",
                   text: "EXEMPLU ELECTRO S.R.L.\nCod produs: HX60-2025-0001",
                   reads: .serialNumber, value: .text("HX60-2025-0001")),
        NewWording(kind: .serviceInvoice, row: .total, wording: "suma datorata",
                   text: "EXEMPLU SERVICE AUTO S.R.L.\nSuma datorată: 695,00 lei",
                   reads: .total, value: .money(Money(695, currency: "RON"))),
        NewWording(kind: .serviceInvoice, row: .invoiceNumber, wording: "numar document",
                   text: "EXEMPLU SERVICE AUTO S.R.L.\nNumăr document: XYZ-2026-0001",
                   reads: .invoiceNumber, value: .text("XYZ-2026-0001")),
        NewWording(kind: .serviceInvoice, row: .providerTaxID, wording: "cod tva",
                   text: "EXEMPLU SERVICE AUTO S.R.L.\nCod TVA: RO 12345674",
                   reads: .providerTaxID, value: .text("RO12345674")),
        NewWording(kind: .rcaPolicy, row: .policyNumber, wording: "identificator polita",
                   text: "POLIȚĂ RCA\nIdentificator poliță: 123456789",
                   reads: .policyNumber, value: .text("123456789")),
        NewWording(kind: .vehicleRegistration, row: .civNumber, wording: "carte identitate vehicul",
                   text: "CERTIFICAT DE ÎNMATRICULARE\nCarte identitate vehicul: J 123456",
                   reads: .civNumber, value: .text("J123456")),
        NewWording(kind: .vehicleRegistration, row: .make, wording: "marca",
                   text: "CERTIFICAT DE ÎNMATRICULARE\nMarca VW",
                   reads: .make, value: .text("VW")),
    ]

    @Test("A wording added to a kind's table is read with no change to the readers", arguments: newWordings)
    func aNewWordingIsRead(_ example: NewWording) throws {
        var profiles = CaptureKindProfile.all
        let index = try #require(profiles.firstIndex { $0.kind == example.kind })
        profiles[index].labels.append((example.row, [example.wording]))

        let before = analyzer.analyze(text: example.text, referenceDate: today, as: example.kind)
        #expect(before.fields.first { $0.key == example.reads }?.value != example.value, "Not read before the wording is in the table")

        let after = analyzer.reading(labelsOf: profiles).analyze(text: example.text, referenceDate: today, as: example.kind)
        #expect(after.fields.first { $0.key == example.reads }?.value == example.value)
    }
}
