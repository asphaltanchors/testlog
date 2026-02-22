//
//  SiteViews.swift
//  TestLog
//
//  Created by Codex on 2/20/26.
//

import SwiftUI
import SwiftData

struct SiteTableView: View {
    let sites: [Site]
    @Binding var selectedSiteIDs: Set<PersistentIdentifier>
    let title: String
    var onAddSite: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Query private var allTests: [PullTest]
    @State private var searchText = ""
    @State private var sortOrder: [KeyPathComparator<Site>] = [
        KeyPathComparator(\Site.sortName, comparator: .localizedStandard)
    ]

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    private var filteredSites: [Site] {
        guard !searchText.isEmpty else { return sites }
        let text = searchText.lowercased()
        return sites.filter { site in
            site.name.lowercased().contains(text) ||
            (site.notes?.lowercased().contains(text) ?? false) ||
            (site.isPrimaryPad && "primary".contains(text))
        }
    }

    private var sortedFilteredSites: [Site] {
        filteredSites.sorted(using: sortOrder)
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
        .searchable(text: $searchText, prompt: "Search sites...")
        .toolbar {
            if let onAddSite {
                ToolbarItem {
                    Button(action: onAddSite) {
                        Label("Add Site", systemImage: "plus")
                    }
                }
            }
        }
    }

#if os(macOS)
    private var macTable: some View {
        Table(of: Site.self, selection: $selectedSiteIDs, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.sortName) { site in
                HStack {
                    Text(site.name).fontWeight(.medium)
                    if site.isPrimaryPad {
                        Text("Primary")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
            .width(min: 170, ideal: 220)

            TableColumn("Grid", value: \.sortGrid) { site in
                Text(gridText(for: site))
            }
            .width(min: 70, ideal: 90)

            TableColumn("Tests", value: \.sortUsageCount) { site in
                Text("\(usageCount(for: site))")
                    .monospacedDigit()
            }
            .width(min: 55, ideal: 70)
        } rows: {
            ForEach(sortedFilteredSites, id: \.persistentModelID) { site in
                TableRow(site)
                    .contextMenu {
                        Button("Delete Site", role: .destructive) {
                            deleteSite(site)
                        }
                    }
            }
        }
    }
#endif

#if os(iOS)
    private var iosList: some View {
        Group {
            if horizontalSizeClass == .compact {
                List {
                    ForEach(filteredSites, id: \.persistentModelID) { site in
                        NavigationLink {
                            SiteDetailView(site: site)
                        } label: {
                            SiteRow(site: site, usageCount: usageCount(for: site))
                        }
                        .contextMenu {
                            Button("Delete Site", role: .destructive) {
                                deleteSite(site)
                            }
                        }
                    }
                    .onDelete(perform: deleteSites)
                }
            } else {
                List(selection: $selectedSiteIDs) {
                    ForEach(filteredSites, id: \.persistentModelID) { site in
                        SiteRow(site: site, usageCount: usageCount(for: site))
                            .tag(site.persistentModelID)
                            .contextMenu {
                                Button("Delete Site", role: .destructive) {
                                    deleteSite(site)
                                }
                            }
                    }
                    .onDelete(perform: deleteSites)
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

    private func gridText(for site: Site) -> String {
        if let columns = site.gridColumns, let rows = site.gridRows {
            return "\(columns)x\(rows)"
        }
        return "—"
    }

    private func usageCount(for site: Site) -> Int {
        allTests.filter { $0.site?.persistentModelID == site.persistentModelID }.count
    }

    private func deleteSite(_ site: Site) {
        withAnimation {
            selectedSiteIDs.remove(site.persistentModelID)
            modelContext.delete(site)
        }
    }

    private func deleteSites(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                deleteSite(filteredSites[index])
            }
        }
    }
}

private struct SiteRow: View {
    let site: Site
    let usageCount: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(site.name)
                        .fontWeight(.semibold)
                    if site.isPrimaryPad {
                        Text("Primary")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                if let columns = site.gridColumns, let rows = site.gridRows {
                    Text("Grid: \(columns)x\(rows)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(usageCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

struct SiteDetailView: View {
    @Bindable var site: Site
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allSites: [Site]
    @Query private var allTests: [PullTest]
    @State private var showingDeleteConfirmation = false

    private var relatedTests: [PullTest] {
        allTests
            .filter { $0.site?.persistentModelID == site.persistentModelID }
            .sorted { ($0.testedDate ?? .distantPast) > ($1.testedDate ?? .distantPast) }
    }

    var body: some View {
        Form {
            Section("Site Info") {
                TextField("Name", text: $site.name)
                Toggle("Primary Site", isOn: $site.isPrimaryPad)
                    .onChange(of: site.isPrimaryPad) { _, isPrimary in
                        guard isPrimary else { return }
                        for other in allSites where other.persistentModelID != site.persistentModelID {
                            other.isPrimaryPad = false
                        }
                    }

                HStack {
                    Text("Grid Columns")
                    Spacer()
                    TextField("", value: $site.gridColumns, format: .number)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                    #if os(iOS)
                        .keyboardType(.numberPad)
                    #endif
                        .frame(width: 90)
                }

                HStack {
                    Text("Grid Rows")
                    Spacer()
                    TextField("", value: $site.gridRows, format: .number)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                    #if os(iOS)
                        .keyboardType(.numberPad)
                    #endif
                        .frame(width: 90)
                }

                TextField("Notes", text: Binding(
                    get: { site.notes ?? "" },
                    set: { site.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(2...5)
            }

            Section("Test Grid (\(relatedTests.count) mapped)") {
                SiteGridView(site: site, tests: relatedTests)
                    .frame(height: 420)
            }
        }
        .navigationTitle(site.name)
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete Site", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .confirmationDialog("Delete this site?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                modelContext.delete(site)
                dismiss()
            }
        } message: {
            Text("This will delete \(site.name). Tests will lose their site reference.")
        }
    }
}

private struct SiteGridView: View {
    let site: Site
    let tests: [PullTest]

    private var testByPosition: [String: PullTest] {
        var dict: [String: PullTest] = [:]
        for test in tests {
            guard let key = GridCoordinateCodec.coordinateKey(
                column: test.location?.gridColumn,
                row: test.location?.gridRow
            ) else { continue }
            dict[key] = test
        }
        return dict
    }

    static func columnLabel(for index: Int) -> String {
        var result = ""
        var n = index
        while n > 0 {
            n -= 1
            result = String(UnicodeScalar(65 + (n % 26))!) + result
            n /= 26
        }
        return result
    }

    var body: some View {
        if let cols = site.gridColumns, let rows = site.gridRows, cols > 0, rows > 0 {
            gridContent(cols: cols, rows: rows)
        } else {
            Text("Configure grid dimensions in Site Info to see the grid.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func gridContent(cols: Int, rows: Int) -> some View {
        let lookup = testByPosition
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Column header row
                HStack(spacing: 0) {
                    Color.clear.frame(width: 28, height: 20)
                    ForEach(1...cols, id: \.self) { c in
                        Text(Self.columnLabel(for: c))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 20)
                    }
                }
                .background(Color.secondary.opacity(0.08))

                // Data rows
                ForEach(1...rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        Text("\(row)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 36)
                            .background(Color.secondary.opacity(0.08))

                        ForEach(1...cols, id: \.self) { c in
                            SiteGridCell(test: lookup["\(c)-\(row)"])
                        }
                    }
                }
            }
        }
    }
}

private struct SiteGridCell: View {
    let test: PullTest?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(fillColor)
                .overlay(Rectangle().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))

            if let test {
                Text(test.testID ?? "?")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(2)
            }
        }
        .frame(width: 36, height: 36)
    }

    private var fillColor: Color {
        guard let test else { return Color.secondary.opacity(0.06) }
        switch test.status {
        case .planned:   return .blue.opacity(0.2)
        case .installed: return .orange.opacity(0.2)
        case .completed: return .green.opacity(0.2)
        }
    }

    private var labelColor: Color {
        guard let test else { return .secondary }
        switch test.status {
        case .planned:   return .blue
        case .installed: return .orange
        case .completed: return .green
        }
    }
}

private extension Site {
    var sortName: String { name }
    var sortGrid: String {
        guard let columns = gridColumns, let rows = gridRows else { return "" }
        return String(format: "%03d-%03d", columns, rows)
    }
    var sortUsageCount: Int { 0 }
}
