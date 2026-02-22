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
    @Query(sort: \Product.name) private var allProducts: [Product]
    @State private var installationEnabled: Bool
    @State private var testingEnabled: Bool
    @State private var installationMixed: Bool
    @State private var testingMixed: Bool
    @State private var installationDate: Date
    @State private var testingDate: Date

    init(tests: [PullTest]) {
        self.tests = tests
        let installedDates = tests.compactMap(\.installedDate)
        let testedDates = tests.compactMap(\.testedDate)
        let installedDateValues = Set(installedDates.map { Calendar.current.startOfDay(for: $0) })
        let testedDateValues = Set(testedDates.map { Calendar.current.startOfDay(for: $0) })
        let installedStatusMixed = !tests.isEmpty && installedDates.count > 0 && installedDates.count < tests.count
        let testedStatusMixed = !tests.isEmpty && testedDates.count > 0 && testedDates.count < tests.count

        _installationEnabled = State(initialValue: !installedDates.isEmpty)
        _testingEnabled = State(initialValue: !testedDates.isEmpty)
        _installationMixed = State(initialValue: installedStatusMixed || installedDateValues.count > 1)
        _testingMixed = State(initialValue: testedStatusMixed || testedDateValues.count > 1)
        _installationDate = State(initialValue: installedDates.first ?? .now)
        _testingDate = State(initialValue: testedDates.first ?? .now)
    }

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

            Section("Dates & Conditions") {
                HStack {
                    Toggle("Installed", isOn: Binding(
                        get: { installationEnabled },
                        set: { newValue in
                            installationEnabled = newValue
                            installationMixed = false
                            setInstallationEnabled(newValue)
                        }
                    ))
                    if installationEnabled {
                        DatePicker("", selection: $installationDate, displayedComponents: [.date])
                            .labelsHidden()
                    }
                }
                .opacity(installationMixed ? 0.55 : 1.0)
                .onChange(of: installationDate) { _, newValue in
                    guard installationEnabled else { return }
                    installationMixed = false
                    applyInstalledStatus(with: newValue)
                }

                HStack {
                    Toggle("Tested", isOn: Binding(
                        get: { testingEnabled },
                        set: { newValue in
                            testingEnabled = newValue
                            testingMixed = false
                            setTestingEnabled(newValue)
                        }
                    ))
                    if testingEnabled {
                        DatePicker("", selection: $testingDate, displayedComponents: [.date])
                            .labelsHidden()
                    }
                }
                .opacity(testingMixed ? 0.55 : 1.0)
                .onChange(of: testingDate) { _, newValue in
                    guard testingEnabled else { return }
                    testingMixed = false
                    applyTestedStatus(with: newValue)
                }
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
            Text("Current \(label):")
                .foregroundStyle(.secondary)
            Text(summary)
                .foregroundColor(unique.count == 1 ? .primary : .orange)
        }
        .font(.caption)
    }

    private func setInstallationEnabled(_ enabled: Bool) {
        if enabled {
            applyInstalledStatus(with: installationDate)
            return
        }

        clearInstalledStatus()
        testingEnabled = false
    }

    private func setTestingEnabled(_ enabled: Bool) {
        if enabled {
            installationEnabled = true
            applyTestedStatus(with: testingDate)
            return
        }

        clearTestedStatus()
    }

    private func applyInstalledStatus(with date: Date) {
        applyToAll { test in
            test.installedDate = date
            if let testedDate = test.testedDate, testedDate < date {
                test.testedDate = date
            }
        }
    }

    private func clearInstalledStatus() {
        applyToAll { test in
            test.installedDate = nil
            test.testedDate = nil
        }
    }

    private func applyTestedStatus(with date: Date) {
        applyToAll { test in
            if let installedDate = test.installedDate, installedDate > date {
                test.installedDate = date
            } else if test.installedDate == nil {
                test.installedDate = date
            }
            test.testedDate = date
        }
    }

    private func clearTestedStatus() {
        applyToAll { test in
            test.testedDate = nil
        }
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
