import AVFoundation
import Foundation

struct DefaultVideoSyncService: VideoSyncing, Sendable {
    nonisolated func detectOffset(primaryURL: URL, secondaryURL: URL) async throws -> VideoSyncResult {
        try await Task.detached(priority: .userInitiated) {
            let primaryClap = await Self.detectClapPeak(in: primaryURL)
            let secondaryClap = await Self.detectClapPeak(in: secondaryURL)

            if let primaryClap, let secondaryClap {
                let offset = secondaryClap.timeSeconds - primaryClap.timeSeconds
                let confidence = max(
                    0.15,
                    min(0.98, (primaryClap.prominence + secondaryClap.prominence) / 2)
                )
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

    private nonisolated static func creationDateFallback(
        primaryURL: URL,
        secondaryURL: URL
    ) throws -> VideoSyncResult {
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

    private nonisolated static func detectClapPeak(
        in url: URL
    ) async -> (timeSeconds: Double, prominence: Double)? {
        let asset = AVURLAsset(url: url)
        let tracks = try? await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks?.first else { return nil }
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
        var channels = 1
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

        let prominence = max(
            0.05,
            min(0.99, (candidate.amplitude - median) / max(candidate.amplitude, 0.0001))
        )
        return (timeSeconds: candidate.time, prominence: prominence)
    }
}
