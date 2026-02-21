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

struct DefaultVideoSyncService: VideoSyncing, Sendable {
    nonisolated func detectOffset(primaryURL: URL, secondaryURL: URL) async throws -> VideoSyncResult {
        try await Task.detached(priority: .userInitiated) {
            let primaryClap = Self.detectClapPeak(in: primaryURL)
            let secondaryClap = Self.detectClapPeak(in: secondaryURL)

            if let primaryClap, let secondaryClap {
                let offset = secondaryClap.timeSeconds - primaryClap.timeSeconds
                let confidence = max(0.15, min(0.98, (primaryClap.prominence + secondaryClap.prominence) / 2))
                let plausibleOffsetLimit = 20.0
                if abs(offset) <= plausibleOffsetLimit {
                    return VideoSyncResult(
                        detectedOffsetSeconds: max(-60, min(60, offset)),
                        confidence: confidence
                    )
                }
            }

            return try Self.creationDateFallback(primaryURL: primaryURL, secondaryURL: secondaryURL)
        }.value
    }

    private nonisolated static func creationDateFallback(primaryURL: URL, secondaryURL: URL) throws -> VideoSyncResult {
        let primaryDate = try primaryURL.resourceValues(forKeys: [.creationDateKey]).creationDate
        let secondaryDate = try secondaryURL.resourceValues(forKeys: [.creationDateKey]).creationDate
        if let primaryDate, let secondaryDate {
            let offset = secondaryDate.timeIntervalSince(primaryDate)
            return VideoSyncResult(
                detectedOffsetSeconds: max(-60, min(60, offset)),
                confidence: 0.25
            )
        }

        return VideoSyncResult(detectedOffsetSeconds: 0, confidence: 0.1)
    }

    private nonisolated static func detectClapPeak(in url: URL) -> (timeSeconds: Double, prominence: Double)? {
        let asset = AVURLAsset(url: url)
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else { return nil }
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        var sampleRate: Double = 0
        var channels: Int = 1
        var frameIndex: Int64 = 0
        let maxAnalyzedSeconds = 20.0
        let envelopeWindowFrames = 1024
        var windowSum: Double = 0
        var windowFrameCount = 0
        var envelope: [(time: Double, amplitude: Double)] = []

        while reader.status == .reading {
            guard let buffer = output.copyNextSampleBuffer() else { break }
            defer { CMSampleBufferInvalidate(buffer) }

            if sampleRate == 0,
               let formatDescription = CMSampleBufferGetFormatDescription(buffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
            {
                sampleRate = asbd.mSampleRate
                channels = max(Int(asbd.mChannelsPerFrame), 1)
            }

            guard sampleRate > 0 else { continue }
            if Double(frameIndex) / sampleRate > maxAnalyzedSeconds { break }

            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let dataLength = CMBlockBufferGetDataLength(blockBuffer)
            guard dataLength > 0 else { continue }

            var data = Data(count: dataLength)
            let status = data.withUnsafeMutableBytes { rawBuffer in
                CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: dataLength,
                    destination: rawBuffer.baseAddress!
                )
            }
            guard status == kCMBlockBufferNoErr else { continue }

            let floatCount = dataLength / MemoryLayout<Float>.size
            if floatCount == 0 { continue }
            let frameCount = floatCount / channels
            if frameCount == 0 { continue }

            data.withUnsafeBytes { raw in
                let samples = raw.bindMemory(to: Float.self)
                for frame in 0..<frameCount {
                    var channelSum: Float = 0
                    let base = frame * channels
                    for c in 0..<channels {
                        channelSum += abs(samples[base + c])
                    }
                    let amplitude = channelSum / Float(channels)
                    windowSum += Double(amplitude)
                    windowFrameCount += 1

                    if windowFrameCount == envelopeWindowFrames {
                        let avg = windowSum / Double(windowFrameCount)
                        let absoluteFrame = frameIndex + Int64(frame)
                        let time = Double(absoluteFrame) / sampleRate
                        envelope.append((time: time, amplitude: avg))
                        windowSum = 0
                        windowFrameCount = 0
                    }
                }
            }
            frameIndex += Int64(frameCount)
        }

        if windowFrameCount > 0, sampleRate > 0 {
            let avg = windowSum / Double(windowFrameCount)
            let time = Double(frameIndex) / sampleRate
            envelope.append((time: time, amplitude: avg))
        }

        guard !envelope.isEmpty else { return nil }

        let maxAmplitude = envelope.map(\.amplitude).max() ?? 0
        guard maxAmplitude > 0 else { return nil }
        let threshold = maxAmplitude * 0.7

        let sorted = envelope.map(\.amplitude).sorted()
        let median = sorted[sorted.count / 2]

        let candidate = envelope.first(where: { $0.time >= 0.05 && $0.amplitude >= threshold })
            ?? envelope.max(by: { $0.amplitude < $1.amplitude })

        guard let candidate else { return nil }

        let prominence = max(0.05, min(0.99, (candidate.amplitude - median) / max(candidate.amplitude, 0.0001)))
        return (timeSeconds: candidate.time, prominence: prominence)
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
        compositionPrimaryTrack.preferredTransform = .identity

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
            try await placedTransform(for: primaryVideoTrack, destination: fullFrameRect, contentMode: .fill),
            at: .zero
        )
        var layerInstructions: [AVVideoCompositionLayerInstruction] = [primaryLayer]

        if let secondaryTrack = secondaryCompositionTrack, let equipmentAsset = request.equipmentAsset {
            let secondaryLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: secondaryTrack)
            let secondarySource = AVURLAsset(url: equipmentAsset.fileURL)
            guard let secondarySourceTrack = try await secondarySource.loadTracks(withMediaType: .video).first else {
                throw VideoFeatureError.assetNotReadable(equipmentAsset.fileURL)
            }
            let pipSize = CGSize(width: request.renderSize.width * 0.30, height: request.renderSize.height * 0.30)
            let pipRect = CGRect(
                x: 32,
                y: request.renderSize.height - pipSize.height - 32,
                width: pipSize.width,
                height: pipSize.height
            )
            secondaryLayer.setTransform(
                try await placedTransform(
                    for: secondarySourceTrack,
                    destination: pipRect,
                    contentMode: .fit,
                    extraQuarterTurnsClockwise: request.syncConfiguration.normalizedEquipmentRotationQuarterTurns,
                    cropRectNormalized: request.syncConfiguration.equipmentCropRectNormalized
                ),
                at: .zero
            )
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

    private enum ContentMode {
        case fill
        case fit
    }

    private func placedTransform(
        for track: AVAssetTrack,
        destination: CGRect,
        contentMode: ContentMode,
        extraQuarterTurnsClockwise: Int = 0,
        cropRectNormalized: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    ) async throws -> CGAffineTransform {
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let sourceRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let orientedSize = CGSize(width: abs(sourceRect.width), height: abs(sourceRect.height))
        guard orientedSize.width > 0, orientedSize.height > 0 else { return .identity }

        let normalizedOrientation = transform.concatenating(
            CGAffineTransform(translationX: -sourceRect.minX, y: -sourceRect.minY)
        )

        let (quarterTurnTransform, rotatedSize) = clockwiseQuarterTurnTransform(
            turns: extraQuarterTurnsClockwise,
            sourceSize: orientedSize
        )
        let croppedRect = absoluteCropRect(
            normalized: cropRectNormalized,
            in: CGRect(origin: .zero, size: rotatedSize)
        )

        guard croppedRect.width > 0, croppedRect.height > 0 else { return .identity }

        let scale: CGFloat
        switch contentMode {
        case .fill:
            scale = max(destination.width / croppedRect.width, destination.height / croppedRect.height)
        case .fit:
            scale = min(destination.width / croppedRect.width, destination.height / croppedRect.height)
        }
        let scaled = CGSize(width: croppedRect.width * scale, height: croppedRect.height * scale)
        let tx = destination.minX + (destination.width - scaled.width) / 2
        let ty = destination.minY + (destination.height - scaled.height) / 2

        return normalizedOrientation
            .concatenating(quarterTurnTransform)
            .concatenating(CGAffineTransform(translationX: -croppedRect.minX, y: -croppedRect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
    }

    private func clockwiseQuarterTurnTransform(turns: Int, sourceSize: CGSize) -> (CGAffineTransform, CGSize) {
        let normalizedTurns = ((turns % 4) + 4) % 4
        switch normalizedTurns {
        case 1:
            return (
                CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: sourceSize.height, ty: 0),
                CGSize(width: sourceSize.height, height: sourceSize.width)
            )
        case 2:
            return (
                CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: sourceSize.width, ty: sourceSize.height),
                sourceSize
            )
        case 3:
            return (
                CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: sourceSize.width),
                CGSize(width: sourceSize.height, height: sourceSize.width)
            )
        default:
            return (.identity, sourceSize)
        }
    }

    private func absoluteCropRect(normalized: CGRect, in bounds: CGRect) -> CGRect {
        let clamped = normalizedCrop(normalized)
        return CGRect(
            x: bounds.minX + clamped.minX * bounds.width,
            y: bounds.minY + clamped.minY * bounds.height,
            width: bounds.width * clamped.width,
            height: bounds.height * clamped.height
        )
    }

    private func normalizedCrop(_ rect: CGRect) -> CGRect {
        let minSize: CGFloat = 0.05
        var out = rect.standardized
        out.origin.x = min(max(out.origin.x.isFinite ? out.origin.x : 0, 0), 1)
        out.origin.y = min(max(out.origin.y.isFinite ? out.origin.y : 0, 0), 1)
        out.size.width = min(max(out.size.width.isFinite ? out.size.width : 1, minSize), 1)
        out.size.height = min(max(out.size.height.isFinite ? out.size.height : 1, minSize), 1)
        if out.maxX > 1 { out.origin.x = max(0, 1 - out.width) }
        if out.maxY > 1 { out.origin.y = max(0, 1 - out.height) }
        return out
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
            let y = ((sample.forceLbs - minForce) / forceRange) * size.height
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
