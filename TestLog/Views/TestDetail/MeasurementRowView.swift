import SwiftUI

struct MeasurementRowView: View {
    @Bindable var measurement: TestMeasurement

    var body: some View {
        HStack {
            if measurement.isManual {
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
            } else {
                Text(measurement.label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(measurement.force.map { String(format: "%.0f", $0) } ?? "—")
                    .monospacedDigit()
            }
        }
    }
}
