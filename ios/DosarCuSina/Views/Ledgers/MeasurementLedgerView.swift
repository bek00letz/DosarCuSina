import SwiftUI
import SwiftData
import Charts

/// Comprehensive quantitative telemetry and lab biomarker ledger view.
/// Displays chronological reading cards, delta consumption calculations,
/// lab reference range alerts (* H / * L), and seasonal progression curves using Swift Charts.
public struct MeasurementLedgerView: View {
    public let asset: Asset
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingAddSheet: Bool = false
    @State private var selectedMetricFilter: String? = nil
    @State private var readingToDelete: MeasurementLog? = nil
    
    public init(asset: Asset) {
        self.asset = asset
    }
    
    private var sortedMeasurements: [MeasurementLog] {
        asset.measurements.sorted { $0.recordedAt > $1.recordedAt }
    }
    
    private var chronologicalMeasurements: [MeasurementLog] {
        asset.measurements.sorted { $0.recordedAt < $1.recordedAt }
    }
    
    private var uniqueMetricNames: [String] {
        Array(Set(asset.measurements.map { $0.metricName })).sorted()
    }
    
    private var filteredMeasurements: [MeasurementLog] {
        if let filter = selectedMetricFilter {
            return sortedMeasurements.filter { $0.metricName == filter }
        }
        return sortedMeasurements
    }
    
    private var chartMeasurements: [MeasurementLog] {
        if let filter = selectedMetricFilter {
            return chronologicalMeasurements.filter { $0.metricName == filter }
        }
        // Default to first metric if multiple exist
        if let firstMetric = uniqueMetricNames.first {
            return chronologicalMeasurements.filter { $0.metricName == firstMetric }
        }
        return chronologicalMeasurements
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Header Bar with Metric Filter & Add Button
            headerBar
            
            if asset.measurements.isEmpty {
                emptyStateCard
            } else {
                // Seasonal Visualization Curve (Swift Charts)
                if chartMeasurements.count >= 2 {
                    chartCard
                }
                
                // Chronological History Cards List
                readingsList
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddMeasurementSheet(asset: asset)
        }
        .confirmationDialog(
            "Șterge Înregistrare",
            isPresented: Binding(
                get: { readingToDelete != nil },
                set: { if !$0 { readingToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Șterge Măsurătoarea", role: .destructive) {
                if let r = readingToDelete {
                    deleteMeasurement(r)
                }
            }
            Button("Anulează", role: .cancel) {}
        } message: {
            Text("Ești sigur că vrei să elimini această citire din dosar?")
        }
    }
    
    // MARK: - Header Bar
    private var headerBar: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jurnal Telemetrie & Măsurători")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("\(asset.measurements.count) înregistrări în dosar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showingAddSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("Adaugă Index")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            }
            
            // Metric Filter Chips (if more than 1 metric name exists)
            if uniqueMetricNames.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            selectedMetricFilter = nil
                        } label: {
                            Text("Toate")
                                .font(.caption.weight(selectedMetricFilter == nil ? .bold : .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedMetricFilter == nil ? Color.blue.opacity(0.18) : Color(uiColor: .tertiarySystemGroupedBackground))
                                .foregroundStyle(selectedMetricFilter == nil ? Color.blue : Color.secondary)
                                .clipShape(Capsule())
                        }
                        
                        ForEach(uniqueMetricNames, id: \.self) { metric in
                            Button {
                                selectedMetricFilter = metric
                            } label: {
                                Text(metric)
                                    .font(.caption.weight(selectedMetricFilter == metric ? .bold : .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(selectedMetricFilter == metric ? Color.blue.opacity(0.18) : Color(uiColor: .tertiarySystemGroupedBackground))
                                    .foregroundStyle(selectedMetricFilter == metric ? Color.blue : Color.secondary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Swift Charts Card
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            let activeMetric = selectedMetricFilter ?? uniqueMetricNames.first ?? "Evoluție"
            let unit = chartMeasurements.first?.unit ?? ""
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Curbă Evoluție & Sezonieră")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    Text("\(activeMetric) (\(unit))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            Chart {
                ForEach(chartMeasurements) { log in
                    // Reference Zone for Lab Biomarkers
                    if let min = log.referenceMin, let max = log.referenceMax {
                        RectangleMark(
                            xStart: .offset(0),
                            xEnd: .offset(0),
                            yStart: .value("Minim", min),
                            yEnd: .value("Maxim", max)
                        )
                        .foregroundStyle(Color.green.opacity(0.08))
                    }
                    
                    LineMark(
                        x: .value("Dată", log.recordedAt),
                        y: .value("Valoare", log.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    
                    PointMark(
                        x: .value("Dată", log.recordedAt),
                        y: .value("Valoare", log.value)
                    )
                    .foregroundStyle(log.isOutOfRange ? Color.red : Color.blue)
                    .symbolSize(log.isOutOfRange ? 45 : 30)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .frame(height: 180)
            .padding(.top, 4)
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - Readings List
    private var readingsList: some View {
        VStack(spacing: 10) {
            ForEach(filteredMeasurements) { reading in
                measurementRowCard(reading)
            }
        }
    }
    
    // MARK: - Single Reading Row Card
    private func measurementRowCard(_ reading: MeasurementLog) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading.metricName)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text(formattedDate(reading.recordedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatValue(reading.value))
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(reading.unit)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    
                    if let sec = reading.secondaryValue {
                        Text("/ \(formatValue(sec))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Badges Row: Delta, Cost, Self-Read, Reference Alert
            HStack(spacing: 6) {
                // Delta badge
                if let delta = reading.deltaFromPrevious {
                    let sign = delta >= 0 ? "+" : ""
                    Text("Δ \(sign)\(formatValue(delta)) \(reading.unit)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(delta >= 0 ? .orange : .green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((delta >= 0 ? Color.orange : Color.green).opacity(0.12))
                        .clipShape(Capsule())
                }
                
                // Estimated cost
                if let cost = reading.estimatedCost {
                    Text("~\(String(format: "%.2f", cost)) RON")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
                
                // Self-read vs estimate
                Text(reading.isSelfRead ? "Autocitit" : "Estimare")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                
                // Out of range indicator (* H / * L)
                if reading.isOutOfRange {
                    if let max = reading.referenceMax, reading.value > max {
                        Text("* H (Peste limită)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.12))
                            .clipShape(Capsule())
                    } else if let min = reading.referenceMin, reading.value < min {
                        Text("* L (Sub limită)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                
                Spacer()
                
                Button {
                    readingToDelete = reading
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            
            if let lab = reading.labOrProviderName, !lab.isEmpty {
                Text("Laborator / Furnizor: \(lab)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            if let notes = reading.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(cardBackground)
    }
    
    // MARK: - Empty State
    private var emptyStateCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            
            Text("Nicio înregistrare în jurnal")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
            
            Text("Adaugă indexul contorului de utilități (energie, gaze, apă), analize medicale sau greutate pentru a genera curbe de evoluție și costuri estimate.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(cardBackground)
    }
    
    // MARK: - Helpers
    private func deleteMeasurement(_ log: MeasurementLog) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            asset.measurements.removeAll { $0.id == log.id }
            modelContext.delete(log)
            asset.updatedAt = Date()
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "ro_RO")
        return formatter.string(from: date)
    }
    
    private func formatValue(_ val: Double) -> String {
        val.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", val) : String(format: "%.2f", val)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.02), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Add Measurement Sheet
private struct AddMeasurementSheet: View {
    let asset: Asset
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedDomain: MeasurementDomain = .electricityMeter
    @State private var metricName: String = ""
    @State private var valueText: String = ""
    @State private var unitText: String = "kWh"
    @State private var recordedAt: Date = Date()
    @State private var unitPriceText: String = "0.68"
    @State private var isSelfRead: Bool = true
    @State private var refMinText: String = ""
    @State private var refMaxText: String = ""
    @State private var labProviderName: String = ""
    @State private var notes: String = ""
    
    init(asset: Asset) {
        self.asset = asset
    }
    
    private var previousValue: Double? {
        let matching = asset.measurements
            .filter { $0.metricName.localizedCaseInsensitiveCompare(metricName) == .orderedSame }
            .sorted { $0.recordedAt > $1.recordedAt }
        return matching.first?.value
    }
    
    private var enteredValue: Double? {
        Double(valueText.replacingOccurrences(of: ",", with: "."))
    }
    
    private var delta: Double? {
        guard let curr = enteredValue, let prev = previousValue else { return nil }
        return curr - prev
    }
    
    private var estimatedCost: Double? {
        guard let d = delta, let price = Double(unitPriceText.replacingOccurrences(of: ",", with: ".")), d > 0 else { return nil }
        return d * price
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Domain & Metric
                Section("Tip Parametru") {
                    Picker("Domeniu", selection: $selectedDomain) {
                        ForEach(MeasurementDomain.allCases, id: \.self) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    .onChange(of: selectedDomain) { _, newDomain in
                        unitText = newDomain.defaultUnit
                        if metricName.isEmpty {
                            metricName = defaultName(for: newDomain)
                        }
                    }
                    
                    TextField("Denumire (ex: Index Zi, Glicemie)", text: $metricName)
                }
                
                // Section 2: Values & Unit
                Section("Valoare Măsurată") {
                    HStack {
                        TextField("Valoare citită", text: $valueText)
                            .keyboardType(.decimalPad)
                            .font(.system(.body, design: .monospaced))
                        
                        TextField("Unitate", text: $unitText)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let prev = previousValue {
                        HStack {
                            Text("Index anterior:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(formatValue(prev)) \(unitText)")
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                        }
                    }
                    
                    if let d = delta {
                        HStack {
                            Text("Consum calculat (Δ):")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(d >= 0 ? "+" : "")\(formatValue(d)) \(unitText)")
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .foregroundStyle(d >= 0 ? .orange : .green)
                        }
                    }
                    
                    DatePicker("Data Înregistrării", selection: $recordedAt, displayedComponents: [.date, .hourAndMinute])
                }
                
                // Section 3: Cost & Billing (for Utilities)
                if selectedDomain == .electricityMeter || selectedDomain == .gasMeter || selectedDomain == .coldWaterMeter || selectedDomain == .hotWaterMeter {
                    Section("Cost & Autocitire") {
                        HStack {
                            Text("Preț unitar (RON/\(unitText)):")
                            Spacer()
                            TextField("Preț", text: $unitPriceText)
                                .keyboardType(.decimalPad)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                        }
                        
                        Toggle("Index Autocitit", isOn: $isSelfRead)
                        
                        if let cost = estimatedCost {
                            HStack {
                                Text("Cost Estimat Factură:")
                                    .font(.subheadline.weight(.bold))
                                Spacer()
                                Text("\(String(format: "%.2f", cost)) RON")
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                
                // Section 4: Health Reference Range (for Biomarkers)
                if selectedDomain == .healthBiomarker || selectedDomain == .bloodPressure || selectedDomain == .diopters {
                    Section("Interval de Referință Laborator") {
                        HStack {
                            TextField("Minim (ex: 70)", text: $refMinText)
                                .keyboardType(.decimalPad)
                            Text("–")
                            TextField("Maxim (ex: 99)", text: $refMaxText)
                                .keyboardType(.decimalPad)
                        }
                    }
                }
                
                // Section 5: Provider & Notes
                Section("Detalii Suplimentare") {
                    TextField("Furnizor / Laborator (ex: Hidroelectrica, Synevo)", text: $labProviderName)
                    TextField("Observații", text: $notes)
                }
            }
            .navigationTitle("Adaugă Măsurătoare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvează") {
                        saveMeasurement()
                    }
                    .font(.body.weight(.bold))
                    .disabled(metricName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || enteredValue == nil)
                }
            }
            .onAppear {
                setupDefaults()
            }
        }
    }
    
    private func setupDefaults() {
        switch asset.category {
        case .home:
            selectedDomain = .electricityMeter
            metricName = "Index Energie Electrică"
            unitText = "kWh"
            unitPriceText = "0.68"
        case .health:
            selectedDomain = .healthBiomarker
            metricName = "Glicemie"
            unitText = "mg/dL"
            refMinText = "70"
            refMaxText = "99"
        case .pet:
            selectedDomain = .bodyWeight
            metricName = "Greutate Corporală"
            unitText = "kg"
        case .vehicle:
            selectedDomain = .odometer
            metricName = "Kilometraj"
            unitText = "km"
        default:
            selectedDomain = .customMetric
            metricName = "Parametru"
            unitText = "unități"
        }
    }
    
    private func defaultName(for domain: MeasurementDomain) -> String {
        switch domain {
        case .electricityMeter: return "Index Energie Electrică"
        case .gasMeter: return "Index Gaze Naturale"
        case .coldWaterMeter: return "Index Apă Rece"
        case .hotWaterMeter: return "Index Apă Caldă"
        case .thermalEnergy: return "Index Energie Termică"
        case .healthBiomarker: return "Analiză Sânge"
        case .bloodPressure: return "Tensiune Arterială"
        case .bodyWeight: return "Greutate"
        case .diopters: return "Dioptrii"
        case .odometer: return "Kilometraj"
        case .customMetric: return "Măsurătoare"
        }
    }
    
    private func saveMeasurement() {
        guard let val = enteredValue else { return }
        
        let price = Double(unitPriceText.replacingOccurrences(of: ",", with: "."))
        let min = Double(refMinText.replacingOccurrences(of: ",", with: "."))
        let max = Double(refMaxText.replacingOccurrences(of: ",", with: "."))
        
        let log = MeasurementLog(
            domain: selectedDomain,
            metricName: metricName.trimmingCharacters(in: .whitespacesAndNewlines),
            value: val,
            unit: unitText.trimmingCharacters(in: .whitespacesAndNewlines),
            recordedAt: recordedAt,
            previousValue: previousValue,
            unitPrice: price,
            isSelfRead: isSelfRead,
            referenceMin: min,
            referenceMax: max,
            labOrProviderName: labProviderName.isEmpty ? nil : labProviderName,
            notes: notes.isEmpty ? nil : notes
        )
        
        log.asset = asset
        asset.measurements.append(log)
        asset.updatedAt = Date()
        
        // If odometer, update currentMetricValue
        if selectedDomain == .odometer {
            asset.currentMetricValue = val
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
    }
    
    private func formatValue(_ val: Double) -> String {
        val.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", val) : String(format: "%.2f", val)
    }
}
