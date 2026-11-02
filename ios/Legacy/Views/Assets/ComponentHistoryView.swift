import SwiftUI
import SwiftData

/// Dedicated view for tracking and cross-referencing specific parts, maintenance items,
/// and repairs over the complete lifecycle of an asset (e.g. brake pads, engine oil, filters).
/// Computes delta km (distance in-between), delta cost, and wear rates.
public struct ComponentHistoryView: View {
    @Bindable public var asset: Asset
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedCategoryFilter: String = "Toate"
    @State private var showingAddServiceItemSheet: Bool = false
    @State private var selectedComponentDetail: String? = nil
    
    public init(asset: Asset) {
        self.asset = asset
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header overview card
                overviewCard
                
                // Category filter pills
                categoryFilterPills
                
                // Grouped Component Cards
                if groupedComponents.isEmpty {
                    emptyComponentsState
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(groupedComponents, id: \.name) { group in
                            componentGroupCard(group: group)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Istoric Piese & Service")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddServiceItemSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
        }
        .sheet(isPresented: $showingAddServiceItemSheet) {
            AddServiceItemSheet(asset: asset)
        }
    }
    
    // MARK: - Component Group Model
    public struct ComponentGroup {
        public let name: String
        public let category: String
        public let items: [ServiceItem] // Sorted newest to oldest
        
        public var latestItem: ServiceItem? { items.first }
        public var previousItem: ServiceItem? { items.count > 1 ? items[1] : nil }
        
        public var deltaKm: Double? {
            guard let latestKm = latestItem?.mileageAtService,
                  let prevKm = previousItem?.mileageAtService,
                  latestKm >= prevKm else { return nil }
            return latestKm - prevKm
        }
        
        public var deltaCost: Double? {
            guard let latestCost = latestItem?.cost,
                  let prevCost = previousItem?.cost else { return nil }
            return latestCost - prevCost
        }
        
        public var costPercentChange: Double? {
            guard let delta = deltaCost,
                  let prevCost = previousItem?.cost,
                  prevCost > 0 else { return nil }
            return (delta / prevCost) * 100
        }
        
        public var timeBetween: String? {
            guard let latestDate = latestItem?.serviceDate,
                  let prevDate = previousItem?.serviceDate,
                  latestDate >= prevDate else { return nil }
            let components = Calendar.current.dateComponents([.year, .month, .day], from: prevDate, to: latestDate)
            if let years = components.year, years > 0 {
                return "\(years) \(years == 1 ? "an" : "ani")" + (components.month ?? 0 > 0 ? " și \(components.month!) luni" : "")
            } else if let months = components.month, months > 0 {
                return "\(months) \(months == 1 ? "lună" : "luni")"
            } else if let days = components.day, days >= 0 {
                return "\(days) \(days == 1 ? "zi" : "zile")"
            }
            return nil
        }
    }
    
    private var groupedComponents: [ComponentGroup] {
        var dict: [String: [ServiceItem]] = [:]
        for item in asset.serviceItems {
            let key = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            dict[key, default: []].append(item)
        }
        
        let groups = dict.map { (name, list) in
            let sorted = list.sorted { $0.serviceDate > $1.serviceDate }
            let cat = sorted.first?.category ?? "General"
            return ComponentGroup(name: name, category: cat, items: sorted)
        }
        
        if selectedCategoryFilter == "Toate" {
            return groups.sorted { ($0.latestItem?.serviceDate ?? Date.distantPast) > ($1.latestItem?.serviceDate ?? Date.distantPast) }
        } else {
            return groups
                .filter { $0.category == selectedCategoryFilter }
                .sorted { ($0.latestItem?.serviceDate ?? Date.distantPast) > ($1.latestItem?.serviceDate ?? Date.distantPast) }
        }
    }
    
    private var categories: [String] {
        var set = Set(asset.serviceItems.map { $0.category })
        set.insert("Frâne")
        set.insert("Ulei & Filtre")
        set.insert("Motor & Transmisie")
        set.insert("Suspensie & Direcție")
        set.insert("Anvelope")
        return ["Toate"] + Array(set).sorted()
    }
    
    // MARK: - UI Subviews
    private var overviewCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(asset.accentColor)
                .frame(width: 52, height: 52)
                .background(asset.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Catalog Piese & Diagnostic")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                
                Text("\(asset.serviceItems.count) piese/intervenții înregistrate în istoric.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
    }
    
    private var categoryFilterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    let isSelected = selectedCategoryFilter == cat
                    Button {
                        selectedCategoryFilter = cat
                    } label: {
                        Text(cat)
                            .font(.system(.caption, design: .rounded, weight: isSelected ? .bold : .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.primary : Color(uiColor: .tertiarySystemFill))
                            .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    private func componentGroupCard(group: ComponentGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row: Component Name & Category Badge
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text(group.category)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                let countBadgeText = group.items.count == 1 ? "1 înlocuire" : "\(group.items.count) înlocuiri"
                Text(countBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(Capsule())
            }
            
            Divider().opacity(0.5)
            
            // Comparison Metrics Card (Between last 2 changes)
            if let latest = group.latestItem {
                VStack(spacing: 8) {
                    // Latest change details
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ultimul schimb:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 6) {
                                Text(latest.serviceDate.formatted(.dateTime.day().month().year()))
                                    .font(.system(.caption, design: .rounded, weight: .bold))
                                
                                if let km = latest.mileageAtService, km.isFinite, km >= 0 {
                                    Text("• \(Int(km)) km")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        if let cost = latest.cost, cost.isFinite {
                            Text("\(String(format: "%.0f", cost)) RON")
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                        }
                    }
                    
                    if let brand = latest.partBrandOrCode, !brand.isEmpty {
                        HStack {
                            Text("Producător / Cod piesă:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(brand)
                                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    
                    // Historical Delta Box (The User's Desired Superpower!)
                    if group.previousItem != nil {
                        HStack(spacing: 12) {
                            if let deltaKm = group.deltaKm {
                                deltaMetricBadge(
                                    title: "Rulate între schimburi",
                                    value: "\(Int(deltaKm)) km",
                                    icon: "gauge.with.needle",
                                    color: .blue
                                )
                            }
                            
                            if let time = group.timeBetween {
                                deltaMetricBadge(
                                    title: "Timp scurs",
                                    value: time,
                                    icon: "clock.arrow.circlepath",
                                    color: .orange
                                )
                            }
                            
                            if let deltaCost = group.deltaCost {
                                let isMore = deltaCost > 0
                                deltaMetricBadge(
                                    title: "Diferență preț",
                                    value: (isMore ? "+" : "") + "\(String(format: "%.0f", deltaCost)) RON",
                                    icon: isMore ? "arrow.up.right" : "arrow.down.right",
                                    color: isMore ? .red : .green
                                )
                            }
                        }
                        .padding(10)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
        )
    }
    
    private func deltaMetricBadge(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(title)
                    .font(.system(size: 9))
            }
            .foregroundStyle(color)
            
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var emptyComponentsState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wrench.adjustable")
                .font(.system(size: 42))
                .foregroundStyle(.blue.opacity(0.8))
                .padding(.top, 30)
            
            Text("Nicio piesă detaliată încă")
                .font(.system(.headline, design: .rounded))
            
            Text("Adaugă componentele schimbate la service (plăcuțe, ulei, filtre) pentru a urmări costurile și uzura în km.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                showingAddServiceItemSheet = true
            } label: {
                Label("Adaugă Piesă / Intervenție", systemImage: "plus")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Add Service Item Sheet
public struct AddServiceItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    public var asset: Asset
    public var event: LifecycleEvent?
    
    @State private var name: String = ""
    @State private var category: String = "Frâne"
    @State private var partBrandOrCode: String = ""
    @State private var cost: String = ""
    @State private var mileage: String = ""
    @State private var serviceDate: Date = Date()
    @State private var notes: String = ""
    @State private var selectedCatalogItem: String? = nil
    
    public init(asset: Asset, event: LifecycleEvent? = nil) {
        self.asset = asset
        self.event = event
        _mileage = State(initialValue: asset.currentMetricValue != nil ? "\(Int(asset.currentMetricValue!))" : "")
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Selectare Rapidă din Catalog") {
                    Picker("Sugestie Piesă", selection: $selectedCatalogItem) {
                        Text("Personalizat / Altă piesă").tag(nil as String?)
                        ForEach(VehicleServiceCatalog.commonComponents, id: \.name) { comp in
                            Text("\(comp.name) (\(comp.category))").tag(comp.name as String?)
                        }
                    }
                    .onChange(of: selectedCatalogItem) { _, newVal in
                        if let newVal = newVal,
                           let match = VehicleServiceCatalog.commonComponents.first(where: { $0.name == newVal }) {
                            name = match.name
                            category = match.category
                        }
                    }
                }
                
                Section("Detalii Piesă & Lucrare") {
                    TextField("Denumire (ex: Plăcuțe frână față)", text: $name)
                    TextField("Categorie (ex: Frâne, Ulei, Filtre)", text: $category)
                    TextField("Brand / Cod Piesă (ex: Brembo P 85 020)", text: $partBrandOrCode)
                }
                
                Section("Cost & Kilometraj") {
                    TextField("Cost piesă / manoperă (RON)", text: $cost)
                        .keyboardType(.decimalPad)
                    
                    TextField("Kilometraj în bord (km)", text: $mileage)
                        .keyboardType(.numberPad)
                    
                    DatePicker("Data intervenției", selection: $serviceDate, displayedComponents: .date)
                }
                
                Section("Note suplimentare") {
                    TextField("Observații (ex: Schimbat la reprezentanță, garanție 2 ani)", text: $notes)
                }
            }
            .navigationTitle("Piesă / Intervenție Nouă")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvează") {
                        saveItem()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveItem() {
        let costVal = Double(cost.replacingOccurrences(of: ",", with: "."))
        let mileageVal = Double(mileage.replacingOccurrences(of: ",", with: "."))
        
        let item = ServiceItem(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
            partBrand: partBrandOrCode.isEmpty ? nil : partBrandOrCode,
            cost: costVal,
            serviceDate: serviceDate,
            mileageAtService: mileageVal,
            notes: notes.isEmpty ? nil : notes
        )
        
        item.asset = asset
        if let event = event {
            item.event = event
        }
        
        // If mileage is higher than current asset odometer, update odometer!
        if let mileageVal = mileageVal, (asset.currentMetricValue == nil || mileageVal > asset.currentMetricValue!) {
            asset.currentMetricValue = mileageVal
            asset.updatedAt = Date()
        }
        
        modelContext.insert(item)
        dismiss()
    }
}
