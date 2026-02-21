import Foundation

struct PullTestAssetValidator: AssetValidation, Sendable {
    nonisolated init() {}
    let maxVideoCount = 2
    let maxTesterDataCount = 1
    let maxVideoBytes: Int64 = 1_073_741_824 // 1 GB
    let supportedVideoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    nonisolated func validate(candidates: [ImportedAssetCandidate], existingAssets: [Asset]) throws {
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
