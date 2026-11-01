import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

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
            .background(Color.groupedBackground.ignoresSafeArea())
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
                .fill(Color.secondaryGroupedBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        )
    }
    
    // MARK: - Template Detail Sheet
    private func templateDetailSheet(_ template: StarterTemplate) -> some View {
        let accent = Color(hex: template.accentColorHex) ?? .blue
        
        return NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Hero
                    HStack(spacing: 16) {
                        Image(systemName: template.iconName)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(width: 68, height: 68)
                            .background(accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(accent.opacity(0.2), lineWidth: 0.5)
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
                            .fill(Color.secondaryGroupedBackground)
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
                            .background(Color.secondaryGroupedBackground)
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
                                    #if canImport(UIKit)
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    #endif
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
                                            .fill(Color.secondaryGroupedBackground)
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
                                            .fill(Color.secondaryGroupedBackground)
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
            .background(Color.groupedBackground.ignoresSafeArea())
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
        
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        
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
        
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        
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
        let accent = Color(hex: template.accentColorHex) ?? .blue
        
        VStack(alignment: .leading, spacing: 14) {
            // Card Header
            HStack(spacing: 14) {
                Image(systemName: template.iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 54, height: 54)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(accent.opacity(0.18), lineWidth: 0.5)
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
                            .fill(accent)
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
                    .fill(Color.tertiaryGroupedBackground)
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
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondaryGroupedBackground)
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Color Semantic Helpers
fileprivate extension Color {
    static var groupedBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color.secondary.opacity(0.08)
        #endif
    }
    
    static var secondaryGroupedBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #else
        return Color.secondary.opacity(0.12)
        #endif
    }
    
    static var tertiaryGroupedBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .tertiarySystemGroupedBackground)
        #else
        return Color.secondary.opacity(0.16)
        #endif
    }
}
