import SwiftUI

struct TestResultsSection: View {
    @Bindable var test: PullTest
    let failureFamilyOptions: [FailureFamily]
    let failureMechanismOptions: [FailureMechanism]
    let failureBehaviorOptions: [FailureBehavior]

    var body: some View {
        Section("Installation Parameters") {
            OptionalEnumPicker("Anchor Material", selection: $test.anchorMaterial)
            OptionalEnumPicker("Hole Diameter", selection: $test.holeDiameter)
            OptionalEnumPicker("Brush Size", selection: $test.brushSize)
        }

        Section("Dates & Conditions") {
            OptionalDatePicker("Installed", selection: $test.installedDate)
            OptionalDatePicker("Tested", selection: $test.testedDate)

            if let days = test.computedCureDays {
                LabeledContent("Computed Cure Days", value: "\(days)")
            }

            HStack {
                Text("Cure Days (override)")
                Spacer()
                TextField("Days", value: $test.cureDays, format: .number)
                    .multilineTextAlignment(.trailing)
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                    .frame(width: 80)
            }

            HStack {
                Text("Pavement Temp (°F)")
                Spacer()
                TextField("°F", value: $test.pavementTemp, format: .number)
                    .multilineTextAlignment(.trailing)
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                    .frame(width: 80)
            }
        }

        Section("Results") {
            OptionalEnumPicker("Test Type", selection: $test.testType)
            OptionalEnumPicker(
                "Failure Family",
                selection: $test.failureFamily,
                options: failureFamilyOptions
            )
            OptionalEnumPicker(
                "Failure Mechanism",
                selection: $test.failureMechanism,
                options: failureMechanismOptions
            )
            OptionalEnumPicker(
                "Failure Behavior",
                selection: $test.failureBehavior,
                options: failureBehaviorOptions
            )
        }
    }
}
