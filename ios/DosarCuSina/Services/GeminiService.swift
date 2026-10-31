import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct InvoiceOCRResponse: Codable, Sendable {
    public let merchant: String
    public let documentType: String
    public let categorySuggestion: String
    public let issueDate: String?
    public let dueDate: String?
    public let totalAmount: Double
    public let currency: String
    public let invoiceNumber: String?
    public let summary: String?
    public let actionableReminderDate: String?
}

public enum GeminiServiceError: LocalizedError {
    case missingAPIKey
    case invalidImageData
    case invalidServerResponse(statusCode: Int, message: String)
    case decodingFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Cheia Gemini API lipsește. Adaug-o în ecranul de Setări sau în Config.xcconfig."
        case .invalidImageData:
            return "Imaginea nu a putut fi procesată."
        case .invalidServerResponse(let code, let msg):
            return "Eroare de la serverul Gemini (Cod \(code)): \(msg)"
        case .decodingFailed(let error):
            return "Nu am putut decoda răspunsul structurat: \(error.localizedDescription)"
        }
    }
}

public final class GeminiService: Sendable {
    public static let shared = GeminiService()
    
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
    
    private init() {}
    
    #if canImport(UIKit)
    /// Performs multimodal semantic extraction using Gemini Flash API
    public func analyzeDocument(image: UIImage, mimeType: String = "image/jpeg") async throws -> InvoiceOCRResponse {
        guard let apiKey = KeychainManager.getGeminiAPIKey(), !apiKey.isEmpty else {
            throw GeminiServiceError.missingAPIKey
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw GeminiServiceError.invalidImageData
        }
        
        let base64Image = imageData.base64EncodedString()
        
        let promptText = """
        Ești un asistent inteligent integrat în aplicația 'Dosar cu Șină'.
        Analizează acest document (factură utilități, deviz service auto, bon fiscal, chitanță garanție, poliță asigurare sau raport medical).
        Extrage informațiile strict în formatul JSON specificat:
        - merchant: numele emitentului/furnizorului
        - documentType: utility_invoice, maintenance_receipt, insurance_policy, medical_report, warranty_receipt sau general_bill
        - categorySuggestion: casa, masina, pet, sanatate, documente, garantii, abonamente sau custom
        - issueDate: data emiterii (YYYY-MM-DD)
        - dueDate: data scadenței sau a expirării valabilității (YYYY-MM-DD)
        - totalAmount: număr zecimal
        - currency: RON, EUR sau USD
        - invoiceNumber: serie și număr factură
        - summary: scurtă descriere a bunurilor/serviciilor
        - actionableReminderDate: data sugerată pentru alertă (cu 3-5 zile înainte de scadență)
        """
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": promptText],
                        [
                            "inlineData": [
                                "mimeType": mimeType,
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.1
            ]
        ]
        
        guard var urlComponents = URLComponents(string: endpoint) else {
            throw URLError(.badURL)
        }
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        guard let url = urlComponents.url else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw GeminiServiceError.invalidServerResponse(statusCode: httpResponse.statusCode, message: errorText)
        }
        
        // Parse Gemini top-level JSON
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = jsonObject["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let textResponse = firstPart["text"] as? String,
              let rawJsonData = textResponse.data(using: .utf8) else {
            throw GeminiServiceError.invalidServerResponse(statusCode: httpResponse.statusCode, message: "Empty model response payload")
        }
        
        do {
            let decoder = JSONDecoder()
            let extracted = try decoder.decode(InvoiceOCRResponse.self, from: rawJsonData)
            return extracted
        } catch {
            throw GeminiServiceError.decodingFailed(error)
        }
    }
    #endif
}
