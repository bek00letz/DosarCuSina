import Foundation

/// The categories that ship with the app, defined once. `TemplateStore`
/// installs them into the database and upgrades installed copies when a
/// `version` here goes up.
///
/// Legal cadences follow `shared/ROMANIAN_ADMINISTRATIVE_STANDARDS.md`.
/// Starter categories (bike, plants, rental, espresso) come from
/// `shared/templates/default_modules.json` and start hidden from home.
public enum BuiltInTemplates {

    public static var all: [TemplateDefinition] {
        [vehicle, home, documents, pet, health, purchase, subscription, other, bike, plants, tenancy, member, espresso]
    }

    public static func definition(for key: String) -> TemplateDefinition? {
        all.first { $0.key == key }
    }

    /// Built-in keys from earlier catalogs and what replaced them. `TemplateStore`
    /// moves assets over; a retired key with no replacement becomes a custom category.
    public static let replacedKeys: [String: String] = ["warranty": Key.purchase]
    public static let retiredKeys: Set<String> = ["rental"]

    /// Field keys renamed along with a replaced template.
    public static let replacedFieldKeys: [String: String] = [
        "warranty.brand": "purchase.brand",
        "warranty.model": "purchase.model",
        "warranty.serial": "purchase.serial",
        "warranty.retailer": "purchase.retailer",
        "warranty.price": "purchase.price",
        "warranty.purchaseDate": "purchase.date",
        "warranty.expiry": "purchase.warrantyUntil",
        "warranty.manualUrl": "purchase.manualUrl",
    ]

    // MARK: Keys

    public enum Key {
        public static let vehicle = "vehicle"
        public static let home = "home"
        public static let documents = "documents"
        public static let pet = "pet"
        public static let health = "health"
        public static let purchase = "purchase"
        public static let subscription = "subscription"
        public static let other = "other"
        public static let bike = "bike"
        public static let plants = "plants"
        public static let tenancy = "tenancy"
        public static let member = "member"
        public static let espresso = "espresso"
    }

    private static func ron(_ amount: Decimal) -> Money { Money(amount, currency: "RON") }

    private static func profile(_ leadDays: [Int], _ consequence: Consequence, grace: Int = 0, followUp: Bool? = nil) -> ReminderProfile {
        ReminderProfile(leadDays: leadDays, consequence: consequence, graceDays: grace, followUpAfterLapse: followUp)
    }

    // MARK: Mainstays

    public static var vehicle: TemplateDefinition {
        TemplateDefinition(
            key: Key.vehicle,
            name: String(localized: "Mașini", comment: "Category name"),
            summary: String(localized: "ITP, RCA, rovinietă și revizii, cu kilometrajul la zi.", comment: "Category summary"),
            symbol: "car.fill",
            tint: .blue,
            heroStyle: .vehicle,
            sections: [
                FieldSection(key: "vehicle.identity", title: String(localized: "Identificare"), fields: [
                    FieldDefinition(key: "vehicle.plate", label: String(localized: "Număr de înmatriculare"), type: .plate, role: .identifier, isEssential: true, placeholder: "B-123-ABC"),
                    FieldDefinition(key: "vehicle.make", label: String(localized: "Marcă"), type: .text, role: .subtitle, isEssential: true, placeholder: "Volkswagen"),
                    FieldDefinition(key: "vehicle.model", label: String(localized: "Model"), type: .text, role: .subtitle, isEssential: true, placeholder: "Golf"),
                    FieldDefinition(key: "vehicle.year", label: String(localized: "An de fabricație"), type: .year, role: .subtitle, isEssential: true, placeholder: "2018"),
                    FieldDefinition(key: "vehicle.vin", label: String(localized: "Serie de șasiu (VIN)"), type: .vin, role: .keyFact),
                    FieldDefinition(key: "vehicle.civ", label: String(localized: "Serie CIV"), type: .text),
                ]),
                FieldSection(key: "vehicle.technical", title: String(localized: "Date tehnice"), fields: [
                    FieldDefinition(key: "vehicle.odometer", label: String(localized: "Kilometraj"), type: .metric, role: .heroMetric, isEssential: true, unit: "km"),
                    FieldDefinition(key: "vehicle.fuel", label: String(localized: "Combustibil"), type: .choice, options: FuelType.options),
                    FieldDefinition(key: "vehicle.engineCc", label: String(localized: "Capacitate cilindrică"), type: .number, unit: "cm³"),
                    FieldDefinition(key: "vehicle.powerHp", label: String(localized: "Putere"), type: .number, unit: "CP"),
                    FieldDefinition(key: "vehicle.usage", label: String(localized: "Folosire"), type: .choice, options: VehicleUse.options),
                ]),
                FieldSection(key: "vehicle.insurance", title: String(localized: "Asigurare"), fields: [
                    FieldDefinition(key: "vehicle.insurer", label: String(localized: "Asigurător RCA"), type: .text, role: .issuer),
                    FieldDefinition(key: "vehicle.policyNumber", label: String(localized: "Număr poliță RCA"), type: .text, role: .keyFact),
                    FieldDefinition(key: "vehicle.claimsPhone", label: String(localized: "Telefon pentru daune"), type: .phone, role: .keyFact),
                ]),
                PurchaseFields.section(prefix: "vehicle"),
            ],
            blueprints: [
                ObligationBlueprint(key: "vehicle.itp", title: String(localized: "ITP"), kind: .legal, recurrence: .legal(.vehicleITP), firstDue: .ask,
                                    reminders: profile([30, 7], .legal),
                                    estimatedCost: ron(180), note: String(localized: "Fără ITP valabil, înmatricularea se suspendă.")),
                ObligationBlueprint(key: "vehicle.rca", title: String(localized: "RCA"), kind: .insurance, recurrence: .interval(.years(1), anchor: .dueDate), firstDue: .ask,
                                    reminders: profile([30, 7, 0], .legal), note: String(localized: "Cere oferte cu o lună înainte, prețurile diferă mult.")),
                ObligationBlueprint(key: "vehicle.vignette", title: String(localized: "Rovinietă"), kind: .legal, recurrence: .interval(.months(12), anchor: .completion), firstDue: .ask,
                                    reminders: profile([7, 0], .legal)),
                ObligationBlueprint(key: "vehicle.service", title: String(localized: "Revizie periodică"), kind: .maintenance,
                                    recurrence: .metric(every: 15_000, unit: "km", fallback: .years(1)), firstDue: .afterInterval(.years(1)),
                                    reminders: profile([14, 1], .comfort, grace: 30)),
                ObligationBlueprint(key: "vehicle.tyres", title: String(localized: "Schimb de anvelope"), kind: .maintenance,
                                    recurrence: .fixedDates([MonthDay(month: 4, day: 15), MonthDay(month: 11, day: 1)]), firstDue: .nextFixedDate,
                                    reminders: profile([14], .comfort, grace: 14)),
                ObligationBlueprint(key: "vehicle.casco", title: String(localized: "CASCO"), kind: .insurance, recurrence: .interval(.years(1), anchor: .dueDate), firstDue: .ask,
                                    reminders: profile([30, 7, 0], .financial), isSuggested: false),
                ObligationBlueprint(key: "vehicle.kit", title: String(localized: "Trusă medicală și stingător"), kind: .legal, recurrence: .none, firstDue: .ask,
                                    reminders: profile([14, 0], .legal), isSuggested: false, note: String(localized: "Data expirării e pe ambalaj.")),
            ],
            components: BuiltInComponents.vehicle,
            pockets: [.upcoming, .documents, .history, .people, .money, .keyFacts]
        )
    }

    public static var home: TemplateDefinition {
        TemplateDefinition(
            key: Key.home,
            name: String(localized: "Locuințe", comment: "Category name"),
            summary: String(localized: "Centrală, gaze, asigurare, impozit și contoare.", comment: "Category summary"),
            symbol: "house.fill",
            tint: .orange,
            heroStyle: .home,
            sections: [
                FieldSection(key: "home.place", title: String(localized: "Locuința"), fields: [
                    FieldDefinition(key: "home.address", label: String(localized: "Adresă"), type: .address, role: .location, isEssential: true),
                    FieldDefinition(key: "home.area", label: String(localized: "Suprafață utilă"), type: .number, unit: "m²"),
                    FieldDefinition(key: "home.year", label: String(localized: "An construcție"), type: .year),
                    FieldDefinition(key: "home.cadastral", label: String(localized: "Număr cadastral"), type: .text),
                ]),
                FieldSection(key: "home.utilities", title: String(localized: "Utilități"), fields: [
                    FieldDefinition(key: "home.pod", label: String(localized: "Cod loc de consum energie (POD)"), type: .text, role: .keyFact),
                    FieldDefinition(key: "home.clc", label: String(localized: "Cod loc de consum gaze (CLC)"), type: .text, role: .keyFact),
                    FieldDefinition(key: "home.waterCode", label: String(localized: "Cod client apă"), type: .text),
                    FieldDefinition(key: "home.meterReadFrom", label: String(localized: "Autocitire de la ziua"), type: .number),
                    FieldDefinition(key: "home.meterReadTo", label: String(localized: "Autocitire până la ziua"), type: .number),
                ]),
                FieldSection(key: "home.insurance", title: String(localized: "Asigurare"), fields: [
                    FieldDefinition(key: "home.insurer", label: String(localized: "Asigurător"), type: .text, role: .issuer),
                    FieldDefinition(key: "home.policyNumber", label: String(localized: "Număr poliță"), type: .text, role: .keyFact),
                    FieldDefinition(key: "home.claimsPhone", label: String(localized: "Telefon pentru daune"), type: .phone, role: .keyFact),
                ]),
                FieldSection(key: "home.heating", title: String(localized: "Centrală termică"), fields: [
                    FieldDefinition(key: "home.boilerModel", label: String(localized: "Model"), type: .text),
                    FieldDefinition(key: "home.boilerSerial", label: String(localized: "Serie"), type: .text),
                ]),
            ],
            blueprints: [
                ObligationBlueprint(key: "home.boilerCheck", title: String(localized: "Verificare centrală (VTP)"), kind: .legal, recurrence: .interval(.years(2), anchor: .completion), firstDue: .ask,
                                    reminders: profile([30, 7], .legal),
                                    note: String(localized: "Obligatorie la cel mult 2 ani, făcută de o firmă autorizată ISCIR.")),
                ObligationBlueprint(key: "home.gasCheck", title: String(localized: "Verificare instalație de gaze"), kind: .legal, recurrence: .interval(.years(2), anchor: .completion), firstDue: .ask,
                                    reminders: profile([30, 7], .legal)),
                ObligationBlueprint(key: "home.gasRevision", title: String(localized: "Revizie instalație de gaze"), kind: .legal, recurrence: .interval(.years(10), anchor: .completion), firstDue: .ask,
                                    reminders: profile([60, 30], .legal),
                                    isSuggested: false),
                ObligationBlueprint(key: "home.pad", title: String(localized: "Asigurare obligatorie (PAD)"), kind: .insurance, recurrence: .interval(.years(1), anchor: .dueDate), firstDue: .ask,
                                    reminders: profile([30, 7, 0], .legal),
                                    estimatedCost: ron(130)),
                ObligationBlueprint(key: "home.buildingTax", title: String(localized: "Impozit pe clădire"), kind: .tax,
                                    recurrence: .fixedDates([MonthDay(month: 3, day: 31), MonthDay(month: 9, day: 30)]), firstDue: .nextFixedDate,
                                    reminders: profile([14, 1], .financial), note: String(localized: "Plata integrală până la 31 martie poate aduce o reducere.")),
                ObligationBlueprint(key: "home.chimney", title: String(localized: "Curățare coș de fum"), kind: .maintenance, recurrence: .interval(.years(1), anchor: .completion), firstDue: .ask,
                                    reminders: profile([14, 0], .comfort, grace: 30), isSuggested: false),
            ],
            components: BuiltInComponents.home,
            pockets: [.upcoming, .tenants, .products, .subscriptions, .documents, .history, .people, .money, .keyFacts]
        )
    }

    public static var documents: TemplateDefinition {
        TemplateDefinition(
            key: Key.documents,
            name: String(localized: "Acte", comment: "Category name"),
            summary: String(localized: "Buletin, pașaport, permis, cu reînnoirea din timp.", comment: "Category summary"),
            symbol: "person.text.rectangle.fill",
            tint: .indigo,
            heroStyle: .document,
            isSensitiveByDefault: true,
            sections: [
                FieldSection(key: "document.main", title: String(localized: "Document"), fields: [
                    FieldDefinition(key: "document.type", label: String(localized: "Tip"), type: .choice, role: .subtitle, isEssential: true, options: DocumentType.options),
                    FieldDefinition(key: "document.number", label: String(localized: "Serie și număr"), type: .text, role: .documentNumber, isSensitive: true),
                    // The personal numeric code lives only here, in a category that asks for Face ID by default.
                    FieldDefinition(key: "document.personalNumber", label: String(localized: "CNP"), type: .text, isSensitive: true),
                    // What forms ask for, read off the document. Sensitive, so never indexed for search.
                    FieldDefinition(key: "document.birthDate", label: String(localized: "Data nașterii"), type: .date, isSensitive: true),
                    FieldDefinition(key: "document.sex", label: String(localized: "Sex"), type: .text, isSensitive: true),
                    FieldDefinition(key: "document.nationality", label: String(localized: "Cetățenie"), type: .text, isSensitive: true),
                    FieldDefinition(key: "document.categories", label: String(localized: "Categorii"), type: .text),
                    FieldDefinition(key: "document.issuer", label: String(localized: "Emis de"), type: .text, role: .issuer),
                    FieldDefinition(key: "document.issueDate", label: String(localized: "Data emiterii"), type: .date, role: .startDate),
                    FieldDefinition(key: "document.expiry", label: String(localized: "Valabil până la"), type: .expiryDate, role: .expiryDate, isEssential: true),
                ]),
            ],
            blueprints: [
                ObligationBlueprint(key: "document.renew", title: String(localized: "Reînnoire"), kind: .renewal, recurrence: .none,
                                    firstDue: .field(key: "document.expiry", offsetDays: 0),
                                    reminders: profile([90, 30], .legal),
                                    reminderVariants: ReminderProfileVariants(field: "document.type", variants: [
                                        DocumentType.passport: profile([180, 60], .legal),
                                        DocumentType.idCard: profile([90, 30], .legal),
                                        DocumentType.drivingLicence: profile([60, 30], .legal),
                                        DocumentType.euHealthCard: profile([30, 7], .health),
                                        DocumentType.greenCard: profile([30, 7], .legal),
                                        DocumentType.bankCard: profile([30, 7], .financial),
                                        DocumentType.eSignature: profile([30, 7], .financial),
                                        DocumentType.criminalRecord: profile([7, 0], .legal),
                                    ]),
                                    note: String(localized: "Programările durează. Pentru pașaport, multe țări cer 6 luni de valabilitate.")),
            ],
            pockets: [.upcoming, .documents, .keyFacts]
        )
    }

    public static var pet: TemplateDefinition {
        TemplateDefinition(
            key: Key.pet,
            name: String(localized: "Animale", comment: "Category name"),
            summary: String(localized: "Vaccinuri, deparazitări, greutate și veterinar.", comment: "Category summary"),
            symbol: "pawprint.fill",
            tint: .brown,
            heroStyle: .pet,
            sections: [
                FieldSection(key: "pet.identity", title: String(localized: "Identitate"), fields: [
                    FieldDefinition(key: "pet.species", label: String(localized: "Specie"), type: .choice, role: .subtitle, isEssential: true, options: PetSpecies.options),
                    FieldDefinition(key: "pet.breed", label: String(localized: "Rasă"), type: .text, role: .subtitle),
                    FieldDefinition(key: "pet.birthDate", label: String(localized: "Data nașterii"), type: .date, role: .startDate, isEssential: true),
                    FieldDefinition(key: "pet.microchip", label: String(localized: "Microcip"), type: .microchip, role: .keyFact),
                    FieldDefinition(key: "pet.passport", label: String(localized: "Pașaport european"), type: .text, role: .keyFact),
                    FieldDefinition(key: "pet.weight", label: String(localized: "Greutate"), type: .number, role: .heroMetric, unit: "kg"),
                ]),
                FieldSection(key: "pet.care", title: String(localized: "Îngrijire"), fields: [
                    FieldDefinition(key: "pet.diet", label: String(localized: "Hrană și porții"), type: .longText),
                ]),
            ],
            blueprints: [
                ObligationBlueprint(key: "pet.rabies", title: String(localized: "Vaccin antirabic"), kind: .legal, recurrence: .interval(.years(1), anchor: .completion), firstDue: .ask,
                                    reminders: profile([1], .health, grace: 7),
                                    // A cat can be a few days late; a dog's rabies vaccine is a legal requirement.
                                    reminderVariants: ReminderProfileVariants(field: "pet.species", variants: [
                                        PetSpecies.cat: profile([1], .health, grace: 7),
                                        PetSpecies.dog: profile([10, 4], .legal),
                                    ]),
                                    note: String(localized: "Obligatoriu și cerut la trecerea graniței.")),
                ObligationBlueprint(key: "pet.vaccine", title: String(localized: "Vaccin anual"), kind: .health, recurrence: .interval(.years(1), anchor: .completion), firstDue: .ask,
                                    reminders: profile([1], .health, grace: 7)),
                ObligationBlueprint(key: "pet.dewormInternal", title: String(localized: "Deparazitare internă"), kind: .health, recurrence: .interval(.months(3), anchor: .completion),
                                    firstDue: .afterInterval(.months(3)),
                                    reminders: profile([1, 0], .health, grace: 7)),
                ObligationBlueprint(key: "pet.dewormExternal", title: String(localized: "Deparazitare externă"), kind: .health, recurrence: .interval(.months(1), anchor: .completion),
                                    firstDue: .afterInterval(.months(1)),
                                    reminders: profile([1, 0], .health, grace: 7)),
                ObligationBlueprint(key: "pet.grooming", title: String(localized: "Toaletaj"), kind: .routine, recurrence: .interval(.weeks(6), anchor: .completion),
                                    firstDue: .afterInterval(.weeks(6)),
                                    reminders: profile([2], .comfort, grace: 14), isSuggested: false),
            ],
            components: BuiltInComponents.pet,
            pockets: [.upcoming, .documents, .history, .people, .money, .keyFacts]
        )
    }

    public static var health: TemplateDefinition {
        TemplateDefinition(
            key: Key.health,
            name: String(localized: "Sănătate", comment: "Category name"),
            summary: String(localized: "Analize, controale, vaccinuri și date de urgență.", comment: "Category summary"),
            symbol: "heart.text.square.fill",
            tint: .pink,
            isSensitiveByDefault: true,
            sections: [
                FieldSection(key: "health.person", title: String(localized: "Persoană"), fields: [
                    FieldDefinition(key: "health.birthDate", label: String(localized: "Data nașterii"), type: .date, role: .startDate),
                    FieldDefinition(key: "health.bloodType", label: String(localized: "Grupa sanguină"), type: .choice, role: .keyFact, isSensitive: true,
                                    options: BloodType.options),
                    FieldDefinition(key: "health.allergies", label: String(localized: "Alergii"), type: .longText, isSensitive: true),
                    FieldDefinition(key: "health.conditions", label: String(localized: "Afecțiuni cronice"), type: .longText, isSensitive: true),
                    FieldDefinition(key: "health.medication", label: String(localized: "Tratament curent"), type: .longText, isSensitive: true),
                ]),
            ],
            blueprints: [
                ObligationBlueprint(key: "health.checkup", title: String(localized: "Analize anuale"), kind: .health, recurrence: .interval(.years(1), anchor: .completion),
                                    firstDue: .afterInterval(.years(1)),
                                    reminders: profile([14, 0], .health, grace: 30)),
                ObligationBlueprint(key: "health.dentist", title: String(localized: "Control stomatologic"), kind: .health, recurrence: .interval(.months(6), anchor: .completion),
                                    firstDue: .afterInterval(.months(6)),
                                    reminders: profile([7, 0], .health, grace: 30)),
                ObligationBlueprint(key: "health.tetanus", title: String(localized: "Rapel antitetanos"), kind: .health, recurrence: .interval(.years(10), anchor: .completion), firstDue: .ask,
                                    reminders: profile([30, 0], .health, grace: 30), isSuggested: false),
                ObligationBlueprint(key: "health.flu", title: String(localized: "Vaccin antigripal"), kind: .health, recurrence: .fixedDates([MonthDay(month: 10, day: 15)]),
                                    firstDue: .nextFixedDate,
                                    reminders: profile([7, 0], .health, grace: 30), isSuggested: false),
                ObligationBlueprint(key: "health.euCard", title: String(localized: "Card european de sănătate"), kind: .renewal, recurrence: .interval(.years(2), anchor: .completion),
                                    firstDue: .ask,
                                    reminders: profile([30, 7], .financial), isSuggested: false),
            ],
            pockets: [.upcoming, .documents, .history, .people, .keyFacts]
        )
    }

    /// One asset per product: what it is, where and when it was bought, what it
    /// cost, and how long the legal guarantee lasts (24 months for new consumer
    /// goods, OUG 140/2021). Answers "cât am plătit pe aragaz" and "când am luat hota".
    public static var purchase: TemplateDefinition {
        TemplateDefinition(
            key: Key.purchase,
            name: String(localized: "Garanții", comment: "Category name"),
            summary: String(localized: "Ce ai cumpărat, cât a costat și până când e în garanție.", comment: "Category summary"),
            symbol: "shield.lefthalf.filled",
            tint: .teal,
            heroStyle: .document,
            sections: [
                FieldSection(key: "purchase.product", title: String(localized: "Produs"), fields: [
                    FieldDefinition(key: "purchase.brand", label: String(localized: "Marcă"), type: .text, role: .subtitle),
                    FieldDefinition(key: "purchase.model", label: String(localized: "Model"), type: .text, role: .subtitle),
                    FieldDefinition(key: "purchase.serial", label: String(localized: "Serie sau IMEI"), type: .text, role: .identifier),
                ]),
                FieldSection(key: "purchase.bought", title: String(localized: "Cumpărare"), fields: [
                    FieldDefinition(key: "purchase.retailer", label: String(localized: "Magazin"), type: .text, role: .retailer, isEssential: true),
                    FieldDefinition(key: "purchase.date", label: String(localized: "Data cumpărării"), type: .date, role: .purchaseDate, isEssential: true),
                    FieldDefinition(key: "purchase.price", label: String(localized: "Preț"), type: .money, role: .purchasePrice, isEssential: true),
                ]),
                FieldSection(key: "purchase.coverage", title: String(localized: "Garanție"), fields: [
                    FieldDefinition(key: "purchase.warrantyMonths", label: String(localized: "Garanție (luni)"), type: .number, unit: String(localized: "luni"),
                                    defaultValue: .number(24)),
                    FieldDefinition(key: "purchase.warrantyUntil", label: String(localized: "Garanția expiră"), type: .expiryDate, role: .warrantyUntil,
                                    derivation: .addMonths(dateField: "purchase.date", monthsField: "purchase.warrantyMonths")),
                    FieldDefinition(key: "purchase.manualUrl", label: String(localized: "Manual de utilizare"), type: .url),
                ]),
            ],
            blueprints: [
                ObligationBlueprint(key: "purchase.warrantyEnds", title: String(localized: "Garanția se termină"), kind: .renewal, recurrence: .none,
                                    firstDue: .field(key: "purchase.warrantyUntil", offsetDays: 0),
                                    reminders: profile([30], .financial, followUp: false),
                                    note: String(localized: "Funcționează totul bine? Acum mai poți reclama gratuit un defect.")),
            ],
            pockets: [.upcoming, .documents, .history, .money, .keyFacts]
        )
    }

    /// A provider, a price per billing cycle and, for fixed-term contracts, the end
    /// date. Reminds about yearly renewals and contract ends, not monthly charges.
    public static var subscription: TemplateDefinition {
        TemplateDefinition(
            key: Key.subscription,
            name: String(localized: "Abonamente", comment: "Category name"),
            summary: String(localized: "Reînnoiri anuale și contracte care se termină.", comment: "Category summary"),
            symbol: "creditcard.fill",
            tint: .purple,
            sections: [
                FieldSection(key: "subscription.main", title: String(localized: "Abonament"), fields: [
                    FieldDefinition(key: "subscription.provider", label: String(localized: "Furnizor"), type: .text, role: .subtitle, isEssential: true),
                    FieldDefinition(key: "subscription.price", label: String(localized: "Preț"), type: .money, role: .heroMetric, isEssential: true),
                    FieldDefinition(key: "subscription.cycle", label: String(localized: "Se plătește"), type: .choice, isEssential: true,
                                    options: BillingCycle.options, defaultValue: .text(BillingCycle.monthly)),
                    FieldDefinition(key: "subscription.renewalDate", label: String(localized: "Următoarea reînnoire"), type: .date),
                    FieldDefinition(key: "subscription.contractEnd", label: String(localized: "Contract până la"), type: .expiryDate, role: .expiryDate),
                    FieldDefinition(key: "subscription.cancelUrl", label: String(localized: "Unde anulezi"), type: .url),
                    FieldDefinition(key: "subscription.card", label: String(localized: "Card (ultimele 4 cifre)"), type: .text, isSensitive: true),
                ]),
            ],
            blueprints: [
                ObligationBlueprint(key: "subscription.renewal", title: String(localized: "Reînnoire anuală"), kind: .payment,
                                    recurrence: .interval(.years(1), anchor: .dueDate),
                                    firstDue: .field(key: "subscription.renewalDate", offsetDays: 0),
                                    reminders: profile([14], .financial, followUp: false),
                                    appliesWhen: BlueprintCondition(field: "subscription.cycle", oneOf: [BillingCycle.yearly]),
                                    note: String(localized: "Decide dacă îl mai vrei înainte să se plătească singur.")),
                ObligationBlueprint(key: "subscription.contractEnd", title: String(localized: "Se termină contractul"), kind: .renewal, recurrence: .none,
                                    firstDue: .field(key: "subscription.contractEnd", offsetDays: 0),
                                    reminders: profile([30], .financial, followUp: false),
                                    note: String(localized: "De obicei prețul crește după. E momentul să ceri o ofertă mai bună.")),
            ],
            pockets: [.upcoming, .documents, .money, .keyFacts]
        )
    }

    public static var other: TemplateDefinition {
        TemplateDefinition(
            key: Key.other,
            name: String(localized: "Altele", comment: "Category name"),
            summary: String(localized: "Orice altceva, cu scadențele tale.", comment: "Category summary"),
            symbol: "square.grid.2x2.fill",
            tint: .gray,
            sections: [
                FieldSection(key: "other.main", title: String(localized: "Detalii"), fields: [
                    FieldDefinition(key: "other.description", label: String(localized: "Descriere scurtă"), type: .text, role: .subtitle),
                    FieldDefinition(key: "other.identifier", label: String(localized: "Serie sau cod"), type: .text, role: .identifier),
                ]),
                PurchaseFields.section(prefix: "other"),
            ],
            pockets: SectionPocket.standard
        )
    }

    // MARK: Starters (hidden from home until chosen)

    public static var bike: TemplateDefinition {
        TemplateDefinition(
            key: Key.bike,
            name: String(localized: "Biciclete", comment: "Category name"),
            summary: String(localized: "Lanț, frâne și service, după kilometri.", comment: "Category summary"),
            symbol: "bicycle",
            tint: .green,
            isOnHomeByDefault: false,
            sections: [
                FieldSection(key: "bike.main", title: String(localized: "Bicicletă"), fields: [
                    FieldDefinition(key: "bike.brand", label: String(localized: "Marcă"), type: .text, role: .subtitle, isEssential: true),
                    FieldDefinition(key: "bike.model", label: String(localized: "Model"), type: .text, role: .subtitle),
                    FieldDefinition(key: "bike.odometer", label: String(localized: "Kilometri parcurși"), type: .metric, role: .heroMetric, isEssential: true, unit: "km"),
                    FieldDefinition(key: "bike.serial", label: String(localized: "Serie cadru"), type: .text, role: .identifier),
                ]),
                PurchaseFields.section(prefix: "bike"),
            ],
            blueprints: [
                ObligationBlueprint(key: "bike.chainLube", title: String(localized: "Curățare și ungere lanț"), kind: .routine,
                                    recurrence: .metric(every: 150, unit: "km", fallback: .months(1)), firstDue: .afterInterval(.months(1)),
                                    reminders: profile([0], .comfort, grace: 7)),
                ObligationBlueprint(key: "bike.brakes", title: String(localized: "Verificare plăcuțe de frână"), kind: .maintenance,
                                    recurrence: .metric(every: 1_000, unit: "km", fallback: .months(6)), firstDue: .afterInterval(.months(6)),
                                    reminders: profile([3, 0], .comfort, grace: 14)),
                ObligationBlueprint(key: "bike.chain", title: String(localized: "Schimb lanț"), kind: .maintenance,
                                    recurrence: .metric(every: 2_000, unit: "km", fallback: .years(1)), firstDue: .afterInterval(.years(1)),
                                    reminders: profile([7, 0], .comfort, grace: 30)),
                ObligationBlueprint(key: "bike.fork", title: String(localized: "Service suspensie"), kind: .maintenance,
                                    recurrence: .interval(.years(1), anchor: .completion), firstDue: .afterInterval(.years(1)),
                                    reminders: profile([7], .comfort, grace: 30), isSuggested: false),
            ],
            components: BuiltInComponents.bike,
            pockets: [.upcoming, .history, .people, .money, .keyFacts]
        )
    }

    public static var plants: TemplateDefinition {
        TemplateDefinition(
            key: Key.plants,
            name: String(localized: "Plante", comment: "Category name"),
            summary: String(localized: "Udat, fertilizat și schimbat ghiveciul.", comment: "Category summary"),
            symbol: "leaf.fill",
            tint: .mint,
            isOnHomeByDefault: false,
            sections: [
                FieldSection(key: "plants.main", title: String(localized: "Plantă"), fields: [
                    FieldDefinition(key: "plants.species", label: String(localized: "Specie"), type: .text, role: .subtitle, isEssential: true),
                    FieldDefinition(key: "plants.place", label: String(localized: "Unde stă"), type: .text, role: .location),
                ]),
            ],
            blueprints: [
                ObligationBlueprint(key: "plants.water", title: String(localized: "Udat"), kind: .routine, recurrence: .interval(.days(7), anchor: .completion),
                                    firstDue: .afterInterval(.days(7)),
                                    reminders: profile([0], .comfort, grace: 2)),
                ObligationBlueprint(key: "plants.feed", title: String(localized: "Fertilizat"), kind: .routine, recurrence: .interval(.months(1), anchor: .completion),
                                    firstDue: .afterInterval(.months(1)),
                                    reminders: profile([0], .comfort, grace: 7)),
                ObligationBlueprint(key: "plants.repot", title: String(localized: "Schimbat ghiveciul"), kind: .routine, recurrence: .interval(.years(2), anchor: .completion),
                                    firstDue: .afterInterval(.years(2)),
                                    reminders: profile([7], .comfort, grace: 30), isSuggested: false),
            ],
            pockets: [.upcoming, .history, .keyFacts]
        )
    }

    /// A tenancy filed under a property: who rents it, the contract, the rent,
    /// the deposit and the meter readings at move-in and move-out. While any
    /// tenancy exists, the household gets the yearly income declaration
    /// (see `HouseholdRules`).
    public static var tenancy: TemplateDefinition {
        TemplateDefinition(
            key: Key.tenancy,
            name: String(localized: "Chiriași", comment: "Category name"),
            summary: String(localized: "Contractul, chiria, garanția și indexurile la mutare.", comment: "Category summary"),
            symbol: "person.2.fill",
            tint: .cyan,
            isOnHomeByDefault: false,
            sections: [
                FieldSection(key: "tenancy.contract", title: String(localized: "Contract"), fields: [
                    FieldDefinition(key: "tenancy.start", label: String(localized: "Început contract"), type: .date, role: .startDate, isEssential: true),
                    FieldDefinition(key: "tenancy.end", label: String(localized: "Sfârșit contract"), type: .expiryDate, role: .expiryDate, isEssential: true),
                ]),
                FieldSection(key: "tenancy.money", title: String(localized: "Bani"), fields: [
                    FieldDefinition(key: "tenancy.rent", label: String(localized: "Chirie lunară"), type: .money, role: .heroMetric, isEssential: true),
                    FieldDefinition(key: "tenancy.paymentDay", label: String(localized: "Ziua de plată"), type: .number, placeholder: "5"),
                    FieldDefinition(key: "tenancy.deposit", label: String(localized: "Garanție încasată"), type: .money),
                ]),
            ],
            blueprints: [
                ObligationBlueprint(key: "tenancy.end", title: String(localized: "Se termină contractul de închiriere"), kind: .renewal, recurrence: .none,
                                    firstDue: .field(key: "tenancy.end", offsetDays: 0),
                                    reminders: profile([60], .financial, followUp: false),
                                    note: String(localized: "Timp să vorbiți despre prelungire sau să cauți alt chiriaș.")),
            ],
            pockets: [.upcoming, .documents, .people, .money, .keyFacts]
        )
    }

    /// A household member, by name only. Their personal documents are filed under
    /// them, so the Acte box can group documents by holder.
    public static var member: TemplateDefinition {
        TemplateDefinition(
            key: Key.member,
            name: String(localized: "Membri ai familiei", comment: "Category name"),
            summary: String(localized: "Cui aparțin actele.", comment: "Category summary"),
            symbol: "person.crop.circle",
            tint: .indigo,
            isOnHomeByDefault: false,
            sections: [],
            pockets: [.upcoming, .documents, .keyFacts]
        )
    }

    public static var espresso: TemplateDefinition {
        TemplateDefinition(
            key: Key.espresso,
            name: String(localized: "Espressoare", comment: "Category name"),
            summary: String(localized: "Curățare, decalcifiere și filtre, după numărul de cafele.", comment: "Category summary"),
            symbol: "cup.and.saucer.fill",
            tint: .brown,
            isOnHomeByDefault: false,
            sections: [
                FieldSection(key: "espresso.main", title: String(localized: "Aparat"), fields: [
                    FieldDefinition(key: "espresso.brand", label: String(localized: "Marcă"), type: .text, role: .subtitle, isEssential: true),
                    FieldDefinition(key: "espresso.model", label: String(localized: "Model"), type: .text, role: .subtitle),
                    FieldDefinition(key: "espresso.shots", label: String(localized: "Cafele făcute"), type: .metric, role: .heroMetric, unit: String(localized: "cafele")),
                ]),
                PurchaseFields.section(prefix: "espresso"),
            ],
            blueprints: [
                ObligationBlueprint(key: "espresso.backflush", title: String(localized: "Curățare grup"), kind: .routine,
                                    recurrence: .metric(every: 100, unit: String(localized: "cafele"), fallback: .weeks(2)), firstDue: .afterInterval(.weeks(2)),
                                    reminders: profile([0], .comfort, grace: 3)),
                ObligationBlueprint(key: "espresso.descale", title: String(localized: "Decalcifiere"), kind: .maintenance,
                                    recurrence: .metric(every: 300, unit: String(localized: "cafele"), fallback: .months(2)), firstDue: .afterInterval(.months(2)),
                                    reminders: profile([3, 0], .comfort, grace: 14)),
                ObligationBlueprint(key: "espresso.filter", title: String(localized: "Schimb filtru de apă"), kind: .maintenance,
                                    recurrence: .interval(.months(2), anchor: .completion), firstDue: .afterInterval(.months(2)),
                                    reminders: profile([3, 0], .comfort, grace: 14)),
            ],
            components: BuiltInComponents.espresso,
            pockets: [.upcoming, .history, .money, .keyFacts]
        )
    }
}

/// The same purchase facts on every category that holds things you buy, so
/// "how much did I pay" and "when did I buy it" work for any asset.
public enum PurchaseFields {
    public static func section(prefix: String) -> FieldSection {
        FieldSection(key: "\(prefix).purchase", title: String(localized: "Cumpărare"), fields: [
            FieldDefinition(key: "\(prefix).purchaseDate", label: String(localized: "Data cumpărării"), type: .date, role: .purchaseDate),
            FieldDefinition(key: "\(prefix).purchasePrice", label: String(localized: "Preț"), type: .money, role: .purchasePrice),
            FieldDefinition(key: "\(prefix).retailer", label: String(localized: "Cumpărat de la"), type: .text, role: .retailer),
            FieldDefinition(key: "\(prefix).warrantyUntil", label: String(localized: "Garanție până la"), type: .expiryDate, role: .warrantyUntil),
        ])
    }
}

