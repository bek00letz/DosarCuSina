import Foundation

/// Reads schema-version 2 archives (exported by the first iOS builds) and turns
/// them into a v3 package, so older backups keep working. Nothing is dropped:
/// values without a v3 field are appended to the asset notes, contacts become
/// providers, and completed events and service records become history entries.
enum DossierV2Converter {
    static func package(from files: [String: Data], calendar: Calendar = .current) throws -> DossierV3.Package {
        let decoder = DossierV3.decoder()
        guard let manifestData = files["manifest.json"],
              let manifest = try? decoder.decode(DossierManifestV2.self, from: manifestData) else {
            throw ArchiveError.unreadableFile("manifest.json")
        }
        for (path, expected) in manifest.checksums {
            guard let data = files[path] else { throw ArchiveError.missingFile(path) }
            guard DossierArchiveReader.sha256(data) == expected.lowercased() else { throw ArchiveError.checksumMismatch(path) }
        }
        func decode<T: Decodable>(_ type: [T].Type, _ path: String) throws -> [T] {
            guard let data = files[path] else { return [] }
            do { return try decoder.decode(type, from: data) } catch { throw ArchiveError.unreadableFile(path) }
        }
        var converter = Converter(calendar: calendar)
        let assets = try decode([AssetDTO].self, "data/assets.json").map { converter.convert($0) }
        try decode([LifecycleEventDTO].self, "data/events.json").forEach { converter.convert($0) }
        try decode([ServiceItemDTO].self, "data/service_history.json").forEach { converter.convert($0) }
        let measurements = try decode([MeasurementLogDTO].self, "data/measurements.json")
        let attachments = try decode([AttachmentMetadataDTO].self, "data/attachments_meta.json")

        let measurementForAttachment = Dictionary(
            measurements.flatMap { log in log.attachmentIds.map { ($0, log.id) } },
            uniquingKeysWith: { first, _ in first }
        )
        let v3Attachments = attachments.map { meta in
            DossierV3.Attachment(
                id: DossierV3.id(meta.id), title: nil, fileName: meta.fileName, kind: DocumentKind.other.rawValue,
                contentType: contentType(forExtension: meta.fileExtension), byteCount: Int(meta.fileSizeBytes),
                sha256: meta.sha256.lowercased(), path: meta.vaultRelativePath, pagePaths: [], thumbnailPath: nil,
                extractedText: meta.extractedText, documentDate: nil, isArchived: false, supersededById: nil,
                createdAt: meta.createdAt, isExample: false, assetId: DossierV3.id(meta.assetId), obligationId: DossierV3.id(meta.eventId),
                historyEntryId: meta.eventId.flatMap { converter.entryForEvent[$0] },
                serviceItemId: nil, measurementId: DossierV3.id(measurementForAttachment[meta.id]), providerId: nil
            )
        }

        let providers = converter.providers.values.sorted { $0.name < $1.name }
        let package = DossierV3.Package(
            manifest: DossierV3.Manifest(
                format: DossierV3.format, schemaVersion: 2, appVersion: manifest.appVersion, platform: manifest.platform,
                exportedAt: manifest.exportDate,
                counts: .init(
                    templates: 0, assets: assets.count, obligations: converter.obligations.count,
                    historyEntries: converter.entries.count, serviceItems: converter.items.count, providers: providers.count,
                    measurements: measurements.count, attachments: v3Attachments.count
                ),
                checksums: manifest.checksums
            ),
            templates: [],
            assets: assets,
            obligations: converter.obligations,
            historyEntries: converter.entries,
            serviceItems: converter.items,
            providers: providers,
            measurements: measurements.map(convert),
            attachments: v3Attachments,
            files: files.filter { $0.key.hasPrefix(DossierV3.Path.vaultPrefix) }
        )
        try DossierArchiveReader.validateReferences(package)
        return package
    }

    static func templateKey(forCategory raw: String) -> String {
        switch raw {
        case "vehicle": return BuiltInTemplates.Key.vehicle
        case "home": return BuiltInTemplates.Key.home
        case "pet": return BuiltInTemplates.Key.pet
        case "health": return BuiltInTemplates.Key.health
        case "documents": return BuiltInTemplates.Key.documents
        case "warranties": return BuiltInTemplates.Key.warranty
        case "subscriptions": return BuiltInTemplates.Key.subscription
        default: return BuiltInTemplates.Key.other
        }
    }

    /// The trade of the main contact of an asset in a v2 category.
    static func trade(forCategory raw: String) -> ProviderTrade {
        switch raw {
        case "vehicle": return .mechanic
        case "home": return .handyman
        case "pet": return .vet
        case "health": return .doctor
        default: return .other
        }
    }

    /// Mutable state for one conversion: obligations, history and providers built along the way.
    struct Converter {
        let calendar: Calendar
        var categoryOf: [UUID: String] = [:]
        var obligations: [DossierV3.Obligation] = []
        var entries: [DossierV3.HistoryEntry] = []
        var items: [DossierV3.ServiceItem] = []
        /// Providers by normalized name, so the same mechanic on two cars is one record.
        var providers: [String: DossierV3.Provider] = [:]
        /// v2 event id → v3 history entry id, for completed events.
        var entryForEvent: [UUID: String] = [:]
        /// (asset, day) → history entry id, for v2 service records without an event.
        var entryForVisit: [String: String] = [:]

        init(calendar: Calendar) {
            self.calendar = calendar
        }

        // MARK: Providers

        @discardableResult
        mutating func provider(_ name: String?, phone: String?, trade: ProviderTrade, assetId: UUID?, at date: Date) -> String? {
            let cleanName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanPhone = phone.map { FieldFormatter.normalize($0, as: .phone) }.flatMap { $0.isEmpty ? nil : $0 }
            guard !cleanName.isEmpty || cleanPhone != nil else { return nil }
            let key = SearchText.normalize(cleanName.isEmpty ? (cleanPhone ?? "") : cleanName)
            var record = providers[key] ?? DossierV3.Provider(
                id: DossierV3.id(UUID()), name: cleanName.isEmpty ? (cleanPhone ?? "") : cleanName, trades: [],
                phone: cleanPhone, email: nil, address: nil, notes: nil, manualRating: nil, wouldCallAgain: nil,
                assetIds: [], isExample: false, createdAt: date, updatedAt: date
            )
            if !record.trades.contains(trade.rawValue) { record.trades.append(trade.rawValue) }
            if let assetId, !record.assetIds.contains(DossierV3.id(assetId)) { record.assetIds.append(DossierV3.id(assetId)) }
            record.phone = record.phone ?? cleanPhone
            providers[key] = record
            return record.id
        }

        // MARK: Assets

        mutating func convert(_ dto: AssetDTO) -> DossierV3.Asset {
            categoryOf[dto.id] = dto.categoryRaw
            let key = templateKey(forCategory: dto.categoryRaw)
            var values = FieldValues()
            var leftovers: [String] = []

            func text(_ field: String, _ value: String?) {
                if let value, !value.isEmpty { values[field] = .text(value) }
            }
            func number(_ field: String, _ value: Double?) {
                if let value { values[field] = .number(value) }
            }
            func day(_ field: String, _ value: Date?) {
                if let value { values[field] = .date(CalendarDay(value, calendar: calendar)) }
            }
            func note(_ label: String, _ value: String?) {
                if let value, !value.isEmpty { leftovers.append("\(label): \(value)") }
            }

            switch key {
            case BuiltInTemplates.Key.vehicle:
                text("vehicle.plate", dto.licensePlate.map { FieldFormatter.normalize($0, as: .plate) })
                text("vehicle.make", dto.make)
                text("vehicle.model", dto.modelName)
                number("vehicle.year", dto.manufactureYear.map(Double.init))
                text("vehicle.vin", dto.vin)
                text("vehicle.civ", dto.civSeries)
                number("vehicle.odometer", dto.currentMetricValue)
                text("vehicle.fuel", dto.fuelType)
                number("vehicle.engineCc", dto.engineDisplacementCc.map(Double.init))
                // v2 stored horsepower in a field named for kilowatts; it was always entered as CP.
                number("vehicle.powerHp", dto.enginePowerKw.map(Double.init))
                note("Motor", dto.engineSpecs)
            case BuiltInTemplates.Key.home:
                text("home.address", dto.address)
                number("home.area", dto.surfaceAreaSqm)
                number("home.year", dto.constructionYear.map(Double.init))
                text("home.cadastral", dto.cadastralNumber)
                text("home.pod", dto.podCode)
                text("home.clc", dto.clcCode)
                text("home.waterCode", dto.waterClientCode)
                number("home.meterReadFrom", dto.meterReadWindowStartDay.map(Double.init))
                number("home.meterReadTo", dto.meterReadWindowEndDay.map(Double.init))
                text("home.boilerModel", dto.heatingBoilerModel)
                text("home.boilerSerial", dto.heatingBoilerSerial)
                note("Contor gaze", dto.gasMeterSerial)
                note("Contor energie", dto.electricityMeterSerial)
                note("Contor apă", dto.waterMeterSerial)
                note("Centrală", dto.heatingBoilerSpecs)
                note("Contoare", dto.meterSerials)
            case BuiltInTemplates.Key.pet:
                text("pet.species", dto.petSpecies ?? dto.speciesAndBreed)
                text("pet.breed", dto.petBreed)
                day("pet.birthDate", dto.birthDate)
                text("pet.microchip", dto.microchipNumber)
                text("pet.passport", dto.petPassportNumber)
                number("pet.weight", dto.weightKg)
                provider(dto.veterinarianClinic ?? dto.vetContactInfo, phone: dto.veterinarianPhone, trade: .vet, assetId: dto.id, at: dto.createdAt)
            case BuiltInTemplates.Key.health:
                day("health.birthDate", dto.birthDate)
                text("health.bloodType", dto.bloodType)
                text("health.allergies", dto.allergies)
                text("health.conditions", dto.chronicConditions)
                provider(dto.familyDoctorName, phone: dto.familyDoctorPhone, trade: .doctor, assetId: dto.id, at: dto.createdAt)
                provider(dto.emergencyContactName ?? dto.emergencyContact, phone: dto.emergencyContactPhone, trade: .emergencyContact, assetId: dto.id, at: dto.createdAt)
                note("Persoană", dto.personName)
            case BuiltInTemplates.Key.documents:
                text("document.number", dto.serialOrImei)
                text("document.issuer", dto.retailerOrIssuer)
                day("document.issueDate", dto.purchaseOrIssueDate)
                day("document.expiry", dto.contractEndDate)
                text("document.holder", dto.personName)
            case BuiltInTemplates.Key.warranty:
                text("warranty.brand", dto.make)
                text("warranty.model", dto.modelName)
                text("warranty.serial", dto.serialOrImei)
                text("warranty.retailer", dto.retailerOrIssuer)
                day("warranty.purchaseDate", dto.purchaseOrIssueDate)
                if let price = dto.purchasePrice { values["warranty.price"] = .money(Money(Decimal(price), currency: dto.currencyCode)) }
                if let purchase = dto.purchaseOrIssueDate {
                    let months = (dto.warrantyMonths ?? 24) + (dto.extendedWarrantyMonths ?? 0)
                    values["warranty.expiry"] = .date(RecurrenceEngine.add(.months(months), to: CalendarDay(purchase, calendar: calendar), calendar: calendar))
                }
            case BuiltInTemplates.Key.subscription:
                text("subscription.provider", dto.providerName)
                if let amount = dto.recurringAmount { values["subscription.price"] = .money(Money(Decimal(amount), currency: dto.currencyCode)) }
                text("subscription.cycle", dto.billingCycle)
                day("subscription.contractEnd", dto.contractEndDate)
                text("subscription.cancelUrl", dto.cancellationUrl)
                text("subscription.card", dto.paymentCardLast4)
            default:
                text("other.description", dto.subtitle)
            }

            // The asset's main contact becomes a provider who looks after it.
            if let id = provider(dto.primaryContactName, phone: dto.primaryContactPhone, trade: trade(forCategory: dto.categoryRaw), assetId: dto.id, at: dto.createdAt),
               let email = dto.primaryContactEmail, !email.isEmpty,
               let key = providers.first(where: { $0.value.id == id })?.key {
                providers[key]?.email = email
            }
            if key != BuiltInTemplates.Key.other { note("Subtitlu", dto.subtitle) }
            for field in dto.dynamicFields {
                let value = field.stringValue ?? field.numberValue.map { String($0) } ?? field.dateValue.map { CalendarDay($0, calendar: calendar).isoString } ?? field.boolValue.map { $0 ? "Da" : "Nu" }
                note(field.label, value)
            }
            let notes = ([dto.notes].compactMap { $0 } + leftovers).filter { !$0.isEmpty }.joined(separator: "\n")

            return DossierV3.Asset(
                id: DossierV3.id(dto.id), templateKey: key, name: dto.name, symbolOverride: nil, tintOverride: nil,
                notes: notes.isEmpty ? nil : notes, values: values, photoPath: nil, isExample: false,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt
            )
        }

        // MARK: Events

        mutating func convert(_ dto: LifecycleEventDTO) {
            let category = categoryOf[dto.assetId] ?? "custom"
            let due = CalendarDay(dto.dueDate, calendar: calendar)
            let cost = dto.cost.map { Money(Decimal($0), currency: dto.currency) }
            let kind = DossierV2Converter.kind(forTitle: dto.title, category: category)
            var reminders = kind.defaultProfile
            if !dto.reminderOffsetDays.isEmpty { reminders.leadDays = Array(Set(dto.reminderOffsetDays.map(abs))).sorted(by: >) }
            let obligation = DossierV3.Obligation(
                id: DossierV3.id(dto.id), assetId: DossierV3.id(dto.assetId), title: dto.title, notes: dto.eventDescription,
                blueprintKey: nil, kind: kind.rawValue, dueDate: due,
                dueMetric: dto.metricTriggerValue, reminders: reminders,
                reminderMinuteOfDay: nil, recurrence: DossierV2Converter.recurrence(cadenceDays: dto.cadenceDays),
                estimatedCost: dto.isCompleted ? nil : cost, provider: dto.provider, reference: dto.policyOrContractNumber,
                status: (dto.isCompleted ? ObligationStatus.done : .active).rawValue, snoozedUntil: nil, isExample: false,
                createdAt: dto.createdAt, updatedAt: dto.completedDate ?? dto.createdAt
            )
            obligations.append(obligation)
            guard dto.isCompleted else { return }
            let entryId = DossierV3.id(UUID())
            entryForEvent[dto.id] = entryId
            entries.append(DossierV3.HistoryEntry(
                id: entryId, assetId: DossierV3.id(dto.assetId), obligationId: obligation.id,
                kind: HistoryKind.forCompleting(kind).rawValue, title: dto.title, occurredAt: dto.completedDate ?? dto.dueDate,
                metricReading: dto.mileageAtEvent, totalCost: cost, note: nil, rating: nil,
                cycleDueDate: due, nextDueDate: nil, previousStatus: ObligationStatus.active.rawValue, previousDueMetric: nil,
                providerIds: [], isExample: false
            ))
        }

        // MARK: Service records

        mutating func convert(_ dto: ServiceItemDTO) {
            let category = categoryOf[dto.assetId] ?? "custom"
            let day = CalendarDay(dto.serviceDate, calendar: calendar)
            let providerId = provider(dto.shopName ?? dto.specialistOrDoctorName, phone: nil, trade: trade(forCategory: category), assetId: dto.assetId, at: dto.serviceDate)

            let entryId: String
            if let eventId = dto.eventId, let existing = entryForEvent[eventId] {
                entryId = existing
            } else if let existing = entryForVisit["\(dto.assetId)|\(day.isoString)"] {
                entryId = existing
            } else {
                entryId = DossierV3.id(UUID())
                entryForVisit["\(dto.assetId)|\(day.isoString)"] = entryId
                entries.append(DossierV3.HistoryEntry(
                    id: entryId, assetId: DossierV3.id(dto.assetId), obligationId: nil,
                    kind: HistoryKind.maintenance.rawValue, title: dto.name, occurredAt: dto.serviceDate,
                    metricReading: dto.mileageAtService, totalCost: nil, note: nil, rating: nil,
                    cycleDueDate: nil, nextDueDate: nil, previousStatus: nil, previousDueMetric: nil,
                    providerIds: [], isExample: false
                ))
            }
            if let providerId, let index = entries.firstIndex(where: { $0.id == entryId }), !entries[index].providerIds.contains(providerId) {
                entries[index].providerIds.append(providerId)
            }
            let components = BuiltInTemplates.definition(for: templateKey(forCategory: category))?.components ?? []
            items.append(DossierV3.ServiceItem(
                id: DossierV3.id(dto.id), entryId: entryId, componentKey: ComponentCatalog.key(for: dto.name, in: components),
                name: dto.name, group: dto.category, partBrandOrCode: dto.partBrandOrCode, partSerialNumber: dto.partSerialNumber,
                cost: dto.cost.map { Money(Decimal($0)) }, laborCost: dto.laborCost.map { Money(Decimal($0)) },
                partsCost: dto.partsCost.map { Money(Decimal($0)) }, supplierId: nil, batchOrTicket: dto.serialOrBatchNumber,
                locationDetail: dto.locationOrToothNumber, daysInService: dto.daysInService, warrantyMonths: dto.warrantyMonths,
                notes: dto.notes, isExample: false
            ))
        }
    }

    // MARK: Shared mappings

    static func recurrence(cadenceDays: Int?) -> RecurrenceRule {
        guard let days = cadenceDays, days > 0 else { return .none }
        switch days {
        case 365, 366: return .interval(.years(1), anchor: .dueDate)
        case 730, 731: return .interval(.years(2), anchor: .dueDate)
        default:
            if days % 365 == 0 { return .interval(.years(days / 365), anchor: .dueDate) }
            if days % 30 == 0 { return .interval(.months(days / 30), anchor: .dueDate) }
            if days % 7 == 0 { return .interval(.weeks(days / 7), anchor: .dueDate) }
            return .interval(.days(days), anchor: .dueDate)
        }
    }

    static func kind(forTitle title: String, category: String) -> ObligationKind {
        let text = SearchText.normalize(title)
        let rules: [(ObligationKind, [String])] = [
            (.legal, ["itp", "rovinieta", "vtp", "iscir", "verificare instalatie", "revizie instalatie", "antirabic"]),
            (.insurance, ["rca", "casco", "pad", "asigurare", "polita"]),
            (.tax, ["impozit", "taxa", "declaratia", "anaf"]),
            (.health, ["vaccin", "analize", "control", "deparazitare", "stomatolog", "screening"]),
            (.renewal, ["pasaport", "buletin", "carte de identitate", "permis", "reinnoire", "expirare", "garantie"]),
            (.payment, ["plata", "factura", "abonament", "chirie"]),
        ]
        for (kind, words) in rules where words.contains(where: { SearchText.containsPhrase(text, $0) }) { return kind }
        switch category {
        case "subscriptions": return .payment
        case "documents": return .renewal
        case "health", "pet": return .health
        default: return .maintenance
        }
    }

    static func convert(_ dto: MeasurementLogDTO) -> DossierV3.Measurement {
        DossierV3.Measurement(
            id: DossierV3.id(dto.id), assetId: DossierV3.id(dto.assetId), kind: measurementKind(domain: dto.domainRawValue, unit: dto.unit).rawValue,
            name: dto.metricName, value: dto.value, secondaryValue: dto.secondaryValue, unit: dto.unit, recordedAt: dto.recordedAt,
            unitPrice: dto.unitPrice.map { Money(Decimal($0)) }, isSelfRead: dto.isSelfRead, referenceMin: dto.referenceMin,
            referenceMax: dto.referenceMax, source: dto.labOrProviderName, notes: dto.notes, isExample: false
        )
    }

    /// v2 stored the Romanian display name of the domain; match on its wording and unit.
    static func measurementKind(domain: String, unit: String) -> MeasurementKind {
        let text = SearchText.normalize(domain)
        if text.contains("electric") { return .electricity }
        if text.contains("gaze") { return .gas }
        if text.contains("apa rece") { return .coldWater }
        if text.contains("apa calda") { return .hotWater }
        if text.contains("termic") { return .thermalEnergy }
        if text.contains("tensiune") { return .bloodPressure }
        if text.contains("greutate") { return .bodyWeight }
        if text.contains("dioptri") { return .diopters }
        if text.contains("kilometraj") || unit == "km" { return .odometer }
        if text.contains("analiz") || text.contains("biomarker") { return .biomarker }
        return .custom
    }

    static func contentType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "com.adobe.pdf"
        case "jpg", "jpeg": return "public.jpeg"
        case "png": return "public.png"
        case "heic": return "public.heic"
        case "txt": return "public.plain-text"
        default: return "public.data"
        }
    }
}
