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
                TextField("Name", text: $product.name)
                Picker("Category", selection: $product.category) {
                    ForEach(ProductCategory.allCases) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                Toggle("Active", isOn: $product.isActive)
                    .onChange(of: product.isActive) { _, isActive in
                        if isActive {
                            product.retiredOn = nil
                        } else if product.retiredOn == nil {
                            product.retiredOn = Date()
                        }
                    }
                if !product.isActive {
                    OptionalDatePicker("Retired On", selection: $product.retiredOn)
                    TextField("Retirement Note", text: Binding(
                        get: { product.retirementNote ?? "" },
                        set: { product.retirementNote = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(2...4)
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
                            Text(test.testID ?? "—")
                            Spacer()
                            StatusBadge(status: test.status)
                        }
                    }
                }
            }
        }
        .navigationTitle(product.name)
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
            Text("This will delete \(product.name). Tests using this product will lose their product reference.")
        }
    }
}

// MARK: - Seed Default Products

func seedDefaultProducts(context: ModelContext) {
    let anchors: [String] = [
        "SP10",
        "SP12",
        "SP18",
        "SP58",
        "SP88",
    ]
    for name in anchors {
        context.insert(Product(name: name, category: .anchor))
    }

    let adhesives: [String] = [
        "EPX3 - MKT LiquidROK 700",
        "EPX5 - MKT LiquidROK 200",
        "EPX2 - Damtite Anchoring Cement",
    ]
    for name in adhesives {
        context.insert(Product(name: name, category: .adhesive))
    }
}
