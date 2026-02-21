import SwiftUI

struct TestIdentitySection: View {
    @Bindable var test: PullTest

    var body: some View {
        Section("Identity") {
            TextField(
                "Test ID",
                text: Binding(
                    get: { test.testID ?? "" },
                    set: { test.testID = $0.isEmpty ? nil : $0 }
                )
            )
        }

        Section("Notes") {
            TextField(
                "Notes",
                text: Binding(
                    get: { test.notes ?? "" },
                    set: { test.notes = $0.isEmpty ? nil : $0 }
                ),
                axis: .vertical
            )
            .lineLimit(3...6)
        }
    }
}
