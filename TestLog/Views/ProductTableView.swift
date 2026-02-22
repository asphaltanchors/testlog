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
    var onAddProduct: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var showArchived = false
    @State private var sortOrder: [KeyPathComparator<Product>] = [
        KeyPathComparator(\Product.sortName, comparator: .localizedStandard)
    ]

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    private var displayedProducts: [Product] {
        products.filter { product in
            showArchived || product.isActive
        }
    }

    private var filteredProducts: [Product] {
        guard !searchText.isEmpty else { return displayedProducts }
        let text = searchText.lowercased()
        return displayedProducts.filter { product in
            product.name.lowercased().contains(text) ||
            product.category.rawValue.lowercased().contains(text) ||
            archiveStatusText(for: product).lowercased().contains(text) ||
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
                Toggle("Show Archived", isOn: $showArchived)
            }
            if let onAddProduct {
                ToolbarItem {
                    Button(action: onAddProduct) {
                        Label("Add Product", systemImage: "plus")
                    }
                }
            }
        }
    }

#if os(macOS)
    private var macTable: some View {
        Table(of: Product.self, selection: $selectedProductIDs, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.sortName) { product in
                Text(product.name)
                    .fontWeight(.medium)
            }
            .width(min: 180, ideal: 260)

            TableColumn("Category", value: \.sortCategory) { product in
                Text(product.category.rawValue)
            }
            .width(min: 90, ideal: 120)

            TableColumn("Status", value: \.sortStatus) { product in
                Text(archiveStatusText(for: product))
            }
            .width(min: 75, ideal: 90)

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
                Text(product.name)
                    .fontWeight(.semibold)
            }
            Spacer()
            HStack(spacing: 8) {
                if !product.isActive {
                    Text("Archived")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(product.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private func archiveStatusText(for product: Product) -> String {
    product.isActive ? "Active" : "Archived"
}

private extension Product {
    var sortName: String { name }
    var sortCategory: String { category.rawValue }
    var sortStatus: String { isActive ? "Active" : "Archived" }
    var sortUsageCount: Int { tests.count + adhesiveTests.count }
}
