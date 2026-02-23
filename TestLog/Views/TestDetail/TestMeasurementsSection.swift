import SwiftUI
import SwiftData

struct TestMeasurementsSection: View {
    @Bindable var test: PullTest
    let modelContext: ModelContext
    @State private var observedPeakDraft = ""

    var body: some View {
        Section("Measurements") {
            HStack {
                Text("Observed Peak (lbs)")
                Spacer()
                TextField(
                    "—",
                    text: $observedPeakDraft
                )
                .multilineTextAlignment(.trailing)
#if os(iOS)
                .keyboardType(.decimalPad)
#endif
                .frame(width: 110)
            }
            .onChange(of: observedPeakDraft) { _, newValue in
                applyObservedPeakDraft(newValue)
            }

            ForEach(
                displayedMeasurements,
                id: \.persistentModelID
            ) { measurement in
                MeasurementRowView(
                    measurement: measurement,
                    ratedStrengthLbs: test.product?.ratedStrengthLbs
                )
            }
            .onDelete(perform: deleteMeasurements)
        }
        .onAppear {
            syncObservedPeakDraft()
        }
        .onChange(of: test.persistentModelID) { _, _ in
            syncObservedPeakDraft()
        }
        .onChange(of: test.observedPeakMeasurement?.force) { _, _ in
            syncObservedPeakDraft()
        }
    }

    private var displayedMeasurements: [TestMeasurement] {
        test.measurements
            .filter { $0.measurementType != .observedPeak }
            .sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    private func syncObservedPeakDraft() {
        guard let value = test.observedPeakMeasurement?.force else {
            observedPeakDraft = ""
            return
        }
        observedPeakDraft = String(format: "%.0f", value)
    }

    private func applyObservedPeakDraft(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if let measurement = test.observedPeakMeasurement {
                modelContext.delete(measurement)
            }
            return
        }

        if let value = Double(trimmed) {
            test.upsertObservedPeakMeasurement(forceLbs: value)
        }
    }

    private func deleteMeasurements(at offsets: IndexSet) {
        let sorted = displayedMeasurements
        for index in offsets {
            modelContext.delete(sorted[index])
        }
    }
}
