//
//  VideoSyncConfiguration.swift
//  TestLog
//
//  Created by Codex on 2/21/26.
//

import Foundation
import CoreGraphics
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
    var equipmentRotationQuarterTurns: Int
    var equipmentCropX: Double
    var equipmentCropY: Double
    var equipmentCropWidth: Double
    var equipmentCropHeight: Double

    init(
        test: PullTest? = nil,
        primaryVideoAssetID: String? = nil,
        equipmentVideoAssetID: String? = nil,
        autoOffsetSeconds: Double? = nil,
        manualOffsetSeconds: Double = 0,
        trimInSeconds: Double? = nil,
        trimOutSeconds: Double? = nil,
        lastSyncedAt: Date? = nil,
        equipmentRotationQuarterTurns: Int = 0,
        equipmentCropX: Double = 0,
        equipmentCropY: Double = 0,
        equipmentCropWidth: Double = 1,
        equipmentCropHeight: Double = 1
    ) {
        self.test = test
        self.primaryVideoAssetID = primaryVideoAssetID
        self.equipmentVideoAssetID = equipmentVideoAssetID
        self.autoOffsetSeconds = autoOffsetSeconds
        self.manualOffsetSeconds = manualOffsetSeconds
        self.trimInSeconds = trimInSeconds
        self.trimOutSeconds = trimOutSeconds
        self.lastSyncedAt = lastSyncedAt
        self.equipmentRotationQuarterTurns = equipmentRotationQuarterTurns
        self.equipmentCropX = equipmentCropX
        self.equipmentCropY = equipmentCropY
        self.equipmentCropWidth = equipmentCropWidth
        self.equipmentCropHeight = equipmentCropHeight
    }

    var effectiveOffsetSeconds: Double {
        (autoOffsetSeconds ?? 0) + manualOffsetSeconds
    }

    var normalizedEquipmentRotationQuarterTurns: Int {
        let mod = equipmentRotationQuarterTurns % 4
        return mod < 0 ? mod + 4 : mod
    }

    var equipmentCropRectNormalized: CGRect {
        get {
            CGRect(
                x: equipmentCropX,
                y: equipmentCropY,
                width: equipmentCropWidth,
                height: equipmentCropHeight
            ).clampedNormalized(minSize: 0.05)
        }
        set {
            let clamped = newValue.clampedNormalized(minSize: 0.05)
            equipmentCropX = clamped.origin.x
            equipmentCropY = clamped.origin.y
            equipmentCropWidth = clamped.width
            equipmentCropHeight = clamped.height
        }
    }
}
