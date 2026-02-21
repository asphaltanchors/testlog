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
