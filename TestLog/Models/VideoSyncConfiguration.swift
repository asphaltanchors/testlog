//
//  VideoSyncConfiguration.swift
//  TestLog
//
//  Created by Codex on 2/21/26.
//

import Foundation
import SwiftData

@Model
final class VideoSyncConfiguration {
    @Relationship(inverse: \PullTest.videoSyncConfiguration)
    var test: PullTest?
    var primaryVideoAssetID: String?
    var equipmentVideoAssetID: String?
    var autoOffsetSeconds: Double?
    var manualOffsetSeconds: Double
    var trimInSeconds: Double?
    var trimOutSeconds: Double?
    var lastSyncedAt: Date?

    init(
        test: PullTest? = nil,
        primaryVideoAssetID: String? = nil,
        equipmentVideoAssetID: String? = nil,
        autoOffsetSeconds: Double? = nil,
        manualOffsetSeconds: Double = 0,
        trimInSeconds: Double? = nil,
        trimOutSeconds: Double? = nil,
        lastSyncedAt: Date? = nil
    ) {
        self.test = test
        self.primaryVideoAssetID = primaryVideoAssetID
        self.equipmentVideoAssetID = equipmentVideoAssetID
        self.autoOffsetSeconds = autoOffsetSeconds
        self.manualOffsetSeconds = manualOffsetSeconds
        self.trimInSeconds = trimInSeconds
        self.trimOutSeconds = trimOutSeconds
        self.lastSyncedAt = lastSyncedAt
    }

    var effectiveOffsetSeconds: Double {
        (autoOffsetSeconds ?? 0) + manualOffsetSeconds
    }
}
