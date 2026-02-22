import SwiftUI
import SwiftData

struct TestSiteLocationSection: View {
    @Bindable var test: PullTest
    let allSites: [Site]
    let allTests: [PullTest]
    let modelContext: ModelContext

    @State private var isGridPreviewExpanded = false

    var body: some View {
        Section("Site & Grid") {
            Picker("Site", selection: $test.site) {
                Text("None").tag(nil as Site?)
                ForEach(allSites, id: \.persistentModelID) { site in
                    Text(site.name).tag(site as Site?)
                }
            }

            if allSites.isEmpty {
                Button("Create Main Pad Site") {
                    let site = Site(name: "Main Pad", isPrimaryPad: true, gridColumns: 50, gridRows: 50)
                    modelContext.insert(site)
                    test.site = site
                }
            }

            if let location = test.location {
                locationEditor(location)
            }
        }
        .onAppear {
            ensureLocationExists()
            test.location?.site = test.site
        }
        .onChange(of: test.persistentModelID) { _, _ in
            ensureLocationExists()
            test.location?.site = test.site
        }
        .onChange(of: test.site?.persistentModelID) { _, _ in
            ensureLocationExists()
            test.location?.site = test.site
        }
    }

    @ViewBuilder
    private func locationEditor(_ location: Location) -> some View {
        Group {
            TextField(
                "Grid Column",
                text: Binding(
                    get: { location.gridColumn ?? "" },
                    set: { location.gridColumn = GridCoordinateCodec.normalizedGridColumnOrNil($0) }
                )
            )

            HStack {
                Text("Grid Row")
                Spacer()
                TextField(
                    "",
                    value: Binding(
                        get: { location.gridRow },
                        set: { location.gridRow = $0 }
                    ),
                    format: .number
                )
                .labelsHidden()
                .multilineTextAlignment(.trailing)
#if os(iOS)
                .keyboardType(.numberPad)
#endif
                .frame(width: 80)
            }

            if let coordinate = GridCoordinateCodec.coordinateLabel(
                column: location.gridColumn,
                row: location.gridRow
            ) {
                LabeledContent("Coordinate", value: coordinate)
            }

            if
                let columnIndex = GridCoordinateCodec.gridColumnIndex(from: location.gridColumn),
                let rowIndex = GridCoordinateCodec.validGridRow(location.gridRow)
            {
                let previewColumns = max(siteGridColumns, columnIndex)
                let previewRows = max(siteGridRows, rowIndex)
                DisclosureGroup("Grid Preview", isExpanded: $isGridPreviewExpanded) {
                    GridCoordinatePreview(
                        columnIndex: columnIndex,
                        rowIndex: rowIndex,
                        totalColumns: previewColumns,
                        totalRows: previewRows,
                        maxColumnLabel: GridCoordinateCodec.gridColumnLabel(for: previewColumns)
                    )
                    .padding(.top, 6)
                }
            }

            if let conflictMessage = locationConflictMessage(for: location) {
                Label(conflictMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

        }
    }

    private func ensureLocationExists() {
        guard test.location == nil else { return }
        let location = Location(site: test.site)
        modelContext.insert(location)
        test.location = location
    }

    private var siteGridColumns: Int {
        max(test.site?.gridColumns ?? 0, 1)
    }

    private var siteGridRows: Int {
        max(test.site?.gridRows ?? 0, 1)
    }

    private func locationConflictMessage(for location: Location) -> String? {
        guard
            let siteID = test.site?.persistentModelID,
            let key = GridCoordinateCodec.coordinateKey(column: location.gridColumn, row: location.gridRow)
        else {
            return nil
        }

        let conflicts = allTests.filter { other in
            guard other.persistentModelID != test.persistentModelID else { return false }
            guard other.site?.persistentModelID == siteID else { return false }
            return GridCoordinateCodec.coordinateKey(
                column: other.location?.gridColumn,
                row: other.location?.gridRow
            ) == key
        }

        guard !conflicts.isEmpty else { return nil }
        let labels = conflicts.compactMap { $0.testID }.sorted()
        guard !labels.isEmpty else {
            return "This coordinate is already used by another test."
        }

        if labels.count > 3 {
            let summary = labels.prefix(3).joined(separator: ", ")
            return "This coordinate is already used by \(summary), +\(labels.count - 3) more."
        }

        return "This coordinate is already used by \(labels.joined(separator: ", "))."
    }
}

private struct GridCoordinatePreview: View {
    let columnIndex: Int
    let rowIndex: Int
    let totalColumns: Int
    let totalRows: Int
    let maxColumnLabel: String

    private let cellSize: CGFloat = 10

    private var previewWidth: CGFloat {
        CGFloat(totalColumns) * cellSize
    }

    private var previewHeight: CGFloat {
        CGFloat(totalRows) * cellSize
    }

    private var viewportHeight: CGFloat {
        min(360, max(180, previewHeight))
    }

    private var pointX: CGFloat {
        (CGFloat(columnIndex) - 0.5) * cellSize
    }

    private var pointY: CGFloat {
        (CGFloat(rowIndex) - 0.5) * cellSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack {
                    Text("Row 1")
                    Spacer()
                    Text("Row \(totalRows)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(height: viewportHeight)

                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary.opacity(0.2))
                            .frame(width: previewWidth, height: previewHeight)

                        Path { path in
                            if totalColumns > 1 {
                                for column in 1..<totalColumns {
                                    let x = CGFloat(column) * cellSize
                                    path.move(to: CGPoint(x: x, y: 0))
                                    path.addLine(to: CGPoint(x: x, y: previewHeight))
                                }
                            }

                            if totalRows > 1 {
                                for row in 1..<totalRows {
                                    let y = CGFloat(row) * cellSize
                                    path.move(to: CGPoint(x: 0, y: y))
                                    path.addLine(to: CGPoint(x: previewWidth, y: y))
                                }
                            }
                        }
                        .stroke(.secondary.opacity(0.25), lineWidth: 0.5)

                        Circle()
                            .fill(.red)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .position(x: pointX, y: pointY)
                    }
                    .frame(width: previewWidth, height: previewHeight)
                }
                .frame(height: viewportHeight)
            }

            HStack {
                Text("A")
                Spacer()
                Text(maxColumnLabel)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
