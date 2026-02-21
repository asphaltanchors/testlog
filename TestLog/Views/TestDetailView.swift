//
//  TestDetailView.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct TestDetailView: View {
    @Bindable var test: PullTest
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Product.name) private var allProducts: [Product]
    @Query(sort: \Site.name) private var allSites: [Site]
    @Query private var allTests: [PullTest]
    @Query private var allAssets: [Asset]

    private var anchorProducts: [Product] {
        allProducts.filter {
            $0.category == .anchor &&
            ($0.isActive || $0.persistentModelID == test.product?.persistentModelID)
        }
    }
    private var adhesiveProducts: [Product] {
        allProducts.filter {
            $0.category == .adhesive &&
            ($0.isActive || $0.persistentModelID == test.adhesive?.persistentModelID)
        }
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
    @State private var isGridPreviewExpanded = false
    @State private var isImportingAssets = false
    @State private var pendingImportCandidates: [ImportedAssetCandidate] = []
    @State private var showingImportReview = false
    @State private var showingVideoWorkspace = false
    @State private var isImportingCandidates = false
    @State private var importStatusMessage: String?
    @State private var mediaErrorMessage: String?

    private let storageManager: AssetStorageManaging = ManagedAssetStorageManager()
    private let assetValidator: AssetValidation = PullTestAssetValidator()

    var body: some View {
        Form {
            // MARK: - Identity
            Section("Identity") {
                TextField("Test ID", text: Binding(
                    get: { test.testID ?? "" },
                    set: { test.testID = $0.isEmpty ? nil : $0 }
                ))
            }

            siteAndLocationSection

            // MARK: - Product
            Section("Product") {
                Picker("Anchor", selection: $test.product) {
                    Text("None").tag(nil as Product?)
                    ForEach(anchorProducts, id: \.persistentModelID) { product in
                        Text(productLabel(product))
                            .tag(product as Product?)
                    }
                }

                Picker("Adhesive", selection: $test.adhesive) {
                    Text("None").tag(nil as Product?)
                    ForEach(adhesiveProducts, id: \.persistentModelID) { product in
                        Text(productLabel(product))
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

#if os(macOS)
            mediaSection
#endif
        }
        .navigationTitle(test.testID ?? "New Test")
        .onAppear {
            test.syncFailureFieldsFromModeIfNeeded()
            test.normalizeFailureSelections()
            test.location?.site = test.site
        }
        .onChange(of: test.testType) { _, _ in
            test.normalizeFailureSelections()
        }
        .onChange(of: test.failureFamily) { _, _ in
            test.normalizeFailureSelections()
        }
        .onChange(of: test.site?.persistentModelID) { _, _ in
            test.location?.site = test.site
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
            Text("This will permanently delete \(test.testID ?? "this test") and all its measurements.")
        }
#if os(macOS)
        .sheet(isPresented: $showingImportReview) {
            importReviewSheet
                .padding(18)
                .frame(width: 560)
                .fixedSize(horizontal: false, vertical: true)
                .presentationSizing(.fitted)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            guard !isImportingCandidates else { return }
                            pendingImportCandidates = []
                            showingImportReview = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isImportingCandidates ? "Importing..." : "Import") {
                            isImportingCandidates = true
                            importStatusMessage = "Preparing import..."
                            Task {
                                await importPendingCandidates()
                            }
                        }
                        .disabled(pendingImportCandidates.isEmpty || isImportingCandidates)
                    }
                }
        }
        .sheet(isPresented: $showingVideoWorkspace) {
            VideoWorkspaceView(test: test)
                .frame(minWidth: 980, idealWidth: 1240, minHeight: 760, idealHeight: 920)
                .presentationSizing(.page)
        }
        .onChange(of: showingImportReview) { _, newValue in
            if !newValue {
                isImportingCandidates = false
                importStatusMessage = nil
            }
        }
        .fileImporter(
            isPresented: $isImportingAssets,
            allowedContentTypes: [.movie, .mpeg4Movie, .data],
            allowsMultipleSelection: true
        ) { result in
            handleFileImportSelection(result)
        }
#endif
        .alert("Media Error", isPresented: Binding(
            get: { mediaErrorMessage != nil },
            set: { if !$0 { mediaErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mediaErrorMessage ?? "Unknown error.")
        }
    }

    private func deleteMeasurements(at offsets: IndexSet) {
        let sorted = test.measurements.sorted(by: { $0.sortOrder < $1.sortOrder })
        for index in offsets {
            modelContext.delete(sorted[index])
        }
    }

    private func productLabel(_ product: Product) -> String {
        product.isActive ? product.name : "\(product.name) (Archived)"
    }

    @ViewBuilder
    private var siteAndLocationSection: some View {
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
            } else {
                Button("Add Location") {
                    let location = Location(site: test.site)
                    modelContext.insert(location)
                    test.location = location
                }
            }
        }
    }

    @ViewBuilder
    private func locationEditor(_ location: Location) -> some View {
        Group {
            TextField("Grid Column", text: Binding(
                get: { location.gridColumn ?? "" },
                set: { location.gridColumn = normalizedGridColumnOrNil($0) }
            ))

            HStack {
                Text("Grid Row")
                Spacer()
                TextField("", value: Binding(
                    get: { location.gridRow },
                    set: { location.gridRow = $0 }
                ), format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                #if os(iOS)
                    .keyboardType(.numberPad)
                #endif
                    .frame(width: 80)
            }

            if let coordinate = coordinateLabel(column: location.gridColumn, row: location.gridRow) {
                LabeledContent("Coordinate", value: coordinate)
            } else {
                Text("Use spreadsheet-style coordinates like A1, L50, or AX15.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if
                let columnIndex = gridColumnIndex(from: location.gridColumn),
                let rowIndex = validGridRow(location.gridRow)
            {
                let previewColumns = max(siteGridColumns, columnIndex)
                let previewRows = max(siteGridRows, rowIndex)
                DisclosureGroup("Grid Preview", isExpanded: $isGridPreviewExpanded) {
                    GridCoordinatePreview(
                        columnIndex: columnIndex,
                        rowIndex: rowIndex,
                        totalColumns: previewColumns,
                        totalRows: previewRows,
                        maxColumnLabel: gridColumnLabel(for: previewColumns)
                    )
                    .padding(.top, 6)
                }
            }

            if let conflictMessage = locationConflictMessage(for: location) {
                Label(conflictMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button("Clear Location", role: .destructive) {
                modelContext.delete(location)
                test.location = nil
            }
        }
    }

    private var siteGridColumns: Int {
        max(test.site?.gridColumns ?? 0, 1)
    }

    private var siteGridRows: Int {
        max(test.site?.gridRows ?? 0, 1)
    }

    private func validGridRow(_ row: Int?) -> Int? {
        guard let row, row > 0 else { return nil }
        return row
    }

    private func coordinateLabel(column: String?, row: Int?) -> String? {
        guard
            let columnIndex = gridColumnIndex(from: column),
            let row = validGridRow(row)
        else {
            return nil
        }
        return "\(gridColumnLabel(for: columnIndex))\(row)"
    }

    private func gridCoordinateKey(column: String?, row: Int?) -> String? {
        guard
            let columnIndex = gridColumnIndex(from: column),
            let row = validGridRow(row)
        else {
            return nil
        }
        return "\(columnIndex)-\(row)"
    }

    private func locationConflictMessage(for location: Location) -> String? {
        guard
            let siteID = test.site?.persistentModelID,
            let key = gridCoordinateKey(column: location.gridColumn, row: location.gridRow)
        else {
            return nil
        }

        let conflicts = allTests.filter { other in
            guard other.persistentModelID != test.persistentModelID else { return false }
            guard other.site?.persistentModelID == siteID else { return false }
            return gridCoordinateKey(column: other.location?.gridColumn, row: other.location?.gridRow) == key
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

    private func gridColumnIndex(from value: String?) -> Int? {
        guard let normalized = normalizedGridColumnOrNil(value ?? "") else { return nil }

        if let numeric = Int(normalized), numeric > 0 {
            return numeric
        }

        let uppercased = normalized.uppercased()
        guard uppercased.allSatisfy(\.isLetter) else { return nil }

        var value = 0
        for scalar in uppercased.unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { return nil }
            value = value * 26 + Int(scalar.value - 64)
        }
        return value > 0 ? value : nil
    }

    private func gridColumnLabel(for index: Int) -> String {
        guard index > 0 else { return "?" }

        var value = index
        var characters: [Character] = []
        while value > 0 {
            let remainder = (value - 1) % 26
            guard let scalar = UnicodeScalar(65 + remainder) else { break }
            characters.append(Character(scalar))
            value = (value - 1) / 26
        }
        return String(characters.reversed())
    }

    private func normalizedGridColumnOrNil(_ value: String) -> String? {
        let compact = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
        return compact.isEmpty ? nil : compact
    }

#if os(macOS)
    @ViewBuilder
    private var mediaSection: some View {
        Section("Media") {
            Button("Attach Files") {
                isImportingAssets = true
            }

            Button("Open Video Workspace") {
                showingVideoWorkspace = true
            }
            .disabled(test.videoAssets.isEmpty)

            if !test.assets.isEmpty {
                ForEach(test.assets.sorted(by: { $0.createdAt > $1.createdAt }), id: \.persistentModelID) { asset in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(asset.filename)
                                .font(.headline)
                            Text("\(asset.assetType.rawValue) • \(asset.videoRole?.rawValue ?? "—")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let bytes = asset.byteSize {
                                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            removeAsset(asset)
                        }
                    }
                }
            } else {
                Text("No media assets attached.")
                    .foregroundStyle(.secondary)
            }

            if let issue = test.validationIssues.first {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            Text(test.videoAssets.isEmpty ? "Attach at least one video to open the workspace." : "Open Video Workspace to trim, align, and export.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var importReviewSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Asset Import")
                .font(.title3.weight(.semibold))

            Group {
                if pendingImportCandidates.count > 3 {
                    ScrollView {
                        importCandidateCards
                    }
                    .frame(maxHeight: 240)
                } else {
                    importCandidateCards
                }
            }

            HStack {
                if isImportingCandidates {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                Text(importStatusMessage ?? "Ready to import \(pendingImportCandidates.count) file(s).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var importCandidateCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($pendingImportCandidates) { $candidate in
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(candidate.sourceURL.lastPathComponent)
                            .font(.headline)

                        Picker("Type", selection: $candidate.selectedAssetType) {
                            Text(AssetType.video.rawValue).tag(AssetType.video)
                            Text(AssetType.testerData.rawValue).tag(AssetType.testerData)
                            Text(AssetType.document.rawValue).tag(AssetType.document)
                        }

                        if candidate.selectedAssetType == .video {
                            Picker("Video Role", selection: $candidate.selectedVideoRole) {
                                ForEach(VideoRole.allCases) { role in
                                    Text(role.rawValue).tag(role)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func assetIdentifier(_ asset: Asset) -> String {
        String(describing: asset.persistentModelID)
    }

    private func handleFileImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            pendingImportCandidates = urls.map { url in
                var candidate = ImportedAssetCandidate(sourceURL: url, suggestedAssetType: suggestedType(for: url))
                if candidate.selectedAssetType == .video {
                    candidate.selectedVideoRole = suggestedRoleForNewVideo()
                }
                return candidate
            }
            showingImportReview = !pendingImportCandidates.isEmpty
        case .failure(let error):
            mediaErrorMessage = error.localizedDescription
        }
    }

    private func suggestedType(for url: URL) -> AssetType {
        let ext = url.pathExtension.lowercased()
        if ["mov", "mp4", "m4v"].contains(ext) { return .video }
        return .testerData
    }

    private func suggestedRoleForNewVideo() -> VideoRole {
        let existingRoles = Set(test.videoAssets.compactMap(\.videoRole))
        if !existingRoles.contains(.anchorView) { return .anchorView }
        if !existingRoles.contains(.equipmentView) { return .equipmentView }
        return .unassigned
    }

    private func importPendingCandidates() async {
        await Task.yield()
        importStatusMessage = "Validating files..."
        defer {
            isImportingCandidates = false
        }

        do {
            try assetValidator.validate(candidates: pendingImportCandidates, existingAssets: test.assets)
            let total = pendingImportCandidates.count
            for (index, candidate) in pendingImportCandidates.enumerated() {
                importStatusMessage = "Importing \(index + 1) of \(total): \(candidate.sourceURL.lastPathComponent)"
                let imported = try await processCandidateOffMain(candidate)
                let asset = Asset(
                    test: test,
                    assetType: imported.assetType,
                    filename: candidate.sourceURL.lastPathComponent,
                    fileURL: imported.destinationURL,
                    notes: nil,
                    byteSize: imported.metadata.byteSize,
                    contentType: imported.metadata.contentType,
                    checksumSHA256: imported.metadata.checksumSHA256,
                    durationSeconds: imported.metadata.durationSeconds,
                    frameRate: imported.metadata.frameRate,
                    videoWidth: imported.metadata.videoWidth,
                    videoHeight: imported.metadata.videoHeight,
                    isManagedCopy: true,
                    videoRole: imported.assetType == .video ? imported.videoRole : nil
                )
                modelContext.insert(asset)
                test.assets.append(asset)

                if imported.assetType == .testerData {
                    if let testerPeakForce = imported.testerPeakForceLbs {
                        test.upsertTesterMaxMeasurement(forceLbs: testerPeakForce)
                    } else {
                        test.removeTesterMaxMeasurement()
                    }
                }
            }
            importStatusMessage = "Import complete."
            showingImportReview = false
            pendingImportCandidates = []
        } catch {
            mediaErrorMessage = error.localizedDescription
            importStatusMessage = "Import failed."
        }
    }

    private func processCandidateOffMain(_ candidate: ImportedAssetCandidate) async throws -> ImportedAssetWorkResult {
        let testStorageKey = test.testID?.isEmpty == false ? (test.testID ?? "Unknown") : String(describing: test.persistentModelID)
        return try await Task.detached(priority: .userInitiated) {
            let storage = ManagedAssetStorageManager()
            let probe = DefaultAssetMetadataProbe()

            let startedScopedAccess = candidate.sourceURL.startAccessingSecurityScopedResource()
            defer {
                if startedScopedAccess {
                    candidate.sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let provisionalID = UUID()
            let destinationURL = try storage.copyIntoManagedStorage(
                from: candidate.sourceURL,
                forTestStorageKey: testStorageKey,
                assetID: provisionalID,
                originalFilename: candidate.sourceURL.lastPathComponent
            )
            let metadata = try await probe.probe(url: destinationURL, assetType: candidate.selectedAssetType)
            let testerPeakForceLbs: Double?
            if candidate.selectedAssetType == .testerData {
                let parser = LBYTesterDataParser()
                let samples = try parser.parseSamples(from: destinationURL)
                testerPeakForceLbs = samples
                    .map(\.forceLbs)
                    .filter { $0.isFinite && $0 > 0 }
                    .max()
            } else {
                testerPeakForceLbs = nil
            }
            return ImportedAssetWorkResult(
                destinationURL: destinationURL,
                assetType: candidate.selectedAssetType,
                videoRole: candidate.selectedVideoRole,
                metadata: metadata,
                testerPeakForceLbs: testerPeakForceLbs
            )
        }.value
    }

    private func removeAsset(_ asset: Asset) {
        do {
            try storageManager.removeManagedFileIfUnreferenced(asset, allAssets: allAssets)
            if test.videoSyncConfiguration?.primaryVideoAssetID == assetIdentifier(asset) {
                test.videoSyncConfiguration?.primaryVideoAssetID = nil
            }
            if test.videoSyncConfiguration?.equipmentVideoAssetID == assetIdentifier(asset) {
                test.videoSyncConfiguration?.equipmentVideoAssetID = nil
            }
            if asset.assetType == .testerData {
                test.removeTesterMaxMeasurement()
            }
            modelContext.delete(asset)
        } catch {
            mediaErrorMessage = error.localizedDescription
        }
    }

#endif

}

private struct ImportedAssetWorkResult: Sendable {
    let destinationURL: URL
    let assetType: AssetType
    let videoRole: VideoRole
    let metadata: AssetImportMetadata
    let testerPeakForceLbs: Double?
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

// MARK: - Measurement Row

struct MeasurementRowView: View {
    @Bindable var measurement: TestMeasurement

    var body: some View {
        HStack {
            if measurement.isManual {
                TextField("", text: $measurement.label, prompt: Text("Label"))
                    .labelsHidden()
                    .frame(minWidth: 100, maxWidth: 150, alignment: .leading)

                Spacer()

                TextField(
                    "",
                    value: $measurement.force,
                    format: .number.precision(.fractionLength(0))
                )
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                    .keyboardType(.decimalPad)
                #endif
                    .frame(width: 110)
            } else {
                Text(measurement.label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(measurement.force.map { String(format: "%.0f", $0) } ?? "—")
                    .monospacedDigit()
            }
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
