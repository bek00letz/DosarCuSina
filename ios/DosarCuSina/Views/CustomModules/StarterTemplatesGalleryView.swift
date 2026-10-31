import SwiftUI
import SwiftData

/// Tactile starter template gallery showcasing ready-to-use module configurations
/// with 1-tap import creating the Asset, LifecycleEvents, and DynamicFields in SwiftData.
public struct StarterTemplatesGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedTemplate: StarterTemplate?
    @State private var importedAssetBanner: String?
    @State private var customAssetName: String = ""
    @State private var selectedEventIds: Set<UUID> = []
    
    public var onAssetImported: ((Asset) -> Void)?
    
    public init(onAssetImported: ((Asset) -> Void)? = nil) {
        self.onAssetImported = onAssetImported
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Subtitle & Polish
                    headerExplainer
                    
                    // Success Toast
                    if let banner = importedAssetBanner {
                        importSuccessBanner(banner)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Template Cards
                    VStack(spacing: 16) {
                        ForEach(StarterTemplate.allTemplates) { template in
                            StarterTemplateCard(
                                template: template,
                                onQuickImport: {
                                    importTemplate(template)
                                },
                                onInspect: {
                                    openTemplateDetail(template)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Șabloane Module")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Închide") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedTemplate) { template in
                templateDetailSheet(template)
            }
        }
    }
    
    // MARK: - Header Explainer
    private var headerExplainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Module Pre-configurate")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
            
            Text("Importă cu un singur tap profile de mentenanță și recurențe legale concepute special pentru echipamentele tale.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Success Banner
    private func importSuccessBanner(_ name: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Activ importat cu succes!")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Text("„\(name)“ a fost adăugat în Dosar cu toate scadențele aferente.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        )
    }
    
    // MARK: - Template Detail Sheet
    private func templateDetailSheet(_ template: StarterTemplate) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Hero
                    HStack(spacing: 16) {
                        Image(systemName: template.iconName)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(Color(hex: template.accentColorHex) ?? .blue)
                            .frame(width: 68, height: 68)
                            .background(
                                (Color(hex: template.accentColorHex) ?? .blue).opacity(0.12)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder((Color(hex: template.accentColorHex) ?? .blue).opacity(0.2), lineWidth: 0.5)
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.title)
                                .font(.system(.title3, design: .rounded, weight: .bold))
                            Text(template.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    
                    // Name Customizer
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Denumire Activ")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        
                        TextField("Denumire personalizată", text: $customAssetName)
                            .font(.system(.body, design: .rounded))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                    }
                    
                    // Events List with Toggles
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Scadențe & Mentenanță Incluse")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Spacer()
                            Text("\(selectedEventIds.count) selectate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack(spacing: 8) {
                            ForEach(template.suggestedEvents) { event in
                                let isSelected = selectedEventIds.contains(event.id)
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    if isSelected {
                                        selectedEventIds.remove(event.id)
                                    } else {
                                        selectedEventIds.insert(event.id)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 20))
                                            .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.5))
                                        
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(event.title)
                                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            
                                            HStack(spacing: 6) {
                                                if let cadence = event.cadenceDays {
                                                    Text("la fiecare \(cadence) zile")
                                                }
                                                if let metric = event.cadenceMetricValue, let unit = event.metricUnit {
                                                    Text("• la fiecare \(Int(metric)) \(unit)")
                                                }
                                                if let cost = event.cost, cost > 0 {
                                                    Text("• ~\(Int(cost)) RON")
                                                }
                                            }
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .strokeBorder(
                                                        isSelected ? Color.blue.opacity(0.3) : Color.primary.opacity(0.06),
                                                        lineWidth: 0.5
                                                    )
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Attributes Preview
                    if !template.suggestedFields.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Atribute Pre-definite")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            
                            VStack(spacing: 6) {
                                ForEach(template.suggestedFields) { field in
                                    HStack {
                                        Text(field.label)
                                            .font(.system(.subheadline, design: .rounded))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(field.defaultValueDescription)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                    )
                                }
                            }
                        }
                    }
                    
                    // Bottom Primary CTA
                    Button {
                        importConfiguredTemplate(template)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Creează Activ în Dosar")
                                .font(.system(.body, design: .rounded, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.top, 10)
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Configurare Șablon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") {
                        selectedTemplate = nil
                    }
                }
            }
        }
    }
    
    private func openTemplateDetail(_ template: StarterTemplate) {
        customAssetName = template.title
        selectedEventIds = Set(template.suggestedEvents.map { $0.id })
        selectedTemplate = template
    }
    
    // MARK: - Direct 1-Tap Import
    private func importTemplate(_ template: StarterTemplate) {
        let calendar = Calendar.current
        let today = Date()
        
        let asset = Asset(
            name: template.title,
            subtitle: template.subtitle,
            category: template.category,
            iconName: template.iconName,
            accentColorHex: template.accentColorHex,
            currentMetricValue: template.initialMetricValue,
            metricUnit: template.metricUnit
        )
        
        modelContext.insert(asset)
        
        // Populate suggested events
        for ev in template.suggestedEvents {
            let due = calendar.date(byAdding: .day, value: ev.initialDueOffsetDays, to: today) ?? today
            let lifecycleEvent = LifecycleEvent(
                title: ev.title,
                dueDate: due,
                cost: ev.cost,
                cadenceDays: ev.cadenceDays,
                cadenceMetricInterval: ev.cadenceMetricValue,
                reminderOffsetDays: [30, 7, 1]
            )
            lifecycleEvent.asset = asset
            modelContext.insert(lifecycleEvent)
        }
        
        // Populate suggested fields
        for field in template.suggestedFields {
            let dynamicField = DynamicField(
                key: field.key,
                label: field.label,
                fieldType: field.fieldType,
                stringValue: field.defaultString,
                numberValue: field.defaultNumber
            )
            asset.dynamicFields.append(dynamicField)
        }
        
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            importedAssetBanner = template.title
        }
        
        onAssetImported?(asset)
        
        // Auto-clear banner after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                importedAssetBanner = nil
            }
        }
    }
    
    // MARK: - Import Configured Template from Sheet
    private func importConfiguredTemplate(_ template: StarterTemplate) {
        let calendar = Calendar.current
        let today = Date()
        let name = customAssetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? template.title
            : customAssetName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let asset = Asset(
            name: name,
            subtitle: template.subtitle,
            category: template.category,
            iconName: template.iconName,
            accentColorHex: template.accentColorHex,
            currentMetricValue: template.initialMetricValue,
            metricUnit: template.metricUnit
        )
        
        modelContext.insert(asset)
        
        // Filter events by user selection
        for ev in template.suggestedEvents where selectedEventIds.contains(ev.id) {
            let due = calendar.date(byAdding: .day, value: ev.initialDueOffsetDays, to: today) ?? today
            let lifecycleEvent = LifecycleEvent(
                title: ev.title,
                dueDate: due,
                cost: ev.cost,
                cadenceDays: ev.cadenceDays,
                cadenceMetricInterval: ev.cadenceMetricValue,
                reminderOffsetDays: [30, 7, 1]
            )
            lifecycleEvent.asset = asset
            modelContext.insert(lifecycleEvent)
        }
        
        for field in template.suggestedFields {
            let dynamicField = DynamicField(
                key: field.key,
                label: field.label,
                fieldType: field.fieldType,
                stringValue: field.defaultString,
                numberValue: field.defaultNumber
            )
            asset.dynamicFields.append(dynamicField)
        }
        
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        
        selectedTemplate = nil
        onAssetImported?(asset)
        dismiss()
    }
}

// MARK: - Starter Template Card
private struct StarterTemplateCard: View {
    let template: StarterTemplate
    let onQuickImport: () -> Void
    let onInspect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Card Header
            HStack(spacing: 14) {
                Image(systemName: template.iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(hex: template.accentColorHex) ?? .blue)
                    .frame(width: 54, height: 54)
                    .background((Color(hex: template.accentColorHex) ?? .blue).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder((Color(hex: template.accentColorHex) ?? .blue).opacity(0.18), lineWidth: 0.5)
                    )
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(template.title)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text(template.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
            }
            
            // Badges Row
            HStack(spacing: 8) {
                Label(template.metricBadgeTitle, systemImage: template.metricBadgeIcon)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                
                Label("\(template.suggestedEvents.count) scadențe", systemImage: "clock.arrow.circlepath")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                
                Spacer()
            }
            
            // Events Preview (Top 3)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(template.suggestedEvents.prefix(3)) { ev in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: template.accentColorHex) ?? .blue)
                            .frame(width: 5, height: 5)
                        Text(ev.title)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        if let days = ev.cadenceDays {
                            Text("la \(days)z")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else if let metric = ev.cadenceMetricValue, let unit = ev.metricUnit {
                            Text("la \(Int(metric)) \(unit)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if template.suggestedEvents.count > 3 {
                    Text("+ încă \(template.suggestedEvents.count - 3) scadențe...")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            )
            
            // Action Buttons
            HStack(spacing: 10) {
                Button {
                    onInspect()
                } label: {
                    Text("Previzualizare")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                
                Button {
                    onQuickImport()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Importă")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color(hex: template.accentColorHex) ?? .blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Template Model Structures
public struct StarterTemplate: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let category: AssetCategory
    public let iconName: String
    public let accentColorHex: String
    public let primaryMetric: String
    public let metricUnit: String?
    public let initialMetricValue: Double?
    public let suggestedEvents: [TemplateEvent]
    public let suggestedFields: [TemplateField]
    
    public var metricBadgeTitle: String {
        switch primaryMetric {
        case "kilometers": return "Contor km"
        case "hours": return "Contor ore"
        case "cycles": return "Contor cicluri"
        default: return "Calendaristic"
        }
    }
    
    public var metricBadgeIcon: String {
        switch primaryMetric {
        case "kilometers": return "gauge.with.dots.needle.bottom.50percent"
        case "hours": return "hourglass"
        case "cycles": return "arrow.triangle.2.circlepath"
        default: return "calendar"
        }
    }
}

public struct TemplateEvent: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let cadenceDays: Int?
    public let cadenceMetricValue: Double?
    public let metricUnit: String?
    public let initialDueOffsetDays: Int
    public let cost: Double?
    
    public init(
        id: UUID = UUID(),
        title: String,
        cadenceDays: Int? = nil,
        cadenceMetricValue: Double? = nil,
        metricUnit: String? = nil,
        initialDueOffsetDays: Int = 30,
        cost: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.cadenceDays = cadenceDays
        self.cadenceMetricValue = cadenceMetricValue
        self.metricUnit = metricUnit
        self.initialDueOffsetDays = initialDueOffsetDays
        self.cost = cost
    }
}

public struct TemplateField: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let key: String
    public let label: String
    public let fieldType: DynamicFieldType
    public let defaultString: String?
    public let defaultNumber: Double?
    
    public init(
        id: UUID = UUID(),
        key: String,
        label: String,
        fieldType: DynamicFieldType = .text,
        defaultString: String? = nil,
        defaultNumber: Double? = nil
    ) {
        self.id = id
        self.key = key
        self.label = label
        self.fieldType = fieldType
        self.defaultString = defaultString
        self.defaultNumber = defaultNumber
    }
    
    public var defaultValueDescription: String {
        if let s = defaultString, !s.isEmpty {
            return s
        }
        if let n = defaultNumber {
            return "\(n)"
        }
        return fieldType.displayTitle
    }
}

// MARK: - Pre-configured Starter Catalog
extension StarterTemplate {
    public static let allTemplates: [StarterTemplate] = [
        // 1. Bicicletă / E-Bike
        StarterTemplate(
            id: "bike",
            title: "Bicicletă / E-Bike",
            subtitle: "Mentenanță lanț, presiune roți, frâne și furcă",
            category: .custom,
            iconName: "bicycle",
            accentColorHex: "34C759",
            primaryMetric: "kilometers",
            metricUnit: "km",
            initialMetricValue: 0.0,
            suggestedEvents: [
                TemplateEvent(title: "Ungere și curățare lanț", cadenceDays: 14, cadenceMetricValue: 150, metricUnit: "km", initialDueOffsetDays: 14, cost: 35),
                TemplateEvent(title: "Verificare presiune cauciucuri", cadenceDays: 7, initialDueOffsetDays: 7, cost: 0),
                TemplateEvent(title: "Verificare uzură plăcuțe frână", cadenceMetricValue: 1000, metricUnit: "km", initialDueOffsetDays: 60, cost: 80),
                TemplateEvent(title: "Înlocuire lanț transmisie", cadenceMetricValue: 2000, metricUnit: "km", initialDueOffsetDays: 180, cost: 120),
                TemplateEvent(title: "Service suspensie / furcă", cadenceDays: 365, cadenceMetricValue: 100, metricUnit: "hours", initialDueOffsetDays: 180, cost: 250)
            ],
            suggestedFields: [
                TemplateField(key: "tip_bicicleta", label: "Tip Bicicletă", defaultString: "MTB / E-Bike"),
                TemplateField(key: "serie_cadru", label: "Serie Cadru", defaultString: ""),
                TemplateField(key: "marime_roti", label: "Mărime Roți", defaultString: "29 inch")
            ]
        ),
        
        // 2. Plante de Interior
        StarterTemplate(
            id: "plants",
            title: "Plante de Interior & Grădină",
            subtitle: "Program udare, fertilizare de sezon și schimbat pământ",
            category: .custom,
            iconName: "leaf.fill",
            accentColorHex: "00C7BE",
            primaryMetric: "calendar",
            metricUnit: nil,
            initialMetricValue: nil,
            suggestedEvents: [
                TemplateEvent(title: "Udare periodică", cadenceDays: 7, initialDueOffsetDays: 3, cost: 0),
                TemplateEvent(title: "Fertilizare de sezon (primăvară/vară)", cadenceDays: 30, initialDueOffsetDays: 14, cost: 25),
                TemplateEvent(title: "Schimbare substrat și ghiveci", cadenceDays: 730, initialDueOffsetDays: 180, cost: 45),
                TemplateEvent(title: "Curățare praf frunze & pulverizare", cadenceDays: 14, initialDueOffsetDays: 7, cost: 0)
            ],
            suggestedFields: [
                TemplateField(key: "specie_nume", label: "Specie / Nume Plantă", defaultString: "Monstera"),
                TemplateField(key: "nivel_lumina", label: "Nivel Lumină", defaultString: "Lumină indirectă")
            ]
        ),
        
        // 3. Proprietăți Închiriate
        StarterTemplate(
            id: "landlord",
            title: "Proprietăți Închiriate",
            subtitle: "Index contoare, încasare chirie, revizie centrală și contract ANAF",
            category: .home,
            iconName: "building.2.fill",
            accentColorHex: "5856D6",
            primaryMetric: "calendar",
            metricUnit: nil,
            initialMetricValue: nil,
            suggestedEvents: [
                TemplateEvent(title: "Scadență plată / încasare chirie", cadenceDays: 30, initialDueOffsetDays: 10, cost: 2200),
                TemplateEvent(title: "Transmitere index apometre & utilități", cadenceDays: 30, initialDueOffsetDays: 25, cost: 0),
                TemplateEvent(title: "Verificare Tehnică Centrală (VTP)", cadenceDays: 730, initialDueOffsetDays: 120, cost: 350),
                TemplateEvent(title: "Reînnoire înregistrare contract ANAF", cadenceDays: 365, initialDueOffsetDays: 240, cost: 0)
            ],
            suggestedFields: [
                TemplateField(key: "nume_chirias", label: "Nume Chiriaș", defaultString: ""),
                TemplateField(key: "numar_contract", label: "Număr Contract ANAF", defaultString: ""),
                TemplateField(key: "garantie", label: "Garanție Depusă (RON)", fieldType: .currency, defaultNumber: 4400.0)
            ]
        ),
        
        // 4. Espressor de Cafea
        StarterTemplate(
            id: "espresso",
            title: "Espressor de Cafea",
            subtitle: "Decalcifiere, schimbat filtru apă și curățare grup",
            category: .custom,
            iconName: "cup.and.saucer.fill",
            accentColorHex: "A2845E",
            primaryMetric: "cycles",
            metricUnit: "cicluri",
            initialMetricValue: 0.0,
            suggestedEvents: [
                TemplateEvent(title: "Curățare chimică grup (Cafiza)", cadenceDays: 14, cadenceMetricValue: 100, metricUnit: "extracții", initialDueOffsetDays: 7, cost: 30),
                TemplateEvent(title: "Decalcifiere completă boiler", cadenceDays: 60, cadenceMetricValue: 300, metricUnit: "extracții", initialDueOffsetDays: 30, cost: 40),
                TemplateEvent(title: "Înlocuire filtru apă / rășină dedurizatoare", cadenceDays: 60, initialDueOffsetDays: 45, cost: 65),
                TemplateEvent(title: "Curățare duză spumare lapte", cadenceDays: 7, initialDueOffsetDays: 2, cost: 0)
            ],
            suggestedFields: [
                TemplateField(key: "model_aparat", label: "Model Espressor", defaultString: ""),
                TemplateField(key: "duritate_apa", label: "Duritate Apă (dH)", fieldType: .number, defaultNumber: 7.0),
                TemplateField(key: "diametru_portfiltru", label: "Portfiltru", defaultString: "58mm")
            ]
        ),
        
        // 5. Ambarcațiuni / Bărci
        StarterTemplate(
            id: "boat",
            title: "Ambarcațiuni / Bărci",
            subtitle: "Revizie motor barcă, antivegetativă și verificare veste salvare",
            category: .custom,
            iconName: "sailboat.fill",
            accentColorHex: "32ADE6",
            primaryMetric: "hours",
            metricUnit: "ore",
            initialMetricValue: 0.0,
            suggestedEvents: [
                TemplateEvent(title: "Revizie motor barcă (Ulei & Filtre)", cadenceDays: 365, cadenceMetricValue: 100, metricUnit: "ore", initialDueOffsetDays: 90, cost: 850),
                TemplateEvent(title: "Vopsea antivegetativă (Antifouling)", cadenceDays: 365, initialDueOffsetDays: 120, cost: 1200),
                TemplateEvent(title: "Verificare veste salvare & siguranță", cadenceDays: 180, initialDueOffsetDays: 60, cost: 0),
                TemplateEvent(title: "Verificare anod sacrificiu (zinc)", cadenceDays: 180, initialDueOffsetDays: 90, cost: 150)
            ],
            suggestedFields: [
                TemplateField(key: "nr_inmatriculare", label: "Număr Pavilion / Înmatriculare", defaultString: ""),
                TemplateField(key: "putere_motor", label: "Putere Motor (CP)", fieldType: .number, defaultNumber: 115.0),
                TemplateField(key: "port_acostare", label: "Port de Ambarcare", defaultString: "")
            ]
        )
    ]
}
