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
    var onAddSite: () -> Void

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
            ToolbarItem {
                Button(action: onAddSite) {
                    Label("Add Site", systemImage: "plus")
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

            Section("Tests (\(relatedTests.count))") {
                if relatedTests.isEmpty {
                    Text("No tests mapped to this site yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(relatedTests, id: \.persistentModelID) { test in
                        HStack {
                            Text(test.testID ?? "—")
                            Spacer()
                            StatusBadge(status: test.status)
                        }
                    }
                }
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

private extension Site {
    var sortName: String { name }
    var sortGrid: String {
        guard let columns = gridColumns, let rows = gridRows else { return "" }
        return String(format: "%03d-%03d", columns, rows)
    }
    var sortUsageCount: Int { 0 }
}
