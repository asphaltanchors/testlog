//
//  VideoServiceContracts.swift
//  TestLog
//
//  Created by Codex on 2/21/26.
//

import Foundation
import CoreGraphics

struct ImportedAssetCandidate: Identifiable, Hashable, Sendable {
    let id = UUID()
    let sourceURL: URL
    let suggestedAssetType: AssetType
    var selectedAssetType: AssetType
    var selectedVideoRole: VideoRole

    init(sourceURL: URL, suggestedAssetType: AssetType) {
        self.sourceURL = sourceURL
        self.suggestedAssetType = suggestedAssetType
        self.selectedAssetType = suggestedAssetType
        self.selectedVideoRole = .unassigned
    }
}

struct AssetImportMetadata: Sendable {
    var byteSize: Int64?
    var contentType: String?
    var checksumSHA256: String?
    var durationSeconds: Double?
    var frameRate: Double?
    var videoWidth: Int?
    var videoHeight: Int?
}

struct VideoSyncResult {
    let detectedOffsetSeconds: Double
    let confidence: Double
}

struct VideoExportRequest {
    let test: PullTest
    let primaryAsset: Asset
    let equipmentAsset: Asset?
    let syncConfiguration: VideoSyncConfiguration
    let outputURL: URL
    let renderSize: CGSize
    let frameRate: Int32
    let forceSamples: [ParsedForceSample]
}

enum VideoFeatureError: LocalizedError {
    case unsupportedFileType(String)
    case fileTooLarge(limitBytes: Int64)
    case tooManyVideos
    case duplicateVideoRole(VideoRole)
    case tooManyTesterBinaryFiles
    case missingPrimaryVideo
    case trimRangeRequired
    case invalidTrimRange
    case assetNotReadable(URL)
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return "Unsupported file type: \(ext)"
        case .fileTooLarge(let limitBytes):
            return "File exceeds size limit of \(ByteCountFormatter.string(fromByteCount: limitBytes, countStyle: .file))."
        case .tooManyVideos:
            return "Only up to 2 videos are allowed per test."
        case .duplicateVideoRole(let role):
            return "Video role '\(role.rawValue)' can only be assigned once."
        case .tooManyTesterBinaryFiles:
            return "Only 1 tester binary file is allowed per test."
        case .missingPrimaryVideo:
            return "A primary video is required for sync/export."
        case .trimRangeRequired:
            return "Set trim-in and trim-out before exporting."
        case .invalidTrimRange:
            return "Trim range is invalid."
        case .assetNotReadable(let url):
            return "Cannot read asset: \(url.lastPathComponent)"
        case .exportFailed:
            return "Video export failed."
        }
    }
}

protocol AssetStorageManaging {
    func managedLocation(forTestStorageKey testStorageKey: String, assetID: UUID, originalFilename: String) throws -> URL
    func copyIntoManagedStorage(from sourceURL: URL, forTestStorageKey testStorageKey: String, assetID: UUID, originalFilename: String) throws -> URL
    func removeManagedFileIfUnreferenced(_ asset: Asset, allAssets: [Asset]) throws
}

protocol AssetMetadataProbing {
    func probe(url: URL, assetType: AssetType) async throws -> AssetImportMetadata
}

protocol AssetValidation {
    func validate(candidates: [ImportedAssetCandidate], existingAssets: [Asset]) throws
}

protocol VideoSyncing {
    func detectOffset(primaryURL: URL, secondaryURL: URL) async throws -> VideoSyncResult
}

protocol VideoExporting {
    func exportComposedVideo(request: VideoExportRequest) async throws
}
