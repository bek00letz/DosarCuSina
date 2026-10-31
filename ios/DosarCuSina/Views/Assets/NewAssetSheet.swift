import SwiftUI
import SwiftData

/// Comprehensive creation wizard for new assets tailored per category.
/// Follows Apple Craftsmanship & Polish Standard with category-specific schemas,
/// interactive obligation setup with real Romanian providers, and unlimited dynamic fields.
public struct NewAssetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Core Identity
    @State private var name: String = ""
    @State private var subtitle: String = ""
    @State private var selectedCategory: AssetCategory = .vehicle
    @State private var metricUnit: String = "km"
    @State private var initialMetricValue: String = ""
    
    // Vehicle Domain Fields
    @State private var licensePlate: String = ""
    @State private var vinNumber: String = ""
    @State private var manufactureYear: String = ""
    @State private var fuelType: String = "Benzină"
    @State private var engineDisplacement: String = ""
    @State private var enginePower: String = ""
    
    // Home Domain Fields
    @State private var fullAddress: String = ""
    @State private var surfaceArea: String = ""
    @State private var constructionYear: String = ""
    @State private var heatingBoilerModel: String = ""
    @State private var heatingBoilerSerial: String = ""
    @State private var gasMeterSerial: String = ""
    @State private var electricityMeterSerial: String = ""
    @State private var waterMeterSerial: String = ""
    
    // Pet Domain Fields
    @State private var petSpecies: String = "Câine"
    @State private var petBreed: String = ""
    @State private var petMicrochipNumber: String = ""
    @State private var petBirthDate: Date = Date()
    @State private var hasPetBirthDate: Bool = false
    @State private var veterinarianClinic: String = ""
    @State private var veterinarianPhone: String = ""
    
    // Health Domain Fields
    @State private var bloodType: String = "A+"
    @State private var familyDoctorName: String = ""
    @State private var familyDoctorPhone: String = ""
    @State private var emergencyContactName: String = ""
    @State private var emergencyContactPhone: String = ""
    @State private var allergiesNotes: String = ""
    
    // Dynamic Fields for Custom Specifications
    @State private var dynamicFields: [DynamicField] = []
    
    // Configurable Initial Events Checklist
    @State private var configuredEvents: [ConfigurableStarterEvent] = []
    
    private let fuelOptions = ["Benzină", "Motorină", "Hibrid", "Plug-in Hybrid", "Electric", "GPL"]
    private let bloodTypeOptions = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-", "Necunoscut"]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: Core Information
                Section("Informații de Bază") {
                    TextField("Denumire (ex: VW Golf 7, Apartament Pipera)", text: $name)
                        .font(.system(.body, design: .rounded))
                    
                    TextField("Subtitlu / Notă (ex: B-123-ABC, 2.0 TDI)", text: $subtitle)
                        .font(.system(.body, design: .rounded))
                    
                    Picker("Categorie Activ", selection: $selectedCategory) {
                        ForEach(AssetCategory.allCases) { cat in
                            Label(cat.title, systemImage: cat.systemIcon).tag(cat)
                        }
                    }
                    .onChange(of: selectedCategory) { _, newCat in
                        updateCategoryDefaults(for: newCat)
                    }
                }
                
                // Section 2: Domain-Specific Fields
                switch selectedCategory {
                case .vehicle:
                    vehicleFieldsSection
                case .home:
                    homeFieldsSection
                case .pet:
                    petFieldsSection
                case .health:
                    healthFieldsSection
                default:
                    EmptyView()
                }
                
                // Section 3: Telemetry & Odometer
                if selectedCategory == .vehicle || selectedCategory == .custom {
                    Section("Contor & Telemetrie") {
                        Picker("Unitate de măsură", selection: $metricUnit) {
                            Text("Kilometri (km)").tag("km")
                            Text("Ore funcționare (h)").tag("hours")
                            Text("Cicluri").tag("cycles")
                            Text("Fără contor").tag("none")
                        }
                        
                        if metricUnit != "none" {
                            HStack {
                                Text("Valoare inițială contor")
                                Spacer()
                                TextField("0", text: $initialMetricValue)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.system(.body, design: .monospaced))
                                Text(metricUnit)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // Section 4: Initial Configurable Obligations Checklist
                if !configuredEvents.isEmpty {
                    Section {
                        ForEach($configuredEvents) { $event in
                            ConfigurableEventRow(event: $event)
                        }
                    } header: {
                        Text("Scadențe & Obligații Implicite")
                    } footer: {
                        Text("Selectează obligațiile dorite și personalizează asigurătorul, data exactă și costul estimat.")
                    }
                }
                
                // Section 5: Dynamic Custom Fields
                Section {
                    DynamicFieldEditorView(fields: $dynamicFields)
                } header: {
                    Text("Atribute Personalizate Suplimentare")
                } footer: {
                    Text("Adaugă oricâte câmpuri specifice ai nevoie (numere de serie, dimensiuni anvelope, conturi bancare).")
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
                    Button("Creează Activ") {
                        saveAsset()
                    }
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                updateCategoryDefaults(for: selectedCategory)
            }
        }
    }
    
    // MARK: - Vehicle Domain Section
    private var vehicleFieldsSection: some View {
        Section("Specificații Vehicul") {
            HStack {
                Text("Număr Înmatriculare")
                Spacer()
                TextField("B-123-ABC", text: $licensePlate)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .font(.system(.body, design: .monospaced, weight: .bold))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Serie Șasiu (VIN)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("17 caractere alfanumerice", text: $vinNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: vinNumber) { _, newValue in
                        if newValue.count > 17 {
                            vinNumber = String(newValue.prefix(17))
                        }
                    }
            }
            
            Picker("Tip Combustibil", selection: $fuelType) {
                ForEach(fuelOptions, id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
            
            HStack {
                Text("An Fabricație")
                Spacer()
                TextField("ex: 2020", text: $manufactureYear)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            
            HStack {
                Text("Capacitate Cilindrică (cm³)")
                Spacer()
                TextField("ex: 1968", text: $engineDisplacement)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            
            HStack {
                Text("Putere Motor (CP)")
                Spacer()
                TextField("ex: 150", text: $enginePower)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
    
    // MARK: - Home Domain Section
    private var homeFieldsSection: some View {
        Section("Specificații Locuință & Utilități") {
            TextField("Adresă completă", text: $fullAddress)
                .font(.system(.body, design: .rounded))
            
            HStack {
                Text("Suprafață Utilă (m²)")
                Spacer()
                TextField("ex: 75", text: $surfaceArea)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            
            HStack {
                Text("An Construcție")
                Spacer()
                TextField("ex: 2012", text: $constructionYear)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Centrală Termică")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Marcă / Model (ex: Bosch Condens 2300)", text: $heatingBoilerModel)
                TextField("Serie Fabricație Centrală", text: $heatingBoilerSerial)
                    .font(.system(.subheadline, design: .monospaced))
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Serii Contoare Utilități")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                    TextField("Serie Contor Gaze", text: $gasMeterSerial)
                        .font(.system(.subheadline, design: .monospaced))
                }
                HStack {
                    Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                    TextField("Serie Contor Curent", text: $electricityMeterSerial)
                        .font(.system(.subheadline, design: .monospaced))
                }
                HStack {
                    Image(systemName: "drop.fill").foregroundStyle(.blue)
                    TextField("Serie Contor Apă", text: $waterMeterSerial)
                        .font(.system(.subheadline, design: .monospaced))
                }
            }
        }
    }
    
    // MARK: - Pet Domain Section
    private var petFieldsSection: some View {
        Section("Specificații Animal de Companie") {
            HStack {
                Text("Specie")
                Spacer()
                TextField("ex: Câine, Pisică", text: $petSpecies)
                    .multilineTextAlignment(.trailing)
            }
            
            HStack {
                Text("Rasă")
                Spacer()
                TextField("ex: Beagle, Birmaneză", text: $petBreed)
                    .multilineTextAlignment(.trailing)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Număr Microchip (15 cifre ISO)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("ex: 642098100123456", text: $petMicrochipNumber)
                    .keyboardType(.numberPad)
                    .font(.system(.body, design: .monospaced))
            }
            
            Toggle("Dată de naștere cunoscută", isOn: $hasPetBirthDate)
            if hasPetBirthDate {
                DatePicker("Data Nașterii", selection: $petBirthDate, displayedComponents: .date)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Cabinet Veterinar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Nume Clinică / Medic", text: $veterinarianClinic)
                TextField("Telefon Contact Clinică", text: $veterinarianPhone)
                    .keyboardType(.phonePad)
            }
        }
    }
    
    // MARK: - Health Domain Section
    private var healthFieldsSection: some View {
        Section("Profil Sănătate") {
            Picker("Grupă Sanguină & Rh", selection: $bloodType) {
                ForEach(bloodTypeOptions, id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Medic de Familie")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Nume Medic de Familie", text: $familyDoctorName)
                TextField("Telefon Cabinet Medic", text: $familyDoctorPhone)
                    .keyboardType(.phonePad)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Contact Urgență (ICE)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Nume Contact", text: $emergencyContactName)
                TextField("Telefon Contact", text: $emergencyContactPhone)
                    .keyboardType(.phonePad)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Alergii sau Afecțiuni Cronice")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("ex: Polen, Penicilină, Arahide", text: $allergiesNotes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }
    
    // MARK: - Category Defaults Setup
    private func updateCategoryDefaults(for category: AssetCategory) {
        let calendar = Calendar.current
        let today = Date()
        
        switch category {
        case .vehicle:
            metricUnit = "km"
            configuredEvents = [
                ConfigurableStarterEvent(
                    title: "Asigurare RCA",
                    provider: RomanianInsuranceCatalog.recommendedInsurers.first?.name ?? "Groupama Asigurări",
                    policyNumber: "",
                    coverageType: "RCA",
                    dueDate: calendar.date(byAdding: .month, value: 6, to: today) ?? today,
                    cadenceDays: 365,
                    estimatedCost: 1150
                ),
                ConfigurableStarterEvent(
                    title: "Inspecție Tehnică Periodică (ITP)",
                    provider: "Stație ITP RAR",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 4, to: today) ?? today,
                    cadenceDays: 365,
                    estimatedCost: 150
                ),
                ConfigurableStarterEvent(
                    title: "Rovinietă Națională",
                    provider: "CNAIR",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 10, to: today) ?? today,
                    cadenceDays: 365,
                    estimatedCost: 140
                ),
                ConfigurableStarterEvent(
                    title: "Revizie Mentenanță (Ulei + Filtre)",
                    provider: "Service Auto",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 8, to: today) ?? today,
                    cadenceDays: 365,
                    cadenceMetricInterval: 15000,
                    estimatedCost: 850
                )
            ]
            
        case .home:
            metricUnit = "none"
            configuredEvents = [
                ConfigurableStarterEvent(
                    title: "Verificare Tehnică Centrală (VTP)",
                    provider: "Tehnician Autorizat ISCIR",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 11, to: today) ?? today,
                    cadenceDays: 730,
                    estimatedCost: 350
                ),
                ConfigurableStarterEvent(
                    title: "Revizie Instalație Gaze",
                    provider: "Operator Autorizat ANRE",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 14, to: today) ?? today,
                    cadenceDays: 730,
                    estimatedCost: 200
                ),
                ConfigurableStarterEvent(
                    title: "Poliță Asigurare Locuință (PAD)",
                    provider: "PAID România",
                    policyNumber: "",
                    coverageType: "PAD Obligatoriu",
                    dueDate: calendar.date(byAdding: .month, value: 5, to: today) ?? today,
                    cadenceDays: 365,
                    estimatedCost: 130
                )
            ]
            
        case .pet:
            metricUnit = "none"
            configuredEvents = [
                ConfigurableStarterEvent(
                    title: "Deparazitare Internă",
                    provider: "Cabinet Veterinar",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 2, to: today) ?? today,
                    cadenceDays: 90,
                    estimatedCost: 50
                ),
                ConfigurableStarterEvent(
                    title: "Vaccin Anual Polivalent + Antirabic",
                    provider: "Cabinet Veterinar",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 7, to: today) ?? today,
                    cadenceDays: 365,
                    estimatedCost: 200
                )
            ]
            
        case .health:
            metricUnit = "none"
            configuredEvents = [
                ConfigurableStarterEvent(
                    title: "Igienizare & Detartraj Stomatologic",
                    provider: "Clinică Stomatologică",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 3, to: today) ?? today,
                    cadenceDays: 180,
                    estimatedCost: 350
                ),
                ConfigurableStarterEvent(
                    title: "Set Anual Analize Sânge (Check-up)",
                    provider: "Laborator Analize",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 6, to: today) ?? today,
                    cadenceDays: 365,
                    estimatedCost: 500
                )
            ]
            
        default:
            metricUnit = "none"
            configuredEvents = []
        }
    }
    
    // MARK: - Save Action
    private func saveAsset() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let metricVal = Double(initialMetricValue.replacingOccurrences(of: ",", with: "."))
        
        let newAsset = Asset(
            name: trimmedName,
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            category: selectedCategory,
            currentMetricValue: metricVal,
            metricUnit: metricUnit == "none" ? nil : metricUnit
        )
        
        // Vehicle Fields
        newAsset.licensePlate = licensePlate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : licensePlate.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.vinNumber = vinNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : vinNumber.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.manufactureYear = Int(manufactureYear)
        newAsset.fuelType = fuelType
        newAsset.engineDisplacementCm3 = Int(engineDisplacement)
        newAsset.enginePowerHp = Int(enginePower)
        
        // Home Fields
        newAsset.fullAddress = fullAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : fullAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.surfaceAreaM2 = Double(surfaceArea.replacingOccurrences(of: ",", with: "."))
        newAsset.constructionYear = Int(constructionYear)
        newAsset.heatingBoilerModel = heatingBoilerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : heatingBoilerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.heatingBoilerSerial = heatingBoilerSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : heatingBoilerSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.gasMeterSerial = gasMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : gasMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.electricityMeterSerial = electricityMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : electricityMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.waterMeterSerial = waterMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : waterMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Pet Fields
        newAsset.petSpecies = petSpecies.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : petSpecies.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.petBreed = petBreed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : petBreed.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.petMicrochipNumber = petMicrochipNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : petMicrochipNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.petBirthDate = hasPetBirthDate ? petBirthDate : nil
        newAsset.veterinarianClinic = veterinarianClinic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : veterinarianClinic.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.veterinarianPhone = veterinarianPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : veterinarianPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Health Fields
        newAsset.bloodType = bloodType
        newAsset.familyDoctorName = familyDoctorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : familyDoctorName.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.familyDoctorPhone = familyDoctorPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : familyDoctorPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.emergencyContactName = emergencyContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : emergencyContactName.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.emergencyContactPhone = emergencyContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : emergencyContactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.allergiesNotes = allergiesNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : allergiesNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        modelContext.insert(newAsset)
        
        // Dynamic Fields
        for field in dynamicFields {
            newAsset.dynamicFields.append(field)
        }
        
        // Selected Initial Events
        for item in configuredEvents where item.isEnabled {
            let ev = LifecycleEvent(
                title: item.title,
                dueDate: item.dueDate,
                cost: item.estimatedCost > 0 ? item.estimatedCost : nil,
                cadenceDays: item.cadenceDays,
                cadenceMetricInterval: item.cadenceMetricInterval,
                provider: item.provider.isEmpty ? nil : item.provider,
                policyOrContractNumber: item.policyNumber.isEmpty ? nil : item.policyNumber,
                coverageType: item.coverageType
            )
            ev.asset = newAsset
            modelContext.insert(ev)
            Task {
                _ = try? await NotificationScheduler.shared.scheduleReminders(for: ev)
            }
        }
        
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
    }
}

// MARK: - Supporting Types & Row Component
public struct ConfigurableStarterEvent: Identifiable {
    public let id = UUID()
    public var isEnabled: Bool = true
    public var title: String
    public var provider: String
    public var policyNumber: String
    public var coverageType: String?
    public var dueDate: Date
    public var cadenceDays: Int?
    public var cadenceMetricInterval: Double?
    public var estimatedCost: Double
}

private struct ConfigurableEventRow: View {
    @Binding var event: ConfigurableStarterEvent
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: $event.isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        
                        if !event.provider.isEmpty {
                            Text(event.provider)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if event.isEnabled {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "slider.horizontal.3")
                            .font(.system(size: 16))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            }
            
            if event.isEnabled && isExpanded {
                VStack(spacing: 8) {
                    Divider()
                    
                    DatePicker("Dată Scadență", selection: $event.dueDate, displayedComponents: .date)
                        .font(.system(.subheadline, design: .rounded))
                    
                    if RomanianInsuranceCatalog.isInsuranceTitle(event.title) {
                        Picker("Furnizor / Asigurător", selection: $event.provider) {
                            ForEach(RomanianInsuranceCatalog.recommendedInsurers) { ins in
                                Text(ins.name).tag(ins.name)
                            }
                        }
                        .font(.system(.subheadline, design: .rounded))
                        
                        TextField("Serie & Număr Poliță (ex: RO/01/...)", text: $event.policyNumber)
                            .font(.system(.subheadline, design: .monospaced))
                            .padding(8)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        TextField("Furnizor (ex: Service, Clinica)", text: $event.provider)
                            .font(.system(.subheadline, design: .rounded))
                            .padding(8)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    
                    HStack {
                        Text("Cost Estimat (RON):")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("Cost", value: $event.estimatedCost, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                            .frame(width: 100)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}
