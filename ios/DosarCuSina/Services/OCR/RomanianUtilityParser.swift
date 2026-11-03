import Foundation

/// Romanian utility providers recognized by the intelligent parser.
public enum RomanianUtilityProvider: String, CaseIterable, Sendable {
    case digi = "DIGI"
    case ppcEnel = "PPC / Enel"
    case hidroelectrica = "Hidroelectrica"
    case eon = "E.ON"
    case engie = "ENGIE"
    case vodafone = "Vodafone"
    case orange = "Orange"
    case general = "General"
    
    public var displayName: String {
        switch self {
        case .digi: return "Digi (RCS & RDS)"
        case .ppcEnel: return "PPC / Enel"
        case .hidroelectrica: return "Hidroelectrica"
        case .eon: return "E.ON Energie"
        case .engie: return "ENGIE Romania"
        case .vodafone: return "Vodafone Romania"
        case .orange: return "Orange Romania"
        case .general: return "Furnizor Utilități"
        }
    }
}

public typealias UtilityProvider = RomanianUtilityProvider

/// Structured data extracted from a Romanian utility invoice.
public struct UtilityBillData: Sendable, Equatable {
    public let provider: RomanianUtilityProvider
    public let clientCode: String?
    public let invoiceNumber: String?
    public let issueDate: Date?
    public let dueDate: Date?
    public let indexReading: Double?
    public let previousIndexReading: Double?
    public let podCode: String?
    public let clcCode: String?
    public let waterClientCode: String?
    public let totalAmount: Double?
    public let currency: String
    public let barcodeRaw: String?
    public let rawMatchedText: String
    
    // Convenience aliases for survey specification parity
    public var meterIndex: String? {
        if let idx = indexReading {
            return String(format: "%.0f", idx)
        }
        return nil
    }
    
    public var consumptionDelta: Double? {
        guard let current = indexReading, let previous = previousIndexReading else { return nil }
        return current - previous
    }
    
    public var paymentCodeOrBarcode: String? {
        barcodeRaw
    }
    
    public init(
        provider: RomanianUtilityProvider,
        clientCode: String? = nil,
        invoiceNumber: String? = nil,
        issueDate: Date? = nil,
        dueDate: Date? = nil,
        indexReading: Double? = nil,
        previousIndexReading: Double? = nil,
        podCode: String? = nil,
        clcCode: String? = nil,
        waterClientCode: String? = nil,
        totalAmount: Double? = nil,
        currency: String = "RON",
        barcodeRaw: String? = nil,
        rawMatchedText: String = ""
    ) {
        self.provider = provider
        self.clientCode = clientCode
        self.invoiceNumber = invoiceNumber
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.indexReading = indexReading
        self.previousIndexReading = previousIndexReading
        self.podCode = podCode
        self.clcCode = clcCode
        self.waterClientCode = waterClientCode
        self.totalAmount = totalAmount
        self.currency = currency
        self.barcodeRaw = barcodeRaw
        self.rawMatchedText = rawMatchedText
    }
}

public typealias UtilityBillExtractionResult = UtilityBillData

/// Production regex parsing engine tailored for Romanian utility bills.
/// Extracts provider, client code, invoice series and number, issue date, due date,
/// meter readings (including 1.8.0 Hidroelectrica active energy), total amount, and barcode payloads.
public final class RomanianUtilityParser: Sendable {
    public static let shared = RomanianUtilityParser()
    
    public init() {}
    
    // MARK: - Diacritics Normalization
    
    /// Converts legacy Romanian cedillas (ş, ţ, Ş, Ţ) to official comma-below diacritics (ș, ț, Ș, Ț).
    public static func normalizeDiacritics(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "\u{015F}", with: "\u{0219}") // ş -> ș
        result = result.replacingOccurrences(of: "\u{015E}", with: "\u{0218}") // Ş -> Ș
        result = result.replacingOccurrences(of: "\u{0163}", with: "\u{021B}") // ţ -> ț
        result = result.replacingOccurrences(of: "\u{0162}", with: "\u{021A}") // Ţ -> Ț
        return result
    }
    
    /// Strips Romanian diacritics for insensitive search (ș/ş->s, ț/ţ->t, ă/â->a, î->i).
    public static func stripDiacritics(_ text: String) -> String {
        return text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "ro_RO"))
    }
    
    // MARK: - Public API
    
    /// Parses raw OCR or document text to extract structured Romanian utility bill data.
    public func parseUtilityBill(text: String) -> UtilityBillData {
        let normalizedText = Self.normalizeDiacritics(text)
        let provider = detectProvider(in: normalizedText)
        let clientCode = extractClientCode(for: provider, in: normalizedText)
        let invoiceNumber = extractInvoiceNumber(for: provider, in: normalizedText)
        let issueDate = extractIssueDate(in: normalizedText)
        let dueDate = extractDueDate(in: normalizedText, issueDate: issueDate)
        let indexReading = extractMeterIndex(for: provider, in: normalizedText)
        let previousIndexReading = extractPreviousMeterIndex(for: provider, in: normalizedText)
        let podCode = extractPodCode(in: normalizedText)
        let clcCode = extractClcCode(in: normalizedText)
        let waterClientCode = extractWaterClientCode(in: normalizedText)
        let (amount, currency) = extractTotalAmount(in: normalizedText)
        let barcode = extractPaymentBarcodeOrCode(for: provider, in: normalizedText)
        
        return UtilityBillData(
            provider: provider,
            clientCode: clientCode,
            invoiceNumber: invoiceNumber,
            issueDate: issueDate,
            dueDate: dueDate,
            indexReading: indexReading,
            previousIndexReading: previousIndexReading,
            podCode: podCode,
            clcCode: clcCode,
            waterClientCode: waterClientCode,
            totalAmount: amount,
            currency: currency,
            barcodeRaw: barcode,
            rawMatchedText: text
        )
    }
    
    // MARK: - Provider Detection
    
    public func detectProvider(in text: String) -> RomanianUtilityProvider {
        let uppercase = text.uppercased()
        // Names match as whole words only: "DIGI" isn't in "DIGITAL", "EON" isn't in "LEONTE".
        func has(_ word: String) -> Bool {
            let escaped = NSRegularExpression.escapedPattern(for: word)
            return uppercase.range(of: #"(?<![A-Z0-9])"# + escaped + #"(?![A-Z0-9])"#, options: .regularExpression) != nil
        }

        if has("HIDROELECTRICA") || has("SPEEH") { return .hidroelectrica }
        if has("RCS & RDS") || has("RCS-RDS") || has("RCS RDS") ||
           (has("DIGI") && (has("ROMANIA") || has("TELECOM") || has("FACTURA") || has("SERVICII"))) {
            return .digi
        }
        if has("PPC ENERGIE") || has("PPC") || has("ENEL ENERGIE") || has("ENEL") { return .ppcEnel }
        if has("ENGIE") || has("GDF SUEZ") { return .engie }
        if has("E.ON") || has("EON ENERGIE") || has("EON") { return .eon }
        if has("VODAFONE") { return .vodafone }
        if has("ORANGE") { return .orange }
        return .general
    }
    
    // MARK: - Client Code Extraction
    
    private func extractClientCode(for provider: RomanianUtilityProvider, in text: String) -> String? {
        let patterns: [String]
        
        switch provider {
        case .digi:
            patterns = [
                #"(?i)(?:cod\s*client|cod\s*abonat|cont\s*client)[:\s]+([0-9]{6,12})\b"#,
                #"(?i)client[:\s]+([0-9]{6,12})\b"#
            ]
        case .ppcEnel:
            patterns = [
                #"(?i)(?:cod\s*client|cod\s*abonat)[:\s]+(30\d{7,8})\b"#,
                #"(?i)(?:cod\s*client|cod\s*abonat)[:\s]+([0-9]{8,12})\b"#
            ]
        case .hidroelectrica:
            patterns = [
                #"(?i)(?:cod\s*client|client)[:\s]+([0-9]{6,12})\b"#,
                #"(?i)cod\s*loc\s*consum\s*\(?clc\)?[:\s]+([0-9]{6,12})\b"#
            ]
        case .eon:
            patterns = [
                #"(?i)(?:cod\s*client|cod\s*incasare|cod\s*încasare)[:\s]+(1\d{9})\b"#,
                #"(?i)(?:cod\s*client|cod\s*incasare)[:\s]+([0-9]{9,11})\b"#
            ]
        case .engie:
            patterns = [
                #"(?i)(?:cod\s*client|referin[tț][aă]|partener)[:\s]+(1\d{9}|2\d{9}|\d{8,10})\b"#,
                #"(?i)cod\s*client[:\s]+([0-9]{8,12})\b"#
            ]
        case .vodafone:
            patterns = [
                #"(?i)(?:cod\s*client|cont\s*client|client\s*nr\.?)[:\s]+([0-9]{8,10})\b"#
            ]
        case .orange:
            patterns = [
                #"(?i)(?:cod\s*abonat|cod\s*client|cont\s*facturare)[:\s]+([0-9]{8,10})\b"#
            ]
        case .general:
            patterns = [
                #"(?i)(?:cod\s*client|num[aă]r\s*client|client\s*id|cod\s*abonat)[:\s]+([A-Z0-9-]{5,15})\b"#
            ]
        }
        
        for pattern in patterns {
            if let match = firstMatch(for: pattern, in: text, captureGroup: 1) {
                return match.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Fallback generic search
        let genericPattern = #"(?i)cod\s*client[:\s]+([0-9A-Z]{5,14})\b"#
        return firstMatch(for: genericPattern, in: text, captureGroup: 1)
    }
    
    // MARK: - Invoice Number Extraction
    
    private func extractInvoiceNumber(for provider: RomanianUtilityProvider, in text: String) -> String? {
        let patterns = [
            #"(?i)(?:factur[aă]\s*(?:fiscal[aă]\s*)?(?:seria\s*\w+\s*)?nr\.?|num[aă]r\s*factur[aă]|serie\s*(?:și|si)?\s*num[aă]r|factura\s*nr)[:\s]+([A-Z0-9\/\-_]{5,25})\b"#,
            #"(?i)(?:seria|serie)[:\s]+([A-Z0-9]+)\s*(?:nr\.?|num[aă]r)[:\s]+([A-Z0-9]+)\b"#,
            #"(?i)nr\.\s*factur[aă][:\s]+([A-Z0-9\/\-_]{5,25})\b"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsString = text as NSString
                if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsString.length)) {
                    if match.numberOfRanges >= 3 && match.range(at: 2).location != NSNotFound {
                        let series = nsString.substring(with: match.range(at: 1))
                        let number = nsString.substring(with: match.range(at: 2))
                        return "\(series) \(number)".trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if match.numberOfRanges >= 2 && match.range(at: 1).location != NSNotFound {
                        return nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Date Extraction
    
    private func extractIssueDate(in text: String) -> Date? {
        let issuePatterns = [
            #"(?i)(?:data\s*emiterii|data\s*facturii|emis[aă]\s*(?:la|pe)|data\s*factur[aă])[:\s]+([0-9]{1,2}[./-](?:[0-9]{1,2}|[IVX]{1,4})[./-][0-9]{4}|[0-9]{1,2}\s+[a-zăîșțA-ZĂÎȘȚ]+\s+[0-9]{4})\b"#
        ]
        
        for pattern in issuePatterns {
            if let dateStr = firstMatch(for: pattern, in: text, captureGroup: 1),
               let parsed = parseDateString(dateStr) {
                return parsed
            }
        }
        
        return nil
    }
    
    private func extractDueDate(in text: String, issueDate: Date?) -> Date? {
        let duePatterns = [
            #"(?i)(?:data\s*scaden[tț]ei|scaden[tț][aă]|(?:data|termen)\s*limit[aă]\s*(?:de\s*)?plat[aă]|termen\s*(?:de\s*)?plat[aă]|scadent\s*(?:la|pe)|pl[aă]te[sș]te\s*p[aâ]n[aă]\s*la)[:.\s]+([0-9]{1,2}[./-](?:[0-9]{1,2}|[IVX]{1,4})[./-][0-9]{4}|[0-9]{1,2}\s+[a-zăîșțA-ZĂÎȘȚ]+\s+[0-9]{4})\b"#
        ]
        
        for pattern in duePatterns {
            if let dateStr = firstMatch(for: pattern, in: text, captureGroup: 1),
               let parsed = parseDateString(dateStr) {
                return parsed
            }
        }
        
        // Edge case fallback: find all dates in document. If ambiguous, pick the largest future date relative to issueDate
        let allDates = extractAllDates(from: text)
        if let issue = issueDate {
            // Find dates occurring after issueDate, within 60 days
            let candidates = allDates.filter { $0 > issue && $0.timeIntervalSince(issue) <= 65 * 86400 }
            if let best = candidates.sorted(by: >).first {
                return best
            }
        }
        
        return allDates.sorted(by: >).first
    }
    
    // MARK: - POD, CLC & Water Identifiers
    
    public func extractPodCode(in text: String) -> String? {
        let patterns = [
            #"(?i)(?:POD|punct\s*de\s*delimitare|loc\s*consum)[:\s]*(RO[A-Z0-9]{10,25})\b"#,
            #"\b(RO[0-9]{3}[A-Z0-9]{8,20})\b"#
        ]
        for p in patterns {
            if let match = firstMatch(for: p, in: text, captureGroup: 1) {
                return match.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    
    public func extractClcCode(in text: String) -> String? {
        let patterns = [
            #"(?i)(?:CLC|cod\s*loc\s*consum\s*\(?clc\)?|loc\s*consum\s*gaze)[:\s]*([A-Z0-9]{6,20})\b"#,
            #"(?i)\b(DEG[0-9]{6,16})\b"#
        ]
        for p in patterns {
            if let match = firstMatch(for: p, in: text, captureGroup: 1) {
                return match.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    
    public func extractWaterClientCode(in text: String) -> String? {
        let patterns = [
            #"(?i)(?:cod\s*client\s*ap[aă]|ap[aă][- ]canal\s*(?:cod\s*client|cod|client)?|apa\s*nova\s*(?:cod\s*client|cod|client))[:\s]*([A-Z0-9-]{5,20})\b"#
        ]
        for p in patterns {
            if let match = firstMatch(for: p, in: text, captureGroup: 1) {
                return match.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    
    public func extractPreviousMeterIndex(for provider: RomanianUtilityProvider, in text: String) -> Double? {
        let patterns = [
            #"(?i)index\s*vechi[:\s]+(\d+(?:[.,]\d+)?)\b"#,
            #"(?i)index\s*anterior[:\s]+(\d+(?:[.,]\d+)?)\b"#
        ]
        for p in patterns {
            if let match = firstMatch(for: p, in: text, captureGroup: 1) {
                if let value = try? RomanianNumber.read(match, as: .meterIndex, from: .document).get().doubleValue {
                    return value
                }
            }
        }
        return nil
    }
    
    // MARK: - Meter Index Extraction
    
    private func extractMeterIndex(for provider: RomanianUtilityProvider, in text: String) -> Double? {
        var patterns: [String] = []
        
        if provider == .hidroelectrica {
            // Prefer 1.8.0 active energy total reading
            patterns.append(#"(?i)(?:1\.8\.0|energie\s*activ[aă])[:\s]+(\d+(?:[.,]\d+)?)\b"#)
            patterns.append(#"(?i)index\s*(?:nou\s*autocitit|nou|curent|citit)[:\s]+(\d+(?:[.,]\d+)?)\b"#)
            patterns.append(#"(?i)index\s*vechi[:\s]+(\d+(?:[.,]\d+)?)\b"#)
        } else if provider == .ppcEnel {
            patterns.append(#"(?i)index\s*(?:nou\s*autocitit|autocitit\s*nou|nou\s*citit|autocitit|nou|curent)[:\s]+(\d+(?:[.,]\d+)?)\b"#)
            patterns.append(#"(?i)index\s*vechi[:\s]+(\d+(?:[.,]\d+)?)\b"#)
        } else if provider == .engie {
            patterns.append(#"(?i)index\s*(?:nou\s*autocitit|nou|curent)[:\s]+(\d+(?:[.,]\d+)?)\s*(?:mc)?\b"#)
            patterns.append(#"(?i)index\s*vechi[:\s]+(\d+(?:[.,]\d+)?)\s*(?:mc)?\b"#)
        } else if provider == .eon {
            patterns.append(#"(?i)index\s*(?:nou\s*autocitit|nou|curent|citit|autocitit)[:\s]+(\d+(?:[.,]\d+)?)\b"#)
            patterns.append(#"(?i)index\s*vechi[:\s]+(\d+(?:[.,]\d+)?)\b"#)
        } else {
            patterns.append(#"(?i)index\s*(?:nou\s*autocitit|nou|curent|autocitit)[:\s]+(\d+(?:[.,]\d+)?)\b"#)
            patterns.append(#"(?i)index\s*vechi[:\s]+(\d+(?:[.,]\d+)?)\b"#)
        }
        
        for pattern in patterns {
            if let match = firstMatch(for: pattern, in: text, captureGroup: 1) {
                if let value = try? RomanianNumber.read(match, as: .meterIndex, from: .document).get().doubleValue {
                    return value
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Total Amount Extraction
    
    private func extractTotalAmount(in text: String) -> (amount: Double?, currency: String) {
        // High confidence contextual anchors
        let anchoredPatterns = [
            #"(?i)(?:total\s*(?:de\s*plat[aă]|factur[aă]|general)?|(?<!cod\s)(?<!termen\s)(?<!data\s)de\s*plat[aă]|rest\s*de\s*plat[aă]|sum[aă]\s*(?:total[aă]|curent[aă]|de\s*plat[aă])|sold\s*(?:total|curent)|valoare\s*total[aă])[:\s]*((?:[0-9]{1,3}(?:[ .\u00A0\u202F][0-9]{3})+(?:,[0-9]{1,2})?|[0-9]+(?:[.,][0-9]{1,2})?))(?!\d)\s*(?:(lei|ron|eur|€(?!\w))(?:\b|\s|$))?"#,
            #"(?i)((?:[0-9]{1,3}(?:[ .\u00A0\u202F][0-9]{3})+(?:,[0-9]{1,2})?|[0-9]+(?:[.,][0-9]{1,2})?))(?!\d)\s*(lei|ron|eur|€(?!\w))(?:\b|\s|$)\s*(?:total\s*(?:de\s*plat[aă])?)\b"#
        ]
        
        for pattern in anchoredPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsString = text as NSString
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
                for match in matches {
                    if match.numberOfRanges >= 2 && match.range(at: 1).location != NSNotFound {
                        let amountStr = nsString.substring(with: match.range(at: 1))
                        if let normalized = normalizeRomanianAmount(amountStr), normalized > 0 && normalized < 500000 {
                            var curr = "RON"
                            if match.numberOfRanges >= 3 && match.range(at: 2).location != NSNotFound {
                                let detectedCurr = nsString.substring(with: match.range(at: 2)).uppercased()
                                if detectedCurr.contains("EUR") || detectedCurr.contains("€") {
                                    curr = "EUR"
                                }
                            }
                            return (normalized, curr)
                        }
                    }
                }
            }
        }
        
        // Fallback: scan all amount tokens and take reasonable highest candidate
        let amountPattern = #"\b\d{1,4}(?:[.,\s\u00A0\u202F]\d{3})*(?:[.,]\d{2})\b"#
        if let regex = try? NSRegularExpression(pattern: amountPattern) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            var amounts: [Double] = []
            for match in matches {
                let raw = nsString.substring(with: match.range)
                if let val = normalizeRomanianAmount(raw), val > 1.0 && val < 500000 {
                    amounts.append(val)
                }
            }
            if let candidate = amounts.sorted(by: >).first {
                return (candidate, "RON")
            }
        }
        
        return (nil, "RON")
    }
    
    // MARK: - Barcode & Payment Code Extraction
    
    private func extractPaymentBarcodeOrCode(for provider: RomanianUtilityProvider, in text: String) -> String? {
        // Specific provider code patterns
        let patterns: [String]
        switch provider {
        case .digi:
            patterns = [
                #"(?i)cod\s*(?:de\s*)?plat[aă][:\s]+(\d{8,14})\b"#,
                #"(?i)num[aă]r\s*contract[:\s]+(\d{8,14})\b"#
            ]
        case .hidroelectrica:
            patterns = [
                #"(?i)\bPOD[:\s]+(RO[A-Z0-9]{10,20})\b"#,
                #"\b(RO[A-Z0-9]{12,18})\b"#, // POD / CLC
                #"(?i)cod\s*(?:de\s*)?plat[aă][:.\s]+(\d{8,16})\b"#
            ]
        case .ppcEnel:
            patterns = [
                #"\b(\d{40,50})\b"#, // Long utility payment barcode
                #"(?i)cod\s*plat[aă][:.\s]+(\d{10,20})\b"#
            ]
        case .eon:
            patterns = [
                #"(?i)cod\s*(?:inregistrare|înregistrare|incasare)[:\s]+(\d{8,14})\b"#,
                #"\b(\d{30,45})\b"#
            ]
        case .engie:
            patterns = [
                #"(?i)cod\s*bare\s*client[:\s]+(\d{10,25})\b"#,
                #"\b(\d{30,45})\b"#
            ]
        default:
            patterns = [
                #"(?i)cod\s*(?:de\s*)?plat[aă][:.\s]+([A-Z0-9-]{8,25})\b"#,
                #"\b(\d{25,48})\b"#
            ]
        }
        
        for pattern in patterns {
            if let match = firstMatch(for: pattern, in: text, captureGroup: 1) {
                return match.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return nil
    }
    
    // MARK: - Helpers
    
    private func firstMatch(for pattern: String, in text: String, captureGroup: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsString = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsString.length)) else { return nil }
        guard match.numberOfRanges > captureGroup && match.range(at: captureGroup).location != NSNotFound else { return nil }
        return nsString.substring(with: match.range(at: captureGroup))
    }
    
    private func extractAllDates(from text: String) -> [Date] {
        var dates: [Date] = []
        // Numeric dates DD.MM.YYYY, DD/MM/YYYY, DD-MM-YYYY and Roman numerals DD.MM.YYYY e.g. 15.XI.2024
        let datePattern = #"\b(0?[1-9]|[12][0-9]|3[01])[./-](0?[1-9]|1[0-2]|[IVX]{1,4})[./-](20\d\d)\b"#
        if let regex = try? NSRegularExpression(pattern: datePattern, options: .caseInsensitive) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                let str = nsString.substring(with: match.range)
                if let parsed = parseDateString(str) {
                    dates.append(parsed)
                }
            }
        }
        return dates
    }
    
    /// Parses dates formatted with numeric, Roman numeral, or written Romanian month representations.
    public static func parseDate(_ rawString: String) -> Date? {
        let normalizedDiacritics = normalizeDiacritics(rawString).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Roman Numeral Month Parsing: "15.XI.2024", "01/IV/2026", "28-II-2025", "12-VIII-2026"
        let romanPattern = #"^([0-9]{1,2})[./-]([IVX]{1,4})[./-](20\d\d)$"#
        if let regex = try? NSRegularExpression(pattern: romanPattern, options: .caseInsensitive) {
            let ns = normalizedDiacritics as NSString
            if let match = regex.firstMatch(in: normalizedDiacritics, range: NSRange(location: 0, length: ns.length)) {
                let day = ns.substring(with: match.range(at: 1))
                let romanMonth = ns.substring(with: match.range(at: 2)).uppercased()
                let year = ns.substring(with: match.range(at: 3))
                
                let romanMap: [String: String] = [
                    "I": "01", "II": "02", "III": "03", "IV": "04",
                    "V": "05", "VI": "06", "VII": "07", "VIII": "08",
                    "IX": "09", "X": "10", "XI": "11", "XII": "12"
                ]
                if let monthNum = romanMap[romanMonth] {
                    let candidate = "\(day).\(monthNum).\(year)"
                    let fmt = DateFormatter()
                    fmt.dateFormat = "d.MM.yyyy"
                    fmt.timeZone = TimeZone(secondsFromGMT: 0)
                    if let d = fmt.date(from: candidate) {
                        return d
                    }
                }
            }
        }
        
        // 2. Check for written Romanian month: e.g. "15 noiembrie 2026"
        let monthMap: [String: String] = [
            "ianuarie": "01", "februarie": "02", "martie": "03", "aprilie": "04",
            "mai": "05", "iunie": "06", "iulie": "07", "august": "08",
            "septembrie": "09", "octombrie": "10", "noiembrie": "11", "decembrie": "12"
        ]
        
        var normalized = normalizedDiacritics
        for (name, num) in monthMap {
            if normalized.lowercased().contains(name) {
                normalized = normalized.lowercased().replacingOccurrences(of: name, with: num)
                // Collapse extra spaces: "15 01 2026" -> "15.01.2026"
                let components = normalized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if components.count == 3 {
                    normalized = "\(components[0]).\(components[1]).\(components[2])"
                }
                break
            }
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ro_RO")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let formats = [
            "dd.MM.yyyy", "dd/MM/yyyy", "dd-MM-yyyy",
            "d.M.yyyy", "d/M/yyyy", "d-M-yyyy",
            "yyyy-MM-dd"
        ]
        
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) {
                return date
            }
        }
        
        return nil
    }
    
    private func parseDateString(_ rawString: String) -> Date? {
        Self.parseDate(rawString)
    }
    
    /// An amount printed on a bill ("1.450,50 lei", "1 450,50 RON", "123,45"), read by the
    /// one number reader (`RomanianNumber`). Nil when it can't be read one way only.
    public static func normalizeRomanianAmount(_ raw: String) -> Double? {
        try? RomanianNumber.read(raw, as: .money, from: .document).get().doubleValue
    }
    
    public static func parseRomanianAmount(_ raw: String) -> Double? {
        normalizeRomanianAmount(raw)
    }
    
    private func normalizeRomanianAmount(_ raw: String) -> Double? {
        Self.normalizeRomanianAmount(raw)
    }
}
