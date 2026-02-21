//
//  DefaultVideoServices.swift
//  TestLog
//
//  Created by Codex on 2/21/26.
//

import AVFoundation
import CryptoKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

struct ManagedAssetStorageManager: AssetStorageManaging, Sendable {
    private let fileManager = FileManager.default
    nonisolated init() {}

    nonisolated func managedLocation(forTestStorageKey testStorageKey: String, assetID: UUID, originalFilename: String) throws -> URL {
        let root = try mediaRootDirectory()
        let testFolder = testStorageKey.urlEncodedFilename
        let destinationDirectory = root
            .appendingPathComponent(testFolder, isDirectory: true)
            .appendingPathComponent(assetID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        return destinationDirectory.appendingPathComponent(originalFilename, isDirectory: false)
    }

    nonisolated func copyIntoManagedStorage(from sourceURL: URL, forTestStorageKey testStorageKey: String, assetID: UUID, originalFilename: String) throws -> URL {
        let destinationURL = try managedLocation(forTestStorageKey: testStorageKey, assetID: assetID, originalFilename: originalFilename)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    nonisolated func removeManagedFileIfUnreferenced(_ asset: Asset, allAssets: [Asset]) throws {
        guard asset.isManagedCopy else { return }
        let refCount = allAssets.filter { $0.fileURL.path == asset.fileURL.path && $0.persistentModelID != asset.persistentModelID }.count
        guard refCount == 0 else { return }
        if fileManager.fileExists(atPath: asset.fileURL.path) {
            try fileManager.removeItem(at: asset.fileURL)
        }

        let parent = asset.fileURL.deletingLastPathComponent()
        if (try? fileManager.contentsOfDirectory(atPath: parent.path).isEmpty) == true {
            try? fileManager.removeItem(at: parent)
        }
    }

    private nonisolated func mediaRootDirectory() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleID = Bundle.main.bundleIdentifier ?? "TestLog"
        let root = appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

struct DefaultAssetMetadataProbe: AssetMetadataProbing, Sendable {
    nonisolated init() {}

    nonisolated func probe(url: URL, assetType: AssetType) async throws -> AssetImportMetadata {
        var metadata = AssetImportMetadata()
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        if let fileSize = resourceValues.fileSize {
            metadata.byteSize = Int64(fileSize)
        }
        metadata.contentType = resourceValues.contentType?.identifier
        metadata.checksumSHA256 = try sha256(url: url)

        guard assetType == .video else {
            return metadata
        }

        let avAsset = AVURLAsset(url: url)
        let duration = try await avAsset.load(.duration)
        metadata.durationSeconds = duration.seconds.isFinite ? duration.seconds : nil
        let tracks = try await avAsset.loadTracks(withMediaType: .video)
        if let track = tracks.first {
            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let transformed = naturalSize.applying(preferredTransform)
            metadata.videoWidth = Int(abs(transformed.width).rounded())
            metadata.videoHeight = Int(abs(transformed.height).rounded())
            let frameRate = try await track.load(.nominalFrameRate)
            metadata.frameRate = Double(frameRate)
        }
        return metadata
    }

    private nonisolated func sha256(url: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw VideoFeatureError.assetNotReadable(url)
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 64 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct PullTestAssetValidator: AssetValidation {
    let maxVideoCount = 2
    let maxTesterDataCount = 1
    let maxVideoBytes: Int64 = 1_073_741_824 // 1 GB
    let supportedVideoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    func validate(candidates: [ImportedAssetCandidate], existingAssets: [Asset]) throws {
        var videoCount = existingAssets.filter { $0.assetType == .video }.count
        var testerCount = existingAssets.filter { $0.assetType == .testerData }.count
        var assignedRoles: Set<VideoRole> = Set(
            existingAssets
                .filter { $0.assetType == .video }
                .compactMap(\.videoRole)
                .filter { $0 != .unassigned }
        )

        for candidate in candidates {
            if candidate.selectedAssetType == .video {
                videoCount += 1
                if videoCount > maxVideoCount {
                    throw VideoFeatureError.tooManyVideos
                }

                let ext = candidate.sourceURL.pathExtension.lowercased()
                if !supportedVideoExtensions.contains(ext) {
                    throw VideoFeatureError.unsupportedFileType(ext)
                }

                if
                    let fileSize = try? candidate.sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                    Int64(fileSize) > maxVideoBytes
                {
                    throw VideoFeatureError.fileTooLarge(limitBytes: maxVideoBytes)
                }

                if candidate.selectedVideoRole != .unassigned {
                    if assignedRoles.contains(candidate.selectedVideoRole) {
                        throw VideoFeatureError.duplicateVideoRole(candidate.selectedVideoRole)
                    }
                    assignedRoles.insert(candidate.selectedVideoRole)
                }
            } else if candidate.selectedAssetType == .testerData {
                testerCount += 1
                if testerCount > maxTesterDataCount {
                    throw VideoFeatureError.tooManyTesterBinaryFiles
                }
            }
        }
    }
}

struct DefaultVideoSyncService: VideoSyncing {
    func detectOffset(primaryURL: URL, secondaryURL: URL) async throws -> VideoSyncResult {
        let primaryAsset = AVURLAsset(url: primaryURL)
        let secondaryAsset = AVURLAsset(url: secondaryURL)

        let primaryCreation = try await primaryAsset.load(.creationDate)
        let secondaryCreation = try await secondaryAsset.load(.creationDate)

        if let primaryCreation, let secondaryCreation {
            let p = try await primaryCreation.load(.dateValue)
            let s = try await secondaryCreation.load(.dateValue)
            if let p, let s {
                let offset = s.timeIntervalSince(p)
                return VideoSyncResult(
                    detectedOffsetSeconds: max(-60, min(60, offset)),
                    confidence: 0.4
                )
            }
        }

        // Deterministic fallback while clap waveform analysis is not yet implemented.
        return VideoSyncResult(detectedOffsetSeconds: 0, confidence: 0.1)
    }
}

struct DefaultVideoExportService: VideoExporting {
    func exportComposedVideo(request: VideoExportRequest) async throws {
        guard let trimIn = request.syncConfiguration.trimInSeconds, let trimOut = request.syncConfiguration.trimOutSeconds else {
            throw VideoFeatureError.trimRangeRequired
        }
        guard trimOut > trimIn else {
            throw VideoFeatureError.invalidTrimRange
        }

        let primarySource = AVURLAsset(url: request.primaryAsset.fileURL)
        let composition = AVMutableComposition()
        guard
            let primaryVideoTrack = try await primarySource.loadTracks(withMediaType: .video).first,
            let compositionPrimaryTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw VideoFeatureError.assetNotReadable(request.primaryAsset.fileURL)
        }

        let start = CMTime(seconds: trimIn, preferredTimescale: 600)
        let duration = CMTime(seconds: trimOut - trimIn, preferredTimescale: 600)
        let range = CMTimeRange(start: start, duration: duration)
        try compositionPrimaryTrack.insertTimeRange(range, of: primaryVideoTrack, at: .zero)
        compositionPrimaryTrack.preferredTransform = try await primaryVideoTrack.load(.preferredTransform)

        if
            let primaryAudioTrack = try await primarySource.loadTracks(withMediaType: .audio).first,
            let compositionPrimaryAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        {
            try compositionPrimaryAudio.insertTimeRange(range, of: primaryAudioTrack, at: .zero)
        }

        var secondaryCompositionTrack: AVMutableCompositionTrack?
        if let equipmentAsset = request.equipmentAsset {
            let secondarySource = AVURLAsset(url: equipmentAsset.fileURL)
            if
                let equipmentVideoTrack = try await secondarySource.loadTracks(withMediaType: .video).first,
                let compositionSecondaryTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            {
                let syncOffset = request.syncConfiguration.effectiveOffsetSeconds
                let sourceStart = max(0, trimIn + syncOffset)
                let sourceRange = CMTimeRange(
                    start: CMTime(seconds: sourceStart, preferredTimescale: 600),
                    duration: duration
                )
                try compositionSecondaryTrack.insertTimeRange(sourceRange, of: equipmentVideoTrack, at: .zero)
                compositionSecondaryTrack.preferredTransform = try await equipmentVideoTrack.load(.preferredTransform)
                secondaryCompositionTrack = compositionSecondaryTrack
            }
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = request.renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: request.frameRate)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let primaryLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionPrimaryTrack)
        let primarySize = try await transformedSize(for: primaryVideoTrack)
        primaryLayer.setTransform(scaleAndCenterTransform(source: primarySize, target: request.renderSize), at: .zero)
        var layerInstructions: [AVVideoCompositionLayerInstruction] = [primaryLayer]

        if let secondaryTrack = secondaryCompositionTrack {
            let secondaryLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: secondaryTrack)
            let secondarySize = try await transformedSize(for: secondaryTrack)
            let pipSize = CGSize(width: request.renderSize.width * 0.30, height: request.renderSize.height * 0.30)
            let pipRect = CGRect(
                x: request.renderSize.width - pipSize.width - 32,
                y: 32,
                width: pipSize.width,
                height: pipSize.height
            )
            secondaryLayer.setTransform(scaleAndFitTransform(source: secondarySize, destination: pipRect), at: .zero)
            layerInstructions.insert(secondaryLayer, at: 0)
        }

        instruction.layerInstructions = layerInstructions
        videoComposition.instructions = [instruction]

        let overlayLayer = buildOverlayLayer(request: request, renderSize: request.renderSize)
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

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else {
            throw VideoFeatureError.exportFailed
        }
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        try await exportSession.export(to: request.outputURL, as: .mp4)
    }

    private func transformedSize(for track: AVAssetTrack) async throws -> CGSize {
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = naturalSize.applying(transform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    private func scaleAndCenterTransform(source: CGSize, target: CGSize) -> CGAffineTransform {
        guard source.width > 0, source.height > 0 else { return .identity }
        let scale = max(target.width / source.width, target.height / source.height)
        let scaled = CGSize(width: source.width * scale, height: source.height * scale)
        let tx = (target.width - scaled.width) / 2
        let ty = (target.height - scaled.height) / 2
        return CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: tx / scale, y: ty / scale)
    }

    private func scaleAndFitTransform(source: CGSize, destination: CGRect) -> CGAffineTransform {
        guard source.width > 0, source.height > 0 else { return .identity }
        let scale = min(destination.width / source.width, destination.height / source.height)
        let scaled = CGSize(width: source.width * scale, height: source.height * scale)
        let tx = destination.origin.x + (destination.width - scaled.width) / 2
        let ty = destination.origin.y + (destination.height - scaled.height) / 2
        return CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: tx / scale, y: ty / scale)
    }

    private func buildOverlayLayer(request: VideoExportRequest, renderSize: CGSize) -> CALayer {
        let overlay = CALayer()
        overlay.frame = CGRect(origin: .zero, size: renderSize)

        let box = CALayer()
        box.backgroundColor = CGColor(gray: 0, alpha: 0.5)
        box.cornerRadius = 10
        box.frame = CGRect(x: 24, y: renderSize.height - 140, width: renderSize.width * 0.45, height: 110)
        overlay.addSublayer(box)

        let title = CATextLayer()
        title.string = request.test.testID ?? "Untitled Test"
        title.fontSize = 26
        title.foregroundColor = CGColor(gray: 1, alpha: 1)
        title.frame = CGRect(x: 36, y: renderSize.height - 80, width: renderSize.width * 0.4, height: 36)
        title.contentsScale = 2
        overlay.addSublayer(title)

        let subtitle = CATextLayer()
        subtitle.string = "\(request.test.product?.name ?? "Unknown Anchor") | \(request.test.adhesive?.name ?? "Unknown Adhesive")"
        subtitle.fontSize = 18
        subtitle.foregroundColor = CGColor(gray: 1, alpha: 0.95)
        subtitle.frame = CGRect(x: 36, y: renderSize.height - 110, width: renderSize.width * 0.4, height: 30)
        subtitle.contentsScale = 2
        overlay.addSublayer(subtitle)

        if !request.forceSamples.isEmpty {
            let graphRect = CGRect(
                x: renderSize.width * 0.52,
                y: renderSize.height - 200,
                width: renderSize.width * 0.44,
                height: 150
            )
            let graphBackground = CALayer()
            graphBackground.frame = graphRect
            graphBackground.backgroundColor = CGColor(gray: 0, alpha: 0.45)
            graphBackground.cornerRadius = 8
            overlay.addSublayer(graphBackground)

            let graphLayer = CAShapeLayer()
            graphLayer.frame = graphRect
            graphLayer.strokeColor = CGColor(red: 0.2, green: 0.85, blue: 0.95, alpha: 1.0)
            graphLayer.fillColor = nil
            graphLayer.lineWidth = 2
            graphLayer.path = buildGraphPath(samples: request.forceSamples, in: graphRect.size)
            overlay.addSublayer(graphLayer)
        }

        return overlay
    }

    private func buildGraphPath(samples: [ParsedForceSample], in size: CGSize) -> CGPath {
        let path = CGMutablePath()
        guard samples.count > 1 else { return path }

        let minTime = samples.map(\.timeSeconds).min() ?? 0
        let maxTime = samples.map(\.timeSeconds).max() ?? 1
        let minForce = samples.map(\.forceLbs).min() ?? 0
        let maxForce = samples.map(\.forceLbs).max() ?? 1
        let timeRange = max(maxTime - minTime, 0.0001)
        let forceRange = max(maxForce - minForce, 0.0001)

        for (index, sample) in samples.enumerated() {
            let x = ((sample.timeSeconds - minTime) / timeRange) * size.width
            let y = size.height - ((sample.forceLbs - minForce) / forceRange) * size.height
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

private extension String {
    var urlEncodedFilename: String {
        replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}
