#if os(macOS)
import Foundation
import SwiftData

extension VideoWorkspaceCoordinator {
    var validVideoSelectionIDs: Set<String> {
        Set(videoAssets.map(assetIdentifier))
    }

    func validSelectionOrEmpty(_ value: String?) -> String {
        guard let value, validVideoSelectionIDs.contains(value) else { return "" }
        return value
    }

    func runAutoSync() async {
        guard
            let primary = primaryVideoAsset,
            let equipment = equipmentVideoAsset
                ?? test?.videoAssets.first(where: { $0.persistentModelID != primary.persistentModelID })
        else {
            statusMessage = "Attach at least two videos for auto sync."
            return
        }

        guard let syncService else { return }

        isRunningAutoSync = true
        defer { isRunningAutoSync = false }

        do {
            guard let primaryURL = primary.resolvedURL, let equipmentURL = equipment.resolvedURL else {
                errorMessage = "Cannot resolve video file paths."
                return
            }
            let result = try await syncService.detectOffset(
                primaryURL: primaryURL,
                secondaryURL: equipmentURL
            )
            syncConfiguration?.autoOffsetSeconds = result.detectedOffsetSeconds
            syncConfiguration?.lastSyncedAt = Date()
            pauseSyncedPlayback()
            seekPlayersToTrimStart()
            statusMessage =
                "Auto sync complete (offset: \(String(format: "%.3f", result.detectedOffsetSeconds))s, confidence: \(String(format: "%.2f", result.confidence)))."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportComposedVideo(to outputURL: URL) async {
        guard
            let exportService,
            let testerDataParser,
            let test,
            let syncConfiguration,
            let primary = primaryVideoAsset
        else {
            errorMessage = VideoFeatureError.missingPrimaryVideo.localizedDescription
            return
        }

        isExportingVideo = true
        defer { isExportingVideo = false }

        do {
            let samples: [ParsedForceSample]
            if let testerAsset = test.testerBinaryAsset, let testerURL = testerAsset.resolvedURL {
                samples = try testerDataParser.parseSamples(from: testerURL)
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
            exportModalState = .completed(outputURL: outputURL)
        } catch {
            exportModalState = .failed(message: error.localizedDescription)
        }
    }

    func ensureSyncConfiguration() {
        guard let test, let modelContext else { return }
        if let existing = test.videoSyncConfiguration {
            syncConfiguration = existing
            return
        }

        let config = VideoSyncConfiguration(test: test)
        modelContext.insert(config)
        test.videoSyncConfiguration = config
        syncConfiguration = config
    }

    func sanitizeWorkspaceState() {
        guard let syncConfiguration, let test else { return }

        if let primaryID = syncConfiguration.primaryVideoAssetID,
           !validVideoSelectionIDs.contains(primaryID)
        {
            syncConfiguration.primaryVideoAssetID = nil
        }
        if let equipmentID = syncConfiguration.equipmentVideoAssetID,
           !validVideoSelectionIDs.contains(equipmentID)
        {
            syncConfiguration.equipmentVideoAssetID = nil
        }

        if syncConfiguration.primaryVideoAssetID == nil,
           let preferred = test.videoAssets.first(where: { $0.videoRole == .anchorView }) ?? test.videoAssets.first
        {
            syncConfiguration.primaryVideoAssetID = assetIdentifier(preferred)
        }
        if syncConfiguration.equipmentVideoAssetID == nil,
           let preferred = test.videoAssets.first(where: { $0.videoRole == .equipmentView })
        {
            syncConfiguration.equipmentVideoAssetID = assetIdentifier(preferred)
        }

        if let auto = syncConfiguration.autoOffsetSeconds, abs(auto) > 20 {
            syncConfiguration.autoOffsetSeconds = nil
        }

        syncConfiguration.equipmentRotationQuarterTurns =
            syncConfiguration.normalizedEquipmentRotationQuarterTurns
        syncConfiguration.equipmentCropRectNormalized = syncConfiguration.equipmentCropRectNormalized

        syncConfiguration.trimInSeconds = normalizedTrimIn
        syncConfiguration.trimOutSeconds = normalizedTrimOut
    }
}
#endif
