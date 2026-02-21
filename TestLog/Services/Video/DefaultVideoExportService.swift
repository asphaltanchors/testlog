import AVFoundation
import Foundation

struct DefaultVideoExportService: VideoExporting {
    private let overlayBuilder = VideoExportOverlayBuilder()

    func exportComposedVideo(request: VideoExportRequest) async throws {
        guard
            let trimIn = request.syncConfiguration.trimInSeconds,
            let trimOut = request.syncConfiguration.trimOutSeconds
        else {
            throw VideoFeatureError.trimRangeRequired
        }
        guard trimOut > trimIn else {
            throw VideoFeatureError.invalidTrimRange
        }

        guard let primaryURL = request.primaryAsset.resolvedURL else {
            throw VideoFeatureError.assetNotReadable(request.primaryAsset.filename)
        }
        let primarySource = AVURLAsset(url: primaryURL)
        let composition = AVMutableComposition()
        guard
            let primaryVideoTrack = try await primarySource.loadTracks(withMediaType: .video).first,
            let compositionPrimaryTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw VideoFeatureError.assetNotReadable(request.primaryAsset.filename)
        }

        let start = CMTime(seconds: trimIn, preferredTimescale: 600)
        let duration = CMTime(seconds: trimOut - trimIn, preferredTimescale: 600)
        let range = CMTimeRange(start: start, duration: duration)
        try compositionPrimaryTrack.insertTimeRange(range, of: primaryVideoTrack, at: .zero)
        compositionPrimaryTrack.preferredTransform = .identity

        if
            let primaryAudioTrack = try await primarySource.loadTracks(withMediaType: .audio).first,
            let compositionPrimaryAudio = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        {
            try compositionPrimaryAudio.insertTimeRange(range, of: primaryAudioTrack, at: .zero)
        }

        var secondaryCompositionTrack: AVMutableCompositionTrack?
        if let equipmentAsset = request.equipmentAsset, let equipmentURL = equipmentAsset.resolvedURL {
            let secondarySource = AVURLAsset(url: equipmentURL)
            if
                let equipmentVideoTrack = try await secondarySource.loadTracks(withMediaType: .video).first,
                let compositionSecondaryTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
            {
                let syncOffset = request.syncConfiguration.effectiveOffsetSeconds
                let sourceStart = max(0, trimIn + syncOffset)
                let sourceRange = CMTimeRange(
                    start: CMTime(seconds: sourceStart, preferredTimescale: 600),
                    duration: duration
                )
                try compositionSecondaryTrack.insertTimeRange(sourceRange, of: equipmentVideoTrack, at: .zero)
                compositionSecondaryTrack.preferredTransform = .identity
                secondaryCompositionTrack = compositionSecondaryTrack
            }
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = request.renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: request.frameRate)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let primaryLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionPrimaryTrack)
        let fullFrameRect = CGRect(origin: .zero, size: request.renderSize)
        primaryLayer.setTransform(
            try await VideoExportTransforms.placedTransform(
                for: primaryVideoTrack,
                destination: fullFrameRect,
                contentMode: .fill
            ),
            at: .zero
        )
        var layerInstructions: [AVVideoCompositionLayerInstruction] = [primaryLayer]

        if
            let secondaryTrack = secondaryCompositionTrack,
            let equipmentAsset = request.equipmentAsset,
            let equipmentURL = equipmentAsset.resolvedURL
        {
            let secondaryLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: secondaryTrack)
            let secondarySource = AVURLAsset(url: equipmentURL)
            guard let secondarySourceTrack = try await secondarySource.loadTracks(withMediaType: .video).first else {
                throw VideoFeatureError.assetNotReadable(equipmentAsset.filename)
            }
            let pipSize = CGSize(width: request.renderSize.width * 0.30, height: request.renderSize.height * 0.30)
            let pipRect = CGRect(
                x: 24,
                y: request.renderSize.height - pipSize.height - 32,
                width: pipSize.width,
                height: pipSize.height
            )
            secondaryLayer.setTransform(
                try await VideoExportTransforms.placedTransform(
                    for: secondarySourceTrack,
                    destination: pipRect,
                    contentMode: .fitLeading,
                    extraQuarterTurnsClockwise: request.syncConfiguration.normalizedEquipmentRotationQuarterTurns,
                    cropRectNormalized: request.syncConfiguration.equipmentCropRectNormalized
                ),
                at: .zero
            )
            layerInstructions.insert(secondaryLayer, at: 0)
        }

        instruction.layerInstructions = layerInstructions
        videoComposition.instructions = [instruction]

        let overlayLayer = overlayBuilder.buildOverlayLayer(request: request, renderSize: request.renderSize)
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: request.renderSize)
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: request.renderSize)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        if FileManager.default.fileExists(atPath: request.outputURL.path) {
            try FileManager.default.removeItem(at: request.outputURL)
        }

        guard
            let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPreset1920x1080
            )
        else {
            throw VideoFeatureError.exportFailed
        }
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        try await exportSession.export(to: request.outputURL, as: .mp4)
    }
}
