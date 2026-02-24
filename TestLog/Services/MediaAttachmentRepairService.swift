import CryptoKit
import Foundation
import SwiftData

struct MediaAttachmentRepairService {
    private nonisolated struct PendingFileAttachment {
        let test: PullTest
        let fileURL: URL
        let relativePath: String
        let assetType: AssetType
        let videoRole: VideoRole?
        let metadata: (createdAt: Date, byteSize: Int64?, checksumSHA256: String?)
    }

    nonisolated struct Report {
        var relinkedOrphanAssets = 0
        var createdMissingAssets = 0
        var deduplicatedFiles = 0
        var repointedAssetReferences = 0
        var skippedUnmappedFiles = 0
        var skippedAmbiguousFiles = 0
        var hashFailures = 0

        var summary: String {
            [
                "Relinked orphan assets: \(relinkedOrphanAssets)",
                "Created missing asset records: \(createdMissingAssets)",
                "Deduplicated identical files: \(deduplicatedFiles)",
                "Repointed asset references: \(repointedAssetReferences)",
                "Skipped unmapped files: \(skippedUnmappedFiles)",
                "Skipped ambiguous files: \(skippedAmbiguousFiles)",
                "Hash failures: \(hashFailures)"
            ].joined(separator: "\n")
        }
    }

    nonisolated init() {}

    nonisolated func run(in modelContext: ModelContext) throws -> Report {
        let root = try MediaPaths.mediaRootDirectory()
        let tests = try modelContext.fetch(FetchDescriptor<PullTest>())
        let assets = try modelContext.fetch(FetchDescriptor<Asset>())

        let testsByFolder = testsByStorageFolder(tests)
        var report = Report()
        let mutableAssets = assets

        let fileURLs = try managedFileURLs(root: root)
        var referencedPaths = Set(mutableAssets.compactMap { asset in
            asset.test == nil ? nil : asset.relativePath
        })
        var pendingAttachments: [PendingFileAttachment] = []

        // Phase 2: discover missing files first.
        for fileURL in fileURLs {
            let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            guard !referencedPaths.contains(relativePath) else { continue }
            guard let folder = topLevelFolder(fromRelativePath: relativePath) else {
                report.skippedUnmappedFiles += 1
                continue
            }
            guard let matches = testsByFolder[folder], !matches.isEmpty else {
                report.skippedUnmappedFiles += 1
                continue
            }
            guard matches.count == 1, let matchedTest = matches.first else {
                report.skippedAmbiguousFiles += 1
                continue
            }

            let metadata = try fileMetadata(for: fileURL)
            let assetType = inferredAssetType(for: fileURL)
            let videoRole = assetType == .video ? suggestedRoleForNewVideo(existingVideos: matchedTest.videoAssets) : nil
            pendingAttachments.append(
                PendingFileAttachment(
                    test: matchedTest,
                    fileURL: fileURL,
                    relativePath: relativePath,
                    assetType: assetType,
                    videoRole: videoRole,
                    metadata: metadata
                )
            )
            referencedPaths.insert(relativePath)
        }

        // Phase 3: apply missing-file attachments.
        var allAssets = mutableAssets
        for attachment in pendingAttachments {
            let asset = Asset(
                test: attachment.test,
                assetType: attachment.assetType,
                filename: attachment.fileURL.lastPathComponent,
                relativePath: attachment.relativePath,
                createdAt: attachment.metadata.createdAt,
                notes: nil,
                byteSize: attachment.metadata.byteSize,
                contentType: nil,
                checksumSHA256: attachment.metadata.checksumSHA256,
                durationSeconds: nil,
                frameRate: nil,
                videoWidth: nil,
                videoHeight: nil,
                isManagedCopy: true,
                videoRole: attachment.videoRole
            )
            modelContext.insert(asset)
            allAssets.append(asset)
            report.createdMissingAssets += 1
        }

        let dedupeOutcome = try deduplicateManagedFiles(
            root: root,
            assets: allAssets
        )
        report.deduplicatedFiles = dedupeOutcome.deletedFiles
        report.repointedAssetReferences = dedupeOutcome.repointedAssetReferences
        report.hashFailures += dedupeOutcome.hashFailures

        try modelContext.save()
        return report
    }

    private nonisolated func deduplicateManagedFiles(root: URL, assets: [Asset]) throws -> (deletedFiles: Int, repointedAssetReferences: Int, hashFailures: Int) {
        let fileURLs = try managedFileURLs(root: root)
        var entriesByHash: [String: [FileDigestEntry]] = [:]
        var hashFailures = 0

        for fileURL in fileURLs {
            let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            do {
                let hash = try sha256(url: fileURL)
                entriesByHash[hash, default: []].append(
                    FileDigestEntry(relativePath: relativePath, url: fileURL)
                )
            } catch {
                hashFailures += 1
            }
        }

        var deletedFiles = 0
        var repointedAssetReferences = 0
        let fileManager = FileManager.default

        for (_, entries) in entriesByHash where entries.count > 1 {
            let sorted = entries.sorted { $0.relativePath < $1.relativePath }
            guard let canonical = sorted.first else { continue }

            for duplicate in sorted.dropFirst() {
                let matchingAssets = assets.filter { $0.relativePath == duplicate.relativePath }
                if !matchingAssets.isEmpty {
                    for asset in matchingAssets {
                        asset.relativePath = canonical.relativePath
                    }
                    repointedAssetReferences += matchingAssets.count
                }

                if fileManager.fileExists(atPath: duplicate.url.path) {
                    try fileManager.removeItem(at: duplicate.url)
                    deletedFiles += 1
                    cleanupEmptyParentDirectories(of: duplicate.url, root: root)
                }
            }
        }

        return (deletedFiles, repointedAssetReferences, hashFailures)
    }

    private nonisolated func managedFileURLs(root: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(url)
            }
        }
        return files
    }

    private nonisolated func testsByStorageFolder(_ tests: [PullTest]) -> [String: [PullTest]] {
        var dictionary: [String: [PullTest]] = [:]
        for test in tests {
            for key in storageFolderKeys(for: test) {
                dictionary[key, default: []].append(test)
            }
        }
        return dictionary
    }

    private nonisolated func storageFolderKeys(for test: PullTest) -> [String] {
        var keys: [String] = []
        if let testID = test.testID, !testID.isEmpty {
            keys.append(testID.urlEncodedFilename)
        }
        let persistentKey = String(describing: test.persistentModelID).urlEncodedFilename
        if !keys.contains(persistentKey) {
            keys.append(persistentKey)
        }
        return keys
    }

    private nonisolated func topLevelFolder(fromRelativePath relativePath: String) -> String? {
        let components = relativePath.split(separator: "/").map(String.init)
        return components.first
    }

    private nonisolated func inferredAssetType(for url: URL) -> AssetType {
        let ext = url.pathExtension.lowercased()
        if ["mov", "mp4", "m4v"].contains(ext) { return .video }
        if ext == "lby" { return .testerData }
        if ["jpg", "jpeg", "png", "heic", "heif"].contains(ext) { return .photo }
        return .document
    }

    private nonisolated func suggestedRoleForNewVideo(existingVideos: [Asset]) -> VideoRole {
        let existingRoles = Set(existingVideos.compactMap(\.videoRole))
        if !existingRoles.contains(.anchorView) { return .anchorView }
        if !existingRoles.contains(.equipmentView) { return .equipmentView }
        return .unassigned
    }

    private nonisolated func fileMetadata(for url: URL) throws -> (createdAt: Date, byteSize: Int64?, checksumSHA256: String?) {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        let createdAt = values.creationDate ?? values.contentModificationDate ?? Date()
        let byteSize = values.fileSize.map(Int64.init)
        let checksum = try? sha256(url: url)
        return (createdAt, byteSize, checksum)
    }

    private nonisolated func sha256(url: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw CocoaError(.fileReadNoSuchFile)
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

    private nonisolated func cleanupEmptyParentDirectories(of fileURL: URL, root: URL) {
        var current = fileURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        while current.path.hasPrefix(root.path), current.path != root.path {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: current.path), contents.isEmpty else {
                return
            }
            try? fileManager.removeItem(at: current)
            current = current.deletingLastPathComponent()
        }
    }

}

private struct FileDigestEntry {
    let relativePath: String
    let url: URL
}
