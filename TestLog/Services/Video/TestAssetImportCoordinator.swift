import Foundation
import SwiftData

@MainActor
final class TestAssetImportCoordinator {
    private let storageManager: AssetStorageManaging
    private let assetValidator: AssetValidation
    private let metadataProbe: AssetMetadataProbing
    private let testerDataParser: TesterDataParsing

    init(
        storageManager: AssetStorageManaging = ManagedAssetStorageManager(),
        assetValidator: AssetValidation = PullTestAssetValidator(),
        metadataProbe: AssetMetadataProbing = DefaultAssetMetadataProbe(),
        testerDataParser: TesterDataParsing = LBYTesterDataParser()
    ) {
        self.storageManager = storageManager
        self.assetValidator = assetValidator
        self.metadataProbe = metadataProbe
        self.testerDataParser = testerDataParser
    }

    func buildCandidates(urls: [URL], existingVideos: [Asset]) -> [ImportedAssetCandidate] {
        urls.map { url in
            var candidate = ImportedAssetCandidate(
                sourceURL: url,
                suggestedAssetType: suggestedType(for: url)
            )
            if candidate.selectedAssetType == .video {
                candidate.selectedVideoRole = suggestedRoleForNewVideo(existingVideos: existingVideos)
            }
            return candidate
        }
    }

    func validate(candidates: [ImportedAssetCandidate], existingAssets: [Asset]) throws {
        try assetValidator.validate(candidates: candidates, existingAssets: existingAssets)
    }

    func importCandidates(
        _ candidates: [ImportedAssetCandidate],
        into test: PullTest,
        modelContext: ModelContext,
        progress: @escaping (String) -> Void
    ) async throws {
        try assetValidator.validate(candidates: candidates, existingAssets: test.assets)

        let total = candidates.count
        for (index, candidate) in candidates.enumerated() {
            progress("Importing \(index + 1) of \(total): \(candidate.sourceURL.lastPathComponent)")
            let imported = try await processCandidateOffMain(candidate, test: test)
            let asset = Asset(
                test: test,
                assetType: imported.assetType,
                filename: candidate.sourceURL.lastPathComponent,
                relativePath: imported.relativePath,
                notes: nil,
                byteSize: imported.metadata.byteSize,
                contentType: imported.metadata.contentType,
                checksumSHA256: imported.metadata.checksumSHA256,
                durationSeconds: imported.metadata.durationSeconds,
                frameRate: imported.metadata.frameRate,
                videoWidth: imported.metadata.videoWidth,
                videoHeight: imported.metadata.videoHeight,
                isManagedCopy: true,
                videoRole: imported.assetType == .video ? imported.videoRole : nil
            )
            modelContext.insert(asset)
            test.assets.append(asset)

            if imported.assetType == .testerData {
                if let testerPeakForce = imported.testerPeakForceLbs {
                    test.upsertTesterMaxMeasurement(forceLbs: testerPeakForce)
                } else {
                    test.removeTesterMaxMeasurement()
                }
            }
        }
    }

    func removeAsset(
        _ asset: Asset,
        from test: PullTest,
        allAssets: [Asset],
        modelContext: ModelContext
    ) throws {
        try storageManager.removeManagedFileIfUnreferenced(asset, allAssets: allAssets)
        if let primaryID = test.videoSyncConfiguration?.primaryVideoAssetID,
           asset.matchesVideoSelectionID(primaryID)
        {
            test.videoSyncConfiguration?.primaryVideoAssetID = nil
        }
        if let equipmentID = test.videoSyncConfiguration?.equipmentVideoAssetID,
           asset.matchesVideoSelectionID(equipmentID)
        {
            test.videoSyncConfiguration?.equipmentVideoAssetID = nil
        }
        if asset.assetType == .testerData {
            test.removeTesterMaxMeasurement()
        }
        modelContext.delete(asset)
    }

    func suggestedType(for url: URL) -> AssetType {
        let ext = url.pathExtension.lowercased()
        if ["mov", "mp4", "m4v"].contains(ext) { return .video }
        return .testerData
    }

    func suggestedRoleForNewVideo(existingVideos: [Asset]) -> VideoRole {
        let existingRoles = Set(existingVideos.compactMap(\.videoRole))
        if !existingRoles.contains(.anchorView) { return .anchorView }
        if !existingRoles.contains(.equipmentView) { return .equipmentView }
        return .unassigned
    }

    private func processCandidateOffMain(
        _ candidate: ImportedAssetCandidate,
        test: PullTest
    ) async throws -> ImportedAssetWorkResult {
        let testStorageKey =
            test.testID?.isEmpty == false
            ? (test.testID ?? "Unknown")
            : String(describing: test.persistentModelID)

        return try await Task.detached(priority: .userInitiated) {
            let storage = ManagedAssetStorageManager()
            let probe = DefaultAssetMetadataProbe()

            let startedScopedAccess = candidate.sourceURL.startAccessingSecurityScopedResource()
            defer {
                if startedScopedAccess {
                    candidate.sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let provisionalID = UUID()
            let relativePath = try storage.copyIntoManagedStorage(
                from: candidate.sourceURL,
                forTestStorageKey: testStorageKey,
                assetID: provisionalID,
                originalFilename: candidate.sourceURL.lastPathComponent
            )
            let root = try MediaPaths.mediaRootDirectory()
            let absoluteURL = root.appendingPathComponent(relativePath)
            let metadata = try await probe.probe(
                url: absoluteURL,
                assetType: candidate.selectedAssetType
            )
            let testerPeakForceLbs: Double?
            if candidate.selectedAssetType == .testerData {
                let parser = LBYTesterDataParser()
                let samples = try parser.parseSamples(from: absoluteURL)
                testerPeakForceLbs = samples
                    .map(\.forceLbs)
                    .filter { $0.isFinite && $0 > 0 }
                    .max()
            } else {
                testerPeakForceLbs = nil
            }
            return ImportedAssetWorkResult(
                relativePath: relativePath,
                assetType: candidate.selectedAssetType,
                videoRole: candidate.selectedVideoRole,
                metadata: metadata,
                testerPeakForceLbs: testerPeakForceLbs
            )
        }.value
    }
}

private struct ImportedAssetWorkResult: Sendable {
    let relativePath: String
    let assetType: AssetType
    let videoRole: VideoRole
    let metadata: AssetImportMetadata
    let testerPeakForceLbs: Double?
}
