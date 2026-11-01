import SwiftUI
import SwiftData

/// Comprehensive creation wizard for new assets tailored across all 8 household categories.
/// Follows Apple Craftsmanship & Polish Standard with category-specific schemas,
/// interactive suggested obligations with real Romanian providers, and unlimited dynamic fields.
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
    @State private var civSeries: String = ""
    @State private var vehicleMake: String = ""
    @State private var vehicleModel: String = ""
    @State private var manufactureYear: String = ""
    @State private var fuelType: String = "Benzină"
    @State private var engineDisplacement: String = ""
    @State private var enginePower: String = ""
    
    // Home Domain Fields
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
    
    // Pet Domain Fields
    @State private var petSpecies: String = "Câine"
    @State private var petBreed: String = ""
    @State private var petMicrochipNumber: String = ""
    @State private var petPassportNumber: String = ""
    @State private var petBirthDate: Date = Date()
    @State private var hasPetBirthDate: Bool = false
    @State private var petWeightKg: String = ""
    @State private var veterinarianClinic: String = ""
    @State private var veterinarianPhone: String = ""
    
    // Health Domain Fields
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
    
    // Warranties & Goods Fields
    @State private var productBrand: String = ""
    @State private var productModel: String = ""
    @State private var warrantySerial: String = ""
    @State private var warrantyRetailer: String = "eMAG"
    @State private var purchaseDate: Date = Date()
    @State private var purchasePriceText: String = ""
    @State private var warrantyMonthsText: String = "24"
    @State private var extendedWarrantyMonthsText: String = "0"
    
    // Subscriptions Fields
    @State private var subscriptionProvider: String = ""
    @State private var subscriptionCycle: String = "Lunar"
    @State private var subscriptionAmountText: String = ""
    @State private var subscriptionCurrency: String = "RON"
    @State private var subscriptionCardLast4: String = ""
    @State private var subscriptionCancelUrl: String = ""
    @State private var subscriptionEndDate: Date = Calendar.current.date(byAdding: .year, value: 2, to: Date()) ?? Date()
    @State private var hasSubscriptionEndDate: Bool = false
    
    // Documents Fields
    @State private var docSeriesNumber: String = ""
    @State private var docIssuer: String = "SPCLEP"
    @State private var docIssueDate: Date = Date()
    @State private var docExpiryDate: Date = Calendar.current.date(byAdding: .year, value: 10, to: Date()) ?? Date()
    
    // Custom / Landlord Fields
    @State private var landlordTenantName: String = ""
    @State private var landlordTenantPhone: String = ""
    @State private var landlordRentAmount: String = ""
    @State private var landlordLeaseEndDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var hasLandlordLeaseEndDate: Bool = false
    
    // Dynamic Fields for Custom Specifications
    @State private var dynamicFields: [DynamicField] = []
    
    // Configurable Initial Events Checklist
    @State private var configuredEvents: [ConfigurableStarterEvent] = []
    
    private let fuelOptions = ["Benzină", "Motorină", "Hibrid", "Plug-in Hybrid", "Electric", "GPL"]
    private let bloodTypeOptions = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-", "Necunoscut"]
    private let cycleOptions = ["Lunar", "Anual", "Trimestrial", "Săptămânal"]
    private let currencyOptions = ["RON", "EUR", "USD"]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: Core Information
                Section("Informații de Bază") {
                    TextField("Denumire (ex: VW Golf, Apartament Pipera, Netflix)", text: $name)
                        .font(.system(.body, design: .rounded))
                    
                    TextField("Subtitlu / Notă secundară", text: $subtitle)
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
                case .warranties:
                    warrantiesFieldsSection
                case .subscriptions:
                    subscriptionsFieldsSection
                case .documents:
                    documentsFieldsSection
                case .custom:
                    customFieldsSection
                }
                
                // Section 3: Telemetry & Odometer (if vehicle, custom, etc.)
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
                        Text("Selectează obligațiile dorite și personalizează asigurătorul, data exactă și costul estimat conform standardelor legale românești.")
                    }
                }
                
                // Section 5: Dynamic Custom Fields
                Section {
                    DynamicFieldEditorView(fields: $dynamicFields)
                } header: {
                    Text("Specificații & Câmpuri Suplimentare")
                } footer: {
                    Text("Poți adăuga un număr nelimitat de atribute (numere de serie, cote, comutatoare, link-uri sau telefoane).")
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
                    Button("Creează") {
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
    
    // MARK: - Vehicle Fields
    private var vehicleFieldsSection: some View {
        Section("Specificații Vehicul") {
            HStack {
                TextField("Număr Înmatriculare (ex: B-123-ABC)", text: $licensePlate)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
            }
            
            TextField("Serie Șasiu / VIN (17 caractere)", text: $vinNumber)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
            
            TextField("Serie CIV (Carte Identitate Vehicul)", text: $civSeries)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
            
            HStack {
                TextField("Marcă (ex: Volkswagen)", text: $vehicleMake)
                TextField("Model (ex: Golf 7)", text: $vehicleModel)
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
    
    // MARK: - Home Fields
    private var homeFieldsSection: some View {
        Section("Detalii Locuință & Utilități") {
            TextField("Adresă completă", text: $fullAddress)
            TextField("Număr Cadastral / CF", text: $cadastralNumber)
            
            HStack {
                TextField("Suprafață utilă (m²)", text: $surfaceArea)
                    .keyboardType(.decimalPad)
                TextField("An construcție", text: $constructionYear)
                    .keyboardType(.numberPad)
            }
            
            TextField("POD Energie Electrică (ex: RO001E...)", text: $podCode)
                .font(.system(.body, design: .monospaced))
            TextField("CLC Gaze Naturale (ex: DEG...)", text: $clcCode)
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
    
    // MARK: - Pet Fields
    private var petFieldsSection: some View {
        Section("Date Animal de Companie") {
            TextField("Specie (ex: Câine, Pisică)", text: $petSpecies)
            TextField("Rasă (ex: Golden Retriever)", text: $petBreed)
            TextField("Microchip ISO (15 cifre)", text: $petMicrochipNumber)
                .keyboardType(.numberPad)
                .font(.system(.body, design: .monospaced))
            TextField("Serie Pașaport European", text: $petPassportNumber)
            
            Toggle("Cunosc data nașterii", isOn: $hasPetBirthDate)
            if hasPetBirthDate {
                DatePicker("Data Nașterii", selection: $petBirthDate, displayedComponents: .date)
            }
            
            HStack {
                Text("Greutate Curentă (kg)")
                Spacer()
                TextField("Ex: 14.5", text: $petWeightKg)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            
            TextField("Clinică / Cabinet Veterinar", text: $veterinarianClinic)
            TextField("Telefon Medic Veterinar", text: $veterinarianPhone)
                .keyboardType(.phonePad)
        }
    }
    
    // MARK: - Health Fields
    private var healthFieldsSection: some View {
        Section("Profil Sănătate & Fișă ICE") {
            TextField("Nume & Prenume Membru", text: $personName)
            
            Toggle("Dată Naștere", isOn: $hasPersonBirthDate)
            if hasPersonBirthDate {
                DatePicker("Data Nașterii", selection: $personBirthDate, displayedComponents: .date)
            }
            
            Picker("Grupă Sanguină & Rh", selection: $bloodType) {
                ForEach(bloodTypeOptions, id: \.self) { Text($0).tag($0) }
            }
            
            TextField("Alergii medicamentoase / alimentare", text: $allergiesNotes)
            TextField("Afecțiuni cronice / tratamente", text: $chronicConditions)
            
            TextField("Medic de Familie", text: $familyDoctorName)
            TextField("Telefon Medic de Familie", text: $familyDoctorPhone)
                .keyboardType(.phonePad)
            
            TextField("Contact de Urgență (ICE)", text: $emergencyContactName)
            TextField("Telefon Contact Urgență", text: $emergencyContactPhone)
                .keyboardType(.phonePad)
        }
    }
    
    // MARK: - Warranties Fields
    private var warrantiesFieldsSection: some View {
        Section("Date Produs & Garanție") {
            HStack {
                TextField("Brand (ex: Apple, Bosch)", text: $productBrand)
                TextField("Model (ex: MacBook Pro)", text: $productModel)
            }
            
            TextField("Serie Produs / IMEI", text: $warrantySerial)
                .font(.system(.body, design: .monospaced))
            
            TextField("Comerciant / Magazin (ex: eMAG, Altex)", text: $warrantyRetailer)
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
                Text("Garanție Extinsă / Extra (luni)")
                Spacer()
                TextField("0", text: $extendedWarrantyMonthsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }
        }
    }
    
    // MARK: - Subscriptions Fields
    private var subscriptionsFieldsSection: some View {
        Section("Detalii Abonament & Plată") {
            TextField("Furnizor / Serviciu (ex: Netflix, Digi, Spotify)", text: $subscriptionProvider)
            
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
            
            TextField("Ultimele 4 cifre ale cardului (ex: 1234)", text: $subscriptionCardLast4)
                .keyboardType(.numberPad)
                .font(.system(.body, design: .monospaced))
            
            TextField("Link portal dezabonare (URL)", text: $subscriptionCancelUrl)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            
            Toggle("Perioadă contractuală minimă (ex: 24 luni)", isOn: $hasSubscriptionEndDate)
            if hasSubscriptionEndDate {
                DatePicker("Expirare Contract", selection: $subscriptionEndDate, displayedComponents: .date)
            }
        }
    }
    
    // MARK: - Documents Fields
    private var documentsFieldsSection: some View {
        Section("Date Act Oficial") {
            TextField("Serie & Număr (ex: DP 123456)", text: $docSeriesNumber)
                .font(.system(.body, design: .monospaced))
            
            TextField("Autoritate Emitentă (ex: SPCLEP, DRPCIV)", text: $docIssuer)
            DatePicker("Data Emiterii", selection: $docIssueDate, displayedComponents: .date)
            DatePicker("Data Expirării", selection: $docExpiryDate, displayedComponents: .date)
        }
    }
    
    // MARK: - Custom Fields
    private var customFieldsSection: some View {
        Section("Detalii Proprietar & Închiriere") {
            TextField("Nume Chiriaș / Beneficiar", text: $landlordTenantName)
            TextField("Telefon Chiriaș", text: $landlordTenantPhone)
                .keyboardType(.phonePad)
            
            HStack {
                Text("Chirie Lunară (RON/EUR)")
                Spacer()
                TextField("0.00", text: $landlordRentAmount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }
            
            Toggle("Contract Înregistrat cu Termen", isOn: $hasLandlordLeaseEndDate)
            if hasLandlordLeaseEndDate {
                DatePicker("Expirare Contract Închiriere", selection: $landlordLeaseEndDate, displayedComponents: .date)
            }
        }
    }
    
    // MARK: - Category Defaults & Suggested Obligations Engine
    private func updateCategoryDefaults(for category: AssetCategory) {
        let calendar = Calendar.current
        let today = Date()
        
        switch category {
        case .vehicle:
            metricUnit = "km"
            configuredEvents = [
                ConfigurableStarterEvent(
                    title: "Asigurare Obligatorie RCA",
                    provider: "Groupama Asigurări",
                    policyNumber: "",
                    coverageType: "RCA",
                    dueDate: calendar.date(byAdding: .month, value: 6, to: today) ?? today,
                    cadenceDays: 365,
                    estimatedCost: 1100
                ),
                ConfigurableStarterEvent(
                    title: "Inspecție Tehnică Periodică (ITP)",
                    provider: "Stație ITP Autorizată RAR",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 8, to: today) ?? today,
                    cadenceDays: 730,
                    estimatedCost: 180
                ),
                ConfigurableStarterEvent(
                    title: "Rovinietă Națională (CNAIR)",
                    provider: "CNAIR",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 4, to: today) ?? today,
                    cadenceDays: 365,
                    estimatedCost: 140
                ),
                ConfigurableStarterEvent(
                    title: "Impozit Auto (Primărie)",
                    provider: "Direcția Taxe și Impozite Locale",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 3, to: today) ?? today,
                    cadenceDays: 365,
                    estimatedCost: 220
                )
            ]
            
        case .home:
            metricUnit = "none"
            configuredEvents = [
                ConfigurableStarterEvent(
                    title: "Verificare Tehnică Centrală (VTP ISCIR)",
                    provider: "Operator Autorizat ISCIR",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 12, to: today) ?? today,
                    cadenceDays: 730,
                    estimatedCost: 350
                ),
                ConfigurableStarterEvent(
                    title: "Verificare Tehnică Instalație Gaze (VIG ANRE)",
                    provider: "Firmă Autorizată ANRE",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 14, to: today) ?? today,
                    cadenceDays: 730,
                    estimatedCost: 250
                ),
                ConfigurableStarterEvent(
                    title: "Poliță Asigurare Locuință Obligatorie (PAD)",
                    provider: "PAID România",
                    policyNumber: "",
                    coverageType: "PAD Obligatoriu",
                    dueDate: calendar.date(byAdding: .month, value: 5, to: today) ?? today,
                    cadenceDays: 365,
                    estimatedCost: 130
                ),
                ConfigurableStarterEvent(
                    title: "Impozit Clădire & Teren (Primărie)",
                    provider: "Direcția Venituri Buget Local",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 3, to: today) ?? today,
                    cadenceDays: 365,
                    estimatedCost: 280
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
                    title: "Deparazitare Externă (Pipetă / Comprimat)",
                    provider: "Cabinet Veterinar",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 1, to: today) ?? today,
                    cadenceDays: 30,
                    estimatedCost: 65
                ),
                ConfigurableStarterEvent(
                    title: "Vaccin Anual Polivalent + Antirabic",
                    provider: "Cabinet Veterinar",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 7, to: today) ?? today,
                    cadenceDays: 365,
                    estimatedCost: 220
                )
            ]
            
        case .health:
            metricUnit = "none"
            configuredEvents = [
                ConfigurableStarterEvent(
                    title: "Igienizare & Detartraj Stomatologic (6 luni)",
                    provider: "Clinică Stomatologică",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 3, to: today) ?? today,
                    cadenceDays: 180,
                    estimatedCost: 350
                ),
                ConfigurableStarterEvent(
                    title: "Set Anual Analize Sânge (Check-up CNAS)",
                    provider: "Laborator Analize Medicale",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 6, to: today) ?? today,
                    cadenceDays: 365,
                    estimatedCost: 450
                ),
                ConfigurableStarterEvent(
                    title: "Control Oftalmologic de Rutină",
                    provider: "Cabinet Oftalmologie",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 9, to: today) ?? today,
                    cadenceDays: 365,
                    estimatedCost: 200
                )
            ]
            
        case .warranties:
            metricUnit = "none"
            configuredEvents = [
                ConfigurableStarterEvent(
                    title: "Expirare Garanție Comercială Produs",
                    provider: warrantyRetailer,
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 24, to: today) ?? today,
                    cadenceDays: nil,
                    estimatedCost: 0
                ),
                ConfigurableStarterEvent(
                    title: "Verificare Last-Chance (-30 Zile Înainte de Ieșire din Garanție)",
                    provider: "Service Autorizat",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .day, value: 700, to: today) ?? today,
                    cadenceDays: nil,
                    estimatedCost: 0
                )
            ]
            
        case .subscriptions:
            metricUnit = "none"
            configuredEvents = [
                ConfigurableStarterEvent(
                    title: "Reînnoire Ciclu Facturare Abonament",
                    provider: subscriptionProvider,
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 1, to: today) ?? today,
                    cadenceDays: 30,
                    estimatedCost: Double(subscriptionAmountText) ?? 50
                ),
                ConfigurableStarterEvent(
                    title: "Alertă Renegociere Perioadă Minimă Contractuală (24 luni)",
                    provider: subscriptionProvider,
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 23, to: today) ?? today,
                    cadenceDays: nil,
                    estimatedCost: 0
                )
            ]
            
        case .documents:
            metricUnit = "none"
            configuredEvents = [
                ConfigurableStarterEvent(
                    title: "Reînnoire Document Oficial",
                    provider: docIssuer,
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .year, value: 10, to: today) ?? today,
                    cadenceDays: nil,
                    estimatedCost: 150
                ),
                ConfigurableStarterEvent(
                    title: "Alertă Călătorii Non-UE (Regula celor 6 Luni)",
                    provider: "Direcția Generală de Pașapoarte",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .day, value: 3470, to: today) ?? today,
                    cadenceDays: nil,
                    estimatedCost: 0
                )
            ]
            
        case .custom:
            metricUnit = "none"
            configuredEvents = [
                ConfigurableStarterEvent(
                    title: "Scadență Plată / Încasare Chirie",
                    provider: "Proprietar / Chiriaș",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 1, to: today) ?? today,
                    cadenceDays: 30,
                    estimatedCost: 2000
                ),
                ConfigurableStarterEvent(
                    title: "Declarația Unică ANAF (Formular 212 - 25 Mai)",
                    provider: "ANAF",
                    policyNumber: "",
                    coverageType: nil,
                    dueDate: calendar.date(byAdding: .month, value: 5, to: today) ?? today,
                    cadenceDays: 365,
                    estimatedCost: 0
                )
            ]
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
        newAsset.vin = vinNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : vinNumber.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.civSeries = civSeries.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : civSeries.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.make = vehicleMake.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : vehicleMake.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.modelName = vehicleModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : vehicleModel.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.manufactureYear = Int(manufactureYear)
        newAsset.fuelType = fuelType
        newAsset.engineDisplacementCc = Int(engineDisplacement)
        newAsset.enginePowerKw = Int(enginePower)
        
        // Home Fields
        newAsset.address = fullAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : fullAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.cadastralNumber = cadastralNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : cadastralNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.surfaceAreaSqm = Double(surfaceArea.replacingOccurrences(of: ",", with: "."))
        newAsset.constructionYear = Int(constructionYear)
        newAsset.podCode = podCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : podCode.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.clcCode = clcCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : clcCode.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.waterClientCode = waterClientCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : waterClientCode.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.meterReadWindowStartDay = Int(meterReadWindowStart)
        newAsset.meterReadWindowEndDay = Int(meterReadWindowEnd)
        newAsset.heatingBoilerModel = heatingBoilerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : heatingBoilerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.heatingBoilerSerial = heatingBoilerSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : heatingBoilerSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.gasMeterSerial = gasMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : gasMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.electricityMeterSerial = electricityMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : electricityMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.waterMeterSerial = waterMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : waterMeterSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Pet Fields
        newAsset.petSpecies = petSpecies.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : petSpecies.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.petBreed = petBreed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : petBreed.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.microchipNumber = petMicrochipNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : petMicrochipNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.petPassportNumber = petPassportNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : petPassportNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.birthDate = hasPetBirthDate ? petBirthDate : nil
        newAsset.weightKg = Double(petWeightKg.replacingOccurrences(of: ",", with: "."))
        newAsset.veterinarianClinic = veterinarianClinic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : veterinarianClinic.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.veterinarianPhone = veterinarianPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : veterinarianPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Health Fields
        newAsset.personName = personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : personName.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasPersonBirthDate { newAsset.birthDate = personBirthDate }
        newAsset.bloodType = bloodType
        newAsset.familyDoctorName = familyDoctorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : familyDoctorName.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.familyDoctorPhone = familyDoctorPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : familyDoctorPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.emergencyContactName = emergencyContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : emergencyContactName.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.emergencyContactPhone = emergencyContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : emergencyContactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.allergies = allergiesNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : allergiesNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        newAsset.chronicConditions = chronicConditions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : chronicConditions.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Warranties Fields
        if selectedCategory == .warranties {
            newAsset.make = productBrand.isEmpty ? nil : productBrand
            newAsset.modelName = productModel.isEmpty ? nil : productModel
            newAsset.serialOrImei = warrantySerial.isEmpty ? nil : warrantySerial
            newAsset.retailerOrIssuer = warrantyRetailer.isEmpty ? nil : warrantyRetailer
            newAsset.purchaseOrIssueDate = purchaseDate
            newAsset.purchasePrice = Double(purchasePriceText.replacingOccurrences(of: ",", with: "."))
            newAsset.warrantyMonths = Int(warrantyMonthsText)
            newAsset.extendedWarrantyMonths = Int(extendedWarrantyMonthsText)
        }
        
        // Subscriptions Fields
        if selectedCategory == .subscriptions {
            newAsset.providerName = subscriptionProvider.isEmpty ? nil : subscriptionProvider
            newAsset.billingCycle = subscriptionCycle
            newAsset.recurringAmount = Double(subscriptionAmountText.replacingOccurrences(of: ",", with: "."))
            newAsset.currencyCode = subscriptionCurrency
            newAsset.paymentCardLast4 = subscriptionCardLast4.isEmpty ? nil : subscriptionCardLast4
            newAsset.cancellationUrl = subscriptionCancelUrl.isEmpty ? nil : subscriptionCancelUrl
            newAsset.contractEndDate = hasSubscriptionEndDate ? subscriptionEndDate : nil
        }
        
        // Documents Fields
        if selectedCategory == .documents {
            newAsset.serialOrImei = docSeriesNumber.isEmpty ? nil : docSeriesNumber
            newAsset.retailerOrIssuer = docIssuer.isEmpty ? nil : docIssuer
            newAsset.purchaseOrIssueDate = docIssueDate
            newAsset.contractEndDate = docExpiryDate
        }
        
        // Custom / Landlord Fields
        if selectedCategory == .custom {
            if !landlordTenantName.isEmpty {
                newAsset.primaryContactName = landlordTenantName
                newAsset.primaryContactRole = "Chiriaș"
            }
            if !landlordTenantPhone.isEmpty { newAsset.primaryContactPhone = landlordTenantPhone }
            if let rent = Double(landlordRentAmount.replacingOccurrences(of: ",", with: ".")), rent > 0 {
                newAsset.recurringAmount = rent
            }
            if hasLandlordLeaseEndDate { newAsset.contractEndDate = landlordLeaseEndDate }
        }
        
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
                provider: item.provider.isEmpty ? nil : item.provider,
                policyOrContractNumber: item.policyNumber.isEmpty ? nil : item.policyNumber,
                coverageType: item.coverageType,
                cadenceDays: item.cadenceDays,
                cadenceMetricInterval: item.cadenceMetricInterval
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
