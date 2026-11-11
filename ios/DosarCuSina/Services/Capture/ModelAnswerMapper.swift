import Foundation

/// Turns a language model's answer into its kind and fields, the same way whoever
/// answered, for the questions it was asked (`ModelQuestions`). Each value is read by its
/// format and checked the way the phone checks its own; `ReadingArbiter` then ranks it
/// against the phone's reading, and `CaptureFieldRules` keeps only what the kind carries.
///
/// What a value is worth depends on what the reader saw:
/// - **The page** (the person's AI provider): every value it read is kept, and what it is
///   worth decides only whether the review marks it. A value passing its own check (a
///   CNP's control digit, a VIN's check digit, the machine-readable zone's check digits) is
///   certain; one that agrees with what the phone recognised, or a date inside its
///   plausibility window, needs no look; anything else is marked "Verifică". Being missing
///   from the phone's text is never a reason to drop or demote it: the phone may have misread.
/// - **The phone's text** (Apple's on-device model): a value is kept only when it is printed
///   in that text, since the model saw nothing else, and is always marked "Verifică"
///   (`CaptureField.needsCheck`). A value passing its own check still ranks as checked.
enum ModelAnswerMapper {

    /// A value proven by its own check digits, read from the page.
    static let checked = 0.95
    /// A value from the page the phone's recognised text agrees with, or a date inside its window.
    static let grounded = 0.8
    /// A value only the page's reader saw: kept, marked "Verifică".
    static let candidate = 0.5
    /// A value Apple's model found in the phone's text.
    static let printedInText = 0.72

    /// How far a value from the page can be trusted.
    private enum Evidence {
        case checked, grounded, candidate

        var confidence: Double {
            switch self {
            case .checked: ModelAnswerMapper.checked
            case .grounded: ModelAnswerMapper.grounded
            case .candidate: ModelAnswerMapper.candidate
            }
        }
    }

    /// The kind the answer names, if it names one.
    static func kind(from answer: JSONValue) -> CaptureDocumentKind? {
        answer[ModelQuestions.kindName]?.string.flatMap(CaptureDocumentKind.init(rawValue:))
    }

    /// The fields of an answer to `questions`. A property it wasn't asked for is ignored.
    static func fields(from answer: JSONValue, asked questions: ModelQuestions, recognizedText: String, today: CalendarDay,
                       resolver: any CaptureComponentResolving) -> [CaptureField] {
        // Dates and the holder follow the kind the reader saw.
        let kind = Self.kind(from: answer) ?? questions.kind
        let reader = questions.reader
        let compactText = RomanianText.compact(recognizedText)
        let printed = CaptureText(recognizedText)
        var fields: [CaptureField] = []

        /// Keeps a value once per key: from the page by its evidence, from the phone's text
        /// only when `inText`.
        func add(_ key: CaptureFieldKey, _ value: CaptureValue, _ evidence: Evidence, inText: Bool, source: String? = nil) {
            guard !fields.contains(where: { $0.key == key }) else { return }
            let confidence: Double
            switch reader {
            case .page: confidence = evidence.confidence
            case .text:
                guard inText else { return }
                confidence = printedInText
            }
            fields.append(CaptureField(key: key, value: value, confidence: confidence, sourceText: source, tier: reader.tier))
        }
        /// Whether the text prints the value: whole, or, for a value printed in parts, each
        /// part ("Seria RO/00/X00/XX nr. 012345678" prints "RO/00/X00/XX 012345678").
        func isPrinted(_ value: String, as key: CaptureFieldKey? = nil) -> Bool {
            let whole = RomanianText.compact(value)
            guard !whole.isEmpty else { return false }
            if compactText.contains(whole) { return true }
            guard let key, let shape = CompositeValue.shape(of: key, kind: kind), let parts = shape.parts(in: value) else { return false }
            let pieces = [parts.series, parts.number].compactMap { $0 }.map(RomanianText.compact)
            return pieces.count == 2 && pieces.allSatisfy { compactText.contains($0) }
        }
        func printedEvidence(_ value: String, as key: CaptureFieldKey? = nil) -> Evidence { isPrinted(value, as: key) ? .grounded : .candidate }

        // The zone first: when its check digits pass, its values are the ones kept.
        if let zone = questions.fields.first(where: { $0.format == .machineReadableZone }),
           let lines = answer[zone.name]?.array?.compactMap(\.string), !lines.isEmpty,
           let mrz = MRZParser.parse(text: lines.joined(separator: "\n"), referenceDate: today.noonDate()),
           mrz.allChecksValid {
            for field in CaptureAnalyzer.machineReadableFields(mrz) {
                add(field.key, field.value, .checked, inText: true, source: CaptureField.machineReadableSource)
            }
        }

        for field in questions.fields {
            guard let key = field.key, let raw = answer[field.name], raw != .null else { continue }
            switch field.format {
            case .machineReadableZone:
                continue
            case .date:
                guard let text = raw.string, let day = isoDay(text) else { continue }
                let window = CaptureConsistency.window(for: key, kind: kind, today: today)
                let inText = RomanianFieldExtractor.allDates(in: printed, window: window).contains { $0.day == day }
                let hasWindow = CaptureConsistency.rules(for: kind).contains { rule in
                    if case .within(key, _, _) = rule { return true }
                    return false
                }
                // The page's reader may have read a date the phone missed: inside its window it needs no look.
                let inWindow = hasWindow && CaptureConsistency.isPlausible(day, for: key, kind: kind, today: today)
                add(key, .day(day), inText || inWindow ? .grounded : .candidate, inText: inText)
            case .personalNumber:
                guard let digits = raw.string?.filter(\.isNumber), digits.count == 13 else { continue }
                add(key, .text(digits), RomanianFieldExtractor.isValidCNP(digits) ? .checked : .candidate, inText: isPrinted(digits))
            case .vin:
                guard let vin = raw.string.map(RomanianText.compact), vin.count == 17 else { continue }
                add(key, .text(vin), RomanianFieldExtractor.vinChecksumValid(vin) ? .checked : printedEvidence(vin), inText: isPrinted(vin))
            case .sex:
                // A judgement about the page, not text copied from it.
                guard let letter = raw.string?.uppercased().first(where: { $0 == "M" || $0 == "F" }) else { continue }
                add(key, .text(String(letter)), .grounded, inText: true)
            case .name:
                guard let text = raw.string, let name = RomanianFieldExtractor.personName(text.uppercased()) else { continue }
                add(key, .text(name), printedEvidence(name), inText: isPrinted(name))
            case .categories:
                guard let text = raw.string, let parsed = IdentityDocumentReader.parse(text, as: .categories) else { continue }
                add(key, parsed.value, printedEvidence(text), inText: isPrinted(text))
            case .money:
                // A number, or text as printed ("1.234,56"): one reader either way.
                guard let reading = ModelQuestions.number(raw["amount"], as: .money), reading.value > 0 else { continue }
                let currency = normalizedCurrency(raw["currency"]?.string)
                let amounts = Set(printed.folded.flatMap { RomanianFieldExtractor.amounts(inLine: $0).map(\.amount) })
                let inText = amounts.contains(reading.value)
                add(key, .money(Money(reading.value, currency: currency)), inText && !reading.needsCheck ? .grounded : .candidate, inText: inText)
            case .integer:
                guard let value = ModelQuestions.wholeNumber(raw, kind: key == .odometer ? .kilometres : .count), value >= 0, value < 10_000_000 else { continue }
                if key == .minimumMonths, !ContractReader.plausibleMonths.contains(value) { continue }
                if key == .warrantyMonths, !Self.warrantyMonths.contains(value) { continue }
                let typed: CaptureValue = key == .odometer ? .metric(value: Decimal(value), unit: .kilometres) : .number(Decimal(value))
                let inText = compactText.contains(String(value))
                add(key, typed, inText ? .grounded : .candidate, inText: inText)
            case .meterIndex:
                guard let reading = ModelQuestions.number(raw, as: .meterIndex), reading.value >= 0, reading.value < 100_000_000 else { continue }
                // The digits as answered, compared with the page's: "12.345,678" is printed 12345678.
                let digits = raw.string ?? NSDecimalNumber(decimal: reading.value).stringValue
                add(key, .number(reading.value), reading.needsCheck ? .candidate : printedEvidence(digits), inText: isPrinted(digits))
            case .lineItems:
                let currency = normalizedCurrency(nil)
                let items = (raw.array ?? []).compactMap { item -> CaptureLineItem? in
                    guard let description = item["description"]?.string?.trimmingCharacters(in: .whitespaces), !description.isEmpty else { return nil }
                    let money = ModelQuestions.number(item["amount"], as: .money).map { Money($0.value, currency: currency) }
                    return CaptureLineItem(description: description, amount: money, componentKey: resolver.componentKey(for: description))
                }
                // From the phone's text, only the lines printed in it.
                let kept = reader == .text ? items.filter { isPrinted($0.description) } : items
                guard !kept.isEmpty else { continue }
                let allPrinted = kept.allSatisfy { isPrinted($0.description) }
                add(key, .lineItems(kept), allPrinted ? .grounded : .candidate, inText: allPrinted)
            case .meterReading:
                // A judgement about the index: kept when it names a known way; from the phone's
                // text only when the text says so, in the words the bill's own reader reads.
                guard let basis = raw.string.flatMap(ReadingBasis.init(rawValue:)) else { continue }
                let said = CaptureDocumentKind.utilityInvoice.profile.meterReadingCues?.mentions(basis, in: printed) ?? false
                add(key, .text(basis.rawValue), said ? .grounded : .candidate, inText: said)
            case .serviceKind:
                // A judgement about the page, not text copied from it: kept when it names a known service.
                guard let service = raw.string, ServiceKind.all.contains(service) else { continue }
                add(key, .text(service), .grounded, inText: true)
            case .coverage:
                // The same for the cover: kept when it names a known one.
                guard let cover = InsuranceCover.key(for: raw.string), InsuranceCover.all.contains(cover) else { continue }
                add(key, .text(cover), .grounded, inText: true)
            case .cardNetwork:
                guard let network = raw.string.flatMap({ PaymentCardNetwork.options.option(for: $0)?.key }) else { continue }
                add(key, .text(network), .grounded, inText: true)
            case .cardLastFour:
                // Whatever came back, only its last four digits are kept: never a whole number.
                guard let lastFour = raw.string.flatMap(PaymentCardNumbers.lastFour(of:)) else { continue }
                add(key, .text(lastFour), printedEvidence(lastFour), inText: isPrinted(lastFour))
            case .text, .documentNumber, .country, .plate, .phone:
                guard let text = raw.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text.lowercased() != "null" else { continue }
                var value = field.format == .documentNumber || field.format == .plate ? text.uppercased() : text
                if key == .phoneNumber {
                    // The person's own number, written the way the phone reads it: "0700 000 000".
                    guard ContractReader.isMobileNumber(value) else { continue }
                    value = ContractReader.displayPhone(value)
                }
                // The same rules as the phone's reading: an address that names a place, and
                // a statement that the bill is paid by direct debit, never an offer of it.
                if key == .supplyAddress, PostalAddress(value) == nil || value.count > ContractReader.addressMaxLength { continue }
                if key == .directDebit, !ContractReader.statesDirectDebit(value) { continue }
                add(key, .text(value), printedEvidence(value, as: key), inText: isPrinted(value, as: key))
            }
        }

        // The holder, as the identity readers name them.
        if kind.isPersonalDocument, !fields.contains(where: { $0.key == .holderName }),
           let surname = fields.first(where: { $0.key == .surname }) {
            let given = fields.first { $0.key == .givenNames }
            let full = [given?.value.text, surname.value.text].compactMap { $0 }.joined(separator: " ")
            fields.append(CaptureField(key: .holderName, value: .text(full), confidence: min(surname.confidence, given?.confidence ?? surname.confidence),
                                       sourceText: nil, tier: reader.tier))
        }
        return fields
    }

    /// How long a warranty can be, in months.
    static let warrantyMonths = 1...240

    // MARK: Text

    static func isoDay(_ value: String) -> CalendarDay? {
        let parts = value.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return CalendarDay(printedYear: parts[0], month: parts[1], day: parts[2])
    }

    static func normalizedCurrency(_ value: String?) -> String {
        switch RomanianText.fold(value ?? "") {
        case "eur", "euro", "€": "EUR"
        case "usd", "$": "USD"
        default: "RON"
        }
    }
}
