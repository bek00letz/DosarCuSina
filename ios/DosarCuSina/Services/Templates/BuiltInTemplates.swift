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
        [vehicle, home, documents, pet, health, warranty, subscription, other, bike, plants, rental, espresso]
    }

    public static func definition(for key: String) -> TemplateDefinition? {
        all.first { $0.key == key }
    }

    // MARK: Keys

    public enum Key {
        public static let vehicle = "vehicle"
        public static let home = "home"
        public static let documents = "documents"
        public static let pet = "pet"
        public static let health = "health"
        public static let warranty = "warranty"
        public static let subscription = "subscription"
        public static let other = "other"
        public static let bike = "bike"
        public static let plants = "plants"
        public static let rental = "rental"
        public static let espresso = "espresso"
    }

    private static func ron(_ amount: Decimal) -> Money { Money(amount, currency: "RON") }

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
                    FieldDefinition(key: "vehicle.year", label: String(localized: "An de fabricație"), type: .number, role: .subtitle, isEssential: true, placeholder: "2018"),
                    FieldDefinition(key: "vehicle.vin", label: String(localized: "Serie de șasiu (VIN)"), type: .vin),
                    FieldDefinition(key: "vehicle.civ", label: String(localized: "Serie CIV"), type: .text),
                ]),
                FieldSection(key: "vehicle.technical", title: String(localized: "Date tehnice"), fields: [
                    FieldDefinition(key: "vehicle.odometer", label: String(localized: "Kilometraj"), type: .metric, role: .heroMetric, isEssential: true, unit: "km"),
                    FieldDefinition(key: "vehicle.fuel", label: String(localized: "Combustibil"), type: .choice, options: [
                        String(localized: "Benzină"), String(localized: "Motorină"), String(localized: "Hibrid"),
                        String(localized: "Hibrid plug-in"), String(localized: "Electric"), String(localized: "GPL"),
                    ]),
                    FieldDefinition(key: "vehicle.engineCc", label: String(localized: "Capacitate cilindrică"), type: .number, unit: "cm³"),
                    FieldDefinition(key: "vehicle.powerHp", label: String(localized: "Putere"), type: .number, unit: "CP"),
                    FieldDefinition(key: "vehicle.usage", label: String(localized: "Folosire"), type: .choice, options: [
                        VehicleUsage.personal, VehicleUsage.commercial,
                    ]),
                ]),
                FieldSection(key: "vehicle.people", title: String(localized: "Oameni de încredere"), fields: [
                    FieldDefinition(key: "vehicle.mechanic", label: String(localized: "Service sau mecanic"), type: .contact, role: .contact),
                    FieldDefinition(key: "vehicle.insurer", label: String(localized: "Asigurător"), type: .text),
                ]),
            ],
            blueprints: [
                ObligationBlueprint(key: "vehicle.itp", title: String(localized: "ITP"), kind: .legal, recurrence: .legal(.vehicleITP), firstDue: .ask,
                                    estimatedCost: ron(180), note: String(localized: "Fără ITP valabil, înmatricularea se suspendă.")),
                ObligationBlueprint(key: "vehicle.rca", title: String(localized: "RCA"), kind: .insurance, recurrence: .interval(.years(1), anchor: .dueDate), firstDue: .ask,
                                    reminderOffsetsDays: [30, 14, 7, 1, 0], note: String(localized: "Cere oferte cu o lună înainte, prețurile diferă mult.")),
                ObligationBlueprint(key: "vehicle.vignette", title: String(localized: "Rovinietă"), kind: .legal, recurrence: .interval(.months(12), anchor: .completion), firstDue: .ask,
                                    reminderOffsetsDays: [7, 1, 0]),
                ObligationBlueprint(key: "vehicle.service", title: String(localized: "Revizie periodică"), kind: .maintenance,
                                    recurrence: .metric(every: 15_000, unit: "km", fallback: .years(1)), firstDue: .afterInterval(.years(1)),
                                    reminderOffsetsDays: [14, 1]),
                ObligationBlueprint(key: "vehicle.tyres", title: String(localized: "Schimb de anvelope"), kind: .maintenance,
                                    recurrence: .fixedDates([MonthDay(month: 4, day: 15), MonthDay(month: 11, day: 1)]), firstDue: .nextFixedDate,
                                    reminderOffsetsDays: [7, 0]),
                ObligationBlueprint(key: "vehicle.casco", title: String(localized: "CASCO"), kind: .insurance, recurrence: .interval(.years(1), anchor: .dueDate), firstDue: .ask,
                                    reminderOffsetsDays: [30, 7, 1, 0], isSuggested: false),
                ObligationBlueprint(key: "vehicle.kit", title: String(localized: "Trusă medicală și stingător"), kind: .legal, recurrence: .none, firstDue: .ask,
                                    reminderOffsetsDays: [14, 0], isSuggested: false, note: String(localized: "Data expirării e pe ambalaj.")),
            ]
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
                    FieldDefinition(key: "home.year", label: String(localized: "An construcție"), type: .number),
                    FieldDefinition(key: "home.cadastral", label: String(localized: "Număr cadastral"), type: .text),
                ]),
                FieldSection(key: "home.utilities", title: String(localized: "Utilități"), fields: [
                    FieldDefinition(key: "home.pod", label: String(localized: "Cod loc de consum energie (POD)"), type: .text),
                    FieldDefinition(key: "home.clc", label: String(localized: "Cod loc de consum gaze (CLC)"), type: .text),
                    FieldDefinition(key: "home.waterCode", label: String(localized: "Cod client apă"), type: .text),
                    FieldDefinition(key: "home.meterReadFrom", label: String(localized: "Autocitire de la ziua"), type: .number),
                    FieldDefinition(key: "home.meterReadTo", label: String(localized: "Autocitire până la ziua"), type: .number),
                ]),
                FieldSection(key: "home.heating", title: String(localized: "Centrală termică"), fields: [
                    FieldDefinition(key: "home.boilerModel", label: String(localized: "Model"), type: .text),
                    FieldDefinition(key: "home.boilerSerial", label: String(localized: "Serie"), type: .text),
                    FieldDefinition(key: "home.technician", label: String(localized: "Tehnician"), type: .contact, role: .contact),
                ]),
            ],
            blueprints: [
                ObligationBlueprint(key: "home.boilerCheck", title: String(localized: "Verificare centrală (VTP)"), kind: .legal, recurrence: .interval(.years(2), anchor: .completion), firstDue: .ask,
                                    note: String(localized: "Obligatorie la cel mult 2 ani, făcută de o firmă autorizată ISCIR.")),
                ObligationBlueprint(key: "home.gasCheck", title: String(localized: "Verificare instalație de gaze"), kind: .legal, recurrence: .interval(.years(2), anchor: .completion), firstDue: .ask),
                ObligationBlueprint(key: "home.gasRevision", title: String(localized: "Revizie instalație de gaze"), kind: .legal, recurrence: .interval(.years(10), anchor: .completion), firstDue: .ask,
                                    isSuggested: false),
                ObligationBlueprint(key: "home.pad", title: String(localized: "Asigurare obligatorie (PAD)"), kind: .insurance, recurrence: .interval(.years(1), anchor: .dueDate), firstDue: .ask,
                                    estimatedCost: ron(130)),
                ObligationBlueprint(key: "home.buildingTax", title: String(localized: "Impozit pe clădire"), kind: .tax,
                                    recurrence: .fixedDates([MonthDay(month: 3, day: 31), MonthDay(month: 9, day: 30)]), firstDue: .nextFixedDate,
                                    reminderOffsetsDays: [14, 3, 0], note: String(localized: "Plata integrală până la 31 martie poate aduce o reducere.")),
                ObligationBlueprint(key: "home.chimney", title: String(localized: "Curățare coș de fum"), kind: .maintenance, recurrence: .interval(.years(1), anchor: .completion), firstDue: .ask,
                                    reminderOffsetsDays: [14, 0], isSuggested: false),
            ]
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
                    FieldDefinition(key: "document.type", label: String(localized: "Tip"), type: .choice, role: .subtitle, isEssential: true, options: [
                        String(localized: "Carte de identitate"), String(localized: "Pașaport"), String(localized: "Permis de conducere"),
                        String(localized: "Card bancar"), String(localized: "Semnătură electronică"), String(localized: "Cazier"), String(localized: "Alt document"),
                    ]),
                    FieldDefinition(key: "document.number", label: String(localized: "Serie și număr"), type: .text, role: .identifier, isSensitive: true),
                    FieldDefinition(key: "document.holder", label: String(localized: "Titular"), type: .text),
                    FieldDefinition(key: "document.issuer", label: String(localized: "Emis de"), type: .text),
                    FieldDefinition(key: "document.issueDate", label: String(localized: "Data emiterii"), type: .date, role: .startDate),
                    FieldDefinition(key: "document.expiry", label: String(localized: "Valabil până la"), type: .expiryDate, role: .expiry, isEssential: true),
                ]),
            ],
            blueprints: [
                ObligationBlueprint(key: "document.renew", title: String(localized: "Reînnoire"), kind: .renewal, recurrence: .none,
                                    firstDue: .field(key: "document.expiry", offsetDays: 0), reminderOffsetsDays: [180, 90, 30, 7, 0],
                                    note: String(localized: "Programările durează. Pentru pașaport, multe țări cer 6 luni de valabilitate.")),
            ]
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
                    FieldDefinition(key: "pet.species", label: String(localized: "Specie"), type: .choice, role: .subtitle, isEssential: true, options: [
                        String(localized: "Pisică"), String(localized: "Câine"), String(localized: "Alt animal"),
                    ]),
                    FieldDefinition(key: "pet.breed", label: String(localized: "Rasă"), type: .text, role: .subtitle),
                    FieldDefinition(key: "pet.birthDate", label: String(localized: "Data nașterii"), type: .date, role: .startDate, isEssential: true),
                    FieldDefinition(key: "pet.microchip", label: String(localized: "Microcip"), type: .microchip, role: .identifier),
                    FieldDefinition(key: "pet.passport", label: String(localized: "Pașaport european"), type: .text),
                    FieldDefinition(key: "pet.weight", label: String(localized: "Greutate"), type: .number, role: .heroMetric, unit: "kg"),
                ]),
                FieldSection(key: "pet.care", title: String(localized: "Îngrijire"), fields: [
                    FieldDefinition(key: "pet.vet", label: String(localized: "Veterinar"), type: .contact, role: .contact),
                    FieldDefinition(key: "pet.diet", label: String(localized: "Hrană și porții"), type: .longText),
                ]),
            ],
            blueprints: [
                ObligationBlueprint(key: "pet.rabies", title: String(localized: "Vaccin antirabic"), kind: .legal, recurrence: .interval(.years(1), anchor: .completion), firstDue: .ask,
                                    note: String(localized: "Obligatoriu și cerut la trecerea graniței.")),
                ObligationBlueprint(key: "pet.vaccine", title: String(localized: "Vaccin anual"), kind: .health, recurrence: .interval(.years(1), anchor: .completion), firstDue: .ask),
                ObligationBlueprint(key: "pet.dewormInternal", title: String(localized: "Deparazitare internă"), kind: .health, recurrence: .interval(.months(3), anchor: .completion),
                                    firstDue: .afterInterval(.months(3)), reminderOffsetsDays: [3, 0]),
                ObligationBlueprint(key: "pet.dewormExternal", title: String(localized: "Deparazitare externă"), kind: .health, recurrence: .interval(.months(1), anchor: .completion),
                                    firstDue: .afterInterval(.months(1)), reminderOffsetsDays: [1, 0]),
                ObligationBlueprint(key: "pet.grooming", title: String(localized: "Toaletaj"), kind: .routine, recurrence: .interval(.weeks(6), anchor: .completion),
                                    firstDue: .afterInterval(.weeks(6)), reminderOffsetsDays: [2], isSuggested: false),
            ]
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
                    FieldDefinition(key: "health.bloodType", label: String(localized: "Grupa sanguină"), type: .choice, role: .subtitle, isSensitive: true,
                                    options: ["0 I+", "0 I−", "A II+", "A II−", "B III+", "B III−", "AB IV+", "AB IV−"]),
                    FieldDefinition(key: "health.allergies", label: String(localized: "Alergii"), type: .longText, isSensitive: true),
                    FieldDefinition(key: "health.conditions", label: String(localized: "Afecțiuni cronice"), type: .longText, isSensitive: true),
                    FieldDefinition(key: "health.medication", label: String(localized: "Tratament curent"), type: .longText, isSensitive: true),
                ]),
                FieldSection(key: "health.contacts", title: String(localized: "Contacte"), fields: [
                    FieldDefinition(key: "health.doctor", label: String(localized: "Medic de familie"), type: .contact, role: .contact),
                    FieldDefinition(key: "health.emergency", label: String(localized: "Contact pentru urgențe"), type: .contact),
                ]),
            ],
            blueprints: [
                ObligationBlueprint(key: "health.checkup", title: String(localized: "Analize anuale"), kind: .health, recurrence: .interval(.years(1), anchor: .completion),
                                    firstDue: .afterInterval(.years(1)), reminderOffsetsDays: [14, 0]),
                ObligationBlueprint(key: "health.dentist", title: String(localized: "Control stomatologic"), kind: .health, recurrence: .interval(.months(6), anchor: .completion),
                                    firstDue: .afterInterval(.months(6)), reminderOffsetsDays: [7, 0]),
                ObligationBlueprint(key: "health.tetanus", title: String(localized: "Rapel antitetanos"), kind: .health, recurrence: .interval(.years(10), anchor: .completion), firstDue: .ask,
                                    reminderOffsetsDays: [30, 0], isSuggested: false),
                ObligationBlueprint(key: "health.flu", title: String(localized: "Vaccin antigripal"), kind: .health, recurrence: .fixedDates([MonthDay(month: 10, day: 15)]),
                                    firstDue: .nextFixedDate, reminderOffsetsDays: [7, 0], isSuggested: false),
                ObligationBlueprint(key: "health.euCard", title: String(localized: "Card european de sănătate"), kind: .renewal, recurrence: .interval(.years(2), anchor: .completion),
                                    firstDue: .ask, reminderOffsetsDays: [30, 7], isSuggested: false),
            ]
        )
    }

    public static var warranty: TemplateDefinition {
        TemplateDefinition(
            key: Key.warranty,
            name: String(localized: "Garanții", comment: "Category name"),
            summary: String(localized: "Bonuri și garanții, cu o alertă înainte să expire.", comment: "Category summary"),
            symbol: "shield.lefthalf.filled",
            tint: .teal,
            heroStyle: .document,
            sections: [
                FieldSection(key: "warranty.product", title: String(localized: "Produs"), fields: [
                    FieldDefinition(key: "warranty.brand", label: String(localized: "Marcă"), type: .text, role: .subtitle, isEssential: true),
                    FieldDefinition(key: "warranty.model", label: String(localized: "Model"), type: .text, role: .subtitle),
                    FieldDefinition(key: "warranty.serial", label: String(localized: "Serie sau IMEI"), type: .text, role: .identifier),
                    FieldDefinition(key: "warranty.retailer", label: String(localized: "Magazin"), type: .text),
                    FieldDefinition(key: "warranty.price", label: String(localized: "Preț"), type: .money),
                ]),
                FieldSection(key: "warranty.coverage", title: String(localized: "Garanție"), fields: [
                    FieldDefinition(key: "warranty.purchaseDate", label: String(localized: "Data cumpărării"), type: .date, role: .startDate, isEssential: true),
                    FieldDefinition(key: "warranty.expiry", label: String(localized: "Garanția expiră"), type: .expiryDate, role: .expiry, isEssential: true),
                    FieldDefinition(key: "warranty.manualUrl", label: String(localized: "Manual de utilizare"), type: .url),
                ]),
            ],
            blueprints: [
                ObligationBlueprint(key: "warranty.lastCheck", title: String(localized: "Verifică produsul cât e în garanție"), kind: .renewal, recurrence: .none,
                                    firstDue: .field(key: "warranty.expiry", offsetDays: -30), reminderOffsetsDays: [7, 0],
                                    note: String(localized: "O lună înainte de expirare, ca să mai poți cere reparații gratuite.")),
            ]
        )
    }

    public static var subscription: TemplateDefinition {
        TemplateDefinition(
            key: Key.subscription,
            name: String(localized: "Abonamente", comment: "Category name"),
            summary: String(localized: "Plăți recurente, perioade de probă și contracte.", comment: "Category summary"),
            symbol: "creditcard.fill",
            tint: .purple,
            sections: [
                FieldSection(key: "subscription.main", title: String(localized: "Abonament"), fields: [
                    FieldDefinition(key: "subscription.provider", label: String(localized: "Furnizor"), type: .text, role: .subtitle, isEssential: true),
                    FieldDefinition(key: "subscription.price", label: String(localized: "Cost pe perioadă"), type: .money, role: .heroMetric, isEssential: true),
                    FieldDefinition(key: "subscription.cycle", label: String(localized: "Se plătește"), type: .choice, isEssential: true, options: [
                        BillingCycle.monthly, BillingCycle.quarterly, BillingCycle.yearly,
                    ]),
                    FieldDefinition(key: "subscription.nextPayment", label: String(localized: "Următoarea plată"), type: .date, isEssential: true),
                    FieldDefinition(key: "subscription.trialEnd", label: String(localized: "Perioada de probă se termină"), type: .date),
                    FieldDefinition(key: "subscription.contractEnd", label: String(localized: "Contract până la"), type: .expiryDate, role: .expiry),
                    FieldDefinition(key: "subscription.cancelUrl", label: String(localized: "Unde anulezi"), type: .url),
                    FieldDefinition(key: "subscription.card", label: String(localized: "Card (ultimele 4 cifre)"), type: .text, isSensitive: true),
                ]),
            ],
            blueprints: [
                ObligationBlueprint(key: "subscription.payment", title: String(localized: "Plată"), kind: .payment, recurrence: .interval(.months(1), anchor: .dueDate),
                                    firstDue: .field(key: "subscription.nextPayment", offsetDays: 0), reminderOffsetsDays: [2, 0]),
                ObligationBlueprint(key: "subscription.trial", title: String(localized: "Se termină perioada de probă"), kind: .payment, recurrence: .none,
                                    firstDue: .field(key: "subscription.trialEnd", offsetDays: 0), reminderOffsetsDays: [2, 1, 0], isSuggested: false,
                                    note: String(localized: "Anulează înainte, dacă nu vrei să plătești.")),
                ObligationBlueprint(key: "subscription.contractEnd", title: String(localized: "Se termină contractul"), kind: .renewal, recurrence: .none,
                                    firstDue: .field(key: "subscription.contractEnd", offsetDays: 0), reminderOffsetsDays: [30, 7], isSuggested: false,
                                    note: String(localized: "Un moment bun să ceri o ofertă mai bună.")),
            ]
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
            ]
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
            ],
            blueprints: [
                ObligationBlueprint(key: "bike.chainLube", title: String(localized: "Curățare și ungere lanț"), kind: .routine,
                                    recurrence: .metric(every: 150, unit: "km", fallback: .months(1)), firstDue: .afterInterval(.months(1)), reminderOffsetsDays: [0]),
                ObligationBlueprint(key: "bike.brakes", title: String(localized: "Verificare plăcuțe de frână"), kind: .maintenance,
                                    recurrence: .metric(every: 1_000, unit: "km", fallback: .months(6)), firstDue: .afterInterval(.months(6)), reminderOffsetsDays: [3, 0]),
                ObligationBlueprint(key: "bike.chain", title: String(localized: "Schimb lanț"), kind: .maintenance,
                                    recurrence: .metric(every: 2_000, unit: "km", fallback: .years(1)), firstDue: .afterInterval(.years(1)), reminderOffsetsDays: [7, 0]),
                ObligationBlueprint(key: "bike.fork", title: String(localized: "Service suspensie"), kind: .maintenance,
                                    recurrence: .interval(.years(1), anchor: .completion), firstDue: .afterInterval(.years(1)), reminderOffsetsDays: [7], isSuggested: false),
            ]
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
                                    firstDue: .afterInterval(.days(7)), reminderOffsetsDays: [0]),
                ObligationBlueprint(key: "plants.feed", title: String(localized: "Fertilizat"), kind: .routine, recurrence: .interval(.months(1), anchor: .completion),
                                    firstDue: .afterInterval(.months(1)), reminderOffsetsDays: [0]),
                ObligationBlueprint(key: "plants.repot", title: String(localized: "Schimbat ghiveciul"), kind: .routine, recurrence: .interval(.years(2), anchor: .completion),
                                    firstDue: .afterInterval(.years(2)), reminderOffsetsDays: [7], isSuggested: false),
            ]
        )
    }

    public static var rental: TemplateDefinition {
        TemplateDefinition(
            key: Key.rental,
            name: String(localized: "Proprietăți închiriate", comment: "Category name"),
            summary: String(localized: "Chirie, contoare, contract și Declarația unică.", comment: "Category summary"),
            symbol: "building.2.fill",
            tint: .cyan,
            heroStyle: .home,
            isOnHomeByDefault: false,
            sections: [
                FieldSection(key: "rental.place", title: String(localized: "Proprietate"), fields: [
                    FieldDefinition(key: "rental.address", label: String(localized: "Adresă"), type: .address, role: .location, isEssential: true),
                    FieldDefinition(key: "rental.rent", label: String(localized: "Chirie lunară"), type: .money, role: .heroMetric, isEssential: true),
                    FieldDefinition(key: "rental.deposit", label: String(localized: "Garanție încasată"), type: .money),
                ]),
                FieldSection(key: "rental.lease", title: String(localized: "Contract"), fields: [
                    FieldDefinition(key: "rental.tenant", label: String(localized: "Chiriaș"), type: .contact, role: .contact, isEssential: true),
                    FieldDefinition(key: "rental.leaseStart", label: String(localized: "Început contract"), type: .date, role: .startDate),
                    FieldDefinition(key: "rental.leaseEnd", label: String(localized: "Sfârșit contract"), type: .expiryDate, role: .expiry),
                ]),
            ],
            blueprints: [
                ObligationBlueprint(key: "rental.rent", title: String(localized: "Încasare chirie"), kind: .payment, recurrence: .interval(.months(1), anchor: .dueDate), firstDue: .ask,
                                    reminderOffsetsDays: [0]),
                ObligationBlueprint(key: "rental.meters", title: String(localized: "Citire contoare la chiriaș"), kind: .routine, recurrence: .interval(.months(1), anchor: .dueDate),
                                    firstDue: .afterInterval(.months(1)), reminderOffsetsDays: [0], isSuggested: false),
                ObligationBlueprint(key: "rental.declaration", title: String(localized: "Declarația unică (formularul 212)"), kind: .tax,
                                    recurrence: .fixedDates([MonthDay(month: 5, day: 25)]), firstDue: .nextFixedDate, reminderOffsetsDays: [30, 7, 1, 0]),
                ObligationBlueprint(key: "rental.leaseEnd", title: String(localized: "Se termină contractul de închiriere"), kind: .renewal, recurrence: .none,
                                    firstDue: .field(key: "rental.leaseEnd", offsetDays: 0), reminderOffsetsDays: [60, 30, 7]),
            ]
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
            ],
            blueprints: [
                ObligationBlueprint(key: "espresso.backflush", title: String(localized: "Curățare grup"), kind: .routine,
                                    recurrence: .metric(every: 100, unit: String(localized: "cafele"), fallback: .weeks(2)), firstDue: .afterInterval(.weeks(2)), reminderOffsetsDays: [0]),
                ObligationBlueprint(key: "espresso.descale", title: String(localized: "Decalcifiere"), kind: .maintenance,
                                    recurrence: .metric(every: 300, unit: String(localized: "cafele"), fallback: .months(2)), firstDue: .afterInterval(.months(2)), reminderOffsetsDays: [3, 0]),
                ObligationBlueprint(key: "espresso.filter", title: String(localized: "Schimb filtru de apă"), kind: .maintenance,
                                    recurrence: .interval(.months(2), anchor: .completion), firstDue: .afterInterval(.months(2)), reminderOffsetsDays: [3, 0]),
            ]
        )
    }
}

/// Choice values the engine reads. Kept as constants so the template and the rules agree.
public enum VehicleUsage {
    public static var personal: String { String(localized: "Personală", comment: "Vehicle usage option") }
    public static var commercial: String { String(localized: "Ridesharing sau taxi", comment: "Vehicle usage option") }
}

public enum BillingCycle {
    public static var monthly: String { String(localized: "Lunar", comment: "Billing cycle option") }
    public static var quarterly: String { String(localized: "Trimestrial", comment: "Billing cycle option") }
    public static var yearly: String { String(localized: "Anual", comment: "Billing cycle option") }
}
