import Foundation
import SwiftData

struct ManagedAssetStorageManager: AssetStorageManaging, Sendable {
    nonisolated init() {}

    nonisolated func managedLocation(
        forTestStorageKey testStorageKey: String,
        assetID: UUID,
        originalFilename: String
    ) throws -> String {
        let root = try MediaPaths.mediaRootDirectory()
        let testFolder = testStorageKey.urlEncodedFilename
        let destinationDirectory = root
            .appendingPathComponent(testFolder, isDirectory: true)
            .appendingPathComponent(assetID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        return "\(testFolder)/\(assetID.uuidString)/\(originalFilename)"
    }

    nonisolated func copyIntoManagedStorage(
        from sourceURL: URL,
        forTestStorageKey testStorageKey: String,
        assetID: UUID,
        originalFilename: String
    ) throws -> String {
        let relativePath = try managedLocation(
            forTestStorageKey: testStorageKey,
            assetID: assetID,
            originalFilename: originalFilename
        )
        let root = try MediaPaths.mediaRootDirectory()
        let destinationURL = root.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return relativePath
    }

    nonisolated func removeManagedFileIfUnreferenced(_ asset: Asset, allAssets: [Asset]) throws {
        let refCount = allAssets.filter {
            $0.relativePath == asset.relativePath && $0.persistentModelID != asset.persistentModelID
        }.count
        guard refCount == 0 else { return }
        guard let resolvedURL = asset.resolvedURL else { return }
        let root = try MediaPaths.mediaRootDirectory().standardizedFileURL
        let resolvedURLInSandbox = resolvedURL.standardizedFileURL

        let isInsideSandboxMediaRoot =
            resolvedURLInSandbox.path == root.path
            || resolvedURLInSandbox.path.hasPrefix(root.path + "/")

        // Keep legacy records removable when they point at sandbox-managed media,
        // even if older schema versions left `isManagedCopy` as false.
        guard asset.isManagedCopy || isInsideSandboxMediaRoot else { return }
        guard resolvedURLInSandbox.path != root.path else { return }
        if FileManager.default.fileExists(atPath: resolvedURLInSandbox.path) {
            try FileManager.default.removeItem(at: resolvedURLInSandbox)
        }

        let parent = resolvedURLInSandbox.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty) == true {
            try? FileManager.default.removeItem(at: parent)
        }
    }
}
