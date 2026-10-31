import SwiftUI
import SwiftData

/// Dedicated sheet for editing an existing asset with tailored fields per category.
/// Follows Apple Craftsmanship & Polish Standard with continuous squircle cards,
/// responsive form fields, and haptic feedback.
public struct EditAssetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable public var asset: Asset
    
    // Core Identity State
    @State private var name: String = ""
    @State private var subtitle: String = ""
    @State private var currentMetricValue: String = ""
    @State private var metricUnit: String = "km"
    
    // Vehicle State
    @State private var licensePlate: String = ""
    @State private var vinNumber: String = ""
    @State private var manufactureYear: String = ""
    @State private var fuelType: String = "Benzină"
    @State private var engineDisplacement: String = ""
    @State private var enginePower: String = ""
    
    // Home State
    @State private var fullAddress: String = ""
    @State private var surfaceArea: String = ""
    @State private var constructionYear: String = ""
    @State private var heatingBoilerModel: String = ""
    @State private var heatingBoilerSerial: String = ""
    @State private var gasMeterSerial: String = ""
    @State private var electricityMeterSerial: String = ""
    @State private var waterMeterSerial: String = ""
    
    // Pet State
    @State private var petSpecies: String = "Câine"
    @State private var petBreed: String = ""
    @State private var petMicrochipNumber: String = ""
    @State private var petBirthDate: Date = Date()
    @State private var hasPetBirthDate: Bool = false
    @State private var veterinarianClinic: String = ""
    @State private var veterinarianPhone: String = ""
    
    // Health State
    @State private var bloodType: String = "A+"
    @State private var familyDoctorName: String = ""
    @State private var familyDoctorPhone: String = ""
    @State private var emergencyContactName: String = ""
    @State private var emergencyContactPhone: String = ""
    @State private var allergiesNotes: String = ""
    
    private let fuelOptions = ["Benzină", "Motorină", "Hibrid", "Plug-in Hybrid", "Electric", "GPL"]
    private let bloodTypeOptions = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-", "Necunoscut"]
    
    public init(asset: Asset) {
        self.asset = asset
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: Core Identity
                Section("Identificare Activ") {
                    TextField("Denumire (ex: VW Golf, Garsonieră)", text: $name)
                        .font(.system(.body, design: .rounded))
                    
                    TextField("Subtitlu / Notă secundară", text: $subtitle)
                        .font(.system(.body, design: .rounded))
                    
                    HStack {
                        Text("Categorie")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Label(asset.category.title, systemImage: asset.category.systemIcon)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(asset.accentColor)
                    }
                }
                
                // Section 2: Category-Specific Fields
                switch asset.category {
                case .vehicle:
                    vehicleSection
                case .home:
                    homeSection
                case .pet:
                    petSection
                case .health:
                    healthSection
                default:
                    EmptyView()
                }
                
                // Section 3: Telemetry (if applicable)
                if asset.category == .vehicle || asset.metricUnit != nil {
                    Section("Contor & Telemetrie") {
                        Picker("Unitate de măsură", selection: $metricUnit) {
                            Text("Kilometri (km)").tag("km")
                            Text("Ore de funcționare (h)").tag("hours")
                            Text("Cicluri").tag("cycles")
                            Text("Fără contor").tag("none")
                        }
                        
                        if metricUnit != "none" {
                            HStack {
                                Text("Valoare curentă")
                                Spacer()
                                TextField("0", text: $currentMetricValue)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.system(.body, design: .monospaced))
                                Text(metricUnit)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // Section 4: Unlimited Dynamic Custom Fields
                Section {
                    DynamicFieldEditorView(asset: asset)
                } header: {
                    Text("Câmpuri & Atribute Suplimentare")
                } footer: {
                    Text("Poți adăuga un număr nelimitat de parametri personalizați (numere de contract, parole, cote sau dimensiuni).")
                }
            }
            .navigationTitle("Editare \(asset.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvează") {
                        saveChanges()
                    }
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                loadInitialState()
            }
        }
    }
    
    // MARK: - Vehicle Section
    private var vehicleSection: some View {
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
                TextField("ex: 2019", text: $manufactureYear)
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
    
    // MARK: - Home Section
    private var homeSection: some View {
        Section("Detalii Locuință & Utilități") {
            TextField("Adresă completă (Str., Nr., Bloc, Ap., Oraș)", text: $fullAddress)
                .font(.system(.body, design: .rounded))
            
            HStack {
                Text("Suprafață Utilă (m²)")
                Spacer()
                TextField("ex: 65", text: $surfaceArea)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            
            HStack {
                Text("An Construcție")
                Spacer()
                TextField("ex: 2008", text: $constructionYear)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Centrală Termică")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Marcă / Model (ex: Viessmann Vitodens 100)", text: $heatingBoilerModel)
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
    
    // MARK: - Pet Section
    private var petSection: some View {
        Section("Date Animal de Companie") {
            HStack {
                Text("Specie")
                Spacer()
                TextField("ex: Câine, Pisică", text: $petSpecies)
                    .multilineTextAlignment(.trailing)
            }
            
            HStack {
                Text("Rasă")
                Spacer()
                TextField("ex: Labrador Retriever", text: $petBreed)
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
                Text("Cabinet Veterinar / Medic")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Nume Clinică / Medic", text: $veterinarianClinic)
                TextField("Telefon Urgență Veterinar", text: $veterinarianPhone)
                    .keyboardType(.phonePad)
            }
        }
    }
    
    // MARK: - Health Section
    private var healthSection: some View {
        Section("Profil Medical & Urgențe") {
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
                Text("Contact în Caz de Urgență (ICE)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Nume Persoană Contact", text: $emergencyContactName)
                TextField("Telefon Urgență", text: $emergencyContactPhone)
                    .keyboardType(.phonePad)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Alergii & Boli Cronice")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("ex: Penicilină, Polen, Diabet", text: $allergiesNotes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }
    
    // MARK: - State Management
    private func loadInitialState() {
        name = asset.name
        subtitle = asset.subtitle ?? ""
        metricUnit = asset.metricUnit ?? (asset.category == .vehicle ? "km" : "none")
        if let val = asset.currentMetricValue {
            currentMetricValue = "\(Int(val))"
        }
        
        // Vehicle
        licensePlate = asset.licensePlate ?? ""
        vinNumber = asset.vinNumber ?? ""
        if let year = asset.manufactureYear {
            manufactureYear = "\(year)"
        }
        fuelType = asset.fuelType ?? "Benzină"
        if let disp = asset.engineDisplacementCm3 {
            engineDisplacement = "\(disp)"
        }
        if let pwr = asset.enginePowerHp {
            enginePower = "\(pwr)"
        }
        
        // Home
        fullAddress = asset.fullAddress ?? ""
        if let s = asset.surfaceAreaM2 {
            surfaceArea = "\(s)"
        }
        if let cy = asset.constructionYear {
            constructionYear = "\(cy)"
        }
        heatingBoilerModel = asset.heatingBoilerModel ?? ""
        heatingBoilerSerial = asset.heatingBoilerSerial ?? ""
        gasMeterSerial = asset.gasMeterSerial ?? ""
        electricityMeterSerial = asset.electricityMeterSerial ?? ""
        waterMeterSerial = asset.waterMeterSerial ?? ""
        
        // Pet
        petSpecies = asset.petSpecies ?? "Câine"
        petBreed = asset.petBreed ?? ""
        petMicrochipNumber = asset.petMicrochipNumber ?? ""
        if let bDate = asset.petBirthDate {
            petBirthDate = bDate
            hasPetBirthDate = true
        }
        veterinarianClinic = asset.veterinarianClinic ?? ""
        veterinarianPhone = asset.veterinarianPhone ?? ""
        
        // Health
        bloodType = asset.bloodType ?? "A+"
        familyDoctorName = asset.familyDoctorName ?? ""
        familyDoctorPhone = asset.familyDoctorPhone ?? ""
        emergencyContactName = asset.emergencyContactName ?? ""
        emergencyContactPhone = asset.emergencyContactPhone ?? ""
        allergiesNotes = asset.allergiesNotes ?? ""
    }
    
    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        asset.name = trimmedName
        asset.subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Metric
        if metricUnit != "none" {
            asset.metricUnit = metricUnit
            if let dbl = Double(currentMetricValue.replacingOccurrences(of: ",", with: ".")) {
                asset.currentMetricValue = dbl
            }
        } else {
            asset.metricUnit = nil
            asset.currentMetricValue = nil
        }
        
        // Vehicle
        asset.licensePlate = licensePlate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : licensePlate.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        asset.vinNumber = vinNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : vinNumber.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        asset.manufactureYear = Int(manufactureYear)
        asset.fuelType = fuelType
        asset.engineDisplacementCm3 = Int(engineDisplacement)
        asset.enginePowerHp = Int(enginePower)
        
        // Home
        asset.fullAddress = fullAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : fullAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.surfaceAreaM2 = Double(surfaceArea.replacingOccurrences(of: ",", with: "."))
        asset.constructionYear = Int(constructionYear)
        asset.heatingBoilerModel = heatingBoilerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : heatingBoilerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.heatingBoilerSerial = heatingBoilerSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : heatingBoilerSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.gasMeterSerial = gasMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : gasMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.electricityMeterSerial = electricityMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : electricityMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.waterMeterSerial = waterMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : waterMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Pet
        asset.petSpecies = petSpecies.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : petSpecies.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.petBreed = petBreed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : petBreed.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.petMicrochipNumber = petMicrochipNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : petMicrochipNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.petBirthDate = hasPetBirthDate ? petBirthDate : nil
        asset.veterinarianClinic = veterinarianClinic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : veterinarianClinic.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.veterinarianPhone = veterinarianPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : veterinarianPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Health
        asset.bloodType = bloodType
        asset.familyDoctorName = familyDoctorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : familyDoctorName.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.familyDoctorPhone = familyDoctorPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : familyDoctorPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.emergencyContactName = emergencyContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : emergencyContactName.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.emergencyContactPhone = emergencyContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : emergencyContactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.allergiesNotes = allergiesNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : allergiesNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        asset.updatedAt = Date()
        
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
    }
}
