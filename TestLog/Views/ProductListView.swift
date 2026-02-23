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
                if product.category == .anchor {
                    OptionalEnumPicker("Default Hole Size", selection: $product.defaultHoleDiameter)

                    HStack {
                        Text("Rated Strength (lbs)")
                        Spacer()
                        TextField("lbs", value: $product.ratedStrengthLbs, format: .number)
                            .multilineTextAlignment(.trailing)
#if os(iOS)
                            .keyboardType(.numberPad)
#endif
                            .frame(width: 80)
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
    let anchors: [(name: String, hole: HoleDiameter?, rated: Int?)] = [
        ("AM625", .sevenEighths, 1000),
        ("SP10", .sevenEighths, 1500),
        ("SP12", .sevenEighths, 2000),
        ("SP18", .one, 2500),
        ("SP58", .oneAndOneHalf, 5000),
        ("SP88", .oneAndOneHalf, nil),
    ]
    for anchor in anchors {
        let isActive = anchor.name != "SP88"
        context.insert(Product(
            name: anchor.name,
            category: .anchor,
            isActive: isActive,
            retiredOn: isActive ? nil : Date(),
            defaultHoleDiameter: anchor.hole,
            ratedStrengthLbs: anchor.rated
        ))
    }

    let adhesives: [String] = [
        "EPX3 - MKT LiquidROK 700",
        "EPX5 - MKT LiquidROK 200",
        "EPX2 - Damtite Anchoring Cement",
        "EPX2 - Quikrete Anchoring Cement",
        "Sika Anchorfix-2",
    ]
    for name in adhesives {
        context.insert(Product(name: name, category: .adhesive))
    }
}
