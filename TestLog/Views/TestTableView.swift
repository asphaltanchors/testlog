//
//  TestTableView.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import SwiftUI
import SwiftData

struct TestTableView: View {
    let tests: [PullTest]
    @Binding var selectedTestIDs: Set<PersistentIdentifier>
    let title: String
    var product: Product? = nil

    @Environment(\.modelContext) private var modelContext
    @Query private var allTests: [PullTest]
    @State private var searchText = ""
    @State private var sortOrder: [KeyPathComparator<PullTest>] = [
        KeyPathComparator(\PullTest.sortLegacyTestID, comparator: .localizedStandard)
    ]
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    private var filteredTests: [PullTest] {
        let base = tests
        guard !searchText.isEmpty else { return base }
        let text = searchText.lowercased()
        return base.filter { test in
            (test.legacyTestID?.lowercased().contains(text) ?? false) ||
            (test.product?.sku.lowercased().contains(text) ?? false) ||
            (test.adhesive?.sku.lowercased().contains(text) ?? false) ||
            (test.notes?.lowercased().contains(text) ?? false)
        }
    }

    private var sortedFilteredTests: [PullTest] {
        filteredTests.sorted(using: sortOrder)
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
        .searchable(text: $searchText, prompt: "Search tests...")
        .toolbar {
            ToolbarItem {
                Button(action: addTest) {
                    Label("Add Test", systemImage: "plus")
                }
            }
        }
    }

    // MARK: - macOS Table

    #if os(macOS)
    private var macTable: some View {
        Table(of: PullTest.self, selection: $selectedTestIDs, sortOrder: $sortOrder) {
            TableColumn("ID", value: \.sortLegacyTestID) { test in
                Text(test.legacyTestID ?? "—")
                    .fontWeight(.medium)
            }
            .width(min: 50, ideal: 65)

            TableColumn("Status", value: \.sortStatus) { test in
                StatusBadge(status: test.status)
            }
            .width(min: 75, ideal: 85)

            TableColumn("Product", value: \.sortProductSKU) { test in
                Text(test.product?.sku ?? "—")
            }
            .width(min: 50, ideal: 60)

            TableColumn("Adhesive", value: \.sortAdhesiveSKU) { test in
                Text(test.adhesive?.sku ?? "—")
            }
            .width(min: 65, ideal: 80)

            TableColumn("Hole", value: \.sortHoleDiameter) { test in
                Text(test.holeDiameter?.rawValue ?? "—")
            }
            .width(min: 50, ideal: 60)

            TableColumn("Peak (lbs)", value: \.sortPeakForce) { test in
                Text(peakForce(for: test))
                    .monospacedDigit()
            }
            .width(min: 65, ideal: 75)

            TableColumn("Tested", value: \.sortTestedDate) { test in
                Text(testedDateText(for: test))
            }
            .width(min: 65, ideal: 80)
        } rows: {
            ForEach(sortedFilteredTests, id: \.persistentModelID) { test in
                TableRow(test)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            deleteTest(test)
                        }
                    }
            }
        }
    }

    private func peakForce(for test: PullTest) -> String {
        guard let peak = test.measurements.compactMap(\.force).max() else { return "—" }
        return String(format: "%.0f", peak)
    }

    private func testedDateText(for test: PullTest) -> String {
        guard let date = test.testedDate else { return "—" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
    #endif

    // MARK: - iOS List

    #if os(iOS)
    private var iosList: some View {
        Group {
            if horizontalSizeClass == .compact {
                List {
                    ForEach(filteredTests, id: \.persistentModelID) { test in
                        NavigationLink {
                            TestDetailView(test: test)
                        } label: {
                            TestRowView(test: test)
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                deleteTest(test)
                            }
                        }
                    }
                    .onDelete(perform: deleteTests)
                }
            } else {
                List(selection: $selectedTestIDs) {
                    ForEach(filteredTests, id: \.persistentModelID) { test in
                        TestRowView(test: test)
                            .tag(test.persistentModelID)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    deleteTest(test)
                                }
                            }
                    }
                    .onDelete(perform: deleteTests)
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

    // MARK: - Actions

    private func addTest() {
        withAnimation {
            let nextNumber = (allTests.compactMap { test in
                guard let id = test.legacyTestID, id.hasPrefix("T") else { return nil }
                return Int(id.dropFirst())
            }.max() ?? 0) + 1
            let testID = String(format: "T%03d", nextNumber)
            let test = PullTest(
                legacyTestID: testID,
                product: product,
                status: .planned
            )
            modelContext.insert(test)
            selectedTestIDs = [test.persistentModelID]
        }
    }

    private func deleteTest(_ test: PullTest) {
        withAnimation {
            selectedTestIDs.remove(test.persistentModelID)
            modelContext.delete(test)
        }
    }

    private func deleteTests(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                deleteTest(filteredTests[index])
            }
        }
    }
}

private extension PullTest {
    var sortLegacyTestID: String { legacyTestID ?? "" }
    var sortStatus: String { status.rawValue }
    var sortProductSKU: String { product?.sku ?? "" }
    var sortAdhesiveSKU: String { adhesive?.sku ?? "" }
    var sortHoleDiameter: String { holeDiameter?.rawValue ?? "" }
    var sortPeakForce: Double { measurements.compactMap(\.force).max() ?? 0 }
    var sortTestedDate: Date { testedDate ?? .distantPast }
}
