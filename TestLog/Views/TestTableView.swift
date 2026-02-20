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
    @Query(sort: \Site.name) private var allSites: [Site]
    @State private var searchText = ""
    @State private var sortOrder: [KeyPathComparator<PullTest>] = [
        KeyPathComparator(\PullTest.sortTestID, comparator: .localizedStandard)
    ]
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    private var filteredTests: [PullTest] {
        let base = tests
        guard !searchText.isEmpty else { return base }
        let text = searchText.lowercased()
        return base.filter { test in
            (test.testID?.lowercased().contains(text) ?? false) ||
            (test.site?.name.lowercased().contains(text) ?? false) ||
            (test.location?.displayLabel.lowercased().contains(text) ?? false) ||
            (test.product?.name.lowercased().contains(text) ?? false) ||
            (test.adhesive?.name.lowercased().contains(text) ?? false) ||
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
            TableColumn("ID", value: \.sortTestID) { test in
                Text(test.testID ?? "—")
                    .fontWeight(.medium)
            }
            .width(min: 50, ideal: 65)

            TableColumn("Status", value: \.sortStatus) { test in
                StatusBadge(status: test.status)
            }
            .width(min: 75, ideal: 85)

            TableColumn("Product", value: \.sortProductName) { test in
                Text(test.product?.name ?? "—")
            }
            .width(min: 50, ideal: 60)

            TableColumn("Adhesive", value: \.sortAdhesiveName) { test in
                Text(test.adhesive?.name ?? "—")
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
                        Button("Duplicate Test") {
                            duplicateTest(test)
                        }
                        Divider()
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
                            Button("Duplicate Test") {
                                duplicateTest(test)
                            }
                            Divider()
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
                                Button("Duplicate Test") {
                                    duplicateTest(test)
                                }
                                Divider()
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
            let testID = nextTestID()
            let test = PullTest(
                testID: testID,
                product: product,
                site: defaultSite()
            )
            modelContext.insert(test)
            selectedTestIDs = [test.persistentModelID]
        }
    }

    private func duplicateTest(_ source: PullTest) {
        withAnimation {
            let duplicatedLocation = source.location.map { location in
                Location(
                    label: location.label,
                    site: location.site ?? source.site,
                    gridColumn: nil,
                    gridRow: nil,
                    notes: location.notes
                )
            }

            let duplicate = PullTest(
                testID: nextTestID(),
                product: source.product,
                site: source.site,
                location: duplicatedLocation,
                installedDate: source.installedDate,
                testedDate: source.testedDate,
                anchorMaterial: source.anchorMaterial,
                adhesive: source.adhesive,
                holeDiameter: source.holeDiameter,
                cureDays: source.cureDays,
                pavementTemp: source.pavementTemp,
                brushSize: source.brushSize,
                testType: source.testType,
                failureFamily: source.failureFamily,
                failureMechanism: source.failureMechanism,
                failureBehavior: source.failureBehavior,
                failureMode: source.failureMode,
                notes: source.notes
            )

            duplicate.measurements = source.measurements.map { measurement in
                TestMeasurement(
                    label: measurement.label,
                    force: measurement.force,
                    displacement: measurement.displacement,
                    timestamp: measurement.timestamp,
                    isManual: measurement.isManual,
                    sortOrder: measurement.sortOrder
                )
            }

            duplicate.assets = source.assets.map { asset in
                Asset(
                    assetType: asset.assetType,
                    filename: asset.filename,
                    fileURL: asset.fileURL,
                    createdAt: asset.createdAt,
                    notes: asset.notes
                )
            }

            modelContext.insert(duplicate)
            selectedTestIDs = [duplicate.persistentModelID]
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

    private func defaultSite() -> Site? {
        allSites.first(where: \.isPrimaryPad) ?? allSites.first
    }

    private func nextTestID() -> String {
        let nextNumber = (allTests.compactMap { test in
            guard let id = test.testID, id.hasPrefix("T") else { return nil }
            return Int(id.dropFirst())
        }.max() ?? 0) + 1
        return String(format: "T%03d", nextNumber)
    }
}

private extension PullTest {
    var sortTestID: String { testID ?? "" }
    var sortStatus: String { status.rawValue }
    var sortProductName: String { product?.name ?? "" }
    var sortAdhesiveName: String { adhesive?.name ?? "" }
    var sortHoleDiameter: String { holeDiameter?.rawValue ?? "" }
    var sortPeakForce: Double { measurements.compactMap(\.force).max() ?? 0 }
    var sortTestedDate: Date { testedDate ?? .distantPast }
}
