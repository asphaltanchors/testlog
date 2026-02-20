//
//  TestLogApp.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import SwiftUI
import SwiftData

@main
struct TestLogApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Product.self,
            PullTest.self,
            TestMeasurement.self,
            Site.self,
            Location.self,
            Asset.self,
        ])
        let configurationName = "TestLog"
        let modelConfiguration = ModelConfiguration(configurationName, schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("ModelContainer creation failed. Resetting local SwiftData store for configuration '\(configurationName)'. Error: \(error)")
            do {
                try deleteStoreArtifacts(configurationName: configurationName)
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

private func deleteStoreArtifacts(configurationName: String) throws {
    let fileManager = FileManager.default
    let applicationSupportURL = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let appDirectoryURL = applicationSupportURL
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "TestLog", isDirectory: true)
    let candidateDirectories = [applicationSupportURL, appDirectoryURL]

    for directory in candidateDirectories where fileManager.fileExists(atPath: directory.path) {
        let directoryContents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for url in directoryContents {
            let fileName = url.lastPathComponent
            if fileName.contains(configurationName) {
                try fileManager.removeItem(at: url)
            }
        }
    }
}
