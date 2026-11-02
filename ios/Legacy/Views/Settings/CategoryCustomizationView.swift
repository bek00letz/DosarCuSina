import SwiftUI

/// View for customizing which category tiles appear on the main Active dashboard and their order.
public struct CategoryCustomizationView: View {
    @State private var manager = CategoryDisplayManager.shared
    @State private var showingAddCustomSheet = false
    @State private var showingResetConfirmation = false
    
    // Custom Category Form State
    @State private var newCategoryTitle: String = ""
    @State private var selectedIcon: String = "briefcase.fill"
    @State private var selectedColorHex: String = "#007AFF"
    
    private let availableIcons = [
        "briefcase.fill", "bicycle", "wrench.and.screwdriver.fill", "cross.case.fill",
        "leaf.fill", "desktopcomputer", "gamecontroller.fill", "camera.fill",
        "shippingbox.fill", "building.columns.fill", "fork.knife", "trophy.fill",
        "airplane", "sailboat.fill", "music.note", "book.fill"
    ]
    
    private let availableColors = [
        "#007AFF", "#34C759", "#FF9500", "#FF2D55",
        "#AF52DE", "#5856D6", "#30B0C7", "#FF3B30",
        "#A2845E", "#8E8E93"
    ]
    
    public init() {}
    
    public var body: some View {
        List {
            Section {
                ForEach($manager.items) { $item in
                    HStack(spacing: 14) {
                        Image(systemName: item.iconName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(item.tintColor)
                            .frame(width: 32, height: 32)
                            .background(item.tintColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(item.isEnabled ? .primary : .secondary)
                            
                            if item.isCustom {
                                Text("Personalizat")
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                            }
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $item.isEnabled)
                            .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }
                .onMove { indices, newOffset in
                    manager.move(fromOffsets: indices, toOffset: newOffset)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let item = manager.items[index]
                        if item.isCustom {
                            manager.removeCustomCategory(id: item.id)
                        }
                    }
                }
            } header: {
                Text("Categorii Active & Ordine")
            } footer: {
                Text("Trage de barele din dreapta pentru a rearanja ordinea pătratelor pe ecranul principal. Dezactivează categoriile care nu te interesează (de ex. dacă nu ai animale sau mașină).")
            }
            
            Section {
                Button {
                    showingAddCustomSheet = true
                } label: {
                    Label("Adaugă Categorie Personalizată", systemImage: "plus.circle.fill")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
                
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label("Resetează la ordinea implicită", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("Personalizare Ecran")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .confirmationDialog(
            "Resetează la configurația implicită?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Resetează", role: .destructive) {
                withAnimation {
                    manager.resetToDefaults()
                }
            }
            Button("Anulează", role: .cancel) {}
        } message: {
            Text("Toate cele 8 categorii standard vor fi reactivate și readuse la ordinea inițială.")
        }
        .sheet(isPresented: $showingAddCustomSheet) {
            addCustomCategorySheet
        }
    }
    
    // MARK: - Add Custom Category Sheet
    private var addCustomCategorySheet: some View {
        NavigationStack {
            Form {
                Section("Denumire Categorie") {
                    TextField("Ex: Bicicletă, PFA, Livadă, Echipamente", text: $newCategoryTitle)
                }
                
                Section("Alege Simbol (Icon)") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(availableIcons, id: \.self) { icon in
                            iconButton(for: icon)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Alege Culoare") {
                    HStack(spacing: 12) {
                        ForEach(availableColors, id: \.self) { colorHex in
                            colorButton(for: colorHex)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Categorie Nouă")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") {
                        showingAddCustomSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvează") {
                        let trimmed = newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            withAnimation {
                                manager.addCustomCategory(
                                    title: trimmed,
                                    iconName: selectedIcon,
                                    colorHex: selectedColorHex
                                )
                            }
                            newCategoryTitle = ""
                            showingAddCustomSheet = false
                        }
                    }
                    .disabled(newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private var selectedColor: Color {
        Color(hex: selectedColorHex) ?? .blue
    }
    
    @ViewBuilder
    private func iconButton(for icon: String) -> some View {
        let isSelected = selectedIcon == icon
        Button {
            selectedIcon = icon
        } label: {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 54, height: 54)
                .background(isSelected ? selectedColor.opacity(0.2) : Color(uiColor: .tertiarySystemGroupedBackground))
                .foregroundStyle(isSelected ? selectedColor : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? selectedColor : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func colorButton(for colorHex: String) -> some View {
        let isSelected = selectedColorHex == colorHex
        let swatch = Color(hex: colorHex) ?? .blue
        Button {
            selectedColorHex = colorHex
        } label: {
            Circle()
                .fill(swatch)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(isSelected ? 0.8 : 0), lineWidth: 3)
                )
        }
        .buttonStyle(.plain)
    }
}
