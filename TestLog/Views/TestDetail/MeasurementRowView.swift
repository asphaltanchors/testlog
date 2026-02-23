import SwiftUI

struct MeasurementRowView: View {
    @Bindable var measurement: TestMeasurement
    var ratedStrengthLbs: Int? = nil

    var body: some View {
        HStack {
            if isEditable {
                TextField("", text: $measurement.label, prompt: Text("Label"))
                    .labelsHidden()
                    .frame(minWidth: 100, maxWidth: 150, alignment: .leading)

                Spacer()

                TextField(
                    "",
                    value: $measurement.force,
                    format: .number.precision(.fractionLength(0))
                )
                .labelsHidden()
                .multilineTextAlignment(.trailing)
#if os(iOS)
                .keyboardType(.decimalPad)
#endif
                .frame(width: 110)
                .foregroundStyle(forceColor(measurement.force))
            } else {
                Text(measurement.label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(measurement.force.map { String(format: "%.0f", $0) } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(forceColor(measurement.force))
            }
        }
    }

    private var isEditable: Bool {
        if measurement.measurementType == .testerPeak {
            return false
        }
        return measurement.isManual
    }

    private func forceColor(_ force: Double?) -> Color {
        guard let force, let rated = ratedStrengthLbs else { return .primary }
        let ratedDouble = Double(rated)
        if force < ratedDouble { return .red }
        if force >= ratedDouble * 2 { return .green }
        return .primary
    }
}
