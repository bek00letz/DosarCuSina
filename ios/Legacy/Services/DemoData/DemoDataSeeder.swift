import Foundation
import SwiftData

/// Authoritative demo data seeder generating realistic, sanitized multi-domain examples
/// across all 8 household domains in full compliance with Romanian Administrative Standards.
public struct DemoDataSeeder {
    
    @MainActor
    public static func seedInitialDataIfNeeded(context: ModelContext, force: Bool = false) {
        if !force {
            let descriptor = FetchDescriptor<Asset>()
            if let count = try? context.fetchCount(descriptor), count > 0 {
                return // Already has user or demo data
            }
        }
        
        let cal = Calendar.current
        let now = Date()
        
        // -------------------------------------------------------------
        // Domain 1: 🏠 Home & Utilities
        // -------------------------------------------------------------
        let home = Asset(
            name: "Apartament 3 Camere Floreasca",
            subtitle: "București, Sector 1",
            category: .home,
            iconName: "house.fill",
            accentColorHex: "FF9500",
            notes: "Apartament reabilitat termic, contorizare individuală."
        )
        home.address = "Str. Aviației nr. 12, Sector 1, București"
        home.cadastralNumber = "234567-C1-U14"
        home.surfaceAreaSqm = 78.5
        home.constructionYear = 2018
        home.podCode = "RO001E123456789012"
        home.clcCode = "DEG0123456"
        home.waterClientCode = "APA-B-892147"
        home.meterReadWindowStartDay = 20
        home.meterReadWindowEndDay = 25
        home.heatingBoilerModel = "Viessmann Vitodens 100-W 25kW"
        home.heatingBoilerSerial = "7723491823901"
        home.heatingBoilerSpecs = "25 kW Tiraj Forțat Gaz Condensare"
        home.primaryContactName = "Ing. Valeriu Dumitrescu"
        home.primaryContactRole = "Tehnician ISCIR Centrală"
        home.primaryContactPhone = "+40 722 334 455"
        context.insert(home)
        
        // Home Measurement Logs (Electricity & Gas with Seasonal Spikes)
        let mHomeE1 = MeasurementLog(
            domain: .electricityMeter,
            metricName: "Index Contor Energie Electrică",
            value: 4120.0,
            unit: "kWh",
            recordedAt: cal.date(byAdding: .month, value: -2, to: now)!,
            previousValue: 3930.0,
            unitPrice: 0.68,
            isSelfRead: true,
            labOrProviderName: "Hidroelectrica"
        )
        mHomeE1.asset = home
        context.insert(mHomeE1)
        
        let mHomeE2 = MeasurementLog(
            domain: .electricityMeter,
            metricName: "Index Contor Energie Electrică",
            value: 4330.0,
            unit: "kWh",
            recordedAt: cal.date(byAdding: .month, value: -1, to: now)!,
            previousValue: 4120.0,
            unitPrice: 0.68,
            isSelfRead: true,
            labOrProviderName: "Hidroelectrica"
        )
        mHomeE2.asset = home
        context.insert(mHomeE2)
        
        let mHomeGas = MeasurementLog(
            domain: .gasMeter,
            metricName: "Index Contor Gaze Naturale",
            value: 1540.0,
            unit: "m³",
            recordedAt: cal.date(byAdding: .month, value: -1, to: now)!,
            previousValue: 1370.0,
            unitPrice: 3.25,
            isSelfRead: true,
            labOrProviderName: "Engie România"
        )
        mHomeGas.asset = home
        context.insert(mHomeGas)
        
        // Home Service Items (Boiler VTP ISCIR)
        let sHomeBoiler = ServiceItem(
            name: "Revizie VTP ISCIR Centrală Termică",
            category: "Încălzire",
            partBrand: "Viessmann Piese Originale",
            cost: 350.0,
            serviceDate: cal.date(byAdding: .month, value: -14, to: now)!,
            specialistOrDoctorName: "Ing. V. Dumitrescu",
            warrantyMonths: 24,
            nextDueDate: cal.date(byAdding: .month, value: 10, to: now)!,
            shopName: "TermoTech Service SRL",
            notes: "Verificare etanșeitate, analiză noxe CO/CO2, curățat filtru Y."
        )
        sHomeBoiler.asset = home
        context.insert(sHomeBoiler)
        
        // Home Lifecycle Events
        let evHomePAD = LifecycleEvent(
            title: "Asigurare Obligatorie Locuință (PAD)",
            dueDate: cal.date(byAdding: .month, value: 4, to: now)!,
            cost: 130.0,
            currency: "RON",
            cadenceDays: 365,
            reminderOffsetDays: [30, 7, 1]
        )
        evHomePAD.provider = "PAID România"
        evHomePAD.policyOrContractNumber = "PAD-2026-881923"
        evHomePAD.coverageType = "PAD Tip A"
        evHomePAD.insuredCoverageAmount = 100000.0
        evHomePAD.asset = home
        context.insert(evHomePAD)
        
        let evHomeGasCheck = LifecycleEvent(
            title: "Verificare Tehnică Instalație Gaze (VIG)",
            dueDate: cal.date(byAdding: .month, value: 8, to: now)!,
            cost: 250.0,
            currency: "RON",
            cadenceDays: 730,
            reminderOffsetDays: [30, 7, 1]
        )
        evHomeGasCheck.provider = "Engie Servicii Autorizate ANRE"
        evHomeGasCheck.asset = home
        context.insert(evHomeGasCheck)
        
        // -------------------------------------------------------------
        // Domain 2: 🚗 Vehicles & Mobility
        // -------------------------------------------------------------
        let car = Asset(
            name: "VW Golf VII 2.0 TDI",
            subtitle: "B-123-ABC",
            category: .vehicle,
            iconName: "car.fill",
            accentColorHex: "007AFF",
            currentMetricValue: 142500.0,
            metricUnit: "km"
        )
        car.vin = "WVWZZZAUZJP123456"
        car.licensePlate = "B-123-ABC"
        car.civSeries = "A1234567"
        car.make = "Volkswagen"
        car.modelName = "Golf 7"
        car.manufactureYear = 2018
        car.fuelType = "Motorină"
        car.engineDisplacementCc = 1968
        car.enginePowerKw = 110
        car.primaryContactName = "Marius Service"
        car.primaryContactRole = "Mecanic Auto"
        car.primaryContactPhone = "+40 721 987 654"
        context.insert(car)
        
        // Consecutive Service Items demonstrating Delta-Km (+47.000 km) & Delta-Cost (+20.9%)
        let sCarBrakes1 = ServiceItem(
            name: "Plăcuțe Frână Față",
            category: "Frâne",
            partBrand: "Brembo P85020",
            cost: 430.0,
            laborCost: 150.0,
            partsCost: 280.0,
            serviceDate: cal.date(byAdding: .year, value: -2, to: now)!,
            mileageAtService: 85000.0,
            warrantyMonths: 12,
            shopName: "AutoExpert Service",
            notes: "Plăcuțe Brembo P85020 montate."
        )
        sCarBrakes1.asset = car
        context.insert(sCarBrakes1)
        
        let sCarBrakes2 = ServiceItem(
            name: "Plăcuțe Frână Față",
            category: "Frâne",
            partBrand: "ATE Ceramic 13.0460",
            cost: 520.0,
            laborCost: 180.0,
            partsCost: 340.0,
            serviceDate: cal.date(byAdding: .month, value: -4, to: now)!,
            mileageAtService: 132000.0,
            warrantyMonths: 12,
            shopName: "Reprezentanță VW",
            notes: "Plăcuțe ATE Ceramic montate (delta: +47.000 km, +20.9% cost)."
        )
        sCarBrakes2.asset = car
        context.insert(sCarBrakes2)
        
        // Vehicle Lifecycle Events (ITP 2y, RCA, Rovinietă 12m)
        let evCarITP = LifecycleEvent(
            title: "Inspecție Tehnică Periodică (ITP)",
            dueDate: cal.date(byAdding: .month, value: 8, to: now)!,
            cost: 160.0,
            currency: "RON",
            cadenceDays: 730,
            reminderOffsetDays: [30, 7, 1]
        )
        evCarITP.serviceLocation = "Stație RAR / AutoTest Floreasca"
        evCarITP.asset = car
        context.insert(evCarITP)
        
        let evCarRCA = LifecycleEvent(
            title: "Poliță Asigurare RCA",
            dueDate: cal.date(byAdding: .month, value: 3, to: now)!,
            cost: 890.0,
            currency: "RON",
            cadenceDays: 365,
            reminderOffsetDays: [30, 14, 7, 1]
        )
        evCarRCA.provider = "Groupama Asigurări"
        evCarRCA.policyOrContractNumber = "RO-GRO-2026-99120"
        evCarRCA.bonusMalusClass = "B6"
        evCarRCA.coverageType = "RCA cu Decontare Directă"
        evCarRCA.asset = car
        context.insert(evCarRCA)
        
        let evCarRovinieta = LifecycleEvent(
            title: "Rovinietă Națională (12 Luni)",
            dueDate: cal.date(byAdding: .month, value: 5, to: now)!,
            cost: 140.0,
            currency: "RON",
            cadenceDays: 365,
            reminderOffsetDays: [7, 1]
        )
        evCarRovinieta.provider = "CNAIR"
        evCarRovinieta.asset = car
        context.insert(evCarRovinieta)
        
        // -------------------------------------------------------------
        // Domain 3: 🩺 Health & Family
        // -------------------------------------------------------------
        let health = Asset(
            name: "Andrei Popescu — Profil Medical",
            subtitle: "Card Medical & Analize",
            category: .health,
            iconName: "heart.fill",
            accentColorHex: "FF2D55"
        )
        health.personName = "Andrei Popescu"
        health.birthDate = cal.date(byAdding: .year, value: -38, to: now)
        health.bloodType = "A II, Rh+"
        health.allergies = "Penicilină, Polen mesteacăn"
        health.chronicConditions = "Hipertensiune ușoară controlată"
        health.familyDoctorName = "Dr. Elena Ionescu"
        health.familyDoctorPhone = "+40 722 123 456"
        health.emergencyContactName = "Maria Popescu (Soție)"
        health.emergencyContactPhone = "+40 722 654 321"
        context.insert(health)
        
        // Health Biomarker Measurement Logs (showing delta improvement)
        let mGlucose = MeasurementLog(
            domain: .healthBiomarker,
            metricName: "Glicemie a jeun",
            value: 92.0,
            unit: "mg/dL",
            recordedAt: cal.date(byAdding: .month, value: -1, to: now)!,
            previousValue: 98.0,
            referenceMin: 70.0,
            referenceMax: 99.0,
            labOrProviderName: "Laborator Synevo"
        )
        mGlucose.asset = health
        context.insert(mGlucose)
        
        let mCholesterol = MeasurementLog(
            domain: .healthBiomarker,
            metricName: "Colesterol LDL",
            value: 125.0,
            unit: "mg/dL",
            recordedAt: cal.date(byAdding: .month, value: -1, to: now)!,
            previousValue: 148.0,
            referenceMin: 0.0,
            referenceMax: 130.0,
            labOrProviderName: "Laborator Synevo",
            notes: "Scădere semnificativă după ajustarea dietei."
        )
        mCholesterol.asset = health
        context.insert(mCholesterol)
        
        // Health Service Items (Dental Implant Passport)
        let sImplant = ServiceItem(
            name: "Implant Dentar Titan & Coroană Zirconiu",
            category: "Stomatologie",
            cost: 3800.0,
            serviceDate: cal.date(byAdding: .month, value: -8, to: now)!,
            specialistOrDoctorName: "Dr. Mihai Stoica",
            serialOrBatchNumber: "Straumann BLX Lot ST-8829104",
            locationOrToothNumber: "Dinte #36 (FDI)",
            warrantyMonths: 120,
            shopName: "Clinica DentalElite",
            notes: "Pașaport implant eliberat, osteointegrare 100% reușită."
        )
        sImplant.asset = health
        context.insert(sImplant)
        
        // -------------------------------------------------------------
        // Domain 4: 🐾 Pets & Vet Care
        // -------------------------------------------------------------
        let pet = Asset(
            name: "Max — Golden Retriever",
            subtitle: "Carnet de Sănătate & Pașaport UE",
            category: .pet,
            iconName: "pawprint.fill",
            accentColorHex: "34C759",
            weightKg: 31.5
        )
        pet.speciesAndBreed = "Câine Golden Retriever"
        pet.microchipNumber = "642098100123456" // Valid 15-digit ISO with 642 Romania prefix
        pet.petPassportNumber = "RO-081293"
        pet.veterinarianClinic = "Clinica Veterinară BlueVets"
        pet.veterinarianPhone = "+40 733 987 654"
        context.insert(pet)
        
        let mPetWeight = MeasurementLog(
            domain: .bodyWeight,
            metricName: "Greutate Corporală",
            value: 31.5,
            unit: "kg",
            recordedAt: cal.date(byAdding: .day, value: -15, to: now)!,
            previousValue: 29.8,
            referenceMin: 27.0,
            referenceMax: 34.0,
            labOrProviderName: "Cântar BlueVets"
        )
        mPetWeight.asset = pet
        context.insert(mPetWeight)
        
        let sPetDeworm = ServiceItem(
            name: "Deparazitare Internă & Externă",
            category: "Veterinar",
            cost: 225.0,
            partsCost: 225.0,
            serviceDate: cal.date(byAdding: .month, value: -2, to: now)!,
            specialistOrDoctorName: "Dr. Cristian Vasilescu",
            serialOrBatchNumber: "Bravecto 1000mg + Milbemax",
            shopName: "Farmacia BlueVets",
            notes: "Fără reacții adverse; greutate la administrare: 31 kg."
        )
        sPetDeworm.asset = pet
        context.insert(sPetDeworm)
        
        // -------------------------------------------------------------
        // Domain 5: 🪪 Identity, Legal & Financial Documents
        // -------------------------------------------------------------
        let docPassport = Asset(
            name: "Pașaport Simplu Electronic",
            subtitle: "Seria 05829144",
            category: .documents,
            iconName: "person.text.rectangle.fill",
            accentColorHex: "5856D6"
        )
        docPassport.serialOrImei = "05829144"
        docPassport.retailerOrIssuer = "SPCP București"
        docPassport.purchaseOrIssueDate = cal.date(byAdding: .year, value: -5, to: now)
        context.insert(docPassport)
        
        // Expiry in 150 days triggers the active 6-month (-180d) non-EU travel restriction alert
        let evPassportExpiry = LifecycleEvent(
            title: "Expirare Pașaport (Atenție Călătorii Non-UE)",
            dueDate: cal.date(byAdding: .day, value: 150, to: now)!,
            cost: 258.0,
            currency: "RON",
            reminderOffsetDays: [180, 60, 30, 7]
        )
        evPassportExpiry.eventDescription = "Sub 6 luni de valabilitate rămasă. Călătoriile non-UE (UK, Turcia, SUA) pot fi restricționate."
        evPassportExpiry.asset = docPassport
        context.insert(evPassportExpiry)
        
        // -------------------------------------------------------------
        // Domain 6: 🛡️ Warranties & Goods
        // -------------------------------------------------------------
        let warrantyAsset = Asset(
            name: "Espressor De'Longhi Magnifica S",
            subtitle: "ECAM 22.110.B",
            category: .warranties,
            iconName: "shield.lefthalf.filled",
            accentColorHex: "AF52DE"
        )
        warrantyAsset.make = "De'Longhi"
        warrantyAsset.modelName = "Magnifica S ECAM 22.110.B"
        warrantyAsset.serialOrImei = "DL-2024-998812"
        warrantyAsset.retailerOrIssuer = "eMAG"
        warrantyAsset.purchaseOrIssueDate = cal.date(byAdding: .month, value: -23, to: now)
        warrantyAsset.purchasePrice = 1499.0
        warrantyAsset.warrantyMonths = 24
        context.insert(warrantyAsset)
        
        // Expiry in 25 days triggers active -30d Last-Chance Warranty Inspection alert
        let evWarrantyExpiry = LifecycleEvent(
            title: "Ultima Șansă: Inspecție Înainte de Expirare Garanție",
            dueDate: cal.date(byAdding: .day, value: 25, to: now)!,
            cost: 0.0,
            currency: "RON",
            reminderOffsetDays: [30, 7]
        )
        evWarrantyExpiry.eventDescription = "Garanția legală expiră în 25 de zile. Verifică pompa și garniturile pentru reparație gratuită."
        evWarrantyExpiry.asset = warrantyAsset
        context.insert(evWarrantyExpiry)
        
        // -------------------------------------------------------------
        // Domain 7: 💳 Subscriptions & Contracts
        // -------------------------------------------------------------
        let subAsset = Asset(
            name: "Internet Fibră 1000 + TV Digi",
            subtitle: "Contract RCS & RDS",
            category: .subscriptions,
            iconName: "creditcard.fill",
            accentColorHex: "00C7BE"
        )
        subAsset.providerName = "Digi România"
        subAsset.billingCycle = "Lunar"
        subAsset.recurringAmount = 65.0
        subAsset.currencyCode = "RON"
        subAsset.paymentCardLast4 = "4412"
        subAsset.cancellationUrl = "https://www.digi.ro/asistenta"
        subAsset.contractEndDate = cal.date(byAdding: .day, value: 45, to: now)
        context.insert(subAsset)
        
        let evSubRetention = LifecycleEvent(
            title: "Expirare Perioadă Minimă Contractuală Digi (Renegociere)",
            dueDate: cal.date(byAdding: .day, value: 45, to: now)!,
            cost: 65.0,
            currency: "RON",
            reminderOffsetDays: [30, 7]
        )
        evSubRetention.eventDescription = "Perioada contractuală de 24 luni expiră. Contactează Digi pentru reofertare sau trecere la preț de retenție."
        evSubRetention.asset = subAsset
        context.insert(evSubRetention)
        
        // -------------------------------------------------------------
        // Domain 8: 🧩 Custom / Landlord Hub
        // -------------------------------------------------------------
        let landlordAsset = Asset(
            name: "Garsonieră Închiriată — Titan",
            subtitle: "Chiriaș: Radu Gheorghe",
            category: .custom,
            iconName: "key.fill",
            accentColorHex: "FF9500"
        )
        landlordAsset.customCategoryName = "Proprietar / Landlord"
        landlordAsset.primaryContactName = "Radu Gheorghe"
        landlordAsset.primaryContactRole = "Chiriaș"
        landlordAsset.primaryContactPhone = "+40 744 555 666"
        landlordAsset.primaryContactEmail = "radu.gheorghe@example.com"
        context.insert(landlordAsset)
        
        // Dynamic Fields for Landlord Hub
        let fRent = DynamicField(
            key: "chirie_lunara",
            label: "Chirie Lunară",
            fieldType: .currency,
            numberValue: 350.0,
            asset: landlordAsset
        )
        context.insert(fRent)
        
        let fDeposit = DynamicField(
            key: "garantie_depozit",
            label: "Garanție Încasată",
            fieldType: .currency,
            numberValue: 700.0,
            asset: landlordAsset
        )
        context.insert(fDeposit)
        
        let fAnaf = DynamicField(
            key: "nr_anaf",
            label: "Număr Înregistrare ANAF",
            fieldType: .text,
            stringValue: "ANAF-B-2025-00912",
            asset: landlordAsset
        )
        context.insert(fAnaf)
        
        // Utility settlement meter reading for tenant
        let mTenantWater = MeasurementLog(
            domain: .coldWaterMeter,
            metricName: "Index Apometru Chiriaș",
            value: 154.0,
            unit: "m³",
            recordedAt: cal.date(byAdding: .day, value: -5, to: now)!,
            previousValue: 148.0,
            unitPrice: 5.60,
            isSelfRead: true,
            notes: "Consum lunar 6 m³ = 33.60 RON."
        )
        mTenantWater.asset = landlordAsset
        context.insert(mTenantWater)
        
        // ANAF Form 212 deadline (May 25 annual deadline)
        let currentYear = cal.component(.year, from: now)
        var anafComponents = DateComponents(year: currentYear, month: 5, day: 25)
        let anafThisYear = cal.date(from: anafComponents) ?? now
        let anafDueDate: Date
        if anafThisYear > now {
            anafDueDate = anafThisYear
        } else {
            anafComponents.year = currentYear + 1
            anafDueDate = cal.date(from: anafComponents) ?? cal.date(byAdding: .month, value: 6, to: now)!
        }
        
        let evAnaf = LifecycleEvent(
            title: "Depunere Declarația Unică ANAF (Formularul 212)",
            dueDate: anafDueDate,
            cost: 0.0,
            currency: "RON",
            cadenceDays: 365,
            reminderOffsetDays: [30, 14, 7]
        )
        evAnaf.eventDescription = "Termen legal anual 25 mai pentru declararea veniturilor din chirii."
        evAnaf.asset = landlordAsset
        context.insert(evAnaf)
        
        try? context.save()
        WidgetDataSyncService.shared.sync(context: context)
    }
    
    @MainActor
    public static func resetAndReseed(context: ModelContext) throws {
        // Delete all existing assets, triggering cascade delete on all related tables
        let assets = try context.fetch(FetchDescriptor<Asset>())
        for a in assets {
            context.delete(a)
        }
        
        // Explicitly cleanup any standalone or orphaned entities
        let events = try context.fetch(FetchDescriptor<LifecycleEvent>())
        for e in events { context.delete(e) }
        
        let services = try context.fetch(FetchDescriptor<ServiceItem>())
        for s in services { context.delete(s) }
        
        let measurements = try context.fetch(FetchDescriptor<MeasurementLog>())
        for m in measurements { context.delete(m) }
        
        let fields = try context.fetch(FetchDescriptor<DynamicField>())
        for f in fields { context.delete(f) }
        
        let attachments = try context.fetch(FetchDescriptor<DocumentAttachment>())
        for att in attachments { context.delete(att) }
        
        try context.save()
        
        // Reseed clean sanitized demo data
        seedInitialDataIfNeeded(context: context, force: true)
    }
}

