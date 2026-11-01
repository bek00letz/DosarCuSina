import SwiftUI
import Combine

/// Model representing a displayed category tile on the main Active dashboard.
public struct CategoryDisplayItem: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public var title: String
    public var iconName: String
    public var colorHex: String
    public var isEnabled: Bool
    public var isCustom: Bool
    public var customTag: String?
    
    public init(
        id: String,
        title: String,
        iconName: String,
        colorHex: String,
        isEnabled: Bool = true,
        isCustom: Bool = false,
        customTag: String? = nil
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.colorHex = colorHex
        self.isEnabled = isEnabled
        self.isCustom = isCustom
        self.customTag = customTag
    }
    
    public var matchingAssetCategory: AssetCategory? {
        AssetCategory(rawValue: id)
    }
    
    public var tintColor: Color {
        switch id {
        case AssetCategory.vehicle.rawValue: return .blue
        case AssetCategory.home.rawValue: return .orange
        case AssetCategory.health.rawValue: return .pink
        case AssetCategory.pet.rawValue: return .brown
        case AssetCategory.documents.rawValue: return .indigo
        case AssetCategory.warranties.rawValue: return .teal
        case AssetCategory.subscriptions.rawValue: return .purple
        case AssetCategory.custom.rawValue: return .gray
        default:
            return Color(hex: colorHex) ?? .blue
        }
    }
}

// MARK: - Color Hex Helper
extension Color {
    public func toHex() -> String {
        return "#007AFF"
    }
}

// MARK: - Category Display Manager
@Observable
public final class CategoryDisplayManager: @unchecked Sendable {
    public static let shared = CategoryDisplayManager()
    
    private let storageKey = "dosarcusina_category_display_items_v2"
    
    public var items: [CategoryDisplayItem] = [] {
        didSet {
            saveToStorage()
        }
    }
    
    public var enabledItems: [CategoryDisplayItem] {
        items.filter { $0.isEnabled }
    }
    
    public init() {
        loadFromStorage()
    }
    
    public static var defaultItems: [CategoryDisplayItem] {
        [
            CategoryDisplayItem(id: AssetCategory.vehicle.rawValue, title: "Auto & Moto", iconName: "car.fill", colorHex: "#007AFF"),
            CategoryDisplayItem(id: AssetCategory.home.rawValue, title: "Locuință & Utilități", iconName: "house.fill", colorHex: "#FF9500"),
            CategoryDisplayItem(id: AssetCategory.health.rawValue, title: "Sănătate & Medical", iconName: "heart.text.square.fill", colorHex: "#FF2D55"),
            CategoryDisplayItem(id: AssetCategory.pet.rawValue, title: "Animale de Companie", iconName: "pawprint.fill", colorHex: "#A2845E"),
            CategoryDisplayItem(id: AssetCategory.documents.rawValue, title: "Documente & Identitate", iconName: "person.text.rectangle.fill", colorHex: "#5856D6"),
            CategoryDisplayItem(id: AssetCategory.warranties.rawValue, title: "Garanții & Bonuri", iconName: "shield.lefthalf.filled", colorHex: "#30B0C7"),
            CategoryDisplayItem(id: AssetCategory.subscriptions.rawValue, title: "Abonamente & Servicii", iconName: "creditcard.fill", colorHex: "#AF52DE"),
            CategoryDisplayItem(id: AssetCategory.custom.rawValue, title: "Active Personalizate", iconName: "square.grid.2x2.fill", colorHex: "#8E8E93")
        ]
    }
    
    private func loadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([CategoryDisplayItem].self, from: data),
           !decoded.isEmpty {
            self.items = decoded
        } else {
            self.items = Self.defaultItems
        }
    }
    
    private func saveToStorage() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }
    
    public func toggleItem(_ item: CategoryDisplayItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isEnabled.toggle()
        }
    }
    
    public func addCustomCategory(title: String, iconName: String, colorHex: String) {
        let tag = "custom_\(UUID().uuidString.prefix(8).lowercased())"
        let newItem = CategoryDisplayItem(
            id: tag,
            title: title,
            iconName: iconName,
            colorHex: colorHex,
            isEnabled: true,
            isCustom: true,
            customTag: tag
        )
        items.append(newItem)
    }
    
    public func removeCustomCategory(id: String) {
        items.removeAll { $0.id == id && $0.isCustom }
    }
    
    public func resetToDefaults() {
        self.items = Self.defaultItems
    }
}
