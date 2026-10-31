import SwiftUI
import SwiftData

/// Comprehensive, granular event editor.
/// Allows full modification of dates, costs, real providers (e.g. Allianz, Groupama, Omniasig),
/// policy numbers, coverage types, mileage, recurrence rules, and attached service line items.
public struct EditEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable public var event: LifecycleEvent
    
    // Core Form State
    @State private var title: String
    @State private var dueDate: Date
    @State private var isCompleted: Bool
    @State private var cost: String
    @State private var currency: String
    
    // Provider & Policy State
    @State private var selectedProvider: String
    @State private var customProviderText: String = ""
    @State private var policyOrContractNumber: String
    @State private var coverageType: String
    @State private var bonusMalusClass: String
    
    // Telemetry & Location
    @State private var mileageAtEvent: String
    @State private var serviceLocation: String
    @State private var eventDescription: String
    
    // Recurrence
    @State private var cadenceDays: Int
    
    // Sub-sheet state
    @State private var showingAddLineItem: Bool = false
    @State private var showingDeleteConfirmation: Bool = false
    
    public init(event: LifecycleEvent) {
        self.event = event
        _title = State(initialValue: event.title)
        _dueDate = State(initialValue: event.dueDate)
        _isCompleted = State(initialValue: event.isCompleted)
        _cost = State(initialValue: event.cost != nil ? String(format: "%.0f", event.cost!) : "")
        _currency = State(initialValue: event.currency)
        
        let prov = event.provider ?? ""
        if RomanianInsurers.all.contains(prov) {
            _selectedProvider = State(initialValue: prov)
        } else if !prov.isEmpty {
            _selectedProvider = State(initialValue: "Alt asigurător / Furnizor")
            _customProviderText = State(initialValue: prov)
        } else {
            _selectedProvider = State(initialValue: "Nespecificat")
        }
        
        _policyOrContractNumber = State(initialValue: event.policyOrContractNumber ?? "")
        _coverageType = State(initialValue: event.coverageType ?? "RCA")
        _bonusMalusClass = State(initialValue: event.bonusMalusClass ?? "B0 (0% Bază)")
        _mileageAtEvent = State(initialValue: event.mileageAtEvent != nil ? "\(Int(event.mileageAtEvent!))" : "")
        _serviceLocation = State(initialValue: event.serviceLocation ?? "")
        _eventDescription = State(initialValue: event.eventDescription ?? "")
        _cadenceDays = State(initialValue: event.cadenceDays ?? 365)
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: Core Details
                Section("Informații Principale") {
                    TextField("Titlu (ex: Asigurare RCA, Revizie 90.000 km)", text: $title)
                    DatePicker("Dată Scadență / Expirare", selection: $dueDate, displayedComponents: .date)
                    
                    HStack {
                        TextField("Cost real", text: $cost)
                            .keyboardType(.decimalPad)
                        
                        Picker("Monedă", selection: $currency) {
                            Text("RON").tag("RON")
                            Text("EUR").tag("EUR")
                            Text("USD").tag("USD")
                        }
                        .pickerStyle(.menu)
                    }
                    
                    Toggle("Marcat ca Rezolvat / Efectuat", isOn: $isCompleted)
                }
                
                // Section 2: Provider & Insurance (If applicable or custom)
                Section("Furnizor & Detalii Poliță / Contract") {
                    Picker("Companie / Asigurător", selection: $selectedProvider) {
                        Text("Nespecificat").tag("Nespecificat")
                        ForEach(RomanianInsurers.all, id: \.self) { insurer in
                            Text(insurer).tag(insurer)
                        }
                    }
                    
                    if selectedProvider == "Alt asigurător / Furnizor" || selectedProvider == "Alt asigurător" {
                        TextField("Nume furnizor / service", text: $customProviderText)
                    }
                    
                    TextField("Serie & Număr Poliță / Contract", text: $policyOrContractNumber)
                    
                    if isInsuranceRelated {
                        Picker("Tip Acoperire", selection: $coverageType) {
                            ForEach(RomanianInsurers.coverageTypes, id: \.self) { cov in
                                Text(cov).tag(cov)
                            }
                        }
                        
                        Picker("Clasă Bonus-Malus", selection: $bonusMalusClass) {
                            ForEach(RomanianInsurers.bonusMalusClasses, id: \.self) { bm in
                                Text(bm).tag(bm)
                            }
                        }
                    }
                }
                
                // Section 3: Telemetry & Location
                Section("Kilometraj & Service") {
                    TextField("Kilometraj la eveniment (km)", text: $mileageAtEvent)
                        .keyboardType(.numberPad)
                    
                    TextField("Locație service / stație ITP / clinică", text: $serviceLocation)
                }
                
                // Section 4: Cadence
                Section("Recurență Automată") {
                    Picker("Interval repetare", selection: $cadenceDays) {
                        Text("Lunar (30 zile)").tag(30)
                        Text("Trimestrial (90 zile)").tag(90)
                        Text("Semestrial (180 zile)").tag(180)
                        Text("Anual (365 zile)").tag(365)
                        Text("La 2 ani (730 zile)").tag(730)
                        Text("Fără repetare").tag(0)
                    }
                }
                
                // Section 5: Piese Schimbate & Manoperă (Service Line Items)
                Section {
                    if event.serviceItems.isEmpty {
                        Text("Nicio piesă sau operațiune detaliată încă.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(event.serviceItems) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    if let brand = item.partBrandOrCode {
                                        Text(brand)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if let c = item.cost {
                                    Text("\(String(format: "%.0f", c)) RON")
                                        .font(.caption.weight(.bold))
                                }
                            }
                        }
                        .onDelete(perform: deleteServiceItem)
                    }
                    
                    if let asset = event.asset {
                        Button {
                            showingAddLineItem = true
                        } label: {
                            Label("Adaugă Piesă / Manoperă la Eveniment", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                } header: {
                    Text("Piese & Consumabile Schimbate")
                } footer: {
                    Text("Poți detalia fiecare piesă (ex: plăcuțe frână, ulei, filtre) pentru a le compara ulterior în istoricul de mentenanță.")
                }
                
                // Section 6: Notes
                Section("Observații") {
                    TextField("Note suplimentare...", text: $eventDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                // Section 7: Destructive Delete Action
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Șterge Acest Eveniment")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Editare Eveniment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Închide") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvează") {
                        saveChanges()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showingAddLineItem) {
                if let asset = event.asset {
                    AddServiceItemSheet(asset: asset, event: event)
                }
            }
            .alert("Confirmare Ștergere", isPresented: $showingDeleteConfirmation) {
                Button("Anulează", role: .cancel) {}
                Button("Șterge", role: .destructive) {
                    deleteEvent()
                }
            } message: {
                Text("Sigur dorești să elimini acest eveniment din dosar?")
            }
        }
    }
    
    private var isInsuranceRelated: Bool {
        let t = title.lowercased()
        return t.contains("rca") || t.contains("casco") || t.contains("asigurare") || t.contains("pad") || selectedProvider != "Nespecificat"
    }
    
    private func saveChanges() {
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.dueDate = dueDate
        event.isCompleted = isCompleted
        if isCompleted && event.completedDate == nil {
            event.completedDate = Date()
        } else if !isCompleted {
            event.completedDate = nil
        }
        
        event.cost = Double(cost.replacingOccurrences(of: ",", with: "."))
        event.currency = currency
        
        let providerToSave: String?
        if selectedProvider == "Alt asigurător / Furnizor" || selectedProvider == "Alt asigurător" {
            providerToSave = customProviderText.isEmpty ? nil : customProviderText
        } else if selectedProvider != "Nespecificat" {
            providerToSave = selectedProvider
        } else {
            providerToSave = nil
        }
        event.provider = providerToSave
        
        event.policyOrContractNumber = policyOrContractNumber.isEmpty ? nil : policyOrContractNumber
        event.coverageType = isInsuranceRelated ? coverageType : nil
        event.bonusMalusClass = isInsuranceRelated ? bonusMalusClass : nil
        
        let mileageVal = Double(mileageAtEvent.replacingOccurrences(of: ",", with: "."))
        event.mileageAtEvent = mileageVal
        event.serviceLocation = serviceLocation.isEmpty ? nil : serviceLocation
        event.eventDescription = eventDescription.isEmpty ? nil : eventDescription
        event.cadenceDays = cadenceDays > 0 ? cadenceDays : nil
        
        // Synchronize asset mileage if higher
        if let asset = event.asset, let mileageVal = mileageVal {
            if asset.currentMetricValue == nil || mileageVal > asset.currentMetricValue! {
                asset.currentMetricValue = mileageVal
                asset.updatedAt = Date()
            }
        }
        
        // Update notification schedule
        if event.isCompleted {
            NotificationScheduler.shared.cancelReminders(for: event)
        } else {
            NotificationScheduler.shared.scheduleReminders(for: event)
        }
        
        dismiss()
    }
    
    private func deleteEvent() {
        NotificationScheduler.shared.cancelReminders(for: event)
        modelContext.delete(event)
        dismiss()
    }
    
    private func deleteServiceItem(at offsets: IndexSet) {
        for index in offsets {
            let item = event.serviceItems[index]
            modelContext.delete(item)
        }
    }
}
