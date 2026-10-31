import SwiftUI

public enum AssetCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case home = "home"
    case vehicle = "vehicle"
    case pet = "pet"
    case health = "health"
    case documents = "documents"
    case warranties = "warranties"
    case subscriptions = "subscriptions"
    case custom = "custom"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .home: return "Casă"
        case .vehicle: return "Mașină"
        case .pet: return "Pet"
        case .health: return "Sănătate"
        case .documents: return "Documente"
        case .warranties: return "Garanții"
        case .subscriptions: return "Abonamente"
        case .custom: return "Personalizat"
        }
    }
    
    public var systemIcon: String {
        switch self {
        case .home: return "house.fill"
        case .vehicle: return "car.fill"
        case .pet: return "pawprint.fill"
        case .health: return "heart.text.square.fill"
        case .documents: return "person.text.rectangle.fill"
        case .warranties: return "shield.lefthalf.filled"
        case .subscriptions: return "creditcard.fill"
        case .custom: return "square.grid.2x2.fill"
        }
    }
    
    public var defaultColor: Color {
        switch self {
        case .home: return .orange
        case .vehicle: return .blue
        case .pet: return .brown
        case .health: return .pink
        case .documents: return .indigo
        case .warranties: return .teal
        case .subscriptions: return .purple
        case .custom: return .gray
        }
    }
}
