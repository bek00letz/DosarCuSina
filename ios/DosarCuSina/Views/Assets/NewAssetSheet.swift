import SwiftUI
import SwiftData

public struct NewAssetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var name: String = ""
    @State private var subtitle: String = ""
    @State private var selectedCategory: AssetCategory = .vehicle
    @State private var metricUnit: String = "km"
    @State private var initialMetricValue: String = ""
    @State private var autoPopulateSuggestedEvents: Bool = true
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Informații de Bază") {
                    TextField("Denumire (ex: VW Golf, Apartament)", text: $name)
                    TextField("Subtitlu / Notă (ex: An 2018, B-123-ABC)", text: $subtitle)
                    
                    Picker("Categorie", selection: $selectedCategory) {
                        ForEach(AssetCategory.allCases) { cat in
                            Label(cat.title, systemImage: cat.systemIcon).tag(cat)
                        }
                    }
                }
                
                if selectedCategory == .vehicle || selectedCategory == .custom {
                    Section("Telemetrie & Contor (Opțional)") {
                        Picker("Unitate de măsură", selection: $metricUnit) {
                            Text("Kilometri (km)").tag("km")
                            Text("Ore funcționare (h)").tag("hours")
                            Text("Cicluri / Extracții").tag("cycles")
                            Text("Fără contor").tag("none")
                        }
                        
                        if metricUnit != "none" {
                            TextField("Valoare inițială contor", text: $initialMetricValue)
                                .keyboardType(.numberPad)
                        }
                    }
                }
                
                Section {
                    Toggle("Generează automat scadențe uzuale", isOn: $autoPopulateSuggestedEvents)
                } footer: {
                    Text("Pre-configurează obligațiile legale și de mentenanță recomandate pentru categoria aleasă.")
                }
            }
            .navigationTitle("Activ Nou")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvează") {
                        saveAsset()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveAsset() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let metricVal = Double(initialMetricValue.replacingOccurrences(of: ",", with: "."))
        
        let newAsset = Asset(
            name: trimmedName,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            category: selectedCategory,
            currentMetricValue: metricVal,
            metricUnit: metricUnit == "none" ? nil : metricUnit
        )
        
        modelContext.insert(newAsset)
        
        if autoPopulateSuggestedEvents {
            populateDefaults(for: newAsset)
        }
        
        dismiss()
    }
    
    private func populateDefaults(for asset: Asset) {
        let calendar = Calendar.current
        let today = Date()
        
        switch asset.category {
        case .vehicle:
            // RCA (1 year)
            let rca = LifecycleEvent(
                title: "Asigurare RCA",
                dueDate: calendar.date(byAdding: .month, value: 6, to: today) ?? today,
                cost: 950,
                cadenceDays: 365,
                reminderOffsetDays: [30, 7, 1]
            )
            rca.asset = asset
            modelContext.insert(rca)
            
            // ITP (1 year / 2 years)
            let itp = LifecycleEvent(
                title: "Inspecție Tehnică Periodică (ITP)",
                dueDate: calendar.date(byAdding: .month, value: 4, to: today) ?? today,
                cost: 150,
                cadenceDays: 365,
                reminderOffsetDays: [30, 7, 1]
            )
            itp.asset = asset
            modelContext.insert(itp)
            
            // Rovinieta
            let rov = LifecycleEvent(
                title: "Rovinietă Națională",
                dueDate: calendar.date(byAdding: .month, value: 10, to: today) ?? today,
                cost: 140,
                cadenceDays: 365,
                reminderOffsetDays: [14, 3, 1]
            )
            rov.asset = asset
            modelContext.insert(rov)
            
            // Revizie Ulei + Filtre
            let rev = LifecycleEvent(
                title: "Revizie Periodicǎ (Ulei + Filtre)",
                dueDate: calendar.date(byAdding: .month, value: 8, to: today) ?? today,
                cost: 800,
                cadenceDays: 365,
                cadenceMetricInterval: 15000,
                reminderOffsetDays: [30, 7]
            )
            rev.asset = asset
            modelContext.insert(rev)
            
        case .home:
            // VTP Centrala (2 ani)
            let vtp = LifecycleEvent(
                title: "Verificare Tehnică Centrală (VTP)",
                dueDate: calendar.date(byAdding: .month, value: 11, to: today) ?? today,
                cost: 350,
                cadenceDays: 730,
                reminderOffsetDays: [30, 7]
            )
            vtp.asset = asset
            modelContext.insert(vtp)
            
            // Verificare Gaze (2 ani)
            let gaze = LifecycleEvent(
                title: "Verificare Instalație Gaze",
                dueDate: calendar.date(byAdding: .month, value: 14, to: today) ?? today,
                cost: 200,
                cadenceDays: 730,
                reminderOffsetDays: [30, 7]
            )
            gaze.asset = asset
            modelContext.insert(gaze)
            
            // Asigurare PAD + Facultativă
            let pad = LifecycleEvent(
                title: "Poliță Asigurare Locuință (PAD)",
                dueDate: calendar.date(byAdding: .month, value: 5, to: today) ?? today,
                cost: 130,
                cadenceDays: 365,
                reminderOffsetDays: [30, 7]
            )
            pad.asset = asset
            modelContext.insert(pad)
            
        case .pet:
            // Deparazitare interna (3 luni)
            let depInt = LifecycleEvent(
                title: "Deparazitare Internă",
                dueDate: calendar.date(byAdding: .month, value: 2, to: today) ?? today,
                cost: 45,
                cadenceDays: 90,
                reminderOffsetDays: [7, 1]
            )
            depInt.asset = asset
            modelContext.insert(depInt)
            
            // Vaccin Anual
            let vacc = LifecycleEvent(
                title: "Vaccin Polivalent + Antirabic",
                dueDate: calendar.date(byAdding: .month, value: 7, to: today) ?? today,
                cost: 180,
                cadenceDays: 365,
                reminderOffsetDays: [14, 3]
            )
            vacc.asset = asset
            modelContext.insert(vacc)
            
        case .health:
            // Detartraj 6 luni
            let det = LifecycleEvent(
                title: "Igienizare & Detartraj Stomatologic",
                dueDate: calendar.date(byAdding: .month, value: 3, to: today) ?? today,
                cost: 300,
                cadenceDays: 180,
                reminderOffsetDays: [14, 3]
            )
            det.asset = asset
            modelContext.insert(det)
            
            // Analize sange anuale
            let analize = LifecycleEvent(
                title: "Set Anual Analize Sânge (Check-up)",
                dueDate: calendar.date(byAdding: .month, value: 6, to: today) ?? today,
                cost: 450,
                cadenceDays: 365,
                reminderOffsetDays: [30, 7]
            )
            analize.asset = asset
            modelContext.insert(analize)
            
        default:
            break
        }
    }
}
