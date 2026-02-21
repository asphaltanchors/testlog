import SwiftUI

struct TestProductsSection: View {
    @Bindable var test: PullTest
    let anchorProducts: [Product]
    let adhesiveProducts: [Product]

    var body: some View {
        Section("Product") {
            Picker("Anchor", selection: $test.product) {
                Text("None").tag(nil as Product?)
                ForEach(anchorProducts, id: \.persistentModelID) { product in
                    Text(productLabel(product))
                        .tag(product as Product?)
                }
            }

            Picker("Adhesive", selection: $test.adhesive) {
                Text("None").tag(nil as Product?)
                ForEach(adhesiveProducts, id: \.persistentModelID) { product in
                    Text(productLabel(product))
                        .tag(product as Product?)
                }
            }
        }
    }

    private func productLabel(_ product: Product) -> String {
        product.isActive ? product.name : "\(product.name) (Archived)"
    }
}
