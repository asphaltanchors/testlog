//
//  TestDetailView.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import SwiftUI
import SwiftData

struct TestDetailView: View {
    @Bindable var test: PullTest
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Product.sku) private var allProducts: [Product]

    private var anchorProducts: [Product] {
        allProducts.filter { $0.category == .anchor }
    }
    private var adhesiveProducts: [Product] {
        allProducts.filter { $0.category == .adhesive }
    }
    private var failureMechanismOptions: [FailureMechanism] {
        FailureMechanism.options(for: test.testType, family: test.failureFamily)
    }
    private var failureBehaviorOptions: [FailureBehavior] {
        FailureBehavior.options(for: test.failureFamily)
    }
    private var failureFamilyOptions: [FailureFamily] {
        FailureFamily.options(for: test.testType)
    }
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Form {
            // MARK: - Identity & Status
            Section("Identity & Status") {
                TextField("Test ID", text: Binding(
                    get: { test.legacyTestID ?? "" },
                    set: { test.legacyTestID = $0.isEmpty ? nil : $0 }
                ))
                Picker("Status", selection: $test.status) {
                    ForEach(TestStatus.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
            }

            // MARK: - Product
            Section("Product") {
                Picker("Anchor", selection: $test.product) {
                    Text("None").tag(nil as Product?)
                    ForEach(anchorProducts, id: \.persistentModelID) { product in
                        Text("\(product.sku) — \(product.displayName)")
                            .tag(product as Product?)
                    }
                }

                Picker("Adhesive", selection: $test.adhesive) {
                    Text("None").tag(nil as Product?)
                    ForEach(adhesiveProducts, id: \.persistentModelID) { product in
                        Text("\(product.sku) — \(product.displayName)")
                            .tag(product as Product?)
                    }
                }
            }

            // MARK: - Installation Parameters
            Section("Installation Parameters") {
                OptionalEnumPicker("Anchor Material", selection: $test.anchorMaterial)
                OptionalEnumPicker("Hole Diameter", selection: $test.holeDiameter)
                OptionalEnumPicker("Brush Size", selection: $test.brushSize)
            }

            // MARK: - Dates & Conditions
            Section("Dates & Conditions") {
                OptionalDatePicker("Installed", selection: $test.installedDate)
                OptionalDatePicker("Tested", selection: $test.testedDate)

                if let days = test.computedCureDays {
                    LabeledContent("Computed Cure Days", value: "\(days)")
                }

                HStack {
                    Text("Cure Days (override)")
                    Spacer()
                    TextField("Days", value: $test.cureDays, format: .number)
                        .multilineTextAlignment(.trailing)
                    #if os(iOS)
                        .keyboardType(.numberPad)
                    #endif
                        .frame(width: 80)
                }

                HStack {
                    Text("Pavement Temp (°F)")
                    Spacer()
                    TextField("°F", value: $test.pavementTemp, format: .number)
                        .multilineTextAlignment(.trailing)
                    #if os(iOS)
                        .keyboardType(.numberPad)
                    #endif
                        .frame(width: 80)
                }
            }

            // MARK: - Results
            Section("Results") {
                OptionalEnumPicker("Test Type", selection: $test.testType)
                OptionalEnumPicker(
                    "Failure Family",
                    selection: $test.failureFamily,
                    options: failureFamilyOptions
                )
                OptionalEnumPicker(
                    "Failure Mechanism",
                    selection: $test.failureMechanism,
                    options: failureMechanismOptions
                )
                OptionalEnumPicker(
                    "Failure Behavior",
                    selection: $test.failureBehavior,
                    options: failureBehaviorOptions
                )
            }

            // MARK: - Measurements
            Section("Measurements") {
                ForEach(test.measurements.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.persistentModelID) { measurement in
                    MeasurementRowView(measurement: measurement)
                }
                .onDelete(perform: deleteMeasurements)

                Button("Add Measurement") {
                    let m = TestMeasurement(
                        test: test,
                        label: "P\(test.measurements.count + 1)",
                        sortOrder: test.measurements.count
                    )
                    modelContext.insert(m)
                }
            }

            // MARK: - Notes
            Section("Notes") {
                TextField("Notes", text: Binding(
                    get: { test.notes ?? "" },
                    set: { test.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(3...6)
            }
        }
        .navigationTitle(test.legacyTestID ?? "New Test")
        .onAppear {
            test.syncFailureFieldsFromLegacyIfNeeded()
            test.normalizeFailureSelections()
        }
        .onChange(of: test.testType) { _, _ in
            test.normalizeFailureSelections()
        }
        .onChange(of: test.failureFamily) { _, _ in
            test.normalizeFailureSelections()
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .confirmationDialog("Delete this test?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                modelContext.delete(test)
                dismiss()
            }
        } message: {
            Text("This will permanently delete \(test.legacyTestID ?? "this test") and all its measurements.")
        }
    }

    private func deleteMeasurements(at offsets: IndexSet) {
        let sorted = test.measurements.sorted(by: { $0.sortOrder < $1.sortOrder })
        for index in offsets {
            modelContext.delete(sorted[index])
        }
    }
}

// MARK: - Measurement Row

struct MeasurementRowView: View {
    @Bindable var measurement: TestMeasurement

    var body: some View {
        HStack {
            TextField("Label", text: $measurement.label)
                .frame(width: 80)
            Spacer()
            TextField("Force (lbs)", value: $measurement.force, format: .number)
                .multilineTextAlignment(.trailing)
            #if os(iOS)
                .keyboardType(.decimalPad)
            #endif
                .frame(width: 100)
        }
    }
}

// MARK: - Optional Enum Picker

struct OptionalEnumPicker<E: RawRepresentable & CaseIterable & Identifiable & Hashable>: View
    where E.RawValue == String, E.AllCases: RandomAccessCollection
{
    let title: String
    @Binding var selection: E?
    let options: [E]

    init(_ title: String, selection: Binding<E?>, options: [E] = Array(E.allCases)) {
        self.title = title
        self._selection = selection
        self.options = options
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Text("—").tag(nil as E?)
            ForEach(options) { value in
                Text(value.rawValue).tag(value as E?)
            }
        }
    }
}

// MARK: - Optional Date Picker

struct OptionalDatePicker: View {
    let title: String
    @Binding var selection: Date?
    @State private var isEnabled: Bool

    init(_ title: String, selection: Binding<Date?>) {
        self.title = title
        self._selection = selection
        self._isEnabled = State(initialValue: selection.wrappedValue != nil)
    }

    var body: some View {
        HStack {
            Toggle(title, isOn: $isEnabled)
                .onChange(of: isEnabled) { _, newValue in
                    if newValue && selection == nil {
                        selection = Date()
                    } else if !newValue {
                        selection = nil
                    }
                }
            if isEnabled, let binding = Binding($selection) {
                DatePicker("", selection: binding, displayedComponents: [.date])
                    .labelsHidden()
            }
        }
    }
}
