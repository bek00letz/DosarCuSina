import Foundation
import SwiftData

// MARK: - Asset Auto-Matching Engine

public struct AssetMatchResult {
    public let asset: Asset
    public let reason: String
    public let score: Int
    
    public init(asset: Asset, reason: String, score: Int) {
        self.asset = asset
        self.reason = reason
        self.score = score
    }
}

extension RomanianUtilityParser {
    /// Evaluates extracted OCR text against a list of candidate assets, scoring matches
    /// by identifier entropy and specificity:
    /// - Vehicle 17-char VIN: 100
    /// - Utility POD / CLC / Water: 90
    /// - Pet Microchip (15-digit ISO): 85
    /// - Vehicle License Plate: 80
    /// - Health Person Name: 60
    /// - Warranty Serial / IMEI: 50
    public static func findBestAssetMatch(for extractedText: String, in assets: [Asset]) -> AssetMatchResult? {
        guard !extractedText.isEmpty else { return nil }
        let normalized = normalizeDiacritics(extractedText).uppercased()
        
        var matches: [AssetMatchResult] = []
        
        for candidate in assets {
            // 1. Vehicle 17-char VIN (Score: 100)
            if let vin = candidate.vin, !vin.isEmpty {
                let cleanVin = vin.replacingOccurrences(of: "-", with: "")
                                  .replacingOccurrences(of: " ", with: "")
                                  .uppercased()
                if cleanVin.count >= 8 {
                    let vinRegexPattern = cleanVin.map { NSRegularExpression.escapedPattern(for: String($0)) }
                                                  .joined(separator: #"[\s\-]*"#)
                    let fullPattern = #"(?i)(?:\b|[^A-Z0-9])"# + vinRegexPattern + #"(?:\b|[^A-Z0-9])"#
                    if let regex = try? NSRegularExpression(pattern: fullPattern) {
                        let ns = normalized as NSString
                        if regex.firstMatch(in: normalized, range: NSRange(location: 0, length: ns.length)) != nil {
                            matches.append(AssetMatchResult(asset: candidate, reason: "Serie Șasiu / VIN (\(vin))", score: 100))
                            continue
                        }
                    }
                    
                    let docNoSpaces = normalized.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
                    if docNoSpaces.contains(cleanVin) {
                        matches.append(AssetMatchResult(asset: candidate, reason: "Serie Șasiu / VIN (\(vin))", score: 100))
                        continue
                    }
                    
                    // Partial VIN support (last 8 characters if preceded by VIN/Serie sasiu anchor)
                    if cleanVin.count == 17 {
                        let last8 = String(cleanVin.suffix(8))
                        let partialPattern = #"(?i)(?:serie\s*(?:de\s*)?[sș]asiu|vin)[:\s]+[\s\-]*"# + NSRegularExpression.escapedPattern(for: last8) + #"(?:\b|[^A-Z0-9])"#
                        if let regex = try? NSRegularExpression(pattern: partialPattern) {
                            let ns = normalized as NSString
                            if regex.firstMatch(in: normalized, range: NSRange(location: 0, length: ns.length)) != nil {
                                matches.append(AssetMatchResult(asset: candidate, reason: "Serie Șasiu / VIN (\(vin))", score: 100))
                                continue
                            }
                        }
                    }
                }
            }
            
            // 2. Utility POD Code (Score: 90)
            if let pod = candidate.podCode, !pod.isEmpty {
                let cleanPod = pod.uppercased()
                if normalized.contains(cleanPod) {
                    matches.append(AssetMatchResult(asset: candidate, reason: "Cod POD Energie (\(pod))", score: 90))
                    continue
                }
            }
            
            // 3. Utility CLC Code (Score: 90)
            if let clc = candidate.clcCode, !clc.isEmpty {
                let cleanClc = clc.uppercased()
                if normalized.contains(cleanClc) {
                    matches.append(AssetMatchResult(asset: candidate, reason: "Cod CLC Gaze (\(clc))", score: 90))
                    continue
                }
            }
            
            // 4. Water Client Code (Score: 90)
            if let water = candidate.waterClientCode, !water.isEmpty {
                let cleanWater = water.uppercased()
                if normalized.contains(cleanWater) {
                    matches.append(AssetMatchResult(asset: candidate, reason: "Cod Client Apă (\(water))", score: 90))
                    continue
                }
            }
            
            // 5. Pet Microchip (15-digit ISO) (Score: 85)
            if let chip = candidate.microchipNumber, !chip.isEmpty {
                if normalized.contains(chip) {
                    matches.append(AssetMatchResult(asset: candidate, reason: "Microcip (\(chip))", score: 85))
                    continue
                }
            }
            
            // 6. Vehicle License Plate (Score: 80)
            if let plate = candidate.licensePlate, !plate.isEmpty {
                let cleanPlate = plate.replacingOccurrences(of: "-", with: "")
                                      .replacingOccurrences(of: " ", with: "")
                                      .uppercased()
                if cleanPlate.count >= 5 {
                    if let tokenRegex = try? NSRegularExpression(pattern: #"([A-Z]+|[0-9]+)"#) {
                        let nsPlate = cleanPlate as NSString
                        let tokenMatches = tokenRegex.matches(in: cleanPlate, range: NSRange(location: 0, length: nsPlate.length))
                        let tokens = tokenMatches.map { nsPlate.substring(with: $0.range) }
                        let plateRegexPattern = tokens.joined(separator: #"[\s\-]*"#)
                        let fullPattern = #"(?i)(?:\b|[^A-Z0-9])"# + plateRegexPattern + #"(?:\b|[^A-Z0-9])"#
                        if let regex = try? NSRegularExpression(pattern: fullPattern) {
                            let nsDoc = normalized as NSString
                            if regex.firstMatch(in: normalized, range: NSRange(location: 0, length: nsDoc.length)) != nil {
                                matches.append(AssetMatchResult(asset: candidate, reason: "Număr Auto (\(plate))", score: 80))
                                continue
                            }
                        }
                    }
                }
            }
            
            // 7. Person Name (Health) (Score: 60)
            if let pName = candidate.personName, !pName.isEmpty {
                let cleanName = pName.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanName.isEmpty && normalized.contains(cleanName) {
                    matches.append(AssetMatchResult(asset: candidate, reason: "Dosar Medical: \(pName)", score: 60))
                    continue
                }
            }
            
            // 8. Serial / IMEI (Warranties) (Score: 50)
            if let sn = candidate.serialOrImei, !sn.isEmpty {
                let cleanSn = sn.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanSn.isEmpty && normalized.contains(cleanSn) {
                    matches.append(AssetMatchResult(asset: candidate, reason: "Serie / IMEI (\(sn))", score: 50))
                    continue
                }
            }
        }
        
        return matches.sorted(by: { $0.score > $1.score }).first
    }
}

