import Foundation
import SwiftData

/// A utility subscription's meter: the index its bills print, kept as readings on the
/// subscription, since the meter belongs to that supply point (a home's gas and water are
/// both in m³, and would mix if they were kept on the home). What it measures and its unit
/// come from the subscription's service (`ServiceKind.meterKind`), never from the bill.
///
/// A bill's index is recorded by capture's filing (`CaptureFilingPlan.meter`, carried out
/// by `CaptureFiler`) through the one reading path, `HouseholdMutations.recordReading`; the
/// subscription's page shows the last one (`last(on:)`).
enum SubscriptionMeter {

    /// The index a bill gives its subscription: the reading saving records.
    struct Reading: Equatable, Sendable {
        var value: Double
        var kind: MeasurementKind
        var unit: MeasurementUnit
        /// The bill's day: a document's reading is dated by the document.
        var day: CalendarDay
        /// How the bill says the index was taken (estimated, read); nil when it doesn't say.
        var basis: ReadingBasis? = nil

        /// "12.345 m³": the index with its unit, as the app writes it.
        var written: String { SubscriptionMeter.written(value, in: unit) }

        /// Whether `log` is this same reading: the same index in the same unit on the same day.
        /// The one rule that keeps a bill filed again from recording its index twice.
        func isRecorded(by log: MeasurementLog, calendar: Calendar) -> Bool {
            !log.isDeleted && log.measurementUnit == unit && log.value == value
                && CalendarDay(log.recordedAt, calendar: calendar) == day
        }

        /// This reading as a step plans it on `subscription` (`PlannedReading`): from the
        /// document, dated by it at noon, with how the bill says it was taken. `replaces` is
        /// the reading the bill recorded before, which filing takes away first. The one plan the
        /// filing asks about and then records.
        @MainActor
        func planned(on subscription: Asset, replacing replaces: UUID?, calendar: Calendar) -> PlannedReading {
            PlannedReading(value, on: subscription, at: day.noonDate(in: calendar), source: .document, unit: unit, kind: kind, basis: basis,
                           replacing: { log in replaces != nil && log.id == replaces })
        }
    }

    /// The reading a bill's index gives a subscription with these values, dated `day`, taken as
    /// `basis` says (`CaptureFieldKey.meterReading`). Nil when the service has no meter or isn't
    /// known (`meterKind`), or the index isn't a number.
    static func reading(_ index: CaptureValue?, basis: CaptureValue? = nil, service: String?, day: CalendarDay) -> Reading? {
        guard let kind = ServiceKind.meterKind(for: service), let unit = kind.defaultUnit,
              let value = number(index), value.isFinite, value >= 0 else { return nil }
        return Reading(value: value, kind: kind, unit: unit, day: day, basis: basis?.text.flatMap(ReadingBasis.init(rawValue:)))
    }

    /// The number an index was read as.
    static func number(_ value: CaptureValue?) -> Double? {
        switch value {
        case .number(let number)?, .metric(let number, _)?: NSDecimalNumber(decimal: number).doubleValue
        default: nil
        }
    }

    /// An index as the app writes it, with its unit: whole when it is whole, with up to three
    /// decimals when the meter prints them ("12.345 m³", "1.234,567 m³").
    static func written(_ value: Double, in unit: MeasurementUnit?) -> String {
        MeasurementUnit.written(value, in: unit, fractionDigits: 0...3)
    }

    // MARK: The last index

    /// The newest index that counts on a subscription's meter.
    struct Last: Equatable {
        var value: Double
        var unit: MeasurementUnit
        var day: CalendarDay
        /// Read off a document kept in the binder (a bill), rather than typed or imported.
        var isFromDocument: Bool
        /// An estimate (`ReadingBasis.estimated`): the bill's estimated index, the last one so far.
        var isEstimate: Bool = false

        var written: String { SubscriptionMeter.written(value, in: unit) }
    }

    /// The last index of the subscription's meter: the last reading of the one cleaned series
    /// (`ReadingSeries`) in its service's unit. Nil without a meter or without readings.
    @MainActor
    static func last(on asset: Asset, calendar: Calendar = .dosar) -> Last? {
        guard let unit = ServiceKind.meterKind(for: SubscriptionFields.service(of: asset.values))?.defaultUnit,
              let latest = HouseholdMutations.readingSeries(of: asset, unit: unit).latest else { return nil }
        let log = (asset.measurements ?? []).first {
            !$0.isDeleted && $0.measurementUnit == unit && $0.recordedAt == latest.date && $0.value == latest.metric
        }
        return Last(value: latest.metric, unit: unit, day: CalendarDay(latest.date, calendar: calendar),
                    isFromDocument: !(log?.attachments ?? []).isEmpty, isEstimate: latest.isEstimate)
    }
}
