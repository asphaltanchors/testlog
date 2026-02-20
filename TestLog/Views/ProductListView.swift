//
//  ProductListView.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//
//  Product detail view for editing product properties.
//  Product navigation is handled by the sidebar in ContentView.

import SwiftUI
import SwiftData

struct ProductDetailView: View {
    @Bindable var product: Product
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false

    private var allRelatedTests: [PullTest] {
        Array(Set(product.tests + product.adhesiveTests))
    }

    var body: some View {
        Form {
            Section("Product Info") {
                TextField("SKU", text: $product.sku)
                TextField("Display Name", text: $product.displayName)
                Picker("Category", selection: $product.category) {
                    ForEach(ProductCategory.allCases) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                TextField("Notes", text: Binding(
                    get: { product.notes ?? "" },
                    set: { product.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(2...4)
            }

            Section("Tests (\(allRelatedTests.count))") {
                if allRelatedTests.isEmpty {
                    Text("No tests use this product yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(allRelatedTests.sorted(by: {
                        ($0.testedDate ?? .distantPast) > ($1.testedDate ?? .distantPast)
                    }), id: \.persistentModelID) { test in
                        HStack {
                            Text(test.legacyTestID ?? "—")
                            Spacer()
                            StatusBadge(status: test.status)
                        }
                    }
                }
            }
        }
        .navigationTitle(product.sku)
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete Product", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .confirmationDialog("Delete this product?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                modelContext.delete(product)
                dismiss()
            }
        } message: {
            Text("This will delete \(product.sku). Tests using this product will lose their product reference.")
        }
    }
}

// MARK: - Seed Default Products

func seedDefaultProducts(context: ModelContext) {
    let anchors: [(String, String)] = [
        ("SP10", "1/4\" Spike Anchor"),
        ("SP12", "5/16\" Spike Anchor"),
        ("SP18", "3/8\" Spike Anchor"),
        ("SP58", "5/8\" Spike Anchor"),
        ("SP88", "7/8\" Spike Anchor"),
    ]
    for (sku, name) in anchors {
        context.insert(Product(sku: sku, displayName: name, category: .anchor))
    }

    let adhesives: [(String, String)] = [
        ("ROK700", "ROK 700 Adhesive"),
        ("Quikrete", "Quikrete Anchoring Adhesive"),
        ("Damtite", "Damtite Adhesive"),
    ]
    for (sku, name) in adhesives {
        context.insert(Product(sku: sku, displayName: name, category: .adhesive))
    }
}
