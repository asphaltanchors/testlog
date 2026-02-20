//
//  ProductTableView.swift
//  TestLog
//
//  Created by Codex on 2/20/26.
//

import SwiftUI
import SwiftData

struct ProductTableView: View {
    let products: [Product]
    @Binding var selectedProductIDs: Set<PersistentIdentifier>
    let title: String
    var onAddProduct: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var sortOrder: [KeyPathComparator<Product>] = [
        KeyPathComparator(\Product.sortSKU, comparator: .localizedStandard)
    ]

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    private var filteredProducts: [Product] {
        guard !searchText.isEmpty else { return products }
        let text = searchText.lowercased()
        return products.filter { product in
            product.sku.lowercased().contains(text) ||
            product.displayName.lowercased().contains(text) ||
            product.category.rawValue.lowercased().contains(text) ||
            (product.notes?.lowercased().contains(text) ?? false)
        }
    }

    private var sortedFilteredProducts: [Product] {
        filteredProducts.sorted(using: sortOrder)
    }

    var body: some View {
        Group {
#if os(macOS)
            macTable
#else
            iosList
#endif
        }
        .navigationTitle(title)
        .searchable(text: $searchText, prompt: "Search products...")
        .toolbar {
            ToolbarItem {
                Button(action: onAddProduct) {
                    Label("Add Product", systemImage: "plus")
                }
            }
        }
    }

#if os(macOS)
    private var macTable: some View {
        Table(of: Product.self, selection: $selectedProductIDs, sortOrder: $sortOrder) {
            TableColumn("SKU", value: \.sortSKU) { product in
                Text(product.sku)
                    .fontWeight(.medium)
            }
            .width(min: 80, ideal: 110)

            TableColumn("Name", value: \.sortDisplayName) { product in
                Text(product.displayName)
            }
            .width(min: 180, ideal: 260)

            TableColumn("Category", value: \.sortCategory) { product in
                Text(product.category.rawValue)
            }
            .width(min: 90, ideal: 120)

            TableColumn("Tests", value: \.sortUsageCount) { product in
                Text("\(product.tests.count + product.adhesiveTests.count)")
                    .monospacedDigit()
            }
            .width(min: 55, ideal: 70)
        } rows: {
            ForEach(sortedFilteredProducts, id: \.persistentModelID) { product in
                TableRow(product)
                    .contextMenu {
                        Button("Delete Product", role: .destructive) {
                            deleteProduct(product)
                        }
                    }
            }
        }
    }
#endif

#if os(iOS)
    private var iosList: some View {
        Group {
            if horizontalSizeClass == .compact {
                List {
                    ForEach(filteredProducts, id: \.persistentModelID) { product in
                        NavigationLink {
                            ProductDetailView(product: product)
                        } label: {
                            ProductRow(product: product)
                        }
                        .contextMenu {
                            Button("Delete Product", role: .destructive) {
                                deleteProduct(product)
                            }
                        }
                    }
                    .onDelete(perform: deleteProducts)
                }
            } else {
                List(selection: $selectedProductIDs) {
                    ForEach(filteredProducts, id: \.persistentModelID) { product in
                        ProductRow(product: product)
                            .tag(product.persistentModelID)
                            .contextMenu {
                                Button("Delete Product", role: .destructive) {
                                    deleteProduct(product)
                                }
                            }
                    }
                    .onDelete(perform: deleteProducts)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
    }
#endif

    private func deleteProduct(_ product: Product) {
        withAnimation {
            selectedProductIDs.remove(product.persistentModelID)
            modelContext.delete(product)
        }
    }

    private func deleteProducts(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                deleteProduct(filteredProducts[index])
            }
        }
    }
}

private struct ProductRow: View {
    let product: Product

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.sku)
                    .fontWeight(.semibold)
                Text(product.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(product.category.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension Product {
    var sortSKU: String { sku }
    var sortDisplayName: String { displayName }
    var sortCategory: String { category.rawValue }
    var sortUsageCount: Int { tests.count + adhesiveTests.count }
}
