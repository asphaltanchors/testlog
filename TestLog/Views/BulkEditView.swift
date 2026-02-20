//
//  BulkEditView.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import SwiftUI
import SwiftData

struct BulkEditView: View {
    let tests: [PullTest]
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Product.name) private var allProducts: [Product]

    private var anchorProducts: [Product] {
        allProducts.filter { $0.category == .anchor && $0.isActive }
    }
    private var adhesiveProducts: [Product] {
        allProducts.filter { $0.category == .adhesive && $0.isActive }
    }

    var body: some View {
        Form {
            Section {
                Label("\(tests.count) tests selected", systemImage: "checkmark.circle.fill")
                    .font(.headline)
            }

            Section("Set Anchor") {
                currentValueSummary("Anchor", values: tests.map { $0.product?.name ?? "None" })
                ForEach(anchorProducts, id: \.persistentModelID) { product in
                    Button {
                        applyToAll { $0.product = product }
                    } label: {
                        Label(product.name, systemImage: "shippingbox")
                    }
                }
                Button("Clear Anchor") {
                    applyToAll { $0.product = nil }
                }
                .foregroundStyle(.secondary)
            }

            Section("Set Adhesive") {
                currentValueSummary("Adhesive", values: tests.map { $0.adhesive?.name ?? "None" })
                ForEach(adhesiveProducts, id: \.persistentModelID) { product in
                    Button {
                        applyToAll { $0.adhesive = product }
                    } label: {
                        Label(product.name, systemImage: "drop.fill")
                    }
                }
                Button("Clear Adhesive") {
                    applyToAll { $0.adhesive = nil }
                }
                .foregroundStyle(.secondary)
            }

            Section("Set Anchor Material") {
                currentValueSummary("Material", values: tests.map { $0.anchorMaterial?.rawValue ?? "None" })
                bulkEnumButtons(AnchorMaterial.self) { test, value in test.anchorMaterial = value }
            }

            Section("Set Hole Diameter") {
                currentValueSummary("Hole", values: tests.map { $0.holeDiameter?.rawValue ?? "None" })
                bulkEnumButtons(HoleDiameter.self) { test, value in test.holeDiameter = value }
            }

            Section("Set Brush Size") {
                currentValueSummary("Brush Size", values: tests.map { $0.brushSize?.rawValue ?? "None" })
                bulkEnumButtons(BrushSize.self) { test, value in test.brushSize = value }
            }

            Section("Set Failure Family") {
                currentValueSummary("Failure Family", values: tests.map { $0.failureFamily?.rawValue ?? "None" })
                bulkEnumButtons(FailureFamily.self) { test, value in test.failureFamily = value }
            }

            Section("Set Failure Mechanism") {
                currentValueSummary("Failure Mechanism", values: tests.map { $0.failureMechanism?.rawValue ?? "None" })
                bulkEnumButtons(FailureMechanism.self) { test, value in test.failureMechanism = value }
            }

            Section("Set Failure Behavior") {
                currentValueSummary("Failure Behavior", values: tests.map { $0.failureBehavior?.rawValue ?? "None" })
                bulkEnumButtons(FailureBehavior.self) { test, value in test.failureBehavior = value }
            }
        }
        .navigationTitle("Bulk Edit")
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    // MARK: - Helpers

    private func applyToAll(_ change: (PullTest) -> Void) {
        withAnimation {
            for test in tests {
                change(test)
            }
        }
    }

    private func currentValueSummary(_ label: String, values: [String]) -> some View {
        let unique = Set(values)
        let summary: String
        if unique.count == 1, let value = unique.first {
            summary = value
        } else {
            summary = "Mixed (\(unique.count) values)"
        }
        return HStack {
            Text("Current:")
                .foregroundStyle(.secondary)
            Text(summary)
                .foregroundColor(unique.count == 1 ? .primary : .orange)
        }
        .font(.caption)
    }

    private func bulkEnumButtons<E: RawRepresentable & CaseIterable & Identifiable>(
        _ type: E.Type,
        apply: @escaping (PullTest, E) -> Void
    ) -> some View where E.RawValue == String, E.AllCases: RandomAccessCollection {
        ForEach(E.allCases) { value in
            Button(value.rawValue) {
                applyToAll { test in apply(test, value) }
            }
        }
    }
}
