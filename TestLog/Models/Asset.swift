//
//  Asset.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import Foundation
import SwiftData

@Model
final class Asset {
    var test: PullTest?
    var assetType: AssetType
    var filename: String
    var relativePath: String
    var createdAt: Date
    var notes: String?
    var byteSize: Int64?
    var contentType: String?
    var checksumSHA256: String?
    var durationSeconds: Double?
    var frameRate: Double?
    var videoWidth: Int?
    var videoHeight: Int?
    var isManagedCopy: Bool
    var videoRole: VideoRole?

    var videoSelectionKey: String {
        relativePath
    }

    var resolvedURL: URL? {
        guard let root = try? MediaPaths.mediaRootDirectory() else { return nil }
        return root.appendingPathComponent(relativePath)
    }

    func matchesVideoSelectionID(_ selectionID: String) -> Bool {
        if selectionID == videoSelectionKey {
            return true
        }
        return selectionID == String(describing: persistentModelID)
    }

    init(
        test: PullTest? = nil,
        assetType: AssetType,
        filename: String,
        relativePath: String,
        createdAt: Date = Date(),
        notes: String? = nil,
        byteSize: Int64? = nil,
        contentType: String? = nil,
        checksumSHA256: String? = nil,
        durationSeconds: Double? = nil,
        frameRate: Double? = nil,
        videoWidth: Int? = nil,
        videoHeight: Int? = nil,
        isManagedCopy: Bool = false,
        videoRole: VideoRole? = nil
    ) {
        self.test = test
        self.assetType = assetType
        self.filename = filename
        self.relativePath = relativePath
        self.createdAt = createdAt
        self.notes = notes
        self.byteSize = byteSize
        self.contentType = contentType
        self.checksumSHA256 = checksumSHA256
        self.durationSeconds = durationSeconds
        self.frameRate = frameRate
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.isManagedCopy = isManagedCopy
        self.videoRole = videoRole
    }
}
