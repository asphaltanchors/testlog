import SwiftUI
import SwiftData

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
                "",
                text: Binding(
                    get: { test.notes ?? "" },
                    set: { test.notes = $0.isEmpty ? nil : $0 }
                ),
                prompt: Text("Notes"),
                axis: .vertical
            )
            .labelsHidden()
            .multilineTextAlignment(.leading)
            .lineLimit(3...6)
        }
    }
}
