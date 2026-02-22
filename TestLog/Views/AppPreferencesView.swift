import SwiftUI
import SwiftData

#if os(macOS)
struct AppPreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Product.name) private var allProducts: [Product]
    @Query(sort: \Site.name) private var allSites: [Site]

    var body: some View {
        Form {
            Section("Products") {
                Text("Set up anchors and adhesives used in tests.")
                    .foregroundStyle(.secondary)

                HStack {
                    Button("New Anchor Product") {
                        createProduct(category: .anchor)
                    }
                    Button("New Adhesive Product") {
                        createProduct(category: .adhesive)
                    }
                }

                Text("\(allProducts.count) total products")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if allProducts.isEmpty {
                    Button("Seed Default Products") {
                        seedDefaultProducts(context: modelContext)
                    }
                }
            }

            Section("Sites") {
                Text("Set up test pads and site grids used in test records.")
                    .foregroundStyle(.secondary)

                Button("New Site") {
                    createSite()
                }

                Text("\(allSites.count) total sites")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if allSites.isEmpty {
                    Button("Seed Main Pad Site") {
                        seedDefaultSites(context: modelContext)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 320)
    }

    private func createProduct(category: ProductCategory) {
        let product = Product(
            name: "New Product",
            category: category
        )
        modelContext.insert(product)
    }

    private func createSite() {
        let site = Site(
            name: "New Site",
            isPrimaryPad: allSites.isEmpty
        )
        modelContext.insert(site)
    }
}
#endif
