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
    @Query(sort: \Product.sku) private var allProducts: [Product]

    private var anchorProducts: [Product] {
        allProducts.filter { $0.category == .anchor }
    }
    private var adhesiveProducts: [Product] {
        allProducts.filter { $0.category == .adhesive }
    }
    @Query(sort: \TestSession.sessionDate, order: .reverse) private var sessions: [TestSession]

    var body: some View {
        Form {
            Section {
                Label("\(tests.count) tests selected", systemImage: "checkmark.circle.fill")
                    .font(.headline)
            }

            Section("Set Status") {
                HStack {
                    ForEach(TestStatus.allCases) { status in
                        Button {
                            applyToAll { $0.status = status }
                        } label: {
                            StatusBadge(status: status)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Set Anchor") {
                currentValueSummary("Anchor", values: tests.map { $0.product?.sku ?? "None" })
                ForEach(anchorProducts, id: \.persistentModelID) { product in
                    Button {
                        applyToAll { $0.product = product }
                    } label: {
                        Label(product.sku + " — " + product.displayName, systemImage: "shippingbox")
                    }
                }
                Button("Clear Anchor") {
                    applyToAll { $0.product = nil }
                }
                .foregroundStyle(.secondary)
            }

            Section("Set Adhesive") {
                currentValueSummary("Adhesive", values: tests.map { $0.adhesive?.sku ?? "None" })
                ForEach(adhesiveProducts, id: \.persistentModelID) { product in
                    Button {
                        applyToAll { $0.adhesive = product }
                    } label: {
                        Label(product.sku + " — " + product.displayName, systemImage: "drop.fill")
                    }
                }
                Button("Clear Adhesive") {
                    applyToAll { $0.adhesive = nil }
                }
                .foregroundStyle(.secondary)
            }

            Section("Set Session") {
                currentValueSummary("Session", values: tests.map {
                    $0.session?.sessionDate.formatted(.dateTime.month(.abbreviated).day().year()) ?? "None"
                })
                ForEach(sessions, id: \.persistentModelID) { session in
                    Button {
                        applyToAll { $0.session = session }
                    } label: {
                        Label(session.sessionDate.formatted(.dateTime.month(.abbreviated).day().year()), systemImage: "calendar")
                    }
                }
                Button("Clear Session") {
                    applyToAll { $0.session = nil }
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

            Section("Set Brushed") {
                currentValueSummary("Brushed", values: tests.map { $0.brushed?.rawValue ?? "None" })
                bulkEnumButtons(BrushedStatus.self) { test, value in test.brushed = value }
            }

            Section("Set Mix Consistency") {
                currentValueSummary("Mix", values: tests.map { $0.mixConsistency?.rawValue ?? "None" })
                bulkEnumButtons(MixConsistency.self) { test, value in test.mixConsistency = value }
            }

            Section("Set Failure Mode") {
                currentValueSummary("Failure", values: tests.map { $0.failureMode?.rawValue ?? "None" })
                bulkEnumButtons(FailureMode.self) { test, value in test.failureMode = value }
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
