import SwiftUI
import SwiftData

public struct AssetsVaultView: View {
    @Query(sort: \Asset.createdAt, order: .reverse) private var assets: [Asset]
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingNewAssetSheet = false
    @State private var searchText: String = ""
    @State private var selectedCategory: AssetCategory? = nil
    @State private var assetToDelete: Asset? = nil
    @State private var showingDeleteAlert = false
    
    public init() {}
    
    // MARK: - Search Match Model
    public struct SearchMatchResult: Identifiable {
        public let asset: Asset
        public let matchType: MatchType
        public let matchDetail: String
        
        public var id: UUID { asset.id }
        
        public enum MatchType {
            case assetTitle
            case identifier(String)       // VIN, Număr Auto, Cod POD, Cod CLC, Microcip, etc.
            case contact(String)          // Doctor, Instalator, etc.
            case event(String)            // Titlu obligație, Furnizor, Poliță
            case serviceItem(String)      // Piesă, Medic, Lot
            case measurement(String)      // Măsurătoare contor / biomarker
            case documentText(String)     // OCR text match
            
            public var badgeText: String {
                switch self {
                case .assetTitle: return "Activ"
                case .identifier(let idName): return idName
                case .contact(let role): return "Contact: \(role)"
                case .event(let title): return "Obligație: \(title)"
                case .serviceItem(let name): return "Service: \(name)"
                case .measurement(let metric): return "Măsurătoare: \(metric)"
                case .documentText(let file): return "OCR: \(file)"
                }
            }
            
            public var icon: String {
                switch self {
                case .assetTitle: return "folder.fill"
                case .identifier: return "number"
                case .contact: return "person.crop.circle"
                case .event: return "calendar"
                case .serviceItem: return "wrench.and.screwdriver"
                case .measurement: return "gauge.medium"
                case .documentText: return "doc.text.magnifyingglass"
                }
            }
        }
    }
    
    // MARK: - 6-Layer Multi-Entity Faceted Search
    public var filteredResults: [SearchMatchResult] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = RomanianUtilityParser.stripDiacritics(trimmed).lowercased()
        
        return assets.compactMap { asset -> SearchMatchResult? in
            // Filter by Category Pill
            if let cat = selectedCategory, asset.category != cat {
                return nil
            }
            
            // If search query is empty, return standard asset card
            if query.isEmpty {
                return SearchMatchResult(asset: asset, matchType: .assetTitle, matchDetail: asset.category.title)
            }
            
            // Layer 1: Asset Core Attributes
            let nameNorm = RomanianUtilityParser.stripDiacritics(asset.name).lowercased()
            let subNorm = RomanianUtilityParser.stripDiacritics(asset.subtitle ?? "").lowercased()
            let notesNorm = RomanianUtilityParser.stripDiacritics(asset.notes ?? "").lowercased()
            if nameNorm.contains(query) || subNorm.contains(query) || notesNorm.contains(query) {
                return SearchMatchResult(asset: asset, matchType: .assetTitle, matchDetail: asset.name)
            }
            
            // Layer 2: Asset Identifiers
            if let vin = asset.vin, vin.lowercased().contains(query) {
                return SearchMatchResult(asset: asset, matchType: .identifier("VIN"), matchDetail: vin)
            }
            if let plate = asset.licensePlate {
                let cleanPlate = plate.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
                let cleanQuery = query.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
                if cleanPlate.contains(cleanQuery) {
                    return SearchMatchResult(asset: asset, matchType: .identifier("Număr Auto"), matchDetail: plate)
                }
            }
            if let pod = asset.podCode, pod.lowercased().contains(query) {
                return SearchMatchResult(asset: asset, matchType: .identifier("Cod POD"), matchDetail: pod)
            }
            if let clc = asset.clcCode, clc.lowercased().contains(query) {
                return SearchMatchResult(asset: asset, matchType: .identifier("Cod CLC"), matchDetail: clc)
            }
            if let water = asset.waterClientCode, water.lowercased().contains(query) {
                return SearchMatchResult(asset: asset, matchType: .identifier("Cod Client Apă"), matchDetail: water)
            }
            if let chip = asset.microchipNumber, chip.contains(query) {
                return SearchMatchResult(asset: asset, matchType: .identifier("Microcip"), matchDetail: chip)
            }
            if let sn = asset.serialOrImei, sn.lowercased().contains(query) {
                return SearchMatchResult(asset: asset, matchType: .identifier("Serie / IMEI"), matchDetail: sn)
            }
            if let pName = asset.personName, RomanianUtilityParser.stripDiacritics(pName).lowercased().contains(query) {
                return SearchMatchResult(asset: asset, matchType: .identifier("Persoană"), matchDetail: pName)
            }
            
            // Layer 3: Associated Contacts
            if let cName = asset.primaryContactName, RomanianUtilityParser.stripDiacritics(cName).lowercased().contains(query) {
                return SearchMatchResult(asset: asset, matchType: .contact(asset.primaryContactRole ?? "Specialist"), matchDetail: cName)
            }
            if let docName = asset.familyDoctorName, RomanianUtilityParser.stripDiacritics(docName).lowercased().contains(query) {
                return SearchMatchResult(asset: asset, matchType: .contact("Medic de Familie"), matchDetail: docName)
            }
            if let vet = asset.veterinarianClinic, RomanianUtilityParser.stripDiacritics(vet).lowercased().contains(query) {
                return SearchMatchResult(asset: asset, matchType: .contact("Clinică Veterinară"), matchDetail: vet)
            }
            
            // Layer 4: Obligations & Lifecycle Events
            for ev in asset.events {
                let evTitle = RomanianUtilityParser.stripDiacritics(ev.title).lowercased()
                let evProv = RomanianUtilityParser.stripDiacritics(ev.provider ?? "").lowercased()
                let evPolicy = (ev.policyOrContractNumber ?? "").lowercased()
                if evTitle.contains(query) || evProv.contains(query) || evPolicy.contains(query) {
                    return SearchMatchResult(asset: asset, matchType: .event(ev.title), matchDetail: ev.provider ?? ev.title)
                }
            }
            
            // Layer 5: Historical Service Items
            for svc in asset.serviceItems {
                let sName = RomanianUtilityParser.stripDiacritics(svc.name).lowercased()
                let sBrand = RomanianUtilityParser.stripDiacritics(svc.partBrand ?? "").lowercased()
                let sDoctor = RomanianUtilityParser.stripDiacritics(svc.specialistOrDoctorName ?? "").lowercased()
                let sBatch = (svc.serialOrBatchNumber ?? "").lowercased()
                let sLoc = (svc.locationOrToothNumber ?? "").lowercased()
                if sName.contains(query) || sBrand.contains(query) || sDoctor.contains(query) || sBatch.contains(query) || sLoc.contains(query) {
                    let detail = svc.specialistOrDoctorName != nil ? "\(svc.name) (\(svc.specialistOrDoctorName!))" : svc.name
                    return SearchMatchResult(asset: asset, matchType: .serviceItem(svc.name), matchDetail: detail)
                }
            }
            
            // Layer 6: Measurement Logs
            for m in asset.measurements {
                let mName = RomanianUtilityParser.stripDiacritics(m.metricName).lowercased()
                let mLab = RomanianUtilityParser.stripDiacritics(m.labOrProviderName ?? "").lowercased()
                if mName.contains(query) || mLab.contains(query) {
                    return SearchMatchResult(asset: asset, matchType: .measurement(m.metricName), matchDetail: "\(m.metricName): \(String(format: "%.1f", m.value)) \(m.unit)")
                }
            }
            
            // Layer 7: Document Attachments OCR Text
            for att in asset.attachments {
                let attName = att.fileName.lowercased()
                if attName.contains(query) {
                    return SearchMatchResult(asset: asset, matchType: .documentText(att.fileName), matchDetail: att.fileName)
                }
                if let text = att.extractedText, RomanianUtilityParser.stripDiacritics(text).lowercased().contains(query) {
                    return SearchMatchResult(asset: asset, matchType: .documentText(att.fileName), matchDetail: att.fileName)
                }
            }
            for ev in asset.events {
                for att in ev.attachments {
                    let attName = att.fileName.lowercased()
                    if attName.contains(query) {
                        return SearchMatchResult(asset: asset, matchType: .documentText(att.fileName), matchDetail: "\(att.fileName) (\(ev.title))")
                    }
                    if let text = att.extractedText, RomanianUtilityParser.stripDiacritics(text).lowercased().contains(query) {
                        return SearchMatchResult(asset: asset, matchType: .documentText(att.fileName), matchDetail: "\(att.fileName) (\(ev.title))")
                    }
                }
            }
            
            return nil
        }
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category Filter Pills
                categoryPillsBar
                
                ScrollView {
                    if assets.isEmpty {
                        emptyVaultState
                    } else if filteredResults.isEmpty {
                        noSearchResultsView
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(filteredResults) { result in
                                NavigationLink {
                                    AssetDetailView(asset: result.asset)
                                } label: {
                                    assetCard(result: result)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    NavigationLink {
                                        AssetDetailView(asset: result.asset)
                                    } label: {
                                        Label("Deschide Dosar", systemImage: "folder.fill")
                                    }
                                    
                                    Divider()
                                    
                                    Button(role: .destructive) {
                                        assetToDelete = result.asset
                                        showingDeleteAlert = true
                                    } label: {
                                        Label("Șterge Activul", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Căutare Active")
            .searchable(text: $searchText, prompt: "Caută activ, serie, contact, service, OCR...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewAssetSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .confirmationDialog(
                "Ștergi acest activ?",
                isPresented: $showingDeleteAlert,
                titleVisibility: .visible,
                presenting: assetToDelete
            ) { asset in
                Button("Șterge definitiv „\(asset.name)”", role: .destructive) {
                    deleteAsset(asset)
                }
                Button("Anulează", role: .cancel) {
                    assetToDelete = nil
                }
            } message: { asset in
                Text("Toate obligațiile, intervențiile tehnice și fișierele asociate dosarului „\(asset.name)” vor fi eliminate.")
            }
            .sheet(isPresented: $showingNewAssetSheet) {
                NewAssetSheet()
            }
        }
    }
    
    private func deleteAsset(_ asset: Asset) {
        withAnimation {
            modelContext.delete(asset)
            try? modelContext.save()
            WidgetDataSyncService.shared.sync(context: modelContext)
        }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        assetToDelete = nil
    }
    
    // MARK: - Category Filter Pills
    private var categoryPillsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryPill(title: "Toate", icon: "square.grid.2x2", category: nil)
                categoryPill(title: "Casă", icon: "house.fill", category: .home)
                categoryPill(title: "Auto", icon: "car.fill", category: .vehicle)
                categoryPill(title: "Sănătate", icon: "heart.text.square.fill", category: .health)
                categoryPill(title: "Animale", icon: "pawprint.fill", category: .pet)
                categoryPill(title: "Documente", icon: "person.text.rectangle.fill", category: .documents)
                categoryPill(title: "Garanții", icon: "shield.lefthalf.filled", category: .warranties)
                categoryPill(title: "Abonamente", icon: "creditcard.fill", category: .subscriptions)
                categoryPill(title: "Custom", icon: "slider.horizontal.3", category: .custom)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
    
    private func categoryPill(title: String, icon: String, category: AssetCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedCategory = category
            }
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: isSelected ? .bold : .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.primary : Color(uiColor: .secondarySystemGroupedBackground))
            .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color.primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: isSelected ? Color.black.opacity(0.12) : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Asset Card
    private func assetCard(result: SearchMatchResult) -> some View {
        let asset = result.asset
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Asset Icon Badge
                Image(systemName: asset.iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(asset.accentColor)
                    .frame(width: 44, height: 44)
                    .background(asset.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    if let sub = asset.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(asset.category.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Urgent badge or count pill
                if asset.urgentEventsCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                        Text("\(asset.urgentEventsCount) urgente")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Capsule())
                } else {
                    Text("\(asset.pendingEventsCount) active")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
            
            // Search Match Attribution Badge (when searching)
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: result.matchType.icon)
                        .font(.caption2)
                    Text("\(result.matchType.badgeText): \(result.matchDetail)")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            
            Divider()
                .opacity(0.5)
            
            // Next event & metric telemetry row
            HStack {
                if let next = asset.nextUpcomingEvent {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Următoarea scadență:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(next.title) • \(next.dueDate.formatted(.dateTime.day().month()))")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                } else {
                    Text("Nicio scadență programată")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let metric = asset.currentMetricValue, let unit = asset.metricUnit {
                    Text("\(Int(metric)) \(unit)")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
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
    
    // MARK: - Empty States
    private var noSearchResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .padding(.top, 40)
            Text("Niciun rezultat găsit")
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text("Nu am găsit active, contacte, piese sau documente pentru «\(searchText)»")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var emptyVaultState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.indigo.gradient)
                .padding(.top, 40)
            
            Text("Seiful de Active este gol")
                .font(.system(.title3, design: .rounded, weight: .semibold))
            
            Text("Creează un spațiu pentru casa ta, mașină, animalul de companie sau un modul personalizat.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                showingNewAssetSheet = true
            } label: {
                Text("Adaugă Activ")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }
}
