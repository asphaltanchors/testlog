#if os(macOS)
//
//  VideoWorkspaceView.swift
//  TestLog
//
//  Created by Codex on 2/21/26.
//

import AVKit
import AVFoundation
import SwiftData
import SwiftUI
struct VideoWorkspaceView: View {
    @Bindable var test: PullTest
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var layoutMode: LayoutMode = .sideBySide
    @State private var isRunningAutoSync = false
    @State private var isExportingVideo = false
    @State private var isPlayingSynced = false
    @State private var isScrubbing = false
    @State private var scrubberTimeSeconds: Double = 0
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var primaryPlayer = AVPlayer()
    @State private var equipmentPlayer = AVPlayer()
    @State private var primaryTimeObserverToken: Any?

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

    private var validVideoSelectionIDs: Set<String> {
        Set(test.videoAssets.map(assetIdentifier))
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

    private var primaryDuration: Double {
        max(primaryVideoAsset?.durationSeconds ?? 0, 1)
    }

    private var equipmentDuration: Double {
        max(equipmentVideoAsset?.durationSeconds ?? 0, 0)
    }

    private var trimUpperBound: Double {
        primaryDuration
    }

    private var timelineDomain: ClosedRange<Double> {
        let primaryStart = 0.0
        let primaryEnd = primaryDuration
        let secondaryStart = syncConfiguration.effectiveOffsetSeconds
        let secondaryEnd = secondaryStart + equipmentDuration

        let lower = min(primaryStart, secondaryStart)
        let upper = max(primaryEnd, secondaryEnd, primaryEnd)
        if upper - lower < 1 {
            return lower...(lower + 1)
        }
        return lower...upper
    }

    private var trimInBinding: Binding<Double> {
        Binding(
            get: { normalizedTrimIn },
            set: { newValue in
                let bounded = min(max(newValue, 0), trimUpperBound)
                syncConfiguration.trimInSeconds = bounded
                if let trimOut = syncConfiguration.trimOutSeconds, trimOut < bounded {
                    syncConfiguration.trimOutSeconds = bounded
                }
                scrubberTimeSeconds = boundedSharedTime(scrubberTimeSeconds)
            }
        )
    }

    private var trimOutBinding: Binding<Double> {
        Binding(
            get: { normalizedTrimOut },
            set: { newValue in
                let bounded = min(max(newValue, 0), trimUpperBound)
                let trimIn = syncConfiguration.trimInSeconds ?? 0
                syncConfiguration.trimOutSeconds = max(trimIn, bounded)
                scrubberTimeSeconds = boundedSharedTime(scrubberTimeSeconds)
            }
        )
    }

    private var normalizedTrimIn: Double {
        min(max(syncConfiguration.trimInSeconds ?? 0, 0), trimUpperBound)
    }

    private var normalizedTrimOut: Double {
        let lower = normalizedTrimIn
        let rawOut = syncConfiguration.trimOutSeconds ?? trimUpperBound
        return min(max(rawOut, lower), trimUpperBound)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                GroupBox("Preview") {
                    previewArea
                        .frame(minHeight: 320)
                }

                GroupBox("Timeline") {
                    timelineEditor
                        .frame(height: 152)
                }

                GroupBox("Workspace Controls") {
                    VStack(alignment: .leading, spacing: 12) {
                        roleSelectors
                        trimControls
                        alignmentControls
                        playbackControls
                        actionRow
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .padding(16)
        .navigationTitle("Video Workspace")
        .onAppear {
            sanitizeWorkspaceState()
            reloadPlayers()
            installPrimaryTimeObserver()
        }
        .onChange(of: syncConfiguration.primaryVideoAssetID) { _, _ in
            reloadPlayers()
        }
        .onChange(of: syncConfiguration.equipmentVideoAssetID) { _, _ in
            reloadPlayers()
        }
        .onChange(of: syncConfiguration.autoOffsetSeconds) { _, _ in
            if !isPlayingSynced {
                seekPlayers(toPrimaryTime: scrubberTimeSeconds)
            }
        }
        .onChange(of: syncConfiguration.manualOffsetSeconds) { _, _ in
            if !isPlayingSynced {
                seekPlayers(toPrimaryTime: scrubberTimeSeconds)
            }
        }
        .onDisappear {
            pauseSyncedPlayback()
            removePrimaryTimeObserver()
        }
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
        if primaryVideoAsset != nil {
            switch layoutMode {
            case .sideBySide:
                HStack(spacing: 12) {
                    WorkspaceVideoPreview(player: primaryPlayer)
                    if equipmentVideoAsset != nil {
                        WorkspaceVideoPreview(player: equipmentPlayer)
                    }
                }
            case .pip:
                ZStack(alignment: .bottomTrailing) {
                    WorkspaceVideoPreview(player: primaryPlayer)
                    if equipmentVideoAsset != nil {
                        WorkspaceVideoPreview(player: equipmentPlayer)
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
                get: { validSelectionOrEmpty(syncConfiguration.primaryVideoAssetID) },
                set: { syncConfiguration.primaryVideoAssetID = $0.isEmpty ? nil : $0 }
            )) {
                Text("Select").tag("")
                ForEach(test.videoAssets, id: \.persistentModelID) { asset in
                    Text(asset.filename).tag(assetIdentifier(asset))
                }
            }

            Picker("Equipment Video", selection: Binding(
                get: { validSelectionOrEmpty(syncConfiguration.equipmentVideoAssetID) },
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
                    TextField("", value: trimInBinding, format: .number.precision(.fractionLength(2)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                HStack {
                    Text("Trim Out")
                    TextField("", value: trimOutBinding, format: .number.precision(.fractionLength(2)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }

            Text("Primary Duration: \(String(format: "%.2f", trimUpperBound))s")
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

    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Linked Playback")
                .font(.headline)

            HStack {
                Button(isPlayingSynced ? "Pause Both" : "Play Both") {
                    if isPlayingSynced {
                        pauseSyncedPlayback()
                    } else {
                        playSyncedFromTrimStart()
                    }
                }
                .disabled(primaryVideoAsset == nil)

                Button("Reset to Trim In") {
                    pauseSyncedPlayback()
                    seekPlayersToTrimStart()
                }
                .disabled(primaryVideoAsset == nil)
            }

            Text("Primary audio only; equipment preview is muted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var timelineEditor: some View {
        DualTrackTimelineView(
            domain: timelineDomain,
            primaryRange: 0...primaryDuration,
            secondaryRange: syncConfiguration.effectiveOffsetSeconds...(syncConfiguration.effectiveOffsetSeconds + equipmentDuration),
            trimIn: trimInBinding,
            trimOut: trimOutBinding,
            playhead: Binding(
                get: { scrubberTimeSeconds },
                set: { scrubberTimeSeconds = boundedSharedTime($0) }
            ),
            onScrubBegan: {
                isScrubbing = true
                pauseSyncedPlayback()
            },
            onScrubChanged: { time in
                seekPlayers(toPrimaryTime: time)
            },
            onScrubEnded: { time in
                isScrubbing = false
                seekPlayers(toPrimaryTime: time)
            }
        )
        .disabled(primaryVideoAsset == nil)
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
                    .padding(.top, 18)
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
            pauseSyncedPlayback()
            seekPlayersToTrimStart()
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

    private func reloadPlayers() {
        pauseSyncedPlayback()

        if let primaryURL = primaryVideoAsset?.fileURL {
            primaryPlayer.replaceCurrentItem(with: AVPlayerItem(url: primaryURL))
        } else {
            primaryPlayer.replaceCurrentItem(with: nil)
        }

        if let equipmentURL = equipmentVideoAsset?.fileURL {
            equipmentPlayer.replaceCurrentItem(with: AVPlayerItem(url: equipmentURL))
        } else {
            equipmentPlayer.replaceCurrentItem(with: nil)
        }

        primaryPlayer.isMuted = false
        equipmentPlayer.isMuted = true
        seekPlayersToTrimStart()
    }

    private func playSyncedFromTrimStart() {
        seekPlayers(toPrimaryTime: scrubberTimeSeconds)
        primaryPlayer.play()
        if equipmentVideoAsset != nil {
            equipmentPlayer.play()
        }
        isPlayingSynced = true
    }

    private func pauseSyncedPlayback() {
        primaryPlayer.pause()
        equipmentPlayer.pause()
        isPlayingSynced = false
    }

    private func seekPlayersToTrimStart() {
        let trimIn = normalizedTrimIn
        scrubberTimeSeconds = boundedSharedTime(trimIn)
        seekPlayers(toPrimaryTime: trimIn)
    }

    private func seekPlayers(toPrimaryTime primaryTime: Double) {
        let boundedPrimary = boundedSharedTime(primaryTime)
        let primaryCMTime = CMTime(seconds: boundedPrimary, preferredTimescale: 600)
        primaryPlayer.seek(to: primaryCMTime, toleranceBefore: .zero, toleranceAfter: .zero)

        let secondaryTime = max(0, boundedPrimary + syncConfiguration.effectiveOffsetSeconds)
        let secondaryCMTime = CMTime(seconds: secondaryTime, preferredTimescale: 600)
        equipmentPlayer.seek(to: secondaryCMTime, toleranceBefore: .zero, toleranceAfter: .zero)
        scrubberTimeSeconds = boundedPrimary
    }

    private var sharedTimelineBounds: ClosedRange<Double> {
        let trimIn = normalizedTrimIn
        let trimOut = normalizedTrimOut
        return trimIn...trimOut
    }

    private func boundedSharedTime(_ value: Double) -> Double {
        min(max(value, sharedTimelineBounds.lowerBound), sharedTimelineBounds.upperBound)
    }

    private func installPrimaryTimeObserver() {
        removePrimaryTimeObserver()
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        primaryTimeObserverToken = primaryPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            guard seconds.isFinite, !isScrubbing else { return }
            scrubberTimeSeconds = boundedSharedTime(seconds)

            if isPlayingSynced && seconds >= sharedTimelineBounds.upperBound {
                pauseSyncedPlayback()
            }
        }
    }

    private func removePrimaryTimeObserver() {
        if let token = primaryTimeObserverToken {
            primaryPlayer.removeTimeObserver(token)
            primaryTimeObserverToken = nil
        }
    }

    private func validSelectionOrEmpty(_ value: String?) -> String {
        guard let value, validVideoSelectionIDs.contains(value) else { return "" }
        return value
    }

    private func sanitizeWorkspaceState() {
        if let primaryID = syncConfiguration.primaryVideoAssetID, !validVideoSelectionIDs.contains(primaryID) {
            syncConfiguration.primaryVideoAssetID = nil
        }
        if let equipmentID = syncConfiguration.equipmentVideoAssetID, !validVideoSelectionIDs.contains(equipmentID) {
            syncConfiguration.equipmentVideoAssetID = nil
        }

        if syncConfiguration.primaryVideoAssetID == nil, let preferred = test.videoAssets.first(where: { $0.videoRole == .anchorView }) ?? test.videoAssets.first {
            syncConfiguration.primaryVideoAssetID = assetIdentifier(preferred)
        }
        if syncConfiguration.equipmentVideoAssetID == nil, let preferred = test.videoAssets.first(where: { $0.videoRole == .equipmentView }) {
            syncConfiguration.equipmentVideoAssetID = assetIdentifier(preferred)
        }

        if let auto = syncConfiguration.autoOffsetSeconds, abs(auto) > 20 {
            syncConfiguration.autoOffsetSeconds = nil
        }

        syncConfiguration.trimInSeconds = normalizedTrimIn
        syncConfiguration.trimOutSeconds = normalizedTrimOut
    }
}

private struct WorkspaceVideoPreview: View {
    let player: AVPlayer

    var body: some View {
        VideoPlayer(player: player)
            .cornerRadius(10)
    }
}

private struct DualTrackTimelineView: View {
    let domain: ClosedRange<Double>
    let primaryRange: ClosedRange<Double>
    let secondaryRange: ClosedRange<Double>
    @Binding var trimIn: Double
    @Binding var trimOut: Double
    @Binding var playhead: Double
    let onScrubBegan: () -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    private let horizontalPadding: CGFloat = 14
    private let lineHeight: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width - horizontalPadding * 2, 1)
            let trimMinGap = max((domain.upperBound - domain.lowerBound) * 0.0025, 0.01)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(height: 104)
                    .offset(x: horizontalPadding, y: 20)

                trackBar(
                    title: "Primary",
                    range: primaryRange,
                    color: .blue,
                    y: 32,
                    width: width
                )

                trackBar(
                    title: "Equipment",
                    range: secondaryRange,
                    color: .green,
                    y: 62,
                    width: width
                )

                let trimInX = xPosition(for: trimIn, width: width)
                let trimOutX = xPosition(for: trimOut, width: width)
                let playheadX = xPosition(for: playhead, width: width)

                Path { path in
                    path.move(to: CGPoint(x: trimInX, y: 20))
                    path.addLine(to: CGPoint(x: trimInX, y: 124))
                }
                .stroke(Color.orange, lineWidth: 2)

                Path { path in
                    path.move(to: CGPoint(x: trimOutX, y: 20))
                    path.addLine(to: CGPoint(x: trimOutX, y: 124))
                }
                .stroke(Color.orange, lineWidth: 2)

                Path { path in
                    path.move(to: CGPoint(x: playheadX, y: 20))
                    path.addLine(to: CGPoint(x: playheadX, y: 124))
                }
                .stroke(Color.white.opacity(0.95), lineWidth: 2)

                handle(x: trimInX, y: 16)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let candidate = time(for: value.location.x, width: width)
                                trimIn = min(max(primaryRange.lowerBound, candidate), trimOut - trimMinGap)
                            }
                    )

                handle(x: trimOutX, y: 16)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let candidate = time(for: value.location.x, width: width)
                                trimOut = max(min(primaryRange.upperBound, candidate), trimIn + trimMinGap)
                            }
                    )

                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .position(x: playheadX, y: 128)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                onScrubBegan()
                                let candidate = time(for: value.location.x, width: width)
                                let clamped = min(max(candidate, trimIn), trimOut)
                                playhead = clamped
                                onScrubChanged(clamped)
                            }
                            .onEnded { value in
                                let candidate = time(for: value.location.x, width: width)
                                let clamped = min(max(candidate, trimIn), trimOut)
                                playhead = clamped
                                onScrubEnded(clamped)
                            }
                    )
            }
            .overlay(alignment: .bottomTrailing) {
                Text(String(format: "Trim %.2fs - %.2fs | Playhead %.2fs", trimIn, trimOut, playhead))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, horizontalPadding)
            }
        }
    }

    private func trackBar(title: String, range: ClosedRange<Double>, color: Color, y: CGFloat, width: CGFloat) -> some View {
        let startX = xPosition(for: range.lowerBound, width: width)
        let endX = xPosition(for: range.upperBound, width: width)
        let barWidth = max(endX - startX, 2)

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: lineHeight / 2)
                .fill(color.opacity(0.85))
                .frame(width: barWidth, height: lineHeight)
                .offset(x: startX, y: y)

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white)
                .offset(x: startX + 8, y: y + 2)
        }
    }

    private func handle(x: CGFloat, y: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.orange)
            .frame(width: 8, height: 16)
            .position(x: x, y: y)
    }

    private func xPosition(for time: Double, width: CGFloat) -> CGFloat {
        let denominator = max(domain.upperBound - domain.lowerBound, 0.0001)
        let normalized = (time - domain.lowerBound) / denominator
        return horizontalPadding + CGFloat(normalized) * width
    }

    private func time(for x: CGFloat, width: CGFloat) -> Double {
        let normalized = Double((x - horizontalPadding) / width)
        let clamped = min(max(normalized, 0), 1)
        return domain.lowerBound + clamped * (domain.upperBound - domain.lowerBound)
    }
}
#endif
