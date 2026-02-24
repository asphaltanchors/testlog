#if os(macOS)
import AVFoundation
import AVKit
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class VideoWorkspaceCoordinator {
    var isRunningAutoSync = false
    var isExportingVideo = false
    var isPlayingSynced = false
    var isScrubbing = false
    var scrubberTimeSeconds: Double = 0
    var statusMessage: String?
    var errorMessage: String?
    var isEditingEquipmentFrame = false
    var exportModalState: ExportModalState?

    let primaryPlayer = AVPlayer()
    let equipmentPlayer = AVPlayer()

    var syncConfiguration: VideoSyncConfiguration?

    var test: PullTest?
    var modelContext: ModelContext?
    var syncService: VideoSyncing?
    var exportService: VideoExporting?
    var testerDataParser: TesterDataParsing?
    var testerDataSamples: [ParsedForceSample] = []
    var testerDataStatusMessage: String?

    var primaryTimeObserverToken: Any?
    var lastScrubSeekUptime: TimeInterval = 0
    var hasAttemptedInitialAutoSync = false
    var primaryLoadedDurationSeconds: Double?
    var equipmentLoadedDurationSeconds: Double?
    var primaryDurationLoadRequestID = UUID()
    var equipmentDurationLoadRequestID = UUID()

    func configure(
        test: PullTest,
        modelContext: ModelContext,
        syncService: VideoSyncing,
        exportService: VideoExporting,
        testerDataParser: TesterDataParsing
    ) {
        self.test = test
        self.modelContext = modelContext
        self.syncService = syncService
        self.exportService = exportService
        self.testerDataParser = testerDataParser

        ensureSyncConfiguration()
        sanitizeWorkspaceState()
        reloadTesterDataSamples()
        reloadPlayers()
        installPrimaryTimeObserver()
    }

    func handleDisappear() {
        pauseSyncedPlayback()
        removePrimaryTimeObserver()
    }

    func handleSpaceBarPress() {
        guard primaryVideoAsset != nil else { return }
        if isPlayingSynced {
            pauseSyncedPlayback()
        } else {
            playSyncedFromCurrentTime()
        }
    }

    var hasPrimaryVideo: Bool {
        primaryVideoAsset != nil
    }

    var primaryDuration: Double {
        max(primaryLoadedDurationSeconds ?? primaryVideoAsset?.durationSeconds ?? 0, 1)
    }

    var equipmentDuration: Double {
        max(equipmentLoadedDurationSeconds ?? equipmentVideoAsset?.durationSeconds ?? 0, 0)
    }

    var timelineDomain: ClosedRange<Double> {
        let primaryStart = 0.0
        let primaryEnd = primaryDuration
        let secondaryStart = equipmentSharedStartTime
        let secondaryEnd = secondaryStart + equipmentDuration

        let lower = min(primaryStart, secondaryStart)
        let upper = max(primaryEnd, secondaryEnd, primaryEnd)
        if upper - lower < 1 {
            return lower...(lower + 1)
        }
        return lower...upper
    }

    var primaryRange: ClosedRange<Double> {
        0...primaryDuration
    }

    var secondaryRange: ClosedRange<Double> {
        let start = equipmentSharedStartTime
        return start...(start + equipmentDuration)
    }

    var effectiveCameraOffsetSeconds: Double {
        syncConfiguration?.effectiveOffsetSeconds ?? 0
    }

    var equipmentSharedStartTime: Double {
        -effectiveCameraOffsetSeconds
    }

    var trimIn: Double {
        normalizedTrimIn
    }

    var trimOut: Double {
        normalizedTrimOut
    }

    func setTrimIn(_ value: Double) {
        guard let syncConfiguration else { return }
        let bounded = min(max(value, 0), primaryDuration)
        syncConfiguration.trimInSeconds = bounded
        if let trimOut = syncConfiguration.trimOutSeconds, trimOut < bounded {
            syncConfiguration.trimOutSeconds = bounded
        }
        scrubberTimeSeconds = boundedSharedTime(scrubberTimeSeconds)
    }

    func setTrimOut(_ value: Double) {
        guard let syncConfiguration else { return }
        let bounded = min(max(value, 0), primaryDuration)
        let trimIn = syncConfiguration.trimInSeconds ?? 0
        syncConfiguration.trimOutSeconds = max(trimIn, bounded)
        scrubberTimeSeconds = boundedSharedTime(scrubberTimeSeconds)
    }

    var primarySelectionID: String {
        validSelectionOrEmpty(syncConfiguration?.primaryVideoAssetID)
    }

    func setPrimarySelectionID(_ id: String) {
        syncConfiguration?.primaryVideoAssetID = id.isEmpty ? nil : id
        sanitizeWorkspaceState()
        reloadPlayers()
    }

    var equipmentSelectionID: String {
        validSelectionOrEmpty(syncConfiguration?.equipmentVideoAssetID)
    }

    func setEquipmentSelectionID(_ id: String) {
        syncConfiguration?.equipmentVideoAssetID = id.isEmpty ? nil : id
        sanitizeWorkspaceState()
        isEditingEquipmentFrame = false
        reloadPlayers()
    }

    var autoOffsetText: String {
        String(format: "%.3fs", syncConfiguration?.autoOffsetSeconds ?? 0)
    }

    var manualOffsetSeconds: Double {
        syncConfiguration?.manualOffsetSeconds ?? 0
    }

    func setManualOffsetSeconds(_ value: Double) {
        syncConfiguration?.manualOffsetSeconds = value
        if !isPlayingSynced {
            seekPlayers(toPrimaryTime: scrubberTimeSeconds)
        }
    }

    var testerDataOffsetSeconds: Double {
        syncConfiguration?.testerDataOffsetSeconds ?? 0
    }

    func setTesterDataOffsetSeconds(_ value: Double) {
        syncConfiguration?.testerDataOffsetSeconds = value
    }

    var equipmentPreviewTimeSeconds: Double {
        clampedTime(mappedEquipmentTime(forPrimaryTime: scrubberTimeSeconds), for: equipmentPlayer)
    }

    var lbySampleTimeSeconds: Double {
        equipmentPreviewTimeSeconds + testerDataOffsetSeconds
    }

    var currentTesterForceKN: Double? {
        interpolatedTesterForceKN(at: lbySampleTimeSeconds)
    }

    var currentTesterForceText: String {
        guard let force = currentTesterForceKN else { return "— kN" }
        return String(format: "%.2f kN", force)
    }

    var equipmentRotationQuarterTurns: Int {
        syncConfiguration?.normalizedEquipmentRotationQuarterTurns ?? 0
    }

    var equipmentCropRectNormalized: CGRect {
        syncConfiguration?.equipmentCropRectNormalized ?? CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    func setEquipmentCropRectNormalized(_ rect: CGRect) {
        syncConfiguration?.equipmentCropRectNormalized = rect
    }

    func rotateEquipmentClockwise() {
        guard let syncConfiguration else { return }
        syncConfiguration.equipmentRotationQuarterTurns =
            (syncConfiguration.normalizedEquipmentRotationQuarterTurns + 1) % 4
    }

    func resetEquipmentCrop() {
        syncConfiguration?.equipmentCropRectNormalized = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    func scrubBegan() {
        isScrubbing = true
        pauseSyncedPlayback()
    }

    func scrubChanged(_ time: Double) {
        seekPlayersDuringScrub(toPrimaryTime: time)
    }

    func scrubEnded(_ time: Double) {
        isScrubbing = false
        seekPlayers(toPrimaryTime: time)
    }

    func setPlayhead(_ time: Double) {
        scrubberTimeSeconds = boundedSharedTime(time)
    }

    func beginExport(to outputURL: URL) {
        exportModalState = .exporting(filename: outputURL.lastPathComponent)
        Task {
            await exportComposedVideo(to: outputURL)
        }
    }

    func clearExportModalIfIdle() {
        if !isExportingVideo {
            exportModalState = nil
        }
    }

    func videoDisplaySize(for asset: Asset?) -> CGSize {
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

    func assetIdentifier(_ asset: Asset) -> String {
        asset.videoSelectionKey
    }

    var videoAssets: [Asset] {
        orderedVideoAssets
    }

    var primaryVideoAsset: Asset? {
        guard !orderedVideoAssets.isEmpty else { return nil }
        if let preferredID = syncConfiguration?.primaryVideoAssetID {
            return resolvedAsset(forSelectionID: preferredID)
        }
        return orderedVideoAssets.first(where: { $0.videoRole == .anchorView }) ?? orderedVideoAssets.first
    }

    var equipmentVideoAsset: Asset? {
        guard !orderedVideoAssets.isEmpty else { return nil }
        if let preferredID = syncConfiguration?.equipmentVideoAssetID {
            return resolvedAsset(forSelectionID: preferredID)
        }
        return orderedVideoAssets.first(where: { $0.videoRole == .equipmentView })
    }

    func refreshSelectionAfterAssetsChange() {
        sanitizeWorkspaceState()
        reloadTesterDataSamples()
        reloadPlayers()
    }

    func mappedEquipmentTime(forPrimaryTime primaryTime: Double) -> Double {
        primaryTime + effectiveCameraOffsetSeconds
    }

    var orderedVideoAssets: [Asset] {
        (test?.videoAssets ?? []).sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            if lhs.filename != rhs.filename {
                return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
            }
            return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
        }
    }

    func resolvedAsset(forSelectionID id: String) -> Asset? {
        orderedVideoAssets.first(where: { $0.matchesVideoSelectionID(id) })
    }
}

enum ExportModalState {
    case exporting(filename: String)
    case completed(outputURL: URL)
    case failed(message: String)
}
#endif
