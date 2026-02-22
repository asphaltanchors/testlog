import SwiftUI

struct OptionalDatePicker: View {
    let title: String
    @Binding var selection: Date?
    @State private var isEnabled: Bool

    init(_ title: String, selection: Binding<Date?>) {
        self.title = title
        self._selection = selection
        self._isEnabled = State(initialValue: selection.wrappedValue != nil)
    }

    var body: some View {
        HStack {
            Toggle(title, isOn: $isEnabled)
                .onChange(of: selection) { _, newValue in
                    isEnabled = newValue != nil
                }
                .onChange(of: isEnabled) { _, newValue in
                    if newValue && selection == nil {
                        selection = Date()
                    } else if !newValue {
                        selection = nil
                    }
                }
            if isEnabled, let binding = Binding($selection) {
                DatePicker("", selection: binding, displayedComponents: [.date])
                    .labelsHidden()
            }
        }
    }
}
