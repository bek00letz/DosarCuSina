import SwiftUI
import SwiftData

/// Fluid SwiftUI screen for designing and assembling custom asset types.
/// Features a searchable SF Symbol picker, Apple system color palette picker,
/// unit trigger selector (calendar, km, hours, cycles), lifecycle event definitions builder,
/// and dynamic field attributes management.
public struct CustomModuleBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Core Identity State
    @State private var name: String = ""
    @State private var subtitle: String = ""
    @State private var selectedColorHex: String = "007AFF"
    @State private var selectedIcon: String = "cube.fill"
    @State private var iconSearchText: String = ""
    @State private var selectedIconCategory: IconCategory = .all
    
    // Telemetry & Trigger State
    @State private var selectedTrigger: TriggerType = .calendar
    @State private var initialMetricValue: String = ""
    @State private var customMetricUnit: String = ""
    
    // Lifecycle Events Builder State
    @State private var draftEvents: [DraftEvent] = []
    @State private var newEventTitle: String = ""
    @State private var newEventDueDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var newEventCadenceDays: Int = 365
    @State private var newEventMetricInterval: String = ""
    @State private var newEventCost: String = ""
    @State private var isAddingEvent: Bool = false
    
    // Dynamic Fields State
    @State private var dynamicFields: [DynamicField] = []
    
    // Template Gallery Sheet
    @State private var showingTemplatesGallery: Bool = false
    
    public var onAssetCreated: ((Asset) -> Void)?
    
    public init(onAssetCreated: ((Asset) -> Void)? = nil) {
        self.onAssetCreated = onAssetCreated
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    // 1. Live Hero Preview Card
                    heroPreviewCard
                    
                    // 2. Identity Section (Name & Subtitle)
                    identitySection
                    
                    // 3. Apple System Color Palette
                    colorPaletteSection
                    
                    // 4. Searchable SF Symbol Grid
                    iconPickerSection
                    
                    // 5. Unit Trigger Selector (Calendar, Km, Hours, Cycles)
                    triggerSelectorSection
                    
                    // 6. Default Lifecycle Events Builder
                    lifecycleEventsSection
                    
                    // 7. Dynamic Fields Section
                    dynamicFieldsSection
                    
                    // 8. Starter Templates Callout
                    templatesCalloutSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Modul Personalizat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Creează Activ") {
                        saveCustomAsset()
                    }
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showingTemplatesGallery) {
                StarterTemplatesGalleryView { importedAsset in
                    onAssetCreated?(importedAsset)
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - 1. Hero Preview Card
    private var heroPreviewCard: some View {
        let accent = Color(hex: selectedColorHex) ?? .blue
        
        return HStack(spacing: 16) {
            Image(systemName: selectedIcon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 66, height: 66)
                .background(accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent.opacity(0.25), lineWidth: 0.5)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name.isEmpty ? "Denumire Activ" : name)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(name.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 6) {
                    Text("Personalizat")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())
                    
                    Text(selectedTrigger.badgeTitle(unit: effectiveMetricUnit))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    
                    if !draftEvents.isEmpty {
                        Text("\(draftEvents.count) scadențe")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - 2. Identity Section
    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Identitate Modul", systemImage: "pencil.and.outline")
            
            VStack(spacing: 10) {
                TextField("Denumire (ex: Trotinetă, Dronă, Generator)", text: $name)
                    .font(.system(.body, design: .rounded))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                TextField("Subtitlu / Notă (ex: Model Pro, B-99-XYZ, An 2024)", text: $subtitle)
                    .font(.system(.body, design: .rounded))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }
    
    // MARK: - 3. Apple System Color Palette
    private var colorPaletteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Culoare Accent", systemImage: "paintpalette.fill")
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(appleColorPalette, id: \.hex) { item in
                        let isSelected = selectedColorHex.uppercased() == item.hex.uppercased()
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            selectedColorHex = item.hex
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: item.hex) ?? .blue)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                                    )
                                
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(2)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        isSelected ? (Color(hex: item.hex) ?? .blue) : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }
    
    // MARK: - 4. SF Symbol Picker Grid
    private var iconPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Pictogramă SF Symbol", systemImage: "app.dashed")
            
            VStack(spacing: 12) {
                // Search Field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 15))
                    
                    TextField("Caută pictogramă...", text: $iconSearchText)
                        .font(.system(.subheadline, design: .rounded))
                    
                    if !iconSearchText.isEmpty {
                        Button {
                            iconSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 14))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                
                // Category Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(IconCategory.allCases, id: \.self) { cat in
                            let isSelected = selectedIconCategory == cat
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                selectedIconCategory = cat
                            } label: {
                                Text(cat.title)
                                    .font(.system(.caption, design: .rounded, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        isSelected
                                            ? Color.blue.opacity(0.18)
                                            : Color(uiColor: .tertiarySystemGroupedBackground)
                                    )
                                    .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Icon Grid (5 columns)
                let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(filteredIcons, id: \.self) { icon in
                        let isSelected = selectedIcon == icon
                        let accent = Color(hex: selectedColorHex) ?? .blue
                        
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            selectedIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 20))
                                .foregroundStyle(isSelected ? accent : .primary)
                                .frame(height: 48)
                                .frame(maxWidth: .infinity)
                                .background(
                                    isSelected
                                        ? accent.opacity(0.15)
                                        : Color(uiColor: .tertiarySystemGroupedBackground)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            isSelected ? accent : Color.clear,
                                            lineWidth: 1.5
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }
    
    // MARK: - 5. Trigger Selector Section
    private var triggerSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Tip Contor & Declanșator", systemImage: "speedometer")
            
            VStack(spacing: 12) {
                // 4 Trigger Cards Grid (2x2)
                let gridCols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                LazyVGrid(columns: gridCols, spacing: 10) {
                    ForEach(TriggerType.allCases, id: \.self) { trigger in
                        let isSelected = selectedTrigger == trigger
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTrigger = trigger
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: trigger.systemIcon)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.blue)
                                    }
                                }
                                
                                Text(trigger.title)
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundStyle(.primary)
                                
                                Text(trigger.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                isSelected
                                    ? Color.blue.opacity(0.12)
                                    : Color(uiColor: .tertiarySystemGroupedBackground)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? Color.blue.opacity(0.4) : Color.primary.opacity(0.04),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Initial Metric Value (if telemetry active)
                if selectedTrigger != .calendar {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Valoare inițială contor:")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 8) {
                            TextField("0", text: $initialMetricValue)
                                .keyboardType(.decimalPad)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            
                            Text(effectiveMetricUnit)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }
    
    // MARK: - 6. Lifecycle Events Builder Section
    private var lifecycleEventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("Scadențe & Obligații Implicite", systemImage: "clock.arrow.circlepath")
                Spacer()
                if !draftEvents.isEmpty {
                    Text("\(draftEvents.count) definite")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            
            VStack(spacing: 12) {
                // Existing Draft Events
                if !draftEvents.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(draftEvents) { ev in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ev.title)
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    
                                    HStack(spacing: 6) {
                                        Text("Scadent: \(formattedDate(ev.dueDate))")
                                        if let cadence = ev.cadenceDays, cadence > 0 {
                                            Text("• la \(cadence)z")
                                        }
                                        if let metric = ev.cadenceMetricInterval {
                                            Text("• la \(Int(metric)) \(effectiveMetricUnit)")
                                        }
                                        if let cost = ev.cost, cost > 0 {
                                            Text("• ~\(Int(cost)) RON")
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        draftEvents.removeAll { $0.id == ev.id }
                                    }
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                            )
                        }
                    }
                }
                
                // Add Event Inline Card / Trigger
                if isAddingEvent {
                    addEventCard
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isAddingEvent = true
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Adaugă Scadență Implicită")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.08))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }
    
    // Inline Card for adding an event
    private var addEventCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Definire Scadență Nouă")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
            
            TextField("Denumire (ex: Revizie anuală, Schimb ulei, Filtru)", text: $newEventTitle)
                .font(.system(.subheadline, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            DatePicker("Prima Scadență", selection: $newEventDueDate, displayedComponents: .date)
                .font(.system(.subheadline, design: .rounded))
            
            Picker("Recurență Calendaristică", selection: $newEventCadenceDays) {
                Text("Fără recurență").tag(0)
                Text("Lunar (30 zile)").tag(30)
                Text("La 3 luni (90 zile)").tag(90)
                Text("La 6 luni (180 zile)").tag(180)
                Text("Anual (365 zile)").tag(365)
                Text("La 2 ani (730 zile)").tag(730)
            }
            .font(.system(.subheadline, design: .rounded))
            
            if selectedTrigger != .calendar {
                HStack(spacing: 8) {
                    Text("Recurență contor (\(effectiveMetricUnit)):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Ex: 1000", text: $newEventMetricInterval)
                        .keyboardType(.decimalPad)
                        .font(.system(.caption, design: .monospaced))
                        .padding(6)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            
            HStack(spacing: 8) {
                Text("Cost estimat (RON):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("0", text: $newEventCost)
                    .keyboardType(.decimalPad)
                    .font(.system(.caption, design: .monospaced))
                    .padding(6)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            
            HStack(spacing: 10) {
                Button("Anulează") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isAddingEvent = false
                        newEventTitle = ""
                    }
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                
                Button("Adaugă") {
                    confirmAddEvent()
                }
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    newEventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.blue.opacity(0.4)
                        : Color.blue
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .disabled(newEventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemGroupedBackground))
        )
    }
    
    private func confirmAddEvent() {
        let trimmed = newEventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let costVal = Double(newEventCost.replacingOccurrences(of: ",", with: "."))
        let metricInterval = Double(newEventMetricInterval.replacingOccurrences(of: ",", with: "."))
        
        let event = DraftEvent(
            title: trimmed,
            dueDate: newEventDueDate,
            cadenceDays: newEventCadenceDays > 0 ? newEventCadenceDays : nil,
            cadenceMetricInterval: metricInterval,
            cost: costVal
        )
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            draftEvents.append(event)
            newEventTitle = ""
            newEventCost = ""
            newEventMetricInterval = ""
            isAddingEvent = false
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    // MARK: - 7. Dynamic Fields Section
    private var dynamicFieldsSection: some View {
        DynamicFieldEditorView(fields: $dynamicFields)
    }
    
    // MARK: - 8. Starter Templates Callout
    private var templatesCalloutSection: some View {
        Button {
            showingTemplatesGallery = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.purple)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Explorează Șabloane Gata Create")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Biciclete, plante, chirii, espressoare și ambarcațiuni cu 1-tap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.purple.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.purple.opacity(0.2), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions: Save Custom Asset
    private func saveCustomAsset() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        let metricVal: Double? = selectedTrigger == .calendar
            ? nil
            : Double(initialMetricValue.replacingOccurrences(of: ",", with: "."))
        
        let unit: String? = selectedTrigger == .calendar
            ? nil
            : effectiveMetricUnit
        
        let asset = Asset(
            name: trimmedName,
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : subtitle,
            category: .custom,
            iconName: selectedIcon,
            accentColorHex: selectedColorHex,
            currentMetricValue: metricVal,
            metricUnit: unit
        )
        
        modelContext.insert(asset)
        
        // Insert lifecycle events
        for draft in draftEvents {
            let ev = LifecycleEvent(
                title: draft.title,
                dueDate: draft.dueDate,
                cost: draft.cost,
                cadenceDays: draft.cadenceDays,
                cadenceMetricInterval: draft.cadenceMetricInterval,
                reminderOffsetDays: [30, 7, 1]
            )
            ev.asset = asset
            modelContext.insert(ev)
        }
        
        // Insert dynamic fields
        for field in dynamicFields {
            asset.dynamicFields.append(field)
        }
        
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onAssetCreated?(asset)
        dismiss()
    }
    
    // MARK: - Helpers
    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
    }
    
    private var effectiveMetricUnit: String {
        switch selectedTrigger {
        case .calendar: return ""
        case .kilometers: return "km"
        case .hours: return "ore"
        case .cycles: return "cicluri"
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "ro_RO")
        return formatter.string(from: date)
    }
    
    private var filteredIcons: [String] {
        let categoryIcons = selectedIconCategory.icons
        if iconSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return categoryIcons
        } else {
            let query = iconSearchText.lowercased()
            return curatedAllIcons.filter { $0.lowercased().contains(query) }
        }
    }
}

// MARK: - Supporting Enums & Types
public enum TriggerType: String, CaseIterable, Sendable {
    case calendar
    case kilometers
    case hours
    case cycles
    
    public var title: String {
        switch self {
        case .calendar: return "Calendaristic"
        case .kilometers: return "Kilometri"
        case .hours: return "Ore Lucru"
        case .cycles: return "Cicluri Serviciu"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .calendar: return "Zile sau luni fără contor"
        case .kilometers: return "Vehicule, biciclete, trotinete"
        case .hours: return "Bărci, utilaje, compresoare"
        case .cycles: return "Espressoare, aparate, baterii"
        }
    }
    
    public var systemIcon: String {
        switch self {
        case .calendar: return "calendar"
        case .kilometers: return "gauge.with.dots.needle.bottom.50percent"
        case .hours: return "hourglass"
        case .cycles: return "arrow.triangle.2.circlepath"
        }
    }
    
    public func badgeTitle(unit: String) -> String {
        switch self {
        case .calendar: return "Calendaristic"
        case .kilometers: return "Contor km"
        case .hours: return "Contor ore"
        case .cycles: return "Contor cicluri"
        }
    }
}

public struct DraftEvent: Identifiable {
    public let id = UUID()
    public var title: String
    public var dueDate: Date
    public var cadenceDays: Int?
    public var cadenceMetricInterval: Double?
    public var cost: Double?
}

// MARK: - Apple Semantic Color Palette
private struct AppleColorItem {
    let name: String
    let hex: String
}

private let appleColorPalette: [AppleColorItem] = [
    AppleColorItem(name: "Albastru", hex: "007AFF"),
    AppleColorItem(name: "Indigo", hex: "5856D6"),
    AppleColorItem(name: "Mov", hex: "AF52DE"),
    AppleColorItem(name: "Roz", hex: "FF2D55"),
    AppleColorItem(name: "Roșu", hex: "FF3B30"),
    AppleColorItem(name: "Portocaliu", hex: "FF9500"),
    AppleColorItem(name: "Verde", hex: "34C759"),
    AppleColorItem(name: "Mentă", hex: "00C7BE"),
    AppleColorItem(name: "Turcoaz", hex: "30B0C7"),
    AppleColorItem(name: "Cian", hex: "32ADE6"),
    AppleColorItem(name: "Maro", hex: "A2845E"),
    AppleColorItem(name: "Gri", hex: "8E8E93")
]

// MARK: - Curated SF Symbol Categories
private enum IconCategory: String, CaseIterable {
    case all = "Toate"
    case vehicles = "Vehicule"
    case homeAndTools = "Casă & Unelte"
    case tech = "Tech"
    case natureAndSports = "Sport & Natură"
    case objects = "Obiecte"
    
    var title: String { rawValue }
    
    var icons: [String] {
        switch self {
        case .all:
            return curatedAllIcons
        case .vehicles:
            return ["car.fill", "bicycle", "scooter", "sailboat.fill", "airplane", "tram.fill", "steeringwheel", "fuelpump.fill", "bus.fill", "cablecar.fill"]
        case .homeAndTools:
            return ["house.fill", "wrench.and.screwdriver.fill", "hammer.fill", "powerplug.fill", "fanblades.fill", "lightbulb.fill", "key.fill", "flame.fill", "lock.fill", "paintbrush.fill"]
        case .tech:
            return ["laptopcomputer", "desktopcomputer", "printer.fill", "camera.fill", "headphones", "tv.fill", "server.rack", "gamecontroller.fill", "cpu.fill", "keyboard.fill"]
        case .natureAndSports:
            return ["leaf.fill", "tree.fill", "figure.run", "tennisball.fill", "tent.fill", "fish.fill", "camera.macro", "drop.fill", "mountain.2.fill", "snowflake"]
        case .objects:
            return ["cube.fill", "cup.and.saucer.fill", "shield.fill", "cross.case.fill", "creditcard.fill", "gift.fill", "doc.text.fill", "star.fill", "heart.fill", "tag.fill"]
        }
    }
}

private let curatedAllIcons: [String] = [
    // Vehicles
    "car.fill", "bicycle", "scooter", "sailboat.fill", "airplane", "tram.fill", "steeringwheel", "fuelpump.fill", "bus.fill", "cablecar.fill",
    // House & Tools
    "house.fill", "wrench.and.screwdriver.fill", "hammer.fill", "powerplug.fill", "fanblades.fill", "lightbulb.fill", "key.fill", "flame.fill", "lock.fill", "paintbrush.fill",
    // Tech
    "laptopcomputer", "desktopcomputer", "printer.fill", "camera.fill", "headphones", "tv.fill", "server.rack", "gamecontroller.fill", "cpu.fill", "keyboard.fill",
    // Nature & Sport
    "leaf.fill", "tree.fill", "figure.run", "tennisball.fill", "tent.fill", "fish.fill", "camera.macro", "drop.fill", "mountain.2.fill", "snowflake",
    // Objects
    "cube.fill", "cup.and.saucer.fill", "shield.fill", "cross.case.fill", "creditcard.fill", "gift.fill", "doc.text.fill", "star.fill", "heart.fill", "tag.fill"
]
