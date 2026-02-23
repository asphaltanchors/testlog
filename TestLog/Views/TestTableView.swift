//
//  TestTableView.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TestTableView: View {
    let tests: [PullTest]
    @Binding var selectedTestIDs: Set<PersistentIdentifier>
    let title: String
    var product: Product? = nil
    var onDropFilesOntoTest: ((PullTest, [URL]) -> Void)? = nil

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
#if os(macOS)
    @State private var previousMacSelection: Set<PersistentIdentifier> = []
    @State private var tableMouseMonitor: Any?
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
#if os(macOS)
        .onAppear {
            guard tableMouseMonitor == nil else { return }
            tableMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
                guard
                    let window = event.window ?? NSApp.keyWindow,
                    let contentView = window.contentView
                else {
                    return event
                }

                let locationInContent = contentView.convert(event.locationInWindow, from: nil)
                let hitView = contentView.hitTest(locationInContent)
                let hitTable = Self.findTableView(from: hitView)
                let responder = window.firstResponder
                let responderName = responder.map { String(describing: type(of: $0)) } ?? "nil"

                if hitTable != nil, responderName.contains("FieldEditor") {
                    window.makeFirstResponder(nil)
                    // Re-post so the row click still lands after ending field editing.
                    DispatchQueue.main.async {
                        NSApp.sendEvent(event)
                    }
                    return nil
                }

                return event
            }
        }
        .onDisappear {
            if let tableMouseMonitor {
                NSEvent.removeMonitor(tableMouseMonitor)
                self.tableMouseMonitor = nil
            }
        }
        .onChange(of: selectedTestIDs) { _, newValue in
            previousMacSelection = newValue
        }
#endif
    }

    // MARK: - macOS Table

    #if os(macOS)
    private var macTable: some View {
        Table(of: PullTest.self, selection: macSelectionBinding, sortOrder: $sortOrder) {
            TableColumn("ID", value: \.sortTestID) { test in
                Text(test.testID ?? "—")
                    .fontWeight(.medium)
            }
            .width(min: 50, ideal: 65)

            TableColumn("Status", value: \.sortStatus) { test in
                HStack(spacing: 4) {
                    StatusBadge(status: test.status)
                    if !test.isValid {
                        InvalidBadge()
                    }
                }
            }
            .width(min: 75, ideal: 130)

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
                    .foregroundStyle(peakForceColor(for: test))
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
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard let selectedTest = selectedTestForDrop else { return false }
            return handleDroppedFileProviders(providers) { urls in
                onDropFilesOntoTest?(selectedTest, urls)
            }
        }
        .onMoveCommand(perform: handleMacMoveCommand)
    }

    private var selectedTestForDrop: PullTest? {
        guard selectedTestIDs.count == 1, let selectedID = selectedTestIDs.first else { return nil }
        return sortedFilteredTests.first(where: { $0.persistentModelID == selectedID })
    }

    private func peakForce(for test: PullTest) -> String {
        guard let peak = test.peakForceLbs else { return "—" }
        return String(format: "%.0f", peak)
    }

    private func peakForceColor(for test: PullTest) -> Color {
        guard let peak = test.peakForceLbs, let rated = test.product?.ratedStrengthLbs else {
            return .primary
        }
        let ratedDouble = Double(rated)
        if peak < ratedDouble { return .red }
        if peak >= ratedDouble * 2 { return .green }
        return .primary
    }

    private func testedDateText(for test: PullTest) -> String {
        guard let date = test.testedDate else { return "—" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var macSelectionBinding: Binding<Set<PersistentIdentifier>> {
        Binding(
            get: { selectedTestIDs },
            set: { newValue in
                let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                let isMultiSelectIntent = modifiers.contains(.command) || modifiers.contains(.shift)

                guard !isMultiSelectIntent, newValue.count > 1 else {
                    selectedTestIDs = newValue
                    previousMacSelection = selectedTestIDs
                    return
                }

                if let newest = newValue.subtracting(previousMacSelection).first {
                    selectedTestIDs = [newest]
                } else if let visibleFallback = sortedFilteredTests
                    .map(\.persistentModelID)
                    .first(where: { newValue.contains($0) }) {
                    selectedTestIDs = [visibleFallback]
                } else {
                    selectedTestIDs = []
                }
                previousMacSelection = selectedTestIDs
            }
        )
    }

    private func handleMacMoveCommand(_ direction: MoveCommandDirection) {
        let orderedIDs = sortedFilteredTests.map(\.persistentModelID)
        guard !orderedIDs.isEmpty else { return }

        switch direction {
        case .down:
            guard let currentID = selectedTestIDs.first else {
                selectedTestIDs = [orderedIDs[0]]
                previousMacSelection = selectedTestIDs
                return
            }

            guard let currentIndex = orderedIDs.firstIndex(of: currentID) else {
                selectedTestIDs = [orderedIDs[0]]
                previousMacSelection = selectedTestIDs
                return
            }

            let nextIndex = min(currentIndex + 1, orderedIDs.count - 1)
            selectedTestIDs = [orderedIDs[nextIndex]]
            previousMacSelection = selectedTestIDs

        case .up:
            guard let currentID = selectedTestIDs.first else {
                selectedTestIDs = [orderedIDs[orderedIDs.count - 1]]
                previousMacSelection = selectedTestIDs
                return
            }

            guard let currentIndex = orderedIDs.firstIndex(of: currentID) else {
                selectedTestIDs = [orderedIDs[orderedIDs.count - 1]]
                previousMacSelection = selectedTestIDs
                return
            }

            let previousIndex = max(currentIndex - 1, 0)
            selectedTestIDs = [orderedIDs[previousIndex]]
            previousMacSelection = selectedTestIDs

        default:
            break
        }
    }

    private static func findTableView(from view: NSView?) -> NSTableView? {
        var node = view
        while let current = node {
            if let table = current as? NSTableView {
                return table
            }
            node = current.superview
        }
        return nil
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
                site: defaultSite(),
                holeDiameter: product?.defaultHoleDiameter
            )
            modelContext.insert(test)
            selectedTestIDs = [test.persistentModelID]
#if os(macOS)
            previousMacSelection = selectedTestIDs
#endif
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
                    measurementType: measurement.measurementType,
                    force: measurement.force,
                    displacement: measurement.displacement,
                    timestamp: measurement.timestamp,
                    isManual: measurement.isManual,
                    sortOrder: measurement.sortOrder
                )
            }

            modelContext.insert(duplicate)
            selectedTestIDs = [duplicate.persistentModelID]
#if os(macOS)
            previousMacSelection = selectedTestIDs
#endif
        }
    }

    private func deleteTest(_ test: PullTest) {
        withAnimation {
            selectedTestIDs.remove(test.persistentModelID)
#if os(macOS)
            previousMacSelection = selectedTestIDs
#endif
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
    var sortPeakForce: Double { peakForceLbs ?? 0 }
    var sortTestedDate: Date { testedDate ?? .distantPast }
}
