import SwiftUI
import SwiftData

struct TestProductsSection: View {
    @Bindable var test: PullTest
    let anchorProducts: [Product]
    let adhesiveProducts: [Product]

    var body: some View {
        Section("Product") {
            Picker("Anchor", selection: Binding<PersistentIdentifier?>(
                get: { test.product?.persistentModelID },
                set: { id in test.product = anchorProducts.first { $0.persistentModelID == id } }
            )) {
                Text("None").tag(nil as PersistentIdentifier?)
                ForEach(anchorProducts, id: \.persistentModelID) { product in
                    Text(productLabel(product))
                        .tag(product.persistentModelID as PersistentIdentifier?)
                }
            }

            Picker("Adhesive", selection: Binding<PersistentIdentifier?>(
                get: { test.adhesive?.persistentModelID },
                set: { id in test.adhesive = adhesiveProducts.first { $0.persistentModelID == id } }
            )) {
                Text("None").tag(nil as PersistentIdentifier?)
                ForEach(adhesiveProducts, id: \.persistentModelID) { product in
                    Text(productLabel(product))
                        .tag(product.persistentModelID as PersistentIdentifier?)
                }
            }
        }
    }

    private func productLabel(_ product: Product) -> String {
        product.isActive ? product.name : "\(product.name) (Archived)"
    }
}
