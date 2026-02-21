import SwiftUI

struct OptionalEnumPicker<E: RawRepresentable & CaseIterable & Identifiable & Hashable>: View
    where E.RawValue == String, E.AllCases: RandomAccessCollection
{
    let title: String
    @Binding var selection: E?
    let options: [E]

    init(_ title: String, selection: Binding<E?>, options: [E] = Array(E.allCases)) {
        self.title = title
        self._selection = selection
        self.options = options
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Text("—").tag(nil as E?)
            ForEach(options) { value in
                Text(value.rawValue).tag(value as E?)
            }
        }
    }
}
