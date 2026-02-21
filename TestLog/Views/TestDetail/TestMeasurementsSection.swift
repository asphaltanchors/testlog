import SwiftUI
import SwiftData

struct TestMeasurementsSection: View {
    @Bindable var test: PullTest
    let modelContext: ModelContext

    var body: some View {
        Section("Measurements") {
            ForEach(
                test.measurements.sorted(by: { $0.sortOrder < $1.sortOrder }),
                id: \.persistentModelID
            ) { measurement in
                MeasurementRowView(measurement: measurement)
            }
            .onDelete(perform: deleteMeasurements)

            Button("Add Measurement") {
                let measurement = TestMeasurement(
                    test: test,
                    label: "P\(test.measurements.count + 1)",
                    sortOrder: test.measurements.count
                )
                modelContext.insert(measurement)
            }
        }
    }

    private func deleteMeasurements(at offsets: IndexSet) {
        let sorted = test.measurements.sorted(by: { $0.sortOrder < $1.sortOrder })
        for index in offsets {
            modelContext.delete(sorted[index])
        }
    }
}
