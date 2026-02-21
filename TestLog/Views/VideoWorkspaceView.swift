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
    @State private var lastScrubSeekUptime: TimeInterval = 0
    @State private var isEditingEquipmentFrame = false

    private let syncService: VideoSyncing = DefaultVideoSyncService()
    private let exportService: VideoExporting = DefaultVideoExportService()
    private let testerDataParser: TesterDataParsing = LBYTesterDataParser()

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

    private var equipmentCropBinding: Binding<CGRect> {
        Binding(
            get: { syncConfiguration.equipmentCropRectNormalized },
            set: { syncConfiguration.equipmentCropRectNormalized = $0 }
        )
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
                        .frame(height: 136)
                }

                GroupBox("Workspace Controls") {
                    VStack(alignment: .leading, spacing: 12) {
                        roleSelectors
                        alignmentControls
                        actionRow
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .padding(16)
        .navigationTitle("Video Workspace")
        .focusable()
        .onKeyPress(.space) {
            if primaryVideoAsset == nil {
                return .ignored
            }
            if isPlayingSynced {
                pauseSyncedPlayback()
            } else {
                playSyncedFromTrimStart()
            }
            return .handled
        }
        .onAppear {
            sanitizeWorkspaceState()
            reloadPlayers()
            installPrimaryTimeObserver()
        }
        .onChange(of: syncConfiguration.primaryVideoAssetID) { _, _ in
            reloadPlayers()
        }
        .onChange(of: syncConfiguration.equipmentVideoAssetID) { _, _ in
            isEditingEquipmentFrame = false
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
            Button("Done") {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        if primaryVideoAsset != nil {
            HStack(spacing: 12) {
                WorkspaceVideoPreview(
                    player: primaryPlayer,
                    videoSize: videoDisplaySize(for: primaryVideoAsset),
                    rotationQuarterTurns: 0,
                    cropRectNormalized: .constant(CGRect(x: 0, y: 0, width: 1, height: 1)),
                    isEditingCrop: .constant(false),
                    showEditingTools: false
                )
                if let equipmentAsset = equipmentVideoAsset {
                    WorkspaceVideoPreview(
                        player: equipmentPlayer,
                        videoSize: videoDisplaySize(for: equipmentAsset),
                        rotationQuarterTurns: syncConfiguration.normalizedEquipmentRotationQuarterTurns,
                        cropRectNormalized: equipmentCropBinding,
                        isEditingCrop: $isEditingEquipmentFrame,
                        showEditingTools: true,
                        onRotateClockwise: rotateEquipmentClockwise,
                        onResetCrop: resetEquipmentCrop
                    )
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
                seekPlayersDuringScrub(toPrimaryTime: time)
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
        if primaryPlayer.currentItem != nil {
            primaryPlayer.play()
        }
        if equipmentVideoAsset != nil, equipmentPlayer.currentItem != nil {
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
        let primaryClamped = clampedTime(boundedPrimary, for: primaryPlayer)
        seek(player: primaryPlayer, to: primaryClamped)

        let secondaryRequested = max(0, boundedPrimary + syncConfiguration.effectiveOffsetSeconds)
        let secondaryClamped = clampedTime(secondaryRequested, for: equipmentPlayer)
        seek(player: equipmentPlayer, to: secondaryClamped)
        scrubberTimeSeconds = boundedPrimary
    }

    private func seekPlayersDuringScrub(toPrimaryTime primaryTime: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastScrubSeekUptime < 0.04 { return }
        lastScrubSeekUptime = now
        seekPlayers(toPrimaryTime: primaryTime)
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

    private func clampedTime(_ requested: Double, for player: AVPlayer) -> Double {
        let nonNegative = max(0, requested)
        guard let item = player.currentItem else { return nonNegative }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return nonNegative }
        return min(nonNegative, max(duration - 0.001, 0))
    }

    private func seek(player: AVPlayer, to seconds: Double) {
        guard let item = player.currentItem else { return }
        if item.status == .failed { return }
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(
            to: time,
            toleranceBefore: CMTime(value: 1, timescale: 60),
            toleranceAfter: CMTime(value: 1, timescale: 60)
        )
    }

    private func videoDisplaySize(for asset: Asset?) -> CGSize {
        guard
            let width = asset?.videoWidth,
            let height = asset?.videoHeight,
            width > 0,
            height > 0
        else {
            return CGSize(width: 16, height: 9)
        }
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    private func rotateEquipmentClockwise() {
        syncConfiguration.equipmentRotationQuarterTurns = (syncConfiguration.normalizedEquipmentRotationQuarterTurns + 1) % 4
    }

    private func resetEquipmentCrop() {
        syncConfiguration.equipmentCropRectNormalized = CGRect(x: 0, y: 0, width: 1, height: 1)
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

        syncConfiguration.equipmentRotationQuarterTurns = syncConfiguration.normalizedEquipmentRotationQuarterTurns
        syncConfiguration.equipmentCropRectNormalized = syncConfiguration.equipmentCropRectNormalized

        syncConfiguration.trimInSeconds = normalizedTrimIn
        syncConfiguration.trimOutSeconds = normalizedTrimOut
    }
}

private struct WorkspaceVideoPreview: View {
    let player: AVPlayer
    let videoSize: CGSize
    let rotationQuarterTurns: Int
    @Binding var cropRectNormalized: CGRect
    @Binding var isEditingCrop: Bool
    let showEditingTools: Bool
    var onRotateClockwise: (() -> Void)? = nil
    var onResetCrop: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let containerSize = geo.size
            let fullVideoRect = aspectFitRect(
                for: orientedVideoSize,
                in: CGRect(origin: .zero, size: containerSize)
            )
            let cropRect = cropRectInView(fullVideoRect: fullVideoRect)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.95))

                if isEditingCrop {
                    OrientedWorkspacePlayer(
                        player: player,
                        quarterTurns: rotationQuarterTurns
                    )
                    .frame(width: fullVideoRect.width, height: fullVideoRect.height)
                    .position(x: fullVideoRect.midX, y: fullVideoRect.midY)

                    CropEditingOverlay(
                        fullVideoRect: fullVideoRect,
                        cropRect: cropRect,
                        onCropChanged: { newCrop in
                            cropRectNormalized = normalizedRect(newCrop, in: fullVideoRect)
                        }
                    )
                } else {
                    let mapped = mappedVideoRect(fullVideoRect: fullVideoRect, cropRect: cropRect)
                    OrientedWorkspacePlayer(
                        player: player,
                        quarterTurns: rotationQuarterTurns
                    )
                    .frame(width: mapped.width, height: mapped.height)
                    .position(x: mapped.midX, y: mapped.midY)
                }

                if showEditingTools {
                    HStack(spacing: 8) {
                        Button(isEditingCrop ? "Done Crop" : "Edit Crop") {
                            isEditingCrop.toggle()
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            onRotateClockwise?()
                        } label: {
                            Label("Rotate 90°", systemImage: "rotate.right")
                        }
                        .buttonStyle(.bordered)

                        Button("Reset") {
                            onResetCrop?()
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var normalizedRotation: Int {
        let mod = rotationQuarterTurns % 4
        return mod < 0 ? mod + 4 : mod
    }

    private var orientedVideoSize: CGSize {
        guard videoSize.width > 0, videoSize.height > 0 else { return CGSize(width: 16, height: 9) }
        if normalizedRotation.isMultiple(of: 2) {
            return videoSize
        }
        return CGSize(width: videoSize.height, height: videoSize.width)
    }

    private func cropRectInView(fullVideoRect: CGRect) -> CGRect {
        let normalized = cropRectNormalized.standardized.clampedNormalized(minSize: 0.05)
        return CGRect(
            x: fullVideoRect.minX + normalized.minX * fullVideoRect.width,
            y: fullVideoRect.minY + normalized.minY * fullVideoRect.height,
            width: fullVideoRect.width * normalized.width,
            height: fullVideoRect.height * normalized.height
        )
    }

    private func normalizedRect(_ rect: CGRect, in fullVideoRect: CGRect) -> CGRect {
        guard fullVideoRect.width > 0, fullVideoRect.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let x = (rect.minX - fullVideoRect.minX) / fullVideoRect.width
        let y = (rect.minY - fullVideoRect.minY) / fullVideoRect.height
        let w = rect.width / fullVideoRect.width
        let h = rect.height / fullVideoRect.height
        return CGRect(x: x, y: y, width: w, height: h).clampedNormalized(minSize: 0.05)
    }

    private func mappedVideoRect(fullVideoRect: CGRect, cropRect: CGRect) -> CGRect {
        let safeCrop = cropRect.standardized
        guard safeCrop.width > 0, safeCrop.height > 0 else { return fullVideoRect }
        let scale = min(fullVideoRect.width / safeCrop.width, fullVideoRect.height / safeCrop.height)
        let targetSize = CGSize(width: safeCrop.width * scale, height: safeCrop.height * scale)
        let targetOrigin = CGPoint(
            x: fullVideoRect.midX - targetSize.width / 2,
            y: fullVideoRect.midY - targetSize.height / 2
        )
        return CGRect(
            x: targetOrigin.x - (safeCrop.minX - fullVideoRect.minX) * scale,
            y: targetOrigin.y - (safeCrop.minY - fullVideoRect.minY) * scale,
            width: fullVideoRect.width * scale,
            height: fullVideoRect.height * scale
        )
    }

    private func aspectFitRect(for sourceSize: CGSize, in bounds: CGRect) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
        let fitted = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: bounds.midX - fitted.width / 2,
            y: bounds.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}

private struct OrientedWorkspacePlayer: View {
    let player: AVPlayer
    let quarterTurns: Int

    var body: some View {
        GeometryReader { geo in
            let turns = normalizedTurns
            let targetSize = geo.size
            let baseSize = turns.isMultiple(of: 2)
                ? targetSize
                : CGSize(width: targetSize.height, height: targetSize.width)

            WorkspacePlayerView(player: player)
                .frame(width: baseSize.width, height: baseSize.height)
                .rotationEffect(.degrees(Double(turns) * 90))
                .position(x: targetSize.width / 2, y: targetSize.height / 2)
        }
        .clipped()
    }

    private var normalizedTurns: Int {
        let mod = quarterTurns % 4
        return mod < 0 ? mod + 4 : mod
    }
}

private struct CropEditingOverlay: View {
    let fullVideoRect: CGRect
    let cropRect: CGRect
    let onCropChanged: (CGRect) -> Void
    @State private var dragStartPoint: CGPoint?
    private let minimumCropPixels: CGFloat = 20

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(fullVideoRect)
                path.addRect(cropRect)
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))

            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange, lineWidth: 2)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let point = clampPointToVideo(value.location)
                    if dragStartPoint == nil {
                        dragStartPoint = point
                    }
                    guard let start = dragStartPoint else { return }
                    let rect = rectFromPoints(start, point).ensuringMinimumSize(
                        minWidth: minimumCropPixels,
                        minHeight: minimumCropPixels,
                        inside: fullVideoRect
                    )
                    onCropChanged(rect)
                }
                .onEnded { _ in
                    dragStartPoint = nil
                }
        )
    }

    private func clampPointToVideo(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, fullVideoRect.minX), fullVideoRect.maxX),
            y: min(max(point.y, fullVideoRect.minY), fullVideoRect.maxY)
        )
    }

    private func rectFromPoints(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }
}

private struct WorkspacePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> WorkspacePlayerNSView {
        let view = WorkspacePlayerNSView()
        view.setPlayer(player)
        return view
    }

    func updateNSView(_ nsView: WorkspacePlayerNSView, context: Context) {
        nsView.setPlayer(player)
    }
}

private final class WorkspacePlayerNSView: NSView {
    private let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func setPlayer(_ player: AVPlayer) {
        if playerLayer.player !== player {
            playerLayer.player = player
        }
    }
}

private extension CGRect {
    func clampedNormalized(minSize: CGFloat) -> CGRect {
        let normalizedMin = min(max(minSize, 0), 1)
        var rect = self.standardized
        rect.origin.x = rect.origin.x.isFinite ? rect.origin.x : 0
        rect.origin.y = rect.origin.y.isFinite ? rect.origin.y : 0
        rect.size.width = rect.size.width.isFinite ? rect.size.width : 1
        rect.size.height = rect.size.height.isFinite ? rect.size.height : 1

        rect.origin.x = min(max(rect.origin.x, 0), 1)
        rect.origin.y = min(max(rect.origin.y, 0), 1)
        rect.size.width = min(max(rect.size.width, normalizedMin), 1)
        rect.size.height = min(max(rect.size.height, normalizedMin), 1)

        if rect.maxX > 1 {
            rect.origin.x = max(0, 1 - rect.width)
        }
        if rect.maxY > 1 {
            rect.origin.y = max(0, 1 - rect.height)
        }
        return rect
    }

    func ensuringMinimumSize(minWidth: CGFloat, minHeight: CGFloat, inside bounds: CGRect) -> CGRect {
        var rect = self.standardized
        rect.size.width = max(rect.width, minWidth)
        rect.size.height = max(rect.height, minHeight)

        if rect.maxX > bounds.maxX {
            rect.origin.x = bounds.maxX - rect.width
        }
        if rect.maxY > bounds.maxY {
            rect.origin.y = bounds.maxY - rect.height
        }
        if rect.minX < bounds.minX {
            rect.origin.x = bounds.minX
        }
        if rect.minY < bounds.minY {
            rect.origin.y = bounds.minY
        }

        rect.size.width = min(rect.width, bounds.width)
        rect.size.height = min(rect.height, bounds.height)
        return rect
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

    private let horizontalPadding: CGFloat = 12
    private let barHeight: CGFloat = 28
    private let primaryY: CGFloat = 20
    private let equipmentY: CGFloat = 56
    private let tracksTopY: CGFloat = 14
    private let tracksBottomY: CGFloat = 92
    private let playheadBottomY: CGFloat = 104

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width - horizontalPadding * 2, 1)
            let trimMinGap = max((domain.upperBound - domain.lowerBound) * 0.0025, 0.01)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(height: tracksBottomY - tracksTopY)
                    .offset(x: horizontalPadding, y: tracksTopY)

                trackBar(title: "Primary", range: primaryRange, color: .blue, y: primaryY, width: width)
                trackBar(title: "Equipment", range: secondaryRange, color: .green, y: equipmentY, width: width)

                let trimInX = xPosition(for: trimIn, width: width)
                let trimOutX = xPosition(for: trimOut, width: width)
                let playheadX = xPosition(for: playhead, width: width)

                verticalMarker(x: trimInX, color: .orange)
                verticalMarker(x: trimOutX, color: .orange)
                verticalMarker(x: playheadX, color: .white.opacity(0.95))

                bracketHandle(x: trimInX, y: tracksTopY - 2, isLeftBracket: true)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let candidate = time(for: value.location.x, width: width)
                                trimIn = min(max(primaryRange.lowerBound, candidate), trimOut - trimMinGap)
                            }
                    )

                bracketHandle(x: trimOutX, y: tracksTopY - 2, isLeftBracket: false)
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
                    .position(x: playheadX, y: playheadBottomY)
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
                    .padding(.bottom, 2)
            }
        }
    }

    private func trackBar(title: String, range: ClosedRange<Double>, color: Color, y: CGFloat, width: CGFloat) -> some View {
        let startX = xPosition(for: range.lowerBound, width: width)
        let endX = xPosition(for: range.upperBound, width: width)
        let barWidth = max(endX - startX, 2)

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.88))
                .frame(width: barWidth, height: barHeight)
                .offset(x: startX, y: y)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .offset(x: startX + 8, y: y + 6)
        }
    }

    private func bracketHandle(x: CGFloat, y: CGFloat, isLeftBracket: Bool) -> some View {
        Text(isLeftBracket ? "[" : "]")
            .font(.system(size: 18, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
            .position(x: x, y: y)
    }

    private func verticalMarker(x: CGFloat, color: Color) -> some View {
        Path { path in
            path.move(to: CGPoint(x: x, y: tracksTopY))
            path.addLine(to: CGPoint(x: x, y: tracksBottomY))
        }
        .stroke(color, lineWidth: 2)
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
