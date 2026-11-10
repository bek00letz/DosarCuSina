import Foundation
import SwiftData

/// What a person or business does for the household. Raw values are part of
/// the `.dosar` contract; unknown values from newer versions are kept as text.
public enum ProviderTrade: String, Codable, CaseIterable, Sendable {
    case mechanic
    case tyreShop
    case inspectionStation
    case bodyShop
    case plumber
    case electrician
    case gasTechnician
    case boilerTechnician
    case hvacTechnician
    case handyman
    case vet
    case doctor
    case dentist
    case insuranceAgent
    /// The insurance company that issued a policy (RCA, CASCO, PAD).
    case insurer
    case accountant
    case tenant
    case emergencyContact
    case other

    public var title: String {
        switch self {
        case .mechanic: return String(localized: "Mecanic")
        case .tyreShop: return String(localized: "Vulcanizare")
        case .inspectionStation: return String(localized: "Stație ITP")
        case .bodyShop: return String(localized: "Tinichigerie")
        case .plumber: return String(localized: "Instalator")
        case .electrician: return String(localized: "Electrician")
        case .gasTechnician: return String(localized: "Tehnician gaze")
        case .boilerTechnician: return String(localized: "Tehnician centrale")
        case .hvacTechnician: return String(localized: "Tehnician aer condiționat")
        case .handyman: return String(localized: "Meșter")
        case .vet: return String(localized: "Veterinar")
        case .doctor: return String(localized: "Medic")
        case .dentist: return String(localized: "Stomatolog")
        case .insuranceAgent: return String(localized: "Agent de asigurări")
        case .insurer: return String(localized: "Asigurător")
        case .accountant: return String(localized: "Contabil")
        case .tenant: return String(localized: "Chiriaș")
        case .emergencyContact: return String(localized: "Contact pentru urgențe")
        case .other: return String(localized: "Altceva")
        }
    }
}

extension DosarSchemaV12 {
    /// A person or business the household relies on: the mechanic, the plumber
    /// who changed the tap, the vet, the insurance agent. Linked to the assets
    /// they look after and to the history entries of the work they did, so
    /// "știi un service bun?" and "cine ți-a schimbat robinetul?" have answers.
    @Model
    public final class Provider {
        public var id: UUID = UUID()
        public var name: String = ""
        /// `ProviderTrade` raw values; free text is allowed for trades not in the list.
        public var trades: [String] = []
        public var phone: String?
        public var email: String?
        public var address: String?
        public var notes: String?
        /// The person's own 1–5 rating, used when no job has been rated.
        public var manualRating: Int?
        /// "Would call again". Nil until the person says.
        public var wouldCallAgain: Bool?
        /// Contacts framework identifier, when linked to the address book. It only
        /// resolves on the device that picked it; the fields above are the source of truth.
        public var contactIdentifier: String?
        /// A firm's tax ID (CUI), digits only, as read off its invoices or policies. Two
        /// records with the same CUI are the same firm, whatever their names say.
        public var taxID: String?
        public var isExample: Bool = false
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()

        @Relationship(deleteRule: .nullify, inverse: \Asset.providers)
        public var assets: [Asset]? = []

        @Relationship(deleteRule: .nullify, inverse: \HistoryEntry.providers)
        public var historyEntries: [HistoryEntry]? = []

        @Relationship(deleteRule: .nullify, inverse: \ServiceItem.supplier)
        public var suppliedItems: [ServiceItem]? = []

        /// Documents from or about them: a contract, a business card, an offer.
        @Relationship(deleteRule: .nullify, inverse: \Attachment.provider)
        public var attachments: [Attachment]? = []

        public init(id: UUID = UUID(), name: String, trades: [ProviderTrade] = [], phone: String? = nil) {
            self.id = id
            self.name = name
            self.trades = trades.map(\.rawValue)
            self.phone = phone
        }

        public var knownTrades: [ProviderTrade] { trades.compactMap(ProviderTrade.init(rawValue:)) }

        public func has(_ trade: ProviderTrade) -> Bool { trades.contains(trade.rawValue) }

        /// The average of rated jobs (rounded to one decimal), or the manual rating.
        public var rating: Double? {
            let ratings = (historyEntries ?? []).compactMap(\.rating).filter { (1...5).contains($0) }
            if !ratings.isEmpty {
                return (Double(ratings.reduce(0, +)) / Double(ratings.count) * 10).rounded() / 10
            }
            return manualRating.map(Double.init)
        }
    }
}
