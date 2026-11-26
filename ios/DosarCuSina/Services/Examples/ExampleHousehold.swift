import Foundation

/// The example household ("Explore with examples"), declared once as data: every step the loader
/// takes, in the order it takes them. A section with its values, the first days of its deadlines
/// and the section it is filed under; a person or firm who works on sections; a record of a
/// section's history; a reading; a completion from before the binder knew its deadline.
///
/// `ExampleDataService` makes each step through the app's actions. `ExampleHouseholdExportTests`
/// writes the same declaration to shared/catalog/examples/household.json, which the Android app
/// loads through its own actions, so both apps load one household and neither keeps a copy of its
/// own (docs/ANDROID_PLAN.md, "How parity is kept", item 1). Days and moments are counted from the
/// moment the examples load. Made-up data only: no real people, plates or identifiers.
struct ExampleHousehold: Encodable, Sendable {
    var steps: [Step]

    /// One thing the loader makes, through one action.
    enum Step: Encodable, Sendable {
        case section(Section)
        case firm(Firm)
        case record(Record)
        case pastCompletion(PastCompletion)
        case reading(Reading)

        private enum Key: String, CodingKey { case section, firm, record, pastCompletion, reading }

        /// One key naming the kind of step, holding the step.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            switch self {
            case .section(let section): try container.encode(section, forKey: .section)
            case .firm(let firm): try container.encode(firm, forKey: .firm)
            case .record(let record): try container.encode(record, forKey: .record)
            case .pastCompletion(let completion): try container.encode(completion, forKey: .pastCompletion)
            case .reading(let reading): try container.encode(reading, forKey: .reading)
            }
        }
    }

    /// A value of a section's field: as a section keeps it, or a day counted from today.
    enum Value: Encodable, Sendable {
        case kept(FieldValue)
        /// The day this many days from the day the examples load (negative: before it).
        case dayFromToday(Int)

        private enum Key: String, CodingKey { case type, days }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .kept(let value):
                try value.encode(to: encoder)
            case .dayFromToday(let days):
                var container = encoder.container(keyedBy: Key.self)
                try container.encode("dayFromToday", forKey: .type)
                try container.encode(days, forKey: .days)
            }
        }

        /// The value a section keeps, on `today`.
        func value(on today: CalendarDay, calendar: Calendar) -> FieldValue {
            switch self {
            case .kept(let value): value
            case .dayFromToday(let days): .date(today.adding(days: days, calendar: calendar))
            }
        }
    }

    /// A section, made with `AssetActions.create`, its deadlines planned as adding a section plans them.
    struct Section: Encodable, Sendable {
        /// The name the steps after it know it by.
        var ref: String
        var category: String
        var name: String
        var values: [String: Value] = [:]
        /// The first day of each deadline the example gives, by its blueprint, in days from today.
        /// Which deadlines start ticked is the add flow's one rule (`PlannedObligation.startsSelected`).
        var firstDue: [String: Int] = [:]
        /// The ref of the section it is filed under.
        var parent: String?
    }

    /// A person or firm, made with `ProviderActions.create`, linked to the sections it works on.
    struct Firm: Encodable, Sendable {
        var ref: String
        var name: String
        var trades: [ProviderTrade]
        var phone: String?
        var linkedTo: [String]
        var rating: Int?
        var wouldCallAgain: Bool?
    }

    /// A record of a section's history, made with `HistoryActions.record`.
    struct Record: Encodable, Sendable {
        var section: String
        var kind: HistoryKind
        var title: String
        /// When it happened: this many days from the moment the examples load, at the same time of day.
        var daysFromNow: Int
        var metricReading: Double?
        var totalCost: Money?
        var items: [Item] = []
        /// The refs of the firms who did it.
        var firms: [String] = []
        var rating: Int?
    }

    /// One line of a record.
    struct Item: Encodable, Sendable {
        var name: String
        var partBrandOrCode: String?
        var cost: Money?
    }

    /// A completion from before the binder knew the deadline (last year's ITP), made with
    /// `ObligationActions.recordPastCompletion`; the deadline stays where it is.
    struct PastCompletion: Encodable, Sendable {
        var section: String
        /// The deadline's blueprint key.
        var deadline: String
        var daysFromNow: Int
        var cost: Money?
    }

    /// A reading of a section, made with `AssetActions.recordMeasurement`.
    struct Reading: Encodable, Sendable {
        var section: String
        var kind: MeasurementKind
        var name: String?
        var value: Double
        var daysFromNow: Int
    }
}

extension ExampleHousehold {
    /// The household the app loads: a car, a home with its appliances and a tenancy, a pet, a person
    /// with two documents, a medical profile and two subscriptions, with the firms who look after them.
    static var standard: ExampleHousehold {
        ExampleHousehold(steps: car + home + pet + person + health + appliances + tenancy + subscriptions)
    }

    private static var car: [Step] {
        [
            .section(Section(
                ref: "car", category: BuiltInTemplates.Key.vehicle, name: "VW Golf",
                values: [
                    "vehicle.plate": .kept(.text("B-123-ABC")),
                    "vehicle.make": .kept(.text("Volkswagen")),
                    "vehicle.model": .kept(.text("Golf")),
                    "vehicle.year": .kept(.number(2018)),
                    "vehicle.fuel": .kept(.text(FuelType.petrol)),
                    "vehicle.usage": .kept(.text(VehicleUse.personal)),
                    "vehicle.odometer": .kept(.number(142_500)),
                ],
                firstDue: ["vehicle.itp": 9, "vehicle.rca": 41, "vehicle.vignette": -2, "vehicle.service": 120]
            )),
            .pastCompletion(PastCompletion(section: "car", deadline: "vehicle.itp", daysFromNow: -721, cost: Money(170))),
            .firm(Firm(ref: "mechanic", name: String(localized: "Service auto exemplu"), trades: [.mechanic, .tyreShop],
                       phone: "0700 000 001", linkedTo: ["car"], wouldCallAgain: true)),
            .record(Record(
                section: "car", kind: .maintenance, title: String(localized: "Revizie anuală"), daysFromNow: -400,
                metricReading: 121_300, totalCost: Money(1_150),
                items: [
                    Item(name: String(localized: "Schimb ulei și filtru"), partBrandOrCode: "5W-30", cost: Money(420)),
                    Item(name: String(localized: "Plăcuțe frână față"), partBrandOrCode: "Exemplu", cost: Money(380)),
                ],
                firms: ["mechanic"], rating: 5
            )),
            .record(Record(
                section: "car", kind: .maintenance, title: String(localized: "Revizie"), daysFromNow: -120,
                metricReading: 136_200, totalCost: Money(690),
                items: [Item(name: String(localized: "Schimb ulei și filtru"), partBrandOrCode: "5W-30", cost: Money(450))],
                firms: ["mechanic"], rating: 4
            )),
        ]
    }

    private static var home: [Step] {
        [
            .section(Section(
                ref: "home", category: BuiltInTemplates.Key.home, name: String(localized: "Apartament Floreasca"),
                values: [
                    "home.address": .kept(.text("Str. Exemplului nr. 12, București")),
                    "home.area": .kept(.number(78.5)),
                    "home.meterReadFrom": .kept(.number(20)),
                    "home.meterReadTo": .kept(.number(25)),
                ],
                firstDue: ["home.boilerCheck": 200, "home.gasCheck": 310, "home.pad": 25]
            )),
            .firm(Firm(ref: "plumber", name: String(localized: "Instalator exemplu"), trades: [.plumber],
                       phone: "0700 000 002", linkedTo: ["home"])),
            .record(Record(
                section: "home", kind: .repair, title: String(localized: "Robinet nou la bucătărie"), daysFromNow: -210,
                totalCost: Money(340),
                items: [Item(name: String(localized: "Baterie bucătărie"), partBrandOrCode: "Exemplu", cost: Money(240))],
                firms: ["plumber"], rating: 5
            )),
            .record(Record(
                section: "home", kind: .purchase, title: String(localized: "Hotă nouă"), daysFromNow: -500,
                totalCost: Money(899),
                items: [Item(name: String(localized: "Hotă"), partBrandOrCode: "Exemplu 60 cm", cost: Money(899))]
            )),
        ]
    }

    private static var pet: [Step] {
        [
            .section(Section(
                ref: "pet", category: BuiltInTemplates.Key.pet, name: "Max",
                values: [
                    "pet.species": .kept(.text(PetSpecies.dog)),
                    "pet.breed": .kept(.text("Golden Retriever")),
                    "pet.birthDate": .kept(.date(CalendarDay(year: 2021, month: 5, day: 10))),
                    "pet.microchip": .kept(.text("642000000000001")),
                    "pet.weight": .kept(.number(31.5)),
                ],
                firstDue: ["pet.rabies": 60, "pet.vaccine": 60, "pet.dewormInternal": 3, "pet.dewormExternal": 12]
            )),
            // The weight it has today is the section's own value, its first reading.
            .reading(Reading(section: "pet", kind: .bodyWeight, value: 30.2, daysFromNow: -120)),
            .reading(Reading(section: "pet", kind: .bodyWeight, value: 31.0, daysFromNow: -60)),
            .firm(Firm(ref: "vet", name: String(localized: "Cabinet veterinar exemplu"), trades: [.vet],
                       phone: "0700 000 003", linkedTo: ["pet"], rating: 5)),
        ]
    }

    /// Documents are filed under the household member they belong to.
    private static var person: [Step] {
        [
            .section(Section(ref: "me", category: BuiltInTemplates.Key.member,
                             name: String(localized: "Eu", comment: "Example household member"))),
            .section(Section(
                ref: "passport", category: BuiltInTemplates.Key.documents, name: String(localized: "Pașaport"),
                values: [
                    "document.type": .kept(.text(DocumentType.passport)),
                    "document.number": .kept(.text("050000000")),
                    "document.expiry": .dayFromToday(150),
                ],
                parent: "me"
            )),
            .section(Section(
                ref: "idCard", category: BuiltInTemplates.Key.documents, name: String(localized: "Carte de identitate"),
                values: ["document.type": .kept(.text(DocumentType.idCard)), "document.expiry": .dayFromToday(900)],
                parent: "me"
            )),
        ]
    }

    private static var health: [Step] {
        [
            .section(Section(
                ref: "health", category: BuiltInTemplates.Key.health, name: String(localized: "Profil medical"),
                values: [
                    "health.bloodType": .kept(.text("bloodType.aPositive")),
                    "health.allergies": .kept(.text(String(localized: "Fără alergii cunoscute"))),
                ],
                firstDue: ["health.checkup": 45, "health.dentist": -1]
            )),
        ]
    }

    private static var appliances: [Step] {
        [
            .section(Section(
                ref: "fridge", category: BuiltInTemplates.Key.purchase, name: String(localized: "Frigider"),
                values: [
                    "purchase.brand": .kept(.text(String(localized: "Frigider combinat"))),
                    "purchase.retailer": .kept(.text(String(localized: "Magazin exemplu"))),
                    "purchase.price": .kept(.money(Money(2_499))),
                    "purchase.date": .dayFromToday(-600),
                ],
                parent: "home"
            )),
            .section(Section(
                ref: "cooker", category: BuiltInTemplates.Key.purchase, name: String(localized: "Aragaz"),
                values: [
                    "purchase.retailer": .kept(.text(String(localized: "Magazin exemplu"))),
                    "purchase.price": .kept(.money(Money(1_350))),
                    "purchase.date": .dayFromToday(-200),
                ],
                parent: "home"
            )),
        ]
    }

    private static var tenancy: [Step] {
        [
            .section(Section(
                ref: "tenancy", category: BuiltInTemplates.Key.tenancy, name: String(localized: "Chiriaș garsonieră"),
                values: [
                    "tenancy.start": .dayFromToday(-300),
                    "tenancy.end": .dayFromToday(65),
                    "tenancy.rent": .kept(.money(Money(450, currency: "EUR"))),
                    "tenancy.paymentDay": .kept(.number(5)),
                    "tenancy.deposit": .kept(.money(Money(450, currency: "EUR"))),
                ],
                parent: "home"
            )),
            .firm(Firm(ref: "tenant", name: String(localized: "Chiriaș exemplu"), trades: [.tenant],
                       phone: "0700 000 004", linkedTo: ["tenancy"])),
            .reading(Reading(section: "tenancy", kind: .coldWater, name: String(localized: "Apă rece la mutare"),
                             value: 312, daysFromNow: -300)),
        ]
    }

    private static var subscriptions: [Step] {
        [
            .section(Section(
                ref: "internet", category: BuiltInTemplates.Key.subscription, name: String(localized: "Internet fibră"),
                values: [
                    "subscription.provider": .kept(.text("Digi")),
                    SubscriptionFields.service: .kept(.text(ServiceKind.internetTV)),
                    "subscription.price": .kept(.money(Money(45))),
                    "subscription.cycle": .kept(.text(BillingCycle.monthly)),
                    "subscription.contractEnd": .dayFromToday(40),
                ]
            )),
            .section(Section(
                ref: "storage", category: BuiltInTemplates.Key.subscription, name: String(localized: "Stocare online"),
                values: [
                    "subscription.provider": .kept(.text(String(localized: "Serviciu exemplu"))),
                    SubscriptionFields.service: .kept(.text(ServiceKind.streaming)),
                    "subscription.price": .kept(.money(Money(Decimal(string: "29.99") ?? 30, currency: "EUR"))),
                    "subscription.cycle": .kept(.text(BillingCycle.yearly)),
                    "subscription.renewalDate": .dayFromToday(18),
                ]
            )),
        ]
    }
}
