#if os(macOS)
//
//  VideoWorkspaceView.swift
//  TestLog
//
//  Created by Codex on 2/21/26.
//

import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct VideoWorkspaceView: View {
    @Bindable var test: PullTest
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var layoutMode: LayoutMode = .sideBySide
    @State private var isRunningAutoSync = false
    @State private var isExportingVideo = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private let syncService: VideoSyncing = DefaultVideoSyncService()
    private let exportService: VideoExporting = DefaultVideoExportService()
    private let testerDataParser: TesterDataParsing = LBYTesterDataParser()

    enum LayoutMode: String, CaseIterable, Identifiable {
        case sideBySide = "Side by Side"
        case pip = "PiP"

        var id: String { rawValue }
    }

    private var syncConfiguration: VideoSyncConfiguration {
        if let existing = test.videoSyncConfiguration {
            return existing
        }
        let config = VideoSyncConfiguration(test: test)
        modelContext.insert(config)
        test.videoSyncConfiguration = config
        return config
    }

    private var primaryVideoAsset: Asset? {
        if let preferredID = syncConfiguration.primaryVideoAssetID {
            return test.videoAssets.first(where: { assetIdentifier($0) == preferredID })
        }
        return test.videoAssets.first(where: { $0.videoRole == .anchorView }) ?? test.videoAssets.first
    }

    private var equipmentVideoAsset: Asset? {
        if let preferredID = syncConfiguration.equipmentVideoAssetID {
            return test.videoAssets.first(where: { assetIdentifier($0) == preferredID })
        }
        return test.videoAssets.first(where: { $0.videoRole == .equipmentView })
    }

    private var trimRangeUpperBound: Double {
        let duration = primaryVideoAsset?.durationSeconds ?? equipmentVideoAsset?.durationSeconds ?? 60
        return max(duration, 1)
    }

    private var trimInBinding: Binding<Double> {
        Binding(
            get: { min(max(syncConfiguration.trimInSeconds ?? 0, 0), trimRangeUpperBound) },
            set: { newValue in
                let bounded = min(max(newValue, 0), trimRangeUpperBound)
                syncConfiguration.trimInSeconds = bounded
                if let trimOut = syncConfiguration.trimOutSeconds, trimOut < bounded {
                    syncConfiguration.trimOutSeconds = bounded
                }
            }
        )
    }

    private var trimOutBinding: Binding<Double> {
        Binding(
            get: { min(max(syncConfiguration.trimOutSeconds ?? trimRangeUpperBound, 0), trimRangeUpperBound) },
            set: { newValue in
                let bounded = min(max(newValue, 0), trimRangeUpperBound)
                let trimIn = syncConfiguration.trimInSeconds ?? 0
                syncConfiguration.trimOutSeconds = max(trimIn, bounded)
            }
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            header

            GroupBox("Preview") {
                previewArea
                    .frame(minHeight: 320)
            }

            GroupBox("Workspace Controls") {
                VStack(alignment: .leading, spacing: 12) {
                    roleSelectors
                    trimControls
                    alignmentControls
                    actionRow
                }
            }
        }
        .padding(16)
        .navigationTitle("Video Workspace")
        .alert("Video Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(test.testID ?? "Test")
                    .font(.title3.weight(.semibold))
                Text("Trim first, then align, then export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Layout", selection: $layoutMode) {
                ForEach(LayoutMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            Button("Done") {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        if let primary = primaryVideoAsset {
            switch layoutMode {
            case .sideBySide:
                HStack(spacing: 12) {
                    WorkspaceVideoPreview(url: primary.fileURL)
                    if let equipment = equipmentVideoAsset {
                        WorkspaceVideoPreview(url: equipment.fileURL)
                    }
                }
            case .pip:
                ZStack(alignment: .bottomTrailing) {
                    WorkspaceVideoPreview(url: primary.fileURL)
                    if let equipment = equipmentVideoAsset {
                        WorkspaceVideoPreview(url: equipment.fileURL)
                            .frame(width: 320, height: 180)
                            .padding(12)
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "No Videos Attached",
                systemImage: "video.slash",
                description: Text("Attach at least one video before using the workspace.")
            )
        }
    }

    private var roleSelectors: some View {
        VStack(spacing: 8) {
            Picker("Primary Video", selection: Binding(
                get: { syncConfiguration.primaryVideoAssetID ?? "" },
                set: { syncConfiguration.primaryVideoAssetID = $0.isEmpty ? nil : $0 }
            )) {
                Text("Select").tag("")
                ForEach(test.videoAssets, id: \.persistentModelID) { asset in
                    Text(asset.filename).tag(assetIdentifier(asset))
                }
            }

            Picker("Equipment Video", selection: Binding(
                get: { syncConfiguration.equipmentVideoAssetID ?? "" },
                set: { syncConfiguration.equipmentVideoAssetID = $0.isEmpty ? nil : $0 }
            )) {
                Text("None").tag("")
                ForEach(test.videoAssets, id: \.persistentModelID) { asset in
                    Text(asset.filename).tag(assetIdentifier(asset))
                }
            }
        }
    }

    private var trimControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trim Range")
                .font(.headline)

            VStack {
                HStack {
                    Text("Trim In")
                    Slider(value: trimInBinding, in: 0...trimRangeUpperBound)
                    TextField("", value: trimInBinding, format: .number.precision(.fractionLength(2)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                HStack {
                    Text("Trim Out")
                    Slider(value: trimOutBinding, in: 0...trimRangeUpperBound)
                    TextField("", value: trimOutBinding, format: .number.precision(.fractionLength(2)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }

            Text("Duration: \(String(format: "%.2f", trimRangeUpperBound))s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var alignmentControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alignment")
                .font(.headline)

            HStack {
                Text("Auto Offset")
                Spacer()
                Text(String(format: "%.3fs", syncConfiguration.autoOffsetSeconds ?? 0))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Manual Camera Offset")
                Spacer()
                TextField("Seconds", value: Binding(
                    get: { syncConfiguration.manualOffsetSeconds },
                    set: { syncConfiguration.manualOffsetSeconds = $0 }
                ), format: .number.precision(.fractionLength(3)))
                    .frame(width: 120)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var actionRow: some View {
        HStack {
            Button("Auto Sync") {
                Task { await runAutoSync() }
            }
            .disabled(isRunningAutoSync || test.videoAssets.count < 2)

            if isRunningAutoSync || isExportingVideo {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Spacer()

            Button("Export Composed Video") {
                Task { await exportComposedVideo() }
            }
            .disabled(isExportingVideo || primaryVideoAsset == nil)
        }
        .overlay(alignment: .bottomLeading) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 22)
            }
        }
    }

    private func runAutoSync() async {
        guard
            let primary = primaryVideoAsset,
            let equipment = equipmentVideoAsset ?? test.videoAssets.first(where: { $0.persistentModelID != primary.persistentModelID })
        else {
            statusMessage = "Attach at least two videos for auto sync."
            return
        }

        isRunningAutoSync = true
        defer { isRunningAutoSync = false }
        do {
            let result = try await syncService.detectOffset(primaryURL: primary.fileURL, secondaryURL: equipment.fileURL)
            syncConfiguration.autoOffsetSeconds = result.detectedOffsetSeconds
            syncConfiguration.lastSyncedAt = Date()
            statusMessage = "Auto sync complete (offset: \(String(format: "%.3f", result.detectedOffsetSeconds))s, confidence: \(String(format: "%.2f", result.confidence)))."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportComposedVideo() async {
        guard let primary = primaryVideoAsset else {
            errorMessage = VideoFeatureError.missingPrimaryVideo.localizedDescription
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(test.testID ?? "Test")_composed.mp4"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        isExportingVideo = true
        defer { isExportingVideo = false }
        do {
            let samples: [ParsedForceSample]
            if let testerAsset = test.testerBinaryAsset {
                samples = try testerDataParser.parseSamples(from: testerAsset.fileURL)
            } else {
                samples = []
            }

            let request = VideoExportRequest(
                test: test,
                primaryAsset: primary,
                equipmentAsset: equipmentVideoAsset,
                syncConfiguration: syncConfiguration,
                outputURL: outputURL,
                renderSize: CGSize(width: 1920, height: 1080),
                frameRate: 30,
                forceSamples: samples
            )
            try await exportService.exportComposedVideo(request: request)

            let values = try outputURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            let exportAsset = Asset(
                test: test,
                assetType: .export,
                filename: outputURL.lastPathComponent,
                fileURL: outputURL,
                byteSize: values.fileSize.map(Int64.init),
                contentType: values.contentType?.identifier
            )
            modelContext.insert(exportAsset)
            test.assets.append(exportAsset)
            statusMessage = "Export completed: \(outputURL.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func assetIdentifier(_ asset: Asset) -> String {
        String(describing: asset.persistentModelID)
    }
}

private struct WorkspaceVideoPreview: View {
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .cornerRadius(10)
            .onDisappear {
                player.pause()
            }
    }
}
#endif
