//
//  MediaPaths.swift
//  TestLog
//
//  Created by Claude on 2/20/26.
//

import Foundation

enum MediaPaths {
    nonisolated static func mediaRootDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = appSupport.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
