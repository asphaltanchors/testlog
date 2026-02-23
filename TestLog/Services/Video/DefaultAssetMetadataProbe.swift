import AVFoundation
import CryptoKit
import Foundation

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

        let avAsset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        metadata.durationSeconds = try await loadRobustDurationSeconds(from: avAsset)
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

    private nonisolated func loadRobustDurationSeconds(from asset: AVAsset) async throws -> Double? {
        let direct = try await asset.load(.duration).seconds
        if direct.isFinite, direct > 1.0 {
            return direct
        }

        let tracks = try await asset.loadTracks(withMediaType: .video)
        if let firstVideo = tracks.first {
            let videoDuration = try await firstVideo.load(.timeRange).duration.seconds
            if videoDuration.isFinite, videoDuration > 1.0 {
                return videoDuration
            }
        }

        let allTracks = try await asset.load(.tracks)
        let trackDurations = try await allTracks.asyncMap { track in
            try await track.load(.timeRange).duration.seconds
        }
        let bestTrackDuration = trackDurations
            .filter { $0.isFinite && $0 > 1.0 }
            .max()
        return bestTrackDuration
    }

    private nonisolated func sha256(url: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw VideoFeatureError.assetNotReadable(url.lastPathComponent)
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

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var output: [T] = []
        output.reserveCapacity(count)
        for element in self {
            output.append(try await transform(element))
        }
        return output
    }
}
