import SwiftUI
import SwiftData

/// Dedicated sheet for editing an existing asset with tailored fields across all 8 household categories.
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
    @State private var civSeries: String = ""
    @State private var vehicleMake: String = ""
    @State private var vehicleModel: String = ""
    @State private var manufactureYear: String = ""
    @State private var fuelType: String = "Benzină"
    @State private var engineDisplacement: String = ""
    @State private var enginePower: String = ""
    
    // Home State
    @State private var fullAddress: String = ""
    @State private var cadastralNumber: String = ""
    @State private var surfaceArea: String = ""
    @State private var constructionYear: String = ""
    @State private var podCode: String = ""
    @State private var clcCode: String = ""
    @State private var waterClientCode: String = ""
    @State private var meterReadWindowStart: String = "20"
    @State private var meterReadWindowEnd: String = "25"
    @State private var heatingBoilerModel: String = ""
    @State private var heatingBoilerSerial: String = ""
    @State private var gasMeterSerial: String = ""
    @State private var electricityMeterSerial: String = ""
    @State private var waterMeterSerial: String = ""
    
    // Pet State
    @State private var petSpecies: String = "Câine"
    @State private var petBreed: String = ""
    @State private var petMicrochipNumber: String = ""
    @State private var petPassportNumber: String = ""
    @State private var petBirthDate: Date = Date()
    @State private var hasPetBirthDate: Bool = false
    @State private var petWeightKg: String = ""
    @State private var veterinarianClinic: String = ""
    @State private var veterinarianPhone: String = ""
    
    // Health State
    @State private var personName: String = ""
    @State private var personBirthDate: Date = Date()
    @State private var hasPersonBirthDate: Bool = false
    @State private var bloodType: String = "A+"
    @State private var familyDoctorName: String = ""
    @State private var familyDoctorPhone: String = ""
    @State private var emergencyContactName: String = ""
    @State private var emergencyContactPhone: String = ""
    @State private var allergiesNotes: String = ""
    @State private var chronicConditions: String = ""
    
    // Warranties State
    @State private var productBrand: String = ""
    @State private var productModel: String = ""
    @State private var warrantySerial: String = ""
    @State private var warrantyRetailer: String = ""
    @State private var purchaseDate: Date = Date()
    @State private var purchasePriceText: String = ""
    @State private var warrantyMonthsText: String = "24"
    @State private var extendedWarrantyMonthsText: String = "0"
    
    // Subscriptions State
    @State private var subscriptionProvider: String = ""
    @State private var subscriptionCycle: String = "Lunar"
    @State private var subscriptionAmountText: String = ""
    @State private var subscriptionCurrency: String = "RON"
    @State private var subscriptionCardLast4: String = ""
    @State private var subscriptionCancelUrl: String = ""
    @State private var subscriptionEndDate: Date = Date()
    @State private var hasSubscriptionEndDate: Bool = false
    
    // Documents State
    @State private var docSeriesNumber: String = ""
    @State private var docIssuer: String = ""
    @State private var docIssueDate: Date = Date()
    @State private var docExpiryDate: Date = Date()
    
    // Custom / Landlord State
    @State private var landlordTenantName: String = ""
    @State private var landlordTenantPhone: String = ""
    @State private var landlordRentAmount: String = ""
    @State private var landlordLeaseEndDate: Date = Date()
    @State private var hasLandlordLeaseEndDate: Bool = false
    
    private let fuelOptions = ["Benzină", "Motorină", "Hibrid", "Plug-in Hybrid", "Electric", "GPL"]
    private let bloodTypeOptions = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-", "Necunoscut"]
    private let cycleOptions = ["Lunar", "Anual", "Trimestrial", "Săptămânal"]
    private let currencyOptions = ["RON", "EUR", "USD"]
    
    public init(asset: Asset) {
        self.asset = asset
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: Core Identity
                Section("Identificare Activ") {
                    TextField("Denumire (ex: VW Golf, Apartament)", text: $name)
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
                case .warranties:
                    warrantiesSection
                case .subscriptions:
                    subscriptionsSection
                case .documents:
                    documentsSection
                case .custom:
                    customSection
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
                                Text("Valoare curentă contor")
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
            }
            .navigationTitle("Editează Activ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvează") { saveChanges() }
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                populateFields()
            }
        }
    }
    
    // MARK: - Vehicle Section
    private var vehicleSection: some View {
        Section("Specificații Vehicul") {
            TextField("Număr Înmatriculare", text: $licensePlate)
                .textInputAutocapitalization(.characters)
                .font(.system(.body, design: .monospaced))
            
            TextField("Serie Șasiu (VIN)", text: $vinNumber)
                .textInputAutocapitalization(.characters)
                .font(.system(.body, design: .monospaced))
            
            TextField("Serie CIV", text: $civSeries)
                .textInputAutocapitalization(.characters)
                .font(.system(.body, design: .monospaced))
            
            HStack {
                TextField("Marcă", text: $vehicleMake)
                TextField("Model", text: $vehicleModel)
            }
            
            HStack {
                Text("An Fabricație")
                Spacer()
                TextField("2018", text: $manufactureYear)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            
            Picker("Combustibil", selection: $fuelType) {
                ForEach(fuelOptions, id: \.self) { Text($0).tag($0) }
            }
            
            HStack {
                TextField("Cilindree (cm³)", text: $engineDisplacement)
                    .keyboardType(.numberPad)
                TextField("Putere (CP/kW)", text: $enginePower)
                    .keyboardType(.numberPad)
            }
        }
    }
    
    // MARK: - Home Section
    private var homeSection: some View {
        Section("Detalii Locuință & Utilități") {
            TextField("Adresă completă", text: $fullAddress)
            TextField("Număr Cadastral / CF", text: $cadastralNumber)
            
            HStack {
                TextField("Suprafață utilă (m²)", text: $surfaceArea)
                    .keyboardType(.decimalPad)
                TextField("An construcție", text: $constructionYear)
                    .keyboardType(.numberPad)
            }
            
            TextField("POD Energie Electrică", text: $podCode)
                .font(.system(.body, design: .monospaced))
            TextField("CLC Gaze Naturale", text: $clcCode)
                .font(.system(.body, design: .monospaced))
            TextField("Cod Client Apă / Canal", text: $waterClientCode)
            
            HStack {
                Text("Fereastră Autocitire:")
                Spacer()
                Text("Zilele")
                TextField("20", text: $meterReadWindowStart)
                    .keyboardType(.numberPad)
                    .frame(width: 32)
                Text("–")
                TextField("25", text: $meterReadWindowEnd)
                    .keyboardType(.numberPad)
                    .frame(width: 32)
            }
            
            TextField("Model Centrală Termică", text: $heatingBoilerModel)
            TextField("Serie Centrală Termică", text: $heatingBoilerSerial)
            TextField("Serie Contor Gaze", text: $gasMeterSerial)
            TextField("Serie Contor Electricitate", text: $electricityMeterSerial)
            TextField("Serie Apometru", text: $waterMeterSerial)
        }
    }
    
    // MARK: - Pet Section
    private var petSection: some View {
        Section("Date Animal de Companie") {
            TextField("Specie", text: $petSpecies)
            TextField("Rasă", text: $petBreed)
            TextField("Microchip ISO", text: $petMicrochipNumber)
                .keyboardType(.numberPad)
                .font(.system(.body, design: .monospaced))
            TextField("Serie Pașaport European", text: $petPassportNumber)
            
            Toggle("Data nașterii cunoscută", isOn: $hasPetBirthDate)
            if hasPetBirthDate {
                DatePicker("Data Nașterii", selection: $petBirthDate, displayedComponents: .date)
            }
            
            HStack {
                Text("Greutate (kg)")
                Spacer()
                TextField("12.5", text: $petWeightKg)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            
            TextField("Clinică Veterinară", text: $veterinarianClinic)
            TextField("Telefon Medic Veterinar", text: $veterinarianPhone)
                .keyboardType(.phonePad)
        }
    }
    
    // MARK: - Health Section
    private var healthSection: some View {
        Section("Profil Sănătate & Fișă ICE") {
            TextField("Nume & Prenume", text: $personName)
            
            Toggle("Data Nașterii", isOn: $hasPersonBirthDate)
            if hasPersonBirthDate {
                DatePicker("Data Nașterii", selection: $personBirthDate, displayedComponents: .date)
            }
            
            Picker("Grupă Sanguină", selection: $bloodType) {
                ForEach(bloodTypeOptions, id: \.self) { Text($0).tag($0) }
            }
            
            TextField("Alergii", text: $allergiesNotes)
            TextField("Afecțiuni cronice", text: $chronicConditions)
            
            TextField("Medic de Familie", text: $familyDoctorName)
            TextField("Telefon Medic de Familie", text: $familyDoctorPhone)
                .keyboardType(.phonePad)
            
            TextField("Contact de Urgență", text: $emergencyContactName)
            TextField("Telefon Urgență", text: $emergencyContactPhone)
                .keyboardType(.phonePad)
        }
    }
    
    // MARK: - Warranties Section
    private var warrantiesSection: some View {
        Section("Date Produs & Garanție") {
            HStack {
                TextField("Brand", text: $productBrand)
                TextField("Model", text: $productModel)
            }
            
            TextField("Serie / IMEI", text: $warrantySerial)
                .font(.system(.body, design: .monospaced))
            
            TextField("Magazin / Comerciant", text: $warrantyRetailer)
            DatePicker("Data Achiziției", selection: $purchaseDate, displayedComponents: .date)
            
            HStack {
                Text("Preț Achiziție (RON)")
                Spacer()
                TextField("0.00", text: $purchasePriceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }
            
            HStack {
                Text("Garanție Standard (luni)")
                Spacer()
                TextField("24", text: $warrantyMonthsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }
            
            HStack {
                Text("Garanție Extinsă (luni)")
                Spacer()
                TextField("0", text: $extendedWarrantyMonthsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }
        }
    }
    
    // MARK: - Subscriptions Section
    private var subscriptionsSection: some View {
        Section("Detalii Abonament & Plată") {
            TextField("Furnizor / Serviciu", text: $subscriptionProvider)
            
            Picker("Periodicitate Facturare", selection: $subscriptionCycle) {
                ForEach(cycleOptions, id: \.self) { Text($0).tag($0) }
            }
            
            HStack {
                TextField("Cost Recurent", text: $subscriptionAmountText)
                    .keyboardType(.decimalPad)
                
                Picker("Monedă", selection: $subscriptionCurrency) {
                    ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            
            TextField("Card Ultimele 4 Cifre", text: $subscriptionCardLast4)
                .keyboardType(.numberPad)
                .font(.system(.body, design: .monospaced))
            
            TextField("Link Dezabonare (URL)", text: $subscriptionCancelUrl)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            
            Toggle("Contract cu Perioadă Minimă", isOn: $hasSubscriptionEndDate)
            if hasSubscriptionEndDate {
                DatePicker("Expirare Contract", selection: $subscriptionEndDate, displayedComponents: .date)
            }
        }
    }
    
    // MARK: - Documents Section
    private var documentsSection: some View {
        Section("Date Act Oficial") {
            TextField("Serie & Număr", text: $docSeriesNumber)
                .font(.system(.body, design: .monospaced))
            
            TextField("Autoritate Emitentă", text: $docIssuer)
            DatePicker("Data Emiterii", selection: $docIssueDate, displayedComponents: .date)
            DatePicker("Data Expirării", selection: $docExpiryDate, displayedComponents: .date)
        }
    }
    
    // MARK: - Custom Section
    private var customSection: some View {
        Section("Detalii Închiriere & Chiriaș") {
            TextField("Nume Chiriaș", text: $landlordTenantName)
            TextField("Telefon Chiriaș", text: $landlordTenantPhone)
                .keyboardType(.phonePad)
            
            HStack {
                Text("Chirie Lunară")
                Spacer()
                TextField("0.00", text: $landlordRentAmount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }
            
            Toggle("Contract cu Dată Fixă", isOn: $hasLandlordLeaseEndDate)
            if hasLandlordLeaseEndDate {
                DatePicker("Expirare Contract", selection: $landlordLeaseEndDate, displayedComponents: .date)
            }
        }
    }
    
    // MARK: - Populate Fields
    private func populateFields() {
        name = asset.name
        subtitle = asset.subtitle ?? ""
        metricUnit = asset.metricUnit ?? "km"
        if let val = asset.currentMetricValue {
            currentMetricValue = val.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", val) : String(format: "%.2f", val)
        }
        
        // Vehicle
        licensePlate = asset.licensePlate ?? ""
        vinNumber = asset.vin ?? asset.vinNumber ?? ""
        civSeries = asset.civSeries ?? ""
        vehicleMake = asset.make ?? ""
        vehicleModel = asset.modelName ?? ""
        if let year = asset.manufactureYear { manufactureYear = "\(year)" }
        fuelType = asset.fuelType ?? "Benzină"
        if let disp = asset.engineDisplacementCc ?? asset.engineDisplacementCm3 { engineDisplacement = "\(disp)" }
        if let pwr = asset.enginePowerKw ?? asset.enginePowerHp { enginePower = "\(pwr)" }
        
        // Home
        fullAddress = asset.address ?? asset.fullAddress ?? ""
        cadastralNumber = asset.cadastralNumber ?? ""
        if let s = asset.surfaceAreaSqm ?? asset.surfaceAreaM2 { surfaceArea = "\(s)" }
        if let cy = asset.constructionYear { constructionYear = "\(cy)" }
        podCode = asset.podCode ?? ""
        clcCode = asset.clcCode ?? ""
        waterClientCode = asset.waterClientCode ?? ""
        if let s = asset.meterReadWindowStartDay { meterReadWindowStart = "\(s)" }
        if let e = asset.meterReadWindowEndDay { meterReadWindowEnd = "\(e)" }
        heatingBoilerModel = asset.heatingBoilerModel ?? ""
        heatingBoilerSerial = asset.heatingBoilerSerial ?? ""
        gasMeterSerial = asset.gasMeterSerial ?? ""
        electricityMeterSerial = asset.electricityMeterSerial ?? ""
        waterMeterSerial = asset.waterMeterSerial ?? ""
        
        // Pet
        petSpecies = asset.petSpecies ?? "Câine"
        petBreed = asset.petBreed ?? ""
        petMicrochipNumber = asset.microchipNumber ?? asset.petMicrochipNumber ?? ""
        petPassportNumber = asset.petPassportNumber ?? ""
        if let bDate = asset.birthDate ?? asset.petBirthDate {
            petBirthDate = bDate
            hasPetBirthDate = true
        }
        if let w = asset.weightKg { petWeightKg = "\(w)" }
        veterinarianClinic = asset.veterinarianClinic ?? ""
        veterinarianPhone = asset.veterinarianPhone ?? ""
        
        // Health
        personName = asset.personName ?? ""
        if let bDate = asset.birthDate {
            personBirthDate = bDate
            hasPersonBirthDate = true
        }
        bloodType = asset.bloodType ?? "A+"
        familyDoctorName = asset.familyDoctorName ?? ""
        familyDoctorPhone = asset.familyDoctorPhone ?? ""
        emergencyContactName = asset.emergencyContactName ?? ""
        emergencyContactPhone = asset.emergencyContactPhone ?? ""
        allergiesNotes = asset.allergies ?? asset.allergiesNotes ?? ""
        chronicConditions = asset.chronicConditions ?? ""
        
        // Warranties
        productBrand = asset.make ?? ""
        productModel = asset.modelName ?? ""
        warrantySerial = asset.serialOrImei ?? ""
        warrantyRetailer = asset.retailerOrIssuer ?? ""
        if let pd = asset.purchaseOrIssueDate { purchaseDate = pd }
        if let price = asset.purchasePrice { purchasePriceText = "\(price)" }
        if let wm = asset.warrantyMonths { warrantyMonthsText = "\(wm)" }
        if let ewm = asset.extendedWarrantyMonths { extendedWarrantyMonthsText = "\(ewm)" }
        
        // Subscriptions
        subscriptionProvider = asset.providerName ?? ""
        subscriptionCycle = asset.billingCycle ?? "Lunar"
        if let amt = asset.recurringAmount { subscriptionAmountText = "\(amt)" }
        subscriptionCurrency = asset.currencyCode.isEmpty ? "RON" : asset.currencyCode
        subscriptionCardLast4 = asset.paymentCardLast4 ?? ""
        subscriptionCancelUrl = asset.cancellationUrl ?? ""
        if let ed = asset.contractEndDate {
            subscriptionEndDate = ed
            hasSubscriptionEndDate = true
        }
        
        // Documents
        docSeriesNumber = asset.serialOrImei ?? ""
        docIssuer = asset.retailerOrIssuer ?? ""
        if let pd = asset.purchaseOrIssueDate { docIssueDate = pd }
        if let ed = asset.contractEndDate { docExpiryDate = ed }
        
        // Custom
        landlordTenantName = asset.primaryContactName ?? ""
        landlordTenantPhone = asset.primaryContactPhone ?? ""
        if let rent = asset.recurringAmount { landlordRentAmount = "\(rent)" }
        if let led = asset.contractEndDate {
            landlordLeaseEndDate = led
            hasLandlordLeaseEndDate = true
        }
    }
    
    // MARK: - Save Changes
    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        asset.name = trimmedName
        asset.subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Metric
        if metricUnit != "none" {
            asset.metricUnit = metricUnit
            let trimmedMetric = currentMetricValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedMetric.isEmpty, let dbl = Double(trimmedMetric.replacingOccurrences(of: ",", with: ".")) {
                asset.currentMetricValue = max(0, dbl)
            } else if trimmedMetric.isEmpty {
                asset.currentMetricValue = nil
            }
        } else {
            asset.metricUnit = nil
            asset.currentMetricValue = nil
        }
        
        // Vehicle
        asset.licensePlate = licensePlate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : licensePlate.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        asset.vin = vinNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : vinNumber.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        asset.civSeries = civSeries.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : civSeries.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        asset.make = vehicleMake.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : vehicleMake.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.modelName = vehicleModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : vehicleModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if let year = Int(manufactureYear) { asset.manufactureYear = max(1900, year) } else { asset.manufactureYear = nil }
        asset.fuelType = fuelType
        if let disp = Int(engineDisplacement) { asset.engineDisplacementCc = max(0, disp) } else { asset.engineDisplacementCc = nil }
        if let pwr = Int(enginePower) { asset.enginePowerKw = max(0, pwr) } else { asset.enginePowerKw = nil }
        
        // Home
        asset.address = fullAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : fullAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.cadastralNumber = cadastralNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : cadastralNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if let area = Double(surfaceArea.replacingOccurrences(of: ",", with: ".")) { asset.surfaceAreaSqm = max(0, area) } else { asset.surfaceAreaSqm = nil }
        if let cy = Int(constructionYear) { asset.constructionYear = max(1800, cy) } else { asset.constructionYear = nil }
        asset.podCode = podCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : podCode.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.clcCode = clcCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : clcCode.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.waterClientCode = waterClientCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : waterClientCode.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.meterReadWindowStartDay = Int(meterReadWindowStart)
        asset.meterReadWindowEndDay = Int(meterReadWindowEnd)
        asset.heatingBoilerModel = heatingBoilerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : heatingBoilerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.heatingBoilerSerial = heatingBoilerSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : heatingBoilerSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.gasMeterSerial = gasMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : gasMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.electricityMeterSerial = electricityMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : electricityMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.waterMeterSerial = waterMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : waterMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Pet
        asset.petSpecies = petSpecies.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : petSpecies.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.petBreed = petBreed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : petBreed.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.microchipNumber = petMicrochipNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : petMicrochipNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.petPassportNumber = petPassportNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : petPassportNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.birthDate = hasPetBirthDate ? petBirthDate : nil
        if let w = Double(petWeightKg.replacingOccurrences(of: ",", with: ".")) { asset.weightKg = max(0, w) } else { asset.weightKg = nil }
        asset.veterinarianClinic = veterinarianClinic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : veterinarianClinic.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.veterinarianPhone = veterinarianPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : veterinarianPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Health
        asset.personName = personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : personName.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasPersonBirthDate { asset.birthDate = personBirthDate }
        asset.bloodType = bloodType
        asset.familyDoctorName = familyDoctorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : familyDoctorName.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.familyDoctorPhone = familyDoctorPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : familyDoctorPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.emergencyContactName = emergencyContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : emergencyContactName.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.emergencyContactPhone = emergencyContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : emergencyContactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.allergies = allergiesNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : allergiesNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.chronicConditions = chronicConditions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : chronicConditions.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Warranties
        if asset.category == .warranties {
            asset.make = productBrand.isEmpty ? nil : productBrand
            asset.modelName = productModel.isEmpty ? nil : productModel
            asset.serialOrImei = warrantySerial.isEmpty ? nil : warrantySerial
            asset.retailerOrIssuer = warrantyRetailer.isEmpty ? nil : warrantyRetailer
            asset.purchaseOrIssueDate = purchaseDate
            asset.purchasePrice = Double(purchasePriceText.replacingOccurrences(of: ",", with: "."))
            asset.warrantyMonths = Int(warrantyMonthsText)
            asset.extendedWarrantyMonths = Int(extendedWarrantyMonthsText)
        }
        
        // Subscriptions
        if asset.category == .subscriptions {
            asset.providerName = subscriptionProvider.isEmpty ? nil : subscriptionProvider
            asset.billingCycle = subscriptionCycle
            asset.recurringAmount = Double(subscriptionAmountText.replacingOccurrences(of: ",", with: "."))
            asset.currencyCode = subscriptionCurrency
            asset.paymentCardLast4 = subscriptionCardLast4.isEmpty ? nil : subscriptionCardLast4
            asset.cancellationUrl = subscriptionCancelUrl.isEmpty ? nil : subscriptionCancelUrl
            asset.contractEndDate = hasSubscriptionEndDate ? subscriptionEndDate : nil
        }
        
        // Documents
        if asset.category == .documents {
            asset.serialOrImei = docSeriesNumber.isEmpty ? nil : docSeriesNumber
            asset.retailerOrIssuer = docIssuer.isEmpty ? nil : docIssuer
            asset.purchaseOrIssueDate = docIssueDate
            asset.contractEndDate = docExpiryDate
        }
        
        // Custom
        if asset.category == .custom {
            if !landlordTenantName.isEmpty {
                asset.primaryContactName = landlordTenantName
                asset.primaryContactRole = "Chiriaș"
            }
            if !landlordTenantPhone.isEmpty { asset.primaryContactPhone = landlordTenantPhone }
            if let rent = Double(landlordRentAmount.replacingOccurrences(of: ",", with: ".")), rent > 0 {
                asset.recurringAmount = rent
            }
            if hasLandlordLeaseEndDate { asset.contractEndDate = landlordLeaseEndDate }
        }
        
        asset.updatedAt = Date()
        
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
    }
}
