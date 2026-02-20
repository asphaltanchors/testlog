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
    var fileURL: URL
    var createdAt: Date
    var notes: String?

    init(
        test: PullTest? = nil,
        assetType: AssetType,
        filename: String,
        fileURL: URL,
        createdAt: Date = Date(),
        notes: String? = nil
    ) {
        self.test = test
        self.assetType = assetType
        self.filename = filename
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.notes = notes
    }
}
